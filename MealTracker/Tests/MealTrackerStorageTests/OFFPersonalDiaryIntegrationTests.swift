import Foundation
import XCTest
import MealTrackerCore
import MealTrackerDiary
import MealTrackerOpenFoodFacts

private actor IntegrationOFFServer {
    private var responses: [OFFResponse]
    private(set) var calls = 0
    init(responses: [OFFResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> OFFResponse {
        calls += 1
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.host, "world.openfoodfacts.org")
        XCTAssertEqual(request.url?.path, "/api/v3/product/3017620422003")
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        return responses.removeFirst()
    }
}

final class OFFPersonalDiaryIntegrationTests: XCTestCase {
    private func response(revision: Int, name: String, germanName: String, protein: Int, energy: Int, countries: [String]) throws -> OFFResponse {
        let product: [String: Any] = [
            "code": "3017620422003", "rev": revision, "last_modified_t": revision * 100,
            "product_name_en": name, "product_name_sv": "Svenskt källnamn \(revision)", "product_name_de": germanName,
            "nutrition_data_per": "100g", "product_quantity_unit": "g", "countries_tags": countries,
            "nutriments": [
                "energy-kcal_100g": energy, "energy-kcal_unit": "kcal",
                "proteins_100g": protein, "proteins_unit": "g",
                "carbohydrates_100g": 10, "carbohydrates_unit": "g",
                "fat_100g": 5, "fat_unit": "g",
                "salt_100g": 1, "salt_unit": "g"
            ]
        ]
        return OFFResponse(data: try JSONSerialization.data(withJSONObject: ["status": "success", "product": product], options: [.sortedKeys]))
    }

    func testOFFRefreshPreservesPersonalProjectionAndHistoricalDiarySnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceDatabase = directory.appendingPathComponent("source/off.sqlite")
        let privateDatabase = directory.appendingPathComponent("private/diary.sqlite")
        let server = IntegrationOFFServer(responses: [
            try response(revision: 1, name: "Initial source name", germanName: "Alter Quellenname", protein: 5, energy: 100, countries: ["en:sweden"]),
            try response(revision: 2, name: "Updated source name", germanName: "Neuer Quellenname", protein: 20, energy: 200, countries: ["en:sweden", "en:germany"])
        ])
        let off = try OFFLibrary(databaseURL: sourceDatabase, transport: { try await server.send($0) }, clock: { Date(timeIntervalSince1970: 1000) }, sleep: { _ in })
        let first = try await off.lookup(barcode: "3017620422003", language: "sv")
        let initialFood = try XCTUnwrap(first.food)
        XCTAssertEqual(initialFood.profile.nutrients["protein"]?.value?.canonicalString, "5")

        let diary = try DiaryStore(databaseURL: privateDatabase)
        let personal = PersonalLibrary(store: diary)
        var personalValues = initialFood.profile.nutrients
        personalValues["protein"] = try NutrientValue(status: .known, value: DecimalAmount("42"), unit: .g)
        personalValues["sodium"] = try NutrientValue(status: .unknown, unit: .mg, reason: "userCleared")
        let personalProfile = try NutritionProfile(profileRevision: "personal-profile-1", basis: initialFood.profile.basis, preparation: initialFood.profile.preparation, density: initialFood.profile.density, nutrients: personalValues, portions: initialFood.profile.portions, provenanceRef: initialFood.profile.provenanceRef)
        let accepted = try personal.saveOverlay(base: initialFood, names: ["sv": .set("Min bestående produkt")], profile: .set(personalProfile), operationID: UUID())
        let component = try MealComponent(food: accepted.food, generationID: UUID(), displayName: accepted.food.names["sv"]!, language: "sv", quantity: LoggedQuantity(amount: DecimalAmount("50"), unit: .grams), fixtureOnly: false, provenance: first.provenance, evidence: [:], overlayRevision: accepted.overlayRevision)
        let event = try diary.save(MealDraft(eatenAt: Date(timeIntervalSince1970: 500), zoneID: "Europe/Stockholm", components: [component]), operationID: UUID(), now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(event.totals["protein"]?.knownSubtotal.canonicalString, "21")
        XCTAssertEqual(event.totals["sodium"]?.completeness, .incomplete)
        XCTAssertEqual(event.components[0].provenance[initialFood.provenanceRef]?.reviewStatus, "community/unverified")

        let refreshed = try await off.refresh(barcode: first.barcode, language: "sv")
        let newestFood = try XCTUnwrap(refreshed.food)
        XCTAssertNotEqual(newestFood.revision, initialFood.revision)
        XCTAssertEqual(newestFood.profile.nutrients["protein"]?.value?.canonicalString, "20")
        let resolved = try personal.resolve(base: newestFood)
        XCTAssertEqual(resolved.overlayRevision, accepted.overlayRevision)
        XCTAssertEqual(resolved.food.names["sv"], "Min bestående produkt")
        XCTAssertEqual(resolved.food.profile, accepted.food.profile)
        XCTAssertEqual(resolved.food.names["en"], "Updated source name")
        XCTAssertEqual(resolved.food.names["de"], "Neuer Quellenname")
        XCTAssertEqual(resolved.food.salesCountries, ["DE", "SE"])
        XCTAssertTrue(resolved.sourceChanged)
        XCTAssertFalse(resolved.needsReview)

        // Reopening the diary and customization layer uses their private data;
        // history must retain the old source/profile/revision and original name.
        let restarted = try DiaryStore(databaseURL: privateDatabase)
        let persisted = try XCTUnwrap(restarted.events(localDate: event.localDate).first)
        XCTAssertEqual(persisted, event)
        XCTAssertEqual(persisted.components[0].food.revision, initialFood.revision)
        XCTAssertEqual(persisted.components[0].food.names["de"], "Alter Quellenname")
        XCTAssertEqual(persisted.components[0].displayName, "Min bestående produkt")
        XCTAssertEqual(persisted.components[0].overlayRevision, accepted.overlayRevision)
        XCTAssertNotNil(persisted.components[0].provenance[initialFood.provenanceRef])
        XCTAssertEqual(try PersonalLibrary(store: restarted).resolve(base: newestFood), resolved)
        let calls = await server.calls
        XCTAssertEqual(calls, 2)
    }
}
