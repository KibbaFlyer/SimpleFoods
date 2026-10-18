import Foundation
import CoreFoundation
import CryptoKit
import GRDB
import MealTrackerCore

public enum OFFError: Error, Equatable { case busy, unsupportedSchema, invalidBarcode, notFound, malformed, http(Int), rateLimited(Date), staleResponse, timeout }
public struct Barcode: Equatable, Sendable {
    public let value: String
    public init(_ value: String) throws {
        guard [8,12,13].contains(value.count), value.utf8.allSatisfy({ (48...57).contains($0) }) else { throw OFFError.invalidBarcode }
        let digits = value.utf8.map { Int($0 - 48) }
        let sum = digits.dropLast().reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset % 2 == 0 ? 3 : 1) }
        guard (10 - sum % 10) % 10 == digits.last else { throw OFFError.invalidBarcode }
        self.value = value
    }
    /// UPC-A and zero-prefixed EAN-13 encode the same GTIN. No other zero stripping.
    public var equivalents: [String] {
        if value.count == 12 { return [value, "0" + value] }
        if value.count == 13 && value.first == "0" { return [value, String(value.dropFirst())] }
        return [value]
    }
}
public struct OFFResponse { public let data: Data; public let status: Int; public let retryAfter: String?
    public init(data: Data, status: Int = 200, retryAfter: String? = nil) { self.data = data; self.status = status; self.retryAfter = retryAfter }
}
public typealias OFFTransport = @Sendable (URLRequest) async throws -> OFFResponse
public struct OFFProduct: Sendable {
    public let barcode: String
    public let revision: String
    public let upstreamModifiedAt: Date
    public let retrievedAt: Date
    public let rawData: Data
    public let food: CatalogueFood?
    public let lastAttempt: Date
    public let lastSuccessfulCheck: Date
    public var sourceURL: URL { URL(string: "https://world.openfoodfacts.org/product/" + barcode)! }
    public var brands: String? { sourceRecord?["brands"] as? String }
    public var manufacturingPlaces: [String] { sourceRecord?["manufacturing_places_tags"] as? [String] ?? [] }
    public var hasApproximateNutrition: Bool {
        let nutrientKeys = ["energy-kcal", "proteins", "carbohydrates", "fat", "saturated-fat", "sugars", "fiber", "salt"]
        if let values = ((sourceRecord?["nutrition"] as? [String: Any])?["aggregated_set"] as? [String: Any])?["nutrients"] as? [String: Any] {
            return nutrientKeys.contains { key in
                (values[key] as? [String: Any])?["modifier"] as? String == "~"
            }
        }
        let nutriments = sourceRecord?["nutriments"] as? [String: Any] ?? [:]
        return nutrientKeys.contains { key in
            nutriments[key + "_modifier"] as? String == "~" ||
            nutriments[key + "_prepared_modifier"] as? String == "~"
        }
    }
    public var names: [String: String] {
        var result: [String: String] = [:]
        for language in ["sv","en","de"] { if let name = sourceRecord?["product_name_" + language] as? String { result[language] = name } }
        if result.isEmpty, let name = sourceRecord?["product_name"] as? String { result["und"] = name }
        return result
    }
    private var sourceRecord: [String: Any]? { ((try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any])?["product"] as? [String: Any] }
    public let quality = "community/unverified"
    public var provenance: [String: Provenance] {
        guard let ref = food?.provenanceRef else { return [:] }
        let object: [String: String] = ["providerID":"off", "sourceRecordID":barcode, "sourceURL":sourceURL.absoluteString, "upstreamVersion":revision, "retrievedAt":ISO8601DateFormatter().string(from:retrievedAt), "sourceLanguage":"und", "licenceReference":licenceURL.absoluteString, "transformationVersion":"off-conservative-v1", "reviewStatus":quality]
        guard let data = try? JSONSerialization.data(withJSONObject:object), let value = try? JSONDecoder().decode(Provenance.self,from:data) else { return [:] }
        return [ref:value]
    }
    public let attribution = "Open Food Facts contributors"
    public let licenceURL = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!
}
public struct OFFNameEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let barcode: String
    public let names: [String: String]
    public let markets: [String]
    public let brand: String?
    public let energyKcal100g: Double?
    public let isApproximate: Bool?
    public var id: String { barcode }
    public var searchableNames: [String] { Array(names.values) + [brand].compactMap { $0 } }

    public init(
        barcode: String,
        names: [String: String],
        markets: [String],
        brand: String? = nil,
        energyKcal100g: Double? = nil,
        isApproximate: Bool? = nil
    ) {
        self.barcode = barcode
        self.names = names
        self.markets = markets
        self.brand = brand
        self.energyKcal100g = energyKcal100g
        self.isApproximate = isApproximate
    }

    public func displayName(language: String) -> String {
        names[language] ?? names["en"] ?? names["sv"] ?? names["de"] ?? names["und"] ?? barcode
    }
}
public struct OFFSyncItem: Sendable { public let barcode: String; public let changed: Bool; public let error: String? }
public struct OFFSyncReport: Sendable {
    public let items: [OFFSyncItem]
    public init(items: [OFFSyncItem]) { self.items = items }
    public var failedCount: Int { items.filter { $0.error != nil }.count }
    public var isComplete: Bool { failedCount == 0 }
}

