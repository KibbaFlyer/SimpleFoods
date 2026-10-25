import Foundation
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerOpenFoodFacts

public enum FoodSearchSource: String, CaseIterable, Identifiable, Sendable {
    case all, openFoodFacts, personal, livsmedelsverket
    public var id: String { rawValue }

    var indexValue: String? {
        switch self {
        case .all: nil
        case .openFoodFacts: "off"
        case .personal: "personal"
        case .livsmedelsverket: "livsmedelsverket"
        }
    }
}

public struct FoodSearchHit: Identifiable, Sendable {
    public let food: CatalogueFood?
    public let nameEntry: OFFNameEntry?
    public var id: FoodID { food?.id ?? .catalogue(namespace: "off", recordID: nameEntry?.barcode ?? "") }

    public init(food: CatalogueFood) { self.food = food; self.nameEntry = nil }
    public init(nameEntry: OFFNameEntry) { self.food = nil; self.nameEntry = nameEntry }
}

public struct FoodSearchPage: Sendable {
    public let hits: [FoodSearchHit]
    public let preferences: [FoodID: FoodSearchPreference]
    public let correctedQuery: String?
    public var foods: [CatalogueFood] { hits.compactMap(\.food) }
    public var openFoodFactsNames: [OFFNameEntry] { hits.compactMap(\.nameEntry) }
}

