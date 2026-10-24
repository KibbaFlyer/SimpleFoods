import Foundation
import Testing
import GRDB
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary

struct FoodSearchHistoryTests {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("diary.sqlite")
    }

    private func food() throws -> CatalogueFood {
        let profile = try NutritionProfile(
            profileRevision: "test", basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g),
            preparation: "asEntered", density: nil,
            nutrients: [Nutrient.energy.rawValue: NutrientValue(status: .known, value: DecimalAmount("250"), unit: .kcal)],
            portions: [], provenanceRef: "test"
        )
        return CatalogueFood(id: .catalogue(namespace: "test", recordID: UUID().uuidString), revision: "1", kind: "ingredient", lifecycle: "active", names: ["en": "Bread"], salesCountries: ["SE"], manufacturingCountries: [], ingredientOrigins: [], barcodes: [], profile: profile, provenanceRef: "test")
    }

    private func draft(food: CatalogueFood, date: Date) throws -> MealDraft {
        let catalogue = try CatalogueRepository.bundledDevelopment()
        let component = try MealComponent(food: food, generationID: catalogue.generationID, displayName: "Bread", language: "en", quantity: LoggedQuantity(amount: DecimalAmount("100"), unit: .grams))
        return MealDraft(eatenAt: date, zoneID: "UTC", components: [component])
    }

    @Test func selectionAndFavoritesPersistAndQueriesStayScoped() throws {
        let url = databaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let food = try food()
        let history = FoodSearchHistory(store: try DiaryStore(databaseURL: url))
        try history.recordSelection(food: food, query: "  BRÉAD  ", language: "en")
        try history.setFavorite(true, food: food)
        let reopened = FoodSearchHistory(store: try DiaryStore(databaseURL: url))
        let selected = try #require(reopened.preferences(query: "bread", language: "en")[food.id])
        #expect(selected.isFavorite)
        #expect(selected.lastSelectedForQuery != nil)
        #expect(selected.lastUsed == nil)
        #expect(!selected.isRecentlyUsed())
        #expect(selected.priority() == 3)
        #expect(try reopened.preferences(query: "milk", language: "en")[food.id]?.priority() == 2)
        #expect(try reopened.preferences(query: "bread", language: "sv")[food.id]?.lastSelectedForQuery == nil)
        try reopened.setFavorite(false, food: food)
        #expect(try reopened.preferences(query: "milk", language: "en")[food.id]?.priority() == 0)
        #expect(try reopened.preferences(query: "bread", language: "en")[food.id]?.priority() == 3)
    }

    @Test func successfulAddsAreRecentAndFailedSavesDoNotPolluteHistory() throws {
        let url = databaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try DiaryStore(databaseURL: url)
        let history = FoodSearchHistory(store: store)
        let food = try food()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = try draft(food: food, date: now.addingTimeInterval(-86_400))
        #expect(throws: DiaryError.injectedFailure) {
            try store.save(draft, operationID: UUID(), now: now, injectFailureBeforeCommit: true)
        }
        #expect(try history.preferences(query: "bread", language: "en").isEmpty)
        let operationID = UUID()
        _ = try store.save(draft, operationID: operationID, now: now)
        _ = try store.save(draft, operationID: operationID, now: now.addingTimeInterval(60))
        let preference = try #require(history.preferences(query: "bread", language: "en")[food.id])
        #expect(preference.lastUsed == now)
        #expect(preference.isRecentlyUsed(now: now.addingTimeInterval(86_400)))
        #expect(preference.priority(now: now) == 1)
        #expect(!preference.isRecentlyUsed(now: now.addingTimeInterval(31 * 86_400)))
    }

    @Test func migrationBackfillsExistingMeals() throws {
        let url = databaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let food = try food()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        do {
            let store = try DiaryStore(databaseURL: url)
            _ = try store.save(draft(food: food, date: now), operationID: UUID(), now: now)
        }
        // Recreate the pre-feature schema while retaining an existing diary entry.
        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.write { db in
                try db.execute(sql: "DROP TABLE food_search_queries; DROP TABLE food_search_history; DELETE FROM grdb_migrations WHERE identifier='private-v4-food-search'")
            }
        }
        let migrated = try DiaryStore(databaseURL: url)
        let preference = try #require(FoodSearchHistory(store: migrated).preferences(query: "bread", language: "en")[food.id])
        #expect(preference.lastUsed == now)
        #expect(preference.food.id == food.id)
    }
}
