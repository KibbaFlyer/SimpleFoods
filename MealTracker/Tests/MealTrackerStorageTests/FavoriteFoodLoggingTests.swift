import Foundation
import Testing
import MealTrackerCore
import MealTrackerDiary
import MealTrackerOpenFoodFacts

struct FavoriteFoodLoggingTests {
    @Test func favoriteCanBeLoggedAfterProductCacheIsCleared() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let responseData = try JSONSerialization.data(withJSONObject: [
            "status": "success",
            "product": [
                "code": "3017620422003", "rev": 1, "last_modified_t": 100,
                "product_name_en": "Bread", "nutrition_data_per": "100g",
                "product_quantity_unit": "g", "countries_tags": ["en:sweden"],
                "nutriments": [
                    "energy-kcal_100g": 250, "energy-kcal_unit": "kcal",
                    "proteins_100g": 8, "proteins_unit": "g",
                    "carbohydrates_100g": 45, "carbohydrates_unit": "g",
                    "fat_100g": 4, "fat_unit": "g"
                ]
            ]
        ])
        let off = try OFFLibrary(databaseURL: directory.appendingPathComponent("off.sqlite"), transport: { _ in OFFResponse(data: responseData) })
        let diary = try DiaryStore(databaseURL: directory.appendingPathComponent("diary.sqlite"))
        let history = FoodSearchHistory(store: diary)
        let first = try await off.lookup(barcode: "3017620422003", language: "en")
        let food = try #require(first.food)
        try history.setFavorite(true, food: food)
        try await off.purgeCachedProduct(barcode: first.barcode)
        #expect(try await off.cachedProducts().isEmpty)
        let favorite = try #require(history.preferences(query: "bread", language: "en")[food.id])
        #expect(favorite.isFavorite)

        // Resolve the complete product before constructing a diary component,
        // just as the app does when adding a history-backed search result.
        guard case let .catalogue(_, barcode) = favorite.food.id else {
            Issue.record("Expected an OFF favorite")
            return
        }
        let restored = try await off.lookup(barcode: barcode, language: "en")
        let restoredFood = try #require(restored.food)
        let component = try MealComponent(food: restoredFood, generationID: UUID(), displayName: "Bread", language: "en", quantity: LoggedQuantity(amount: DecimalAmount("50"), unit: .grams), provenance: restored.provenance)
        let event = try diary.save(MealDraft(eatenAt: Date(), zoneID: "UTC", components: [component]), operationID: UUID())
        #expect(event.components.first?.food.id == food.id)
        #expect(event.totals[Nutrient.energy.rawValue]?.knownSubtotal.value == 125)
    }
}
