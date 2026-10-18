import Foundation
import GRDB
import MealTrackerCore

public enum LivsmedelsverketError: Error {
    case malformedResponse
    case http(Int)
    case responseTooLarge
}

public struct LivsmedelsverketSyncReport: Sendable {
    public let available: Int
    public let changed: Int
    public let failed: Int
}

public func livsmedelsverketProvenance(for food: CatalogueFood) -> [String: Provenance] {
    guard case let .catalogue(namespace, recordID) = food.id, namespace == "livsmedelsverket" else { return [:] }
    let value: [String: String] = [
        "providerID": namespace,
        "sourceRecordID": recordID,
        "sourceURL": "https://dataportal.livsmedelsverket.se/livsmedel/api/v1/livsmedel/\(recordID)",
        "upstreamVersion": food.revision,
        "retrievedAt": ISO8601DateFormatter().string(from: Date()),
        "sourceLanguage": "sv",
        "licenceReference": "https://creativecommons.org/licenses/by/4.0/deed.sv",
        "transformationVersion": "mealtracker-slv-v1",
        "reviewStatus": "government-source"
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let provenance = try? JSONDecoder().decode(Provenance.self, from: data) else { return [:] }
    return [food.provenanceRef: provenance]
}

/// Persistent mirror of Livsmedelsverket's food database. Source records remain
/// immutable here; user customizations are applied by `PersonalLibrary`.
public actor LivsmedelsverketLibrary {
    private struct Page: Decodable {
        struct Meta: Decodable { let totalRecords: Int }
        struct Item: Decodable {
            let nummer: Int
            let version: String
            let namn: String
        }
        let meta: Meta
        let livsmedel: [Item]

        enum CodingKeys: String, CodingKey { case meta = "_meta", livsmedel }
    }

    private struct NutrientRecord: Decodable {
        let euroFIRkod: String
        let varde: Double
        let enhet: String
        let vardetypkod: String?
    }

    private let db: DatabaseQueue
    private let session: URLSession
    private let userAgent: String
    private let sleep: @Sendable (Duration) async throws -> Void
    private let baseURL = URL(string: "https://dataportal.livsmedelsverket.se/livsmedel/api/v1/")!

    public init(
        databaseURL: URL,
        session: URLSession? = nil,
        userAgent: String = "SimpleFoods/1.0",
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var excludedDirectory = directory
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(directoryValues)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        db = try DatabaseQueue(path: databaseURL.path)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
        self.userAgent = userAgent
        self.sleep = sleep
        try db.write { database in
            try database.execute(sql: "CREATE TABLE IF NOT EXISTS slv_food (number INTEGER PRIMARY KEY, source_version TEXT NOT NULL, payload BLOB NOT NULL, updated REAL NOT NULL)")
        }
        #if os(iOS)
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
        #endif
    }

    public func foods() throws -> [CatalogueFood] {
        try db.read { database in
            try Data.fetchAll(database, sql: "SELECT payload FROM slv_food ORDER BY number")
                .compactMap { try? JSONDecoder().decode(CatalogueFood.self, from: $0) }
        }
    }

    /// Fetches the complete index, then downloads nutrition only for new or changed records.
    public func sync() async -> LivsmedelsverketSyncReport {
        do {
            let index = try await fetchIndex()
            let versions = try await db.read { database in
                Dictionary(uniqueKeysWithValues: try Row.fetchAll(database, sql: "SELECT number, source_version FROM slv_food").map {
                    ($0["number"] as Int, $0["source_version"] as String)
                })
            }
            let changed = index.filter { versions[$0.nummer] != $0.version }
            var imported = 0
            var failures = 0

            // Keep pressure on the public service modest while avoiding thousands
            // of serial round trips on the initial import.
            for start in stride(from: 0, to: changed.count, by: 4) {
                guard !Task.isCancelled else { break }
                let batch = Array(changed[start..<min(start + 4, changed.count)])
                let results = await withTaskGroup(of: (Page.Item, Result<CatalogueFood, Error>).self) { group in
                    for item in batch {
                        group.addTask { [self] in
                            do {
                                let url = baseURL.appending(path: "livsmedel/\(item.nummer)/naringsvarden").appending(queryItems: [.init(name: "sprak", value: "1")])
                                let data = try await request(url, maximumBytes: 1_000_000)
                                let values = try JSONDecoder().decode([NutrientRecord].self, from: data)
                                return (item, Result { try Self.food(item: item, values: values) })
                            } catch { return (item, .failure(error)) }
                        }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
                for (item, result) in results {
                    switch result {
                    case let .success(food):
                        do {
                            let payload = try JSONEncoder().encode(food)
                            try await db.write { database in
                                try database.execute(sql: "INSERT INTO slv_food VALUES (?,?,?,?) ON CONFLICT(number) DO UPDATE SET source_version=excluded.source_version,payload=excluded.payload,updated=excluded.updated", arguments: [item.nummer, item.version, payload, Date().timeIntervalSince1970])
                            }
                            imported += 1
                        } catch { failures += 1 }
                    case .failure: failures += 1
                    }
                }
            }
            return .init(available: index.count, changed: imported, failed: failures)
        } catch {
            return .init(available: (try? foods().count) ?? 0, changed: 0, failed: 1)
        }
    }

    private func fetchIndex() async throws -> [Page.Item] {
        var offset = 0
        let limit = 500
        var result: [Page.Item] = []
        while true {
            let url = baseURL.appending(path: "livsmedel").appending(queryItems: [
                .init(name: "offset", value: String(offset)),
                .init(name: "limit", value: String(limit)),
                .init(name: "sprak", value: "1")
            ])
            let data = try await request(url, maximumBytes: 2_000_000)
            let page = try JSONDecoder().decode(Page.self, from: data)
            guard page.meta.totalRecords >= 0,
                  page.meta.totalRecords <= 10_000,
                  page.livsmedel.count <= limit,
                  page.livsmedel.allSatisfy({ $0.nummer > 0 && !$0.version.isEmpty && !$0.namn.isEmpty }) else {
                throw LivsmedelsverketError.malformedResponse
            }
            result.append(contentsOf: page.livsmedel)
            offset += page.livsmedel.count
            if offset >= page.meta.totalRecords || page.livsmedel.isEmpty { return result }
        }
    }

    private func request(_ url: URL, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard data.count <= maximumBytes else { throw LivsmedelsverketError.responseTooLarge }
                guard let response = response as? HTTPURLResponse else { throw LivsmedelsverketError.malformedResponse }
                if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                    guard attempt < 2 else { throw LivsmedelsverketError.http(response.statusCode) }
                    try await sleep(retryDelay(response: response, attempt: attempt))
                    continue
                }
                guard response.statusCode == 200 else { throw LivsmedelsverketError.http(response.statusCode) }
                return data
            } catch let error as LivsmedelsverketError {
                throw error
            } catch {
                lastError = error
                guard attempt < 2 else { throw error }
                try await sleep(.seconds(1 << attempt))
            }
        }
        throw lastError ?? LivsmedelsverketError.malformedResponse
    }

    private func retryDelay(response: HTTPURLResponse, attempt: Int) -> Duration {
        if let value = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Int(value), seconds > 0 {
            return .seconds(min(seconds, 60))
        }
        return .seconds(1 << attempt)
    }

    private static func food(item: Page.Item, values: [NutrientRecord]) throws -> CatalogueFood {
        let mappings: [String: Nutrient] = ["PROT": .protein, "FAT": .totalFat, "CHO": .carbohydrateAvailable, "FIBT": .fibre, "SUGAR": .sugars, "FASAT": .saturatedFat, "NACL": .salt, "NA": .sodium]
        var nutrients: [String: NutrientValue] = [:]
        for value in values {
            let nutrient: Nutrient?
            if value.euroFIRkod == "ENERC", value.enhet.lowercased() == "kcal" { nutrient = .energy }
            else { nutrient = mappings[value.euroFIRkod] }
            guard let nutrient, value.varde.isFinite, value.varde >= 0 else { continue }
            let amount = try DecimalAmount(String(value.varde))
            nutrients[nutrient.rawValue] = try NutrientValue(status: value.varde == 0 ? .knownZero : .known, value: amount, unit: nutrient.unit)
        }
        guard !nutrients.isEmpty else { throw LivsmedelsverketError.malformedResponse }
        let reference = "livsmedelsverket-\(item.nummer)-\(item.version)"
        let profile = try NutritionProfile(profileRevision: item.version, basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g), preparation: "other", density: nil, nutrients: nutrients, portions: [], provenanceRef: reference)
        return CatalogueFood(id: .catalogue(namespace: "livsmedelsverket", recordID: String(item.nummer)), revision: item.version, kind: "ingredient", lifecycle: "active", names: ["sv": item.namn], salesCountries: ["SE"], manufacturingCountries: [], ingredientOrigins: ["SE"], barcodes: [], profile: profile, provenanceRef: reference)
    }
}
