import XCTest
import Foundation
import GRDB
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary

final class PersonalLibraryTests: XCTestCase {
    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("diary.sqlite") }
    private func sourceFoods() throws -> (CatalogueFood, CatalogueFood) {
        let catalogue = try CatalogueRepository.bundledDevelopment()
        let newest = try XCTUnwrap(catalogue.barcodeMatches("0000000000001").first)
        return (try catalogue.retainedFood(id: newest.id, revision: "r1"), newest)
    }
    private func profile(_ original: NutritionProfile, basis: NutritionBasis? = nil) throws -> NutritionProfile {
        try NutritionProfile(profileRevision: "personal-1", basis: basis ?? original.basis, preparation: original.preparation, density: original.density, nutrients: ["protein": try NutrientValue(status: .known, value: DecimalAmount("42"), unit: .g)], portions: original.portions, provenanceRef: "user-authored")
    }
    func testOverridesSurviveSourceUpdateAndResetUsesNewestBase() throws {
        let (v1, v2) = try sourceFoods()
        let database = url()
        let library = PersonalLibrary(store: try DiaryStore(databaseURL: database))
        let operation = UUID()
        let changedProfile = try PersonalLibrary.clearingNutrient(.sodium, in: profile(v1.profile))
        let saved = try library.saveOverlay(base: v1, names: ["sv": .set("Min korv"), "de": .clear], profile: .set(changedProfile), operationID: operation)
        XCTAssertEqual(try library.saveOverlay(base: v1, names: ["sv": .set("Min korv"), "de": .clear], profile: .set(changedProfile), operationID: operation), saved)
        let restarted = PersonalLibrary(store: try DiaryStore(databaseURL: database))
        let updated = try restarted.resolve(base: v2)
        XCTAssertEqual(updated.food.names["sv"], "Min korv")
        XCTAssertNil(updated.food.names["de"])
        XCTAssertEqual(updated.food.profile.nutrients["protein"]?.value?.canonicalString, "42")
        XCTAssertEqual(updated.food.profile.nutrients["sodium"]?.reason, "userCleared")
        XCTAssertEqual(updated.food.profile.nutrients["energy.declared"]?.reason, "userCleared")
        XCTAssertTrue(updated.sourceChanged)
        let reset = try restarted.resetOverlay(base: v2, expectedRevision: 1, operationID: UUID())
        XCTAssertEqual(reset.food, v2)
        XCTAssertFalse(reset.sourceChanged)
        XCTAssertFalse(reset.needsReview)
        XCTAssertEqual(reset.overlayRevision, 2)
    }
    func testBasisDriftKeepsEntireAcceptedOverrideAndNamesAreIndependent() throws {
        let (v1, v2) = try sourceFoods()
        let library = PersonalLibrary(store: try DiaryStore(databaseURL: url()))
        let saved = try library.saveOverlay(base: v1, names: ["sv": .set("Personligt")], profile: .set(profile(v1.profile)), operationID: UUID())
        let changed = CatalogueFood(id: v2.id, revision: "r3", kind: v2.kind, lifecycle: v2.lifecycle, names: v2.names, salesCountries: v2.salesCountries, manufacturingCountries: v2.manufacturingCountries, ingredientOrigins: v2.ingredientOrigins, barcodes: v2.barcodes, profile: try profile(v2.profile, basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .ml)), provenanceRef: v2.provenanceRef)
        let drifted = try library.resolve(base: changed)
        XCTAssertTrue(drifted.needsReview)
        XCTAssertEqual(drifted.food.profile, saved.food.profile)
        let clearedName = try library.saveOverlay(base: changed, names: ["sv": .inherit], expectedRevision: 1, operationID: UUID())
        XCTAssertEqual(clearedName.food.names["sv"], changed.names["sv"])
        XCTAssertEqual(clearedName.food.profile, saved.food.profile)
        XCTAssertTrue(clearedName.needsReview)
    }
    func testPersonalFoodRestartHideAndHistoryPinsRemain() throws {
        let (_, base) = try sourceFoods()
        let database = url()
        let store = try DiaryStore(databaseURL: database)
        let library = PersonalLibrary(store: store)
        let created = try library.savePersonal(kind: "ingredient", names: ["sv": "Mitt livsmedel"], authorLanguage: "sv", profile: profile(base.profile), operationID: UUID())
        let component = try MealComponent(food: created.food, generationID: UUID(), displayName: "Mitt livsmedel", language: "sv", quantity: LoggedQuantity(amount: DecimalAmount("100"), unit: .grams), fixtureOnly: false)
        let event = try store.save(MealDraft(eatenAt: Date(timeIntervalSince1970: 1_700_000_000), zoneID: "Europe/Stockholm", components: [component]), operationID: UUID())
        let restarted = PersonalLibrary(store: try DiaryStore(databaseURL: database))
        XCTAssertEqual(try restarted.personalFood(id: created.id), created)
        let hidden = try restarted.hidePersonal(id: created.id, expectedRevision: 1, operationID: UUID())
        XCTAssertTrue(hidden.hidden)
        XCTAssertTrue(try restarted.personalFoods().isEmpty)
        XCTAssertEqual(try restarted.personalFoods(includeHidden: true), [hidden])
        XCTAssertEqual(try restarted.personalHistory(id: created.id), [created, hidden])
        XCTAssertEqual(try store.events(localDate: event.localDate).first?.components, event.components)
    }
    func testSourceRemovingFallbackNameRetainsAcceptedProjectionForReview() throws {
        let (_, base) = try sourceFoods()
        let library = PersonalLibrary(store: try DiaryStore(databaseURL: url()))
        _ = try library.saveOverlay(base: base, names: ["sv": .clear, "de": .clear], operationID: UUID())
        let changed = CatalogueFood(id: base.id, revision: "r3", kind: base.kind, lifecycle: base.lifecycle, names: ["sv": "Only remaining source language"], salesCountries: base.salesCountries, manufacturingCountries: base.manufacturingCountries, ingredientOrigins: base.ingredientOrigins, barcodes: base.barcodes, profile: base.profile, provenanceRef: base.provenanceRef)
        let result = try library.resolve(base: changed)
        XCTAssertTrue(result.needsReview)
        XCTAssertEqual(result.food.names, ["en": base.names["en"]!])
    }
    func testExplicitSodiumClearDoesNotBecomeDerivedSaltValue() throws {
        let (_, base) = try sourceFoods()
        let cleared = try PersonalLibrary.clearingNutrient(.sodium, in: base.profile)
        let result = try NutritionCalculator.calculate(profile: cleared, quantity: .grams(DecimalAmount("100")))
        XCTAssertEqual(result[.sodium].completeness, .incomplete)
        XCTAssertEqual(result[.sodium].missingReasons, ["userCleared"])
        XCTAssertEqual(result[.sodium].knownSubtotal, 0)
    }
    func testRevisionConflictAndOperationPayloadConflict() throws {
        let (_, base) = try sourceFoods()
        let library = PersonalLibrary(store: try DiaryStore(databaseURL: url()))
        let operation = UUID()
        _ = try library.saveOverlay(base: base, names: ["en": .set("Mine")], operationID: operation)
        XCTAssertThrowsError(try library.saveOverlay(base: base, names: ["en": .set("Other")], operationID: operation)) { XCTAssertEqual($0 as? DiaryError, .operationConflict) }
        XCTAssertThrowsError(try library.saveOverlay(base: base, names: ["en": .clear], operationID: UUID())) { XCTAssertEqual($0 as? DiaryError, .staleRevision) }
        let created = try library.savePersonal(kind: "product", names: ["en": "Own product"], authorLanguage: "en", profile: profile(base.profile), operationID: UUID())
        XCTAssertThrowsError(try library.savePersonal(id: created.id, kind: "product", names: ["en": "New name"], authorLanguage: "en", profile: profile(base.profile), operationID: UUID())) { XCTAssertEqual($0 as? DiaryError, .staleRevision) }
    }
    func testV1MigrationPreservesDiaryAndWorkingDraftRecovery() throws {
        let (_, base) = try sourceFoods()
        let database = url()
        let component = try MealComponent(food: base, generationID: UUID(), displayName: "Snapshot", language: "en", quantity: LoggedQuantity(amount: DecimalAmount("10"), unit: .grams))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let oldDraft = MealDraft(eatenAt: date, zoneID: "UTC", components: [component])
        let event: MealEvent
        do {
            let store = try DiaryStore(databaseURL: database)
            event = try store.save(oldDraft, operationID: UUID())
            try store.saveDraft(oldDraft)
        }
        // Recreate the exact v1 schema by removing only the new migration's
        // tables/column, retaining v1 data and its GRDB migration receipt.
        do {
            let db = try DatabaseQueue(path: database.path)
            try db.write { db in
                for name in ["personal_overlays", "overlay_history", "personal_foods", "personal_food_history", "personal_operations"] { try db.execute(sql: "DROP TABLE \(name)") }
                try db.execute(sql: "ALTER TABLE drafts DROP COLUMN saved_at")
                try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='private-v2-personal'")
            }
        }
        let reopened = try DiaryStore(databaseURL: database)
        XCTAssertEqual(try reopened.events(localDate: event.localDate), [event])
        XCTAssertEqual(try reopened.loadDraft(id: oldDraft.id), oldDraft)
        let rawState = Data(#"{"schemaVersion":1,"rawQuantity":"not-a-number","expectedEventRevision":7,"selectedOFFBarcode":"000123"}"#.utf8)
        let working = MealDraft(eatenAt: date, zoneID: "UTC", components: [], workingState: rawState, expectedEventRevision: 7)
        try reopened.saveDraft(working)
        let restarted = try DiaryStore(databaseURL: database)
        XCTAssertEqual(try restarted.drafts().first, working)
        XCTAssertEqual(try restarted.loadDraft(id: working.id)?.workingState, rawState)
        XCTAssertEqual(try restarted.loadDraft(id: working.id)?.expectedEventRevision, 7)
    }
}
