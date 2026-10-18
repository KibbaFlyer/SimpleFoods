import XCTest
import GRDB
import MealTrackerCatalog
import MealTrackerCore
import MealTrackerDiary

final class SavedMealStorageTests: XCTestCase {
    private func databaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("diary.sqlite")
    }

    private func ingredient() throws -> MealComponent {
        let catalogue = try CatalogueRepository.bundledDevelopment()
        let profile = try NutritionProfile(
            profileRevision: "saved-meal-test-r1",
            basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g),
            preparation: "test",
            density: nil,
            nutrients: [
                Nutrient.energy.rawValue: NutrientValue(status: .known, value: DecimalAmount("100"), unit: .kcal)
            ],
            portions: [],
            provenanceRef: "test"
        )
        let food = CatalogueFood(
            id: .personal(UUID()),
            revision: "1",
            kind: "ingredient",
            lifecycle: "active",
            names: ["en": "Test ingredient"],
            salesCountries: [],
            manufacturingCountries: [],
            ingredientOrigins: [],
            barcodes: [],
            profile: profile,
            provenanceRef: "test"
        )
        return try MealComponent(
            food: food,
            generationID: catalogue.generationID,
            displayName: "Test ingredient",
            language: "en",
            quantity: LoggedQuantity(amount: DecimalAmount("200"), unit: .grams)
        )
    }

    private func draft(name: String = "Test meal", tags: [String] = ["weekday"], servings: String = "4") throws -> SavedMealDraft {
        try SavedMealDraft(
            name: name,
            tags: tags,
            servingsProduced: DecimalAmount(servings),
            ingredients: [try ingredient()]
        )
    }

    func testSavedMealCRUDPersistsHistoryAndOperationReceipts() throws {
        let url = databaseURL()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = createdAt.addingTimeInterval(60)
        let deletedAt = updatedAt.addingTimeInterval(60)
        let createOperation = UUID()
        let initialDraft = try draft()

        let created: SavedMeal
        do {
            let store = try DiaryStore(databaseURL: url)
            created = try store.createSavedMeal(initialDraft, operationID: createOperation, now: createdAt)
            XCTAssertEqual(try store.createSavedMeal(initialDraft, operationID: createOperation, now: deletedAt), created)
            XCTAssertEqual(created.revision, 1)
            XCTAssertEqual(created.createdAt, createdAt)
            XCTAssertEqual(created.updatedAt, createdAt)
            XCTAssertEqual(try store.savedMeals(), [created])

            let revisedDraft = try draft(name: "Updated meal", tags: ["dinner"], servings: "2")
            let updated = try store.updateSavedMeal(
                id: created.id,
                draft: revisedDraft,
                expectedRevision: created.revision,
                operationID: UUID(),
                now: updatedAt
            )
            XCTAssertEqual(updated.revision, 2)
            XCTAssertEqual(updated.createdAt, createdAt)
            XCTAssertEqual(updated.updatedAt, updatedAt)
            XCTAssertEqual(updated.name, "Updated meal")
            XCTAssertThrowsError(try store.updateSavedMeal(id: created.id, draft: revisedDraft, expectedRevision: 1, operationID: UUID())) {
                XCTAssertEqual($0 as? DiaryError, .staleRevision)
            }

            let deleteOperation = UUID()
            let deleted = try store.deleteSavedMeal(id: created.id, expectedRevision: updated.revision, operationID: deleteOperation, now: deletedAt)
            XCTAssertEqual(try store.deleteSavedMeal(id: created.id, expectedRevision: updated.revision, operationID: deleteOperation, now: createdAt), deleted)
            XCTAssertEqual(deleted.revision, 3)
            XCTAssertEqual(deleted.deletedAt, deletedAt)
            XCTAssertTrue(try store.savedMeals().isEmpty)
            XCTAssertEqual(try store.savedMealHistory(id: created.id), [created, updated, deleted])
        }

        let restarted = try DiaryStore(databaseURL: url)
        let deleted = try XCTUnwrap(try restarted.savedMeal(id: created.id))
        XCTAssertEqual(deleted.revision, 3)
        XCTAssertEqual(deleted.deletedAt, deletedAt)
        XCTAssertTrue(try restarted.savedMeals().isEmpty)
    }

    func testServingScalingUsesTheProducedServingCountAndRejectsDeletedMeals() throws {
        let store = try DiaryStore(databaseURL: databaseURL())
        let meal = try store.createSavedMeal(try draft(), operationID: UUID())

        let components = try meal.components(forServings: DecimalAmount("1.5"))
        XCTAssertEqual(components.count, 1)
        XCTAssertEqual(components[0].quantity.amount, try DecimalAmount("75"))
        XCTAssertEqual(components[0].quantity.unit, .grams)

        let deleted = try store.deleteSavedMeal(id: meal.id, expectedRevision: meal.revision, operationID: UUID())
        XCTAssertThrowsError(try deleted.components(forServings: DecimalAmount("1"))) {
            XCTAssertEqual($0 as? DiaryError, .invalidInput)
        }
    }

    func testV2DatabaseMigratesSavedMealTablesOnce() throws {
        let url = databaseURL()
        _ = try DiaryStore(databaseURL: url)

        let database = try DatabaseQueue(path: url.path)
        try database.write { db in
            try db.execute(sql: "DROP TABLE saved_meal_operations")
            try db.execute(sql: "DROP TABLE saved_meal_history")
            try db.execute(sql: "DROP TABLE saved_meals")
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='private-v3-saved-meals'")
        }

        let migrated = try DiaryStore(databaseURL: url)
        XCTAssertTrue(try migrated.savedMeals().isEmpty)
        let saved = try migrated.createSavedMeal(try draft(), operationID: UUID())
        XCTAssertEqual(try migrated.savedMeal(id: saved.id), saved)

        _ = try DiaryStore(databaseURL: url)
        XCTAssertEqual(try database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier='private-v3-saved-meals'") }, 1)
    }
}