/// One ranking and candidate-retrieval path for every food picker. All database
/// work, normalization, decoding and sorting execute outside the main actor.
public actor FoodSearchService {
    private let catalogue: CatalogueRepository
    private let personal: PersonalLibrary
    private let history: FoodSearchHistory
    private let off: OFFLibrary
    private let livsmedelsverket: LivsmedelsverketLibrary
    private var index: FoodNameSearchIndex?
    private var records: [String: Record] = [:]
    private var preferences: [FoodID: FoodSearchPreference] = [:]
    private var loadedRevision: Int64?
    private var sourceRevision = 0
    private var loadedSourceRevision = -1

    private struct SearchKey: Hashable {
        let query: String
        let language: String
        let market: String?
        let source: String
        let favoritesOnly: Bool
        let revision: Int64?
        let sourceRevision: Int
    }
    private var visibleResults: [SearchKey: [FoodID]] = [:]

    private struct Record {
        let food: CatalogueFood
        let names: [String: String]
        let brand: String
        let source: String
        let markets: [String]
    }

    private struct Ranked {
        let hit: FoodSearchHit
        let name: String
        let missingTerms: Int
        let textRank: Int
        let priority: Int
        let recency: Date
        let correction: String?
    }

    public init(catalogue: CatalogueRepository, personal: PersonalLibrary, diary: DiaryStore, off: OFFLibrary, livsmedelsverket: LivsmedelsverketLibrary) {
        self.catalogue = catalogue
        self.personal = personal
        self.history = FoodSearchHistory(store: diary)
        self.off = off
        self.livsmedelsverket = livsmedelsverket
    }

    public func invalidateSources() { sourceRevision += 1 }

    private static func key(_ id: FoodID) -> String {
        switch id {
        case let .catalogue(namespace, recordID): "catalogue:\(namespace):\(recordID)"
        case let .personal(id): "personal:\(id.uuidString)"
        }
    }

    private func refresh() async throws {
        let revision = try history.revision()
        guard index == nil || loadedRevision != revision || loadedSourceRevision != sourceRevision else { return }
        let capturedSourceRevision = sourceRevision
        let products = try await off.cachedProducts()
        let slv = try await livsmedelsverket.foods()
        try Task.checkCancellation()
        let personalFoods = try personal.personalFoods().map(\.food)
        let storedPreferences = try history.preferences(query: "", language: "en")
        var foods = try catalogue.search(query: "") + slv + products.compactMap(\.food) + personalFoods
        var known = Set(foods.map(\.id))
        for preference in storedPreferences.values {
            guard case .catalogue = preference.food.id, known.insert(preference.food.id).inserted else { continue }
            foods.append(preference.food)
        }
        let productsByID = Dictionary(uniqueKeysWithValues: products.compactMap { product in product.food.map { ($0.id, product) } })
        var next: [String: Record] = [:]
        for base in foods {
            try Task.checkCancellation()
            let food = try personal.resolve(base: base).food
            var names = food.names
            var brand = productsByID[food.id]?.brands ?? ""
            let source: String
            let markets: [String]
            switch food.id {
            case .personal:
                source = "personal"; markets = ["SE", "DE"]
            case let .catalogue(namespace, barcode):
                source = namespace
                markets = namespace == "livsmedelsverket" ? ["SE"] : food.salesCountries
                if namespace == "off", let entry = try await off.name(barcode: barcode) {
                    names = entry.names.merging(names) { _, effective in effective }
                    if brand.isEmpty { brand = entry.brand ?? "" }
                }
            }
            next[Self.key(food.id)] = Record(food: food, names: names, brand: brand, source: source, markets: markets)
        }
        try Task.checkCancellation()
        let nextIndex = try FoodNameSearchIndex()
        try nextIndex.replace(with: next.map { key, record in
            FoodSearchDocument(id: key, source: record.source, names: record.names, brand: record.brand, markets: record.markets)
        })
        records = next
        index = nextIndex
        preferences = storedPreferences
        loadedRevision = revision
        loadedSourceRevision = capturedSourceRevision
    }

    public func search(query: String, language: String, market: String?, source: FoodSearchSource = .all, favoritesOnly: Bool = false, limit: Int = 21) async throws -> FoodSearchPage {
        try Task.checkCancellation()
        try await refresh()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, limit)
        let dates = try history.selectionDates(query: query, language: language)
        let requestPreferences = preferences.mapValues { preference in
            FoodSearchPreference(food: preference.food, lastUsed: preference.lastUsed, isFavorite: preference.isFavorite, lastSelectedForQuery: dates[preference.food.id])
        }
        guard !query.isEmpty || market != nil || source != .all || favoritesOnly else {
            return FoodSearchPage(hits: [], preferences: requestPreferences, correctedQuery: nil)
        }
        guard let index else { return FoodSearchPage(hits: [], preferences: requestPreferences, correctedQuery: nil) }
        // Overfetch a bounded candidate set for reranking. Personalized foods are
        // unioned separately so they cannot be lost behind this retrieval cutoff.
        let searchKey = SearchKey(query: query, language: language, market: market, source: source.rawValue, favoritesOnly: favoritesOnly, revision: loadedRevision, sourceRevision: loadedSourceRevision)
        let candidateLimit = max(160, limit * 4)
        let local = try index.candidates(query: query, language: language, market: market, source: source.indexValue, limit: candidateLimit)
        let requestRecords = records
        let localIDs = Set(local.ids).union(requestPreferences.keys.map(Self.key))
        let locale = Locale(identifier: language)
        let now = Date()
        var ranked: [FoodID: Ranked] = [:]

        func add(_ hit: FoodSearchHit, names: [String: String], brand: String, correction: String?) {
            let displayName = names[language] ?? names["en"] ?? names["sv"] ?? names["de"] ?? names["und"] ?? names.sorted { $0.key < $1.key }.first?.value ?? ""
            let searchable = Array(names.values) + [brand]
            var effectiveQuery = query
            var effectiveCorrection: String?
            var quality = Self.quality(query: query, displayName: displayName, names: searchable, locale: locale)
            if quality == nil, let correction {
                effectiveQuery = correction
                effectiveCorrection = correction
                quality = Self.quality(query: effectiveQuery, displayName: displayName, names: searchable, locale: locale)
            }
            guard let quality else { return }
            let preference = requestPreferences[hit.id]
            guard !favoritesOnly || preference?.isFavorite == true else { return }
            ranked[hit.id] = Ranked(hit: hit, name: displayName, missingTerms: quality.missing, textRank: quality.rank, priority: preference?.priority(now: now) ?? 0, recency: preference?.lastSelectedForQuery ?? preference?.lastUsed ?? .distantPast, correction: effectiveCorrection)
        }

        for key in localIDs {
            guard let record = requestRecords[key], source.indexValue == nil || record.source == source.indexValue,
                  market == nil || record.markets.contains(market ?? "") else { continue }
            add(FoodSearchHit(food: record.food), names: record.names, brand: record.brand, correction: local.correctedQuery)
        }
        if !favoritesOnly, source == .all || source == .openFoodFacts {
            let result = try await off.searchNames(query: query, language: language, market: market, limit: candidateLimit)
            try Task.checkCancellation()
            for entry in result.entries {
                let id = FoodID.catalogue(namespace: "off", recordID: entry.barcode)
                if let record = requestRecords[Self.key(id)] {
                    // Hydration must not change matching behavior or duplicate a result.
                    add(FoodSearchHit(food: record.food), names: record.names, brand: record.brand, correction: result.correctedQuery)
                } else {
                    add(FoodSearchHit(nameEntry: entry), names: entry.names, brand: entry.brand ?? "", correction: result.correctedQuery)
                }
            }
        }
        let hasLiteralMatches = ranked.values.contains { $0.correction == nil }
        var sorted = ranked.values.filter { !hasLiteralMatches || $0.correction == nil }.sorted { left, right in
            if left.missingTerms != right.missingTerms { return left.missingTerms < right.missingTerms }
            if left.priority != right.priority { return left.priority > right.priority }
            if left.priority > 0, left.recency != right.recency { return left.recency > right.recency }
            if left.textRank != right.textRank { return left.textRank < right.textRank }
            let order = left.name.compare(right.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: locale)
            if order != .orderedSame { return order == .orderedAscending }
            return Self.key(left.hit.id) < Self.key(right.hit.id)
        }
        try Task.checkCancellation()
        // Keep already displayed rows in place when a larger candidate window
        // introduces additional matches during pagination.
        if let previous = visibleResults[searchKey] {
            let byID = Dictionary(uniqueKeysWithValues: sorted.map { ($0.hit.id, $0) })
            let retained = previous.compactMap { byID[$0] }
            let retainedIDs = Set(retained.map { $0.hit.id })
            sorted = retained + sorted.filter { !retainedIDs.contains($0.hit.id) }
        }
        if visibleResults.count >= 8, visibleResults[searchKey] == nil { visibleResults.removeAll() }
        visibleResults[searchKey] = Array(sorted.prefix(limit)).map { $0.hit.id }
        return FoodSearchPage(hits: Array(sorted.prefix(limit)).map(\.hit), preferences: requestPreferences, correctedQuery: sorted.first?.correction)
    }

    private static func quality(query: String, displayName: String, names: [String], locale: Locale) -> (missing: Int, rank: Int)? {
        let terms = FoodNameSearchIndex.terms(query)
        guard !terms.isEmpty else { return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (0, 0) : nil }
        let haystack = names.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        let matched = terms.filter { haystack.contains($0) }.count
        guard matched > 0 else { return nil }
        let rank = FoodSearchRanking.rank(displayName: displayName, searchableNames: names, query: query, locale: locale) ?? 120
        return (terms.count - matched, rank)
    }
}
