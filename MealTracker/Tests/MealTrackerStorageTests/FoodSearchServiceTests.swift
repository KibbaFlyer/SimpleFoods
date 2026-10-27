import Foundation
import Testing
import GRDB
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary
import MealTrackerOpenFoodFacts

struct FoodSearchServiceTests {
    private struct Fixture {
        let directory: URL
        let diary: DiaryStore
        let personal: PersonalLibrary
        let off: OFFLibrary
        let service: FoodSearchService
    }

    private func fixture(entries: [OFFNameEntry] = []) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let diary = try DiaryStore(databaseURL: directory.appendingPathComponent("diary.sqlite"))
        let personal = PersonalLibrary(store: diary)
        let offURL = directory.appendingPathComponent("off.sqlite")
        let off = try OFFLibrary(databaseURL: offURL, transport: { _ in throw URLError(.notConnectedToInternet) }, seedBundledNameIndex: false)
        let database = try DatabaseQueue(path: offURL.path)
        try database.write { db in
            for entry in entries {
                try db.execute(sql: "INSERT INTO off_name_index VALUES (?,?,?,?)", arguments: [entry.barcode, try JSONEncoder().encode(entry), "", "|" + entry.markets.joined(separator: "|") + "|"])
            }
        }
        let catalogue = try CatalogueRepository.bundledDevelopment()
        let slv = try LivsmedelsverketLibrary(databaseURL: directory.appendingPathComponent("slv.sqlite"))
        let service = FoodSearchService(catalogue: catalogue, personal: personal, diary: diary, off: off, livsmedelsverket: slv)
        return Fixture(directory: directory, diary: diary, personal: personal, off: off, service: service)
    }

    private func create(_ name: String, in fixture: Fixture) throws -> PersonalFood {
        let profile = try NutritionProfile(profileRevision: "test", basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g), preparation: "asEntered", density: nil, nutrients: [Nutrient.energy.rawValue: NutrientValue(status: .known, value: DecimalAmount("100"), unit: .kcal)], portions: [], provenanceRef: "personal.user")
        return try fixture.personal.savePersonal(id: UUID(), kind: "ingredient", names: ["en": name], authorLanguage: "en", profile: profile, operationID: UUID())
    }

    @Test func coverageBeforePersonalizationAndSourceFilter() async throws {
        let f = try fixture(entries: [OFFNameEntry(barcode: "3017620422003", names: ["en": "Whole wheat bread"], markets: ["SE"], brand: "Bakery")])
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let partial = try create("Bread", in: f)
        let full = try create("Whole wheat bread homemade", in: f)
        let history = FoodSearchHistory(store: f.diary)
        try history.setFavorite(true, food: partial.food)
        try history.recordSelection(food: partial.food, query: "whole wheat bread", language: "en")
        let results = try await f.service.search(query: "whole wheat bread", language: "en", market: nil)
        #expect(results.hits.first?.id != partial.food.id)
        #expect(results.hits.contains { $0.id == full.food.id })
        let onlyFavorites = try await f.service.search(query: "bread", language: "en", market: nil, favoritesOnly: true)
        #expect(onlyFavorites.hits.map(\.id) == [partial.food.id])
        let onlySource = try await f.service.search(query: "bread", language: "en", market: "SE", source: .openFoodFacts)
        #expect(onlySource.hits.count == 1)
        #expect(onlySource.hits.first?.nameEntry?.barcode == "3017620422003")
        #expect(try await f.service.search(query: "bread", language: "en", market: "DE", source: .openFoodFacts).hits.isEmpty)
    }

    @Test func queryHistoryAndFavoritesStayFreshWithoutRestart() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let usual = try create("Zebra bread", in: f)
        _ = try create("Bread", in: f)
        _ = try await f.service.search(query: "bread", language: "en", market: nil, source: .personal)
        let history = FoodSearchHistory(store: f.diary)
        try history.recordSelection(food: usual.food, query: " BRÉAD ", language: "en")
        let repeated = try await f.service.search(query: "bread", language: "en", market: nil, source: .personal)
        #expect(repeated.hits.first?.id == usual.food.id)
        try history.setFavorite(true, food: usual.food)
        #expect(try await f.service.search(query: "", language: "en", market: nil, favoritesOnly: true).hits.map(\.id) == [usual.food.id])
        try history.setFavorite(false, food: usual.food)
        #expect(try await f.service.search(query: "", language: "en", market: nil, favoritesOnly: true).hits.isEmpty)
        _ = try f.personal.savePersonal(id: usual.id, kind: "ingredient", names: ["en": "Milk"], authorLanguage: "en", profile: usual.food.profile, expectedRevision: usual.revision, operationID: UUID())
        #expect(try await f.service.search(query: "bread", language: "en", market: nil, source: .personal).hits.allSatisfy { $0.id != usual.food.id })
        #expect(try await f.service.search(query: "milk", language: "en", market: nil, source: .personal).hits.first?.id == usual.food.id)
    }

    @Test func usualFoodSurvivesCandidateCutoffAndResultsAreStable() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        for index in 0..<170 { _ = try create("Bread \(index)", in: f) }
        let usual = try create("Zebra bread", in: f)
        try FoodSearchHistory(store: f.diary).recordSelection(food: usual.food, query: "bread", language: "en")
        let first = try await f.service.search(query: "bread", language: "en", market: nil, source: .personal, limit: 21)
        let second = try await f.service.search(query: "bread", language: "en", market: nil, source: .personal, limit: 41)
        #expect(first.hits.first?.id == usual.food.id)
        #expect(first.hits.count == 21)
        #expect(first.hits.map(\.id) == Array(second.hits.prefix(21)).map(\.id))
    }

    @Test func alternateNamesBrandsTyposAndPunctuation() async throws {
        let f = try fixture(entries: [OFFNameEntry(barcode: "3017620422003", names: ["en": "Bread", "sv": "Bröd"], markets: ["SE"], brand: "Bakery")])
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let branded = try await f.service.search(query: "bakery brod", language: "en", market: "SE")
        #expect(branded.hits.first?.nameEntry?.barcode == "3017620422003")
        let typo = try await f.service.search(query: "braed", language: "en", market: "SE")
        #expect(typo.correctedQuery == "bread")
        #expect(typo.hits.count == 1)
        #expect(try await f.service.search(query: "%_\"", language: "en", market: "SE").hits.isEmpty)
    }
}