/// A separate cache database. Nothing here writes bundled catalogues, private overlays or meal snapshots.
public actor OFFLibrary {
    private let db: DatabaseQueue
    private let transport: OFFTransport
    private let clock: @Sendable () -> Date
    private let userAgent: String
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var lastSearchRequestAt: Date?
    private var blockedUntil: Date?
    private var lastRequestAt: Date?
    private var fetching = false
    public init(databaseURL: URL, transport: OFFTransport? = nil, clock: @escaping @Sendable () -> Date = { Date() }, userAgent: String = "SimpleFoods/0.2", sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var excludedDirectory = directory
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(directoryValues)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        self.db = try DatabaseQueue(path: databaseURL.path); self.clock = clock; self.userAgent = userAgent; self.sleep = sleep
        self.transport = transport ?? { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 45
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard data.count <= 2_000_000 else { throw OFFError.malformed }
            guard let response = response as? HTTPURLResponse else { throw OFFError.malformed }
            return OFFResponse(data: data, status: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
        }
        try db.write { db in
            let version = try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
            guard (0...3).contains(version) else { throw OFFError.unsupportedSchema }
            try db.execute(sql: "PRAGMA user_version = 3")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS off_revision (id TEXT PRIMARY KEY, code TEXT NOT NULL, rev TEXT NOT NULL, modified REAL NOT NULL, raw BLOB NOT NULL, fetched REAL NOT NULL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS off_current (code TEXT PRIMARY KEY, revision_id TEXT REFERENCES off_revision(id), attempt REAL NOT NULL, success REAL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS off_name_index (barcode TEXT PRIMARY KEY, payload BLOB NOT NULL, search_text TEXT NOT NULL, markets TEXT NOT NULL)")
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS off_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        }
        try Self.seedBundledNames(into: db)
        var protectedURL = databaseURL
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        #if os(iOS)
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
        #endif
    }
    public func names(query: String, language: String, market: String?, limit: Int? = nil) throws -> [OFFNameEntry] {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: language))
        var conditions: [String] = []
        var arguments = StatementArguments()
        if !needle.isEmpty {
            let terms = needle.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { $0.count > 1 }
            let needles = terms.count > 1 ? [needle] + terms : [needle]
            conditions.append("(" + Array(repeating: "search_text LIKE ?", count: needles.count).joined(separator: " OR ") + ")")
            for searchNeedle in needles {
                arguments += ["%\(searchNeedle)%"]
            }
        }
        if let market {
            conditions.append("markets LIKE ?")
            arguments += ["%|\(market)|%"]
        }
        let whereClause = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
        let entries: [OFFNameEntry] = try db.read {
            try Data.fetchAll($0, sql: "SELECT payload FROM off_name_index\(whereClause)", arguments: arguments)
                .compactMap { try? JSONDecoder().decode(OFFNameEntry.self, from: $0) }
        }
        let locale = Locale(identifier: language)
        let ranked: [(entry: OFFNameEntry, name: String, rank: Int)] = entries.compactMap { entry in
            let name = entry.displayName(language: language)
            guard let rank = FoodSearchRanking.rank(displayName: name, searchableNames: entry.searchableNames, query: query, locale: locale) else { return nil }
            return (entry: entry, name: name, rank: rank)
        }
        let sorted = ranked.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            return left.name.compare(right.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric], range: nil, locale: locale) == .orderedAscending
        }
        return limit.map { Array(sorted.prefix(max(1, $0)).map(\.entry)) } ?? sorted.map(\.entry)
    }
    public func name(barcode: String) throws -> OFFNameEntry? {
        let validated = try Barcode(barcode)
        return try db.read { database in
            for code in validated.equivalents {
                if let payload = try Data.fetchOne(database, sql: "SELECT payload FROM off_name_index WHERE barcode=?", arguments: [code]) {
                    return try JSONDecoder().decode(OFFNameEntry.self, from: payload)
                }
            }
            return nil
        }
    }

    private static func seedBundledNames(into db: DatabaseQueue) throws {
        guard let url = Bundle.module.url(forResource: "OFFNameIndex", withExtension: "jsonl") else { return }
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let current = try db.read { try String.fetchOne($0, sql: "SELECT value FROM off_metadata WHERE key='nameIndexDigest'") }
        guard current != digest else { return }
        let decoder = JSONDecoder()
        let entries = data.split(separator: 0x0A).compactMap { try? decoder.decode(OFFNameEntry.self, from: Data($0)) }
        try db.write { database in
            try database.execute(sql: "DELETE FROM off_name_index")
            for entry in entries {
                let searchText = ([entry.barcode] + Array(entry.names.values) + [entry.brand].compactMap { $0 }).joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                try database.execute(sql: "INSERT INTO off_name_index VALUES (?,?,?,?)", arguments: [entry.barcode, try JSONEncoder().encode(entry), searchText, "|" + entry.markets.joined(separator: "|") + "|"])
            }
            try database.execute(sql: "INSERT INTO off_metadata VALUES ('nameIndexDigest',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", arguments: [digest])
        }
    }
    public func cached(barcode: String) throws -> OFFProduct? {
        let barcode = try Barcode(barcode)
        return try db.read { db in
            for code in barcode.equivalents {
                if let row = try Row.fetchOne(db, sql: "SELECT r.*, c.attempt, c.success FROM off_current c JOIN off_revision r ON r.id=c.revision_id WHERE c.code=?", arguments: [code]) {
                    let raw: Data = row["raw"]; let code: String = row["code"]; let rev: String = row["rev"]
                    return OFFProduct(barcode: code, revision: rev, upstreamModifiedAt: Date(timeIntervalSince1970: row["modified"]), retrievedAt: Date(timeIntervalSince1970: row["fetched"]), rawData: raw, food: try Self.map(raw, code: code, revision: rev), lastAttempt: Date(timeIntervalSince1970: row["attempt"]), lastSuccessfulCheck: Date(timeIntervalSince1970: row["success"]))
                }
            }
            return nil
        }
    }
    public func cachedProducts() throws -> [OFFProduct] {
        let codes = try db.read { try String.fetchAll($0, sql: "SELECT code FROM off_current WHERE revision_id IS NOT NULL ORDER BY code") }
        return try codes.compactMap { try cached(barcode: $0) }
    }
    /// Removes every locally cached trace of a product, including its search
    /// index entry and all downloaded revisions.
    public func purgeCachedProduct(barcode: String) throws {
        let codes = try Barcode(barcode).equivalents
        try db.write { database in
            for code in codes {
                try database.execute(sql: "DELETE FROM off_current WHERE code=?", arguments: [code])
                try database.execute(sql: "DELETE FROM off_revision WHERE code=?", arguments: [code])
                try database.execute(sql: "DELETE FROM off_name_index WHERE barcode=?", arguments: [code])
            }
        }
    }
    public func refresh(barcode: String, language: String = "sv") async throws -> OFFProduct {
        let validated = try Barcode(barcode)
        return try await fetch(try cached(barcode: validated.value)?.barcode ?? validated.value, language: language)
    }
    /// Local-first lookup: usable cached nutrition never starts a request. An
    /// unsupported cached snapshot is retried because OFF data may have been
    /// completed since it was downloaded.
    public func lookup(barcode: String, language: String = "sv") async throws -> OFFProduct {
        if let existing = try cached(barcode: barcode), existing.food != nil { return existing }
        let code = try Barcode(barcode).value
        return try await withThrowingTaskGroup(of: OFFProduct.self) { group in
            group.addTask { try await self.fetch(code, language: language) }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw OFFError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw OFFError.timeout }
            return result
        }
    }
    public func sync() async -> OFFSyncReport {
        guard !fetching else { return OFFSyncReport(items:[.init(barcode:"*",changed:false,error:"busy")]) }
        return await performTrackedSync()
    }
    private func performTrackedSync() async -> OFFSyncReport {
        let codes: [String]
        do { codes = try await db.read { try String.fetchAll($0, sql: "SELECT code FROM off_current WHERE revision_id IS NOT NULL ORDER BY code") } }
        catch { return OFFSyncReport(items: [.init(barcode: "*", changed: false, error: String(describing: error))]) }
        var items: [OFFSyncItem] = []
        for code in codes {
            do { let old = try cached(barcode: code); let current = try await fetch(code, language: "sv"); items.append(.init(barcode: code, changed: old?.revision != current.revision || old?.upstreamModifiedAt != current.upstreamModifiedAt || old?.rawData != current.rawData, error: nil)) }
            catch { items.append(.init(barcode: code, changed: false, error: String(describing: error))) }
        }
        return OFFSyncReport(items: items)
    }
    private func fetch(_ code: String, language: String) async throws -> OFFProduct {
        guard !fetching else { throw OFFError.busy }
        fetching = true; defer { fetching = false }
        let now = clock()
        if let blockedUntil, now < blockedUntil { throw OFFError.rateLimited(blockedUntil) }
        try await db.write { try $0.execute(sql: "INSERT INTO off_current(code,attempt) VALUES (?,?) ON CONFLICT(code) DO UPDATE SET attempt=MAX(attempt,excluded.attempt)", arguments: [code, now.timeIntervalSince1970]) }
        var parts = URLComponents(string: "https://world.openfoodfacts.org/api/v3/product/\(code)")!
        parts.queryItems = [URLQueryItem(name: "lc", value: ["sv","en","de"].contains(language) ? language : "en"), URLQueryItem(name: "fields", value: "code,product_name,product_name_sv,product_name_en,product_name_de,brands,nutrition,nutriments,nutrition_data_per,nutrition_data_prepared_per,product_quantity,product_quantity_unit,quantity,last_modified_t,rev,countries_tags,origins_tags,manufacturing_places_tags")]
        var request = URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData); request.httpMethod = "GET"; request.setValue(userAgent, forHTTPHeaderField: "User-Agent"); request.timeoutInterval = 30
        if let lastRequestAt {
            let wait = max(0, 4.1 - clock().timeIntervalSince(lastRequestAt))
            if wait > 0 { try await sleep(wait) }
        }
        lastRequestAt = clock()
        let response = try await transport(request)
        let completedAt = clock()
        if response.status == 429 {
            let seconds = response.retryAfter.flatMap(Double.init).flatMap { $0.isFinite ? max(1, $0) : nil } ?? 60
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            blockedUntil = response.retryAfter.flatMap(formatter.date(from:)).map { max(completedAt.addingTimeInterval(1), $0) } ?? completedAt.addingTimeInterval(seconds)
            throw OFFError.rateLimited(blockedUntil!)
        }
        if response.status == 404 { throw OFFError.notFound }
        guard response.status == 200 else { throw OFFError.http(response.status) }
        guard let envelope = try JSONSerialization.jsonObject(with: response.data) as? [String: Any], (envelope["status"] as? String == "success" || (envelope["status"] as? NSNumber)?.intValue == 1), let p = envelope["product"] as? [String: Any], let returned = p["code"] as? String, try Barcode(code).equivalents.contains(returned), let timestamp = p["last_modified_t"] as? NSNumber, let revNumber = p["rev"] as? NSNumber, CFGetTypeID(timestamp) != CFBooleanGetTypeID(), CFGetTypeID(revNumber) != CFBooleanGetTypeID(), timestamp.doubleValue.rounded() == timestamp.doubleValue, revNumber.doubleValue.rounded() == revNumber.doubleValue, timestamp.doubleValue > 0, timestamp.doubleValue <= completedAt.timeIntervalSince1970, revNumber.intValue > 0 else { throw OFFError.malformed }
        let modified = timestamp.doubleValue; let rev = revNumber.stringValue
        let old = try cached(barcode: code)
        if let old, modified < old.upstreamModifiedAt.timeIntervalSince1970 || (Int(rev) ?? 0) < (Int(old.revision) ?? 0) { throw OFFError.staleResponse }
        try await db.write { db in
            if old == nil || old!.revision != rev || old!.upstreamModifiedAt.timeIntervalSince1970 < modified || old!.rawData != response.data {
                let id = UUID().uuidString
                try db.execute(sql: "INSERT INTO off_revision VALUES (?,?,?,?,?,?)", arguments: [id, code, rev, modified, response.data, completedAt.timeIntervalSince1970])
                try db.execute(sql: "UPDATE off_current SET revision_id=? WHERE code=?", arguments: [id, code])
            }
            try db.execute(sql: "UPDATE off_current SET success=MAX(COALESCE(success,0),?) WHERE code=?", arguments: [completedAt.timeIntervalSince1970, code])
        }
        return try cached(barcode: code)!
    }
    private static func countryCodes(_ tags: [String]) -> [String] {
        let known = ["en:sweden":"SE", "en:germany":"DE", "en:italy":"IT", "en:france":"FR", "en:united-kingdom":"GB", "en:united-states":"US", "en:denmark":"DK", "en:norway":"NO", "en:finland":"FI"]
        return Array(Set(tags.compactMap { known[$0] })).sorted()
    }
    private static func map(_ raw: Data, code: String, revision: String) throws -> CatalogueFood? {
        guard let envelope = try JSONSerialization.jsonObject(with: raw) as? [String: Any], let p = envelope["product"] as? [String: Any] else { return nil }
        let aggregated = (p["nutrition"] as? [String: Any])?["aggregated_set"] as? [String: Any]
        let sourceNutrients = p["nutriments"] as? [String: Any] ?? [:]
        var candidates: [(basis: String, preparation: String, nutrients: [String: Any])] = []
        if let aggregated {
            guard let preparation = aggregated["preparation"] as? String,
                  ["as_sold", "prepared"].contains(preparation),
                  let per = aggregated["per"] as? String,
                  ["100g","100ml"].contains(per),
                  let values = aggregated["nutrients"] as? [String: Any] else { return nil }
            var nutrients: [String: Any] = [:]
            for (key, rawValue) in values {
                guard let value = rawValue as? [String: Any],
                      supportedModifier(value["modifier"] as? String),
                      value["source_per"] as? String == per,
                      value["source"] as? String == "packaging",
                      let direct = value["value"] as? NSNumber,
                      let unit = value["unit"] as? String else { continue }
                nutrients[key + "_100g"] = direct
                nutrients[key + "_unit"] = unit
                if let modifier = value["modifier"] as? String { nutrients[key + "_modifier"] = modifier }
            }
            candidates.append((per, preparation, nutrients))
        } else {
            if let per = p["nutrition_data_per"] as? String, ["100g", "100ml"].contains(per) {
                candidates.append((per, "as_sold", sourceNutrients))
            }
            if let per = p["nutrition_data_prepared_per"] as? String, ["100g", "100ml"].contains(per) {
                var prepared: [String: Any] = [:]
                for key in ["energy-kcal", "proteins", "carbohydrates", "fat", "saturated-fat", "sugars", "fiber", "salt"] {
                    for suffix in ["_100g", "_unit", "_modifier"] {
                        if let value = sourceNutrients[key + "_prepared" + suffix] {
                            prepared[key + suffix] = value
                        }
                    }
                }
                candidates.append((per, "prepared", prepared))
            }
        }
        let immutableRevision = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let ref = "off:\(code):\(immutableRevision)"
        var names: [String: String] = [:]
        for language in ["sv","en","de"] { if let name = p["product_name_\(language)"] as? String, !name.isEmpty { names[language] = name } }
        if names.isEmpty, let name = p["product_name"] as? String, !name.isEmpty { names["und"] = name }
        guard !names.isEmpty else { return nil }
        let fields: [(Nutrient, String, String)] = [(.energy,"energy-kcal","kcal"),(.protein,"proteins","g"),(.carbohydrateAvailable,"carbohydrates","g"),(.totalFat,"fat","g"),(.saturatedFat,"saturated-fat","g"),(.sugars,"sugars","g"),(.fibre,"fiber","g"),(.salt,"salt","g")]
        for candidate in candidates {
            // A generic legacy 100g marker plus volume package units is ambiguous; keep source only.
            if candidate.basis == "100g", let unit = p["product_quantity_unit"] as? String, ["ml","cl","l"].contains(unit) { continue }
            var nutrients: [String: Any] = [:]
            for (nutrient,key,unit) in fields {
                // No kJ->kcal, salt->sodium or carbohydrate-definition conversions.
                let modifier = candidate.nutrients[key + "_modifier"] as? String
                if supportedModifier(modifier), let declaredUnit = candidate.nutrients[key + "_unit"] as? String, declaredUnit == unit,
                   let number = candidate.nutrients[key + "_100g"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                   let decimal = try? DecimalAmount(number.stringValue) {
                    if decimal.value > 0 {
                        nutrients[nutrient.rawValue] = ["status": "known", "value": decimal.canonicalString, "unit": unit]
                    } else if decimal.value == 0 {
                        nutrients[nutrient.rawValue] = ["status": "knownZero", "value": decimal.canonicalString, "unit": unit]
                    } else {
                        nutrients[nutrient.rawValue] = ["status":"unknown", "reason":"notProvidedOrUnsupportedUnit", "unit":unit]
                    }
                } else {
                    nutrients[nutrient.rawValue] = ["status":"unknown", "reason":"notProvidedOrUnsupportedUnit", "unit":unit]
                }
            }
            let requiredNutrients: [Nutrient] = [.energy, .protein, .carbohydrateAvailable, .totalFat]
            guard requiredNutrients.allSatisfy({ nutrient in
                guard let value = nutrients[nutrient.rawValue] as? [String: Any],
                      let status = value["status"] as? String else { return false }
                return status == "known" || status == "knownZero"
            }) else { continue }
            let object: [String: Any] = ["id":["scope":"catalogue","namespace":"off","recordID":code], "revision":immutableRevision,"kind":"product","lifecycle":"active","names":names,"salesCountries":Self.countryCodes(p["countries_tags"] as? [String] ?? []), "manufacturingCountries":[], "ingredientOrigins":Self.countryCodes(p["origins_tags"] as? [String] ?? []), "barcodes":[code], "provenanceRef":ref,"profile":["profileRevision":immutableRevision,"basis":["quantity":"100","unit":candidate.basis == "100ml" ? "ml" : "g"],"preparation":candidate.preparation,"nutrients":nutrients,"portions":[],"provenanceRef":ref]]
            return try JSONDecoder().decode(CatalogueFood.self, from: JSONSerialization.data(withJSONObject: object))
        }
        return nil
    }

    private static func supportedModifier(_ modifier: String?) -> Bool {
        modifier == nil || modifier == "~"
    }
}
