import Foundation
import XCTest
@testable import MealTrackerCore

final class NutritionTests: XCTestCase {
    private func amount(_ text: String) throws -> DecimalAmount { try DecimalAmount(text) }
    private func fixture(_ version: Int = 1) throws -> CatalogueFixture {
        let path = Bundle.module.url(forResource: "fixture-v\(version)", withExtension: "json", subdirectory: "Fixtures")!
        let result = try JSONDecoder().decode(CatalogueFixture.self, from: Data(contentsOf: path))
        try result.validate()
        return result
    }
    private func profile(_ id: String, version: Int = 1) throws -> NutritionProfile {
        try fixture(version).foods.first { $0.id == .catalogue(namespace: "mealtracker.synthetic", recordID: id) }!.profile
    }
    private func with(_ original: NutritionProfile, basis: NutritionBasis? = nil, density: Density? = nil, nutrients: [String: NutrientValue]? = nil, portions: [Portion]? = nil) throws -> NutritionProfile {
        try NutritionProfile(profileRevision: original.profileRevision, basis: basis ?? original.basis, preparation: original.preparation, density: density, nutrients: nutrients ?? original.nutrients, portions: portions ?? original.portions, provenanceRef: original.provenanceRef)
    }
    func testStrictDecimalWireAndCanonicalization() throws {
        XCTAssertEqual(try amount("1.2300").canonicalString, "1.23")
        for invalid in ["1\n", " 1", "1 ", "-1", "-0", "+1", "01", ".5", "1.", "1e2", "NaN", "1,5", "1000000000000", "0.0000000001"] {
            XCTAssertThrowsError(try amount(invalid), invalid)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(DecimalAmount.self, from: Data("1".utf8)))
        XCTAssertEqual(try amount("999999999999.999999999").value, Decimal(string: "999999999999.999999999")!)
    }
    func testSharedFixtureVersionsRoundtripAndLeadingZeros() throws {
        for version in [1, 2] {
            let pack = try fixture(version)
            XCTAssertEqual(pack.foods.count, 4)
            XCTAssertEqual(pack.foods[0].barcodes, ["0000000000001"])
            let decoded = try JSONDecoder().decode(CatalogueFixture.self, from: JSONEncoder().encode(pack))
            try decoded.validate()
            XCTAssertEqual(decoded.foods[0].ingredientOrigins, [])
            XCTAssertEqual(decoded.foods[0].id, pack.foods[0].id)
        }
        XCTAssertEqual(try profile("sausage", version: 2).nutrients["protein"]?.value?.canonicalString, "11")
        XCTAssertEqual(try fixture(2).retainedRevisions.count, 2)
    }
    func testDeclaredEnergyUnknownAndSaltFallback() throws {
        let result = try NutritionCalculator.calculate(profile: profile("sausage"), quantity: .grams(amount("75")))
        XCTAssertEqual(result[.energy].knownSubtotal, Decimal(string: "150")!)
        XCTAssertEqual(result[.protein].knownSubtotal, Decimal(string: "7.5")!)
        XCTAssertEqual(result[.fibre].completeness, .incomplete)
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.fibre, totals: result), .incomplete)
        XCTAssertEqual(result[.sodium].knownSubtotal, 300)
        XCTAssertTrue(result[.sodium].derived)
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.energy, totals: result), .eligible)
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.carbohydrateAvailable, totals: result), .semanticPolicyRequired)
    }
    func testDirectSodiumNeverAddedToSalt() throws {
        let source = try profile("sausage")
        var nutrients = source.nutrients
        nutrients["sodium"] = try NutrientValue(status: .known, value: amount("123"), unit: .mg)
        let result = try NutritionCalculator.calculate(profile: with(source, nutrients: nutrients), quantity: .grams(amount("100")))
        XCTAssertEqual(result[.sodium].knownSubtotal, 123)
        XCTAssertFalse(result[.sodium].derived)
    }
    func testDensityConversionAndEstimatePropagation() throws {
        let oil = try profile("oil")
        let result = try NutritionCalculator.calculate(profile: oil, quantity: .grams(amount("9")))
        XCTAssertEqual(result[.energy].knownSubtotal, 81)
        XCTAssertEqual(try NutritionCalculator.calculate(profile: oil, quantity: .millilitres(amount("10")))[.energy].knownSubtotal, 81)
        XCTAssertThrowsError(try NutritionCalculator.calculate(profile: with(oil), quantity: .grams(amount("9"))))
        let estimate = try Density(gramsPerMillilitre: amount("0.9"), evidenceRef: "synthetic-measured", quality: .estimated)
        let estimated = try NutritionCalculator.calculate(profile: with(oil, density: estimate), quantity: .grams(amount("9")))
        XCTAssertTrue(estimated[.energy].estimated)
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.energy, totals: estimated), .estimatedPolicyRequired)
    }
    func testPortionAndDefinedPortionPhysicalEquivalent() throws {
        let sausage = try profile("sausage")
        XCTAssertEqual(try NutritionCalculator.calculate(profile: sausage, quantity: .portions(id: "p1", count: amount("2")))[.energy].knownSubtotal, 100)
        let basis = try NutritionBasis(quantity: amount("1"), unit: .definedPortion, portionID: "p1")
        let piece = try with(sausage, basis: basis)
        XCTAssertEqual(try NutritionCalculator.calculate(profile: piece, quantity: .grams(amount("50")))[.energy].knownSubtotal, 400)
        XCTAssertEqual(try NutritionCalculator.calculate(profile: piece, quantity: .portions(id: "p1", count: amount("2")))[.energy].knownSubtotal, 400)
        XCTAssertThrowsError(try NutritionCalculator.calculate(profile: piece, quantity: .millilitres(amount("50"))))
    }
    func testRecipeServingYieldAndIncompleteSubtotal() throws {
        let sausage = try NutritionCalculator.calculate(profile: profile("sausage"), quantity: .grams(amount("100")))
        let potatoes = try NutritionCalculator.calculate(profile: profile("potato"), quantity: .grams(amount("200")))
        XCTAssertEqual(potatoes[.totalFat].completeness, .complete)
        XCTAssertEqual(potatoes[.totalFat].knownSubtotal, 0)
        let total = try NutritionCalculator.aggregate([sausage, potatoes])
        XCTAssertEqual(total[.energy].knownSubtotal, 360)
        XCTAssertEqual(total[.fibre].knownSubtotal, 4)
        XCTAssertEqual(total[.fibre].completeness, .incomplete)
        XCTAssertEqual(try NutritionCalculator.recipe(total: total, servings: amount("2"), finishedYieldGrams: amount("250"), consumed: .grams(amount("125")))[.energy].knownSubtotal, 180)
        XCTAssertEqual(try NutritionCalculator.recipe(total: total, servings: amount("2"), finishedYieldGrams: nil, consumed: .servings(amount("1")))[.energy].knownSubtotal, 180)
        XCTAssertThrowsError(try NutritionCalculator.recipe(total: total, servings: amount("2"), finishedYieldGrams: nil, consumed: .grams(amount("100"))))
    }
    func testTraceBoundCannotSurviveUnknownAggregate() throws {
        let trace = try NutritionCalculator.calculate(profile: profile("trace"), quantity: .grams(amount("100")))
        XCTAssertEqual(trace[.fibre].completeness, .traceBounded)
        XCTAssertEqual(trace[.fibre].exclusiveTraceUpperBound, Decimal(string: "0.1")!)
        let unknown = try NutritionCalculator.calculate(profile: profile("sausage"), quantity: .grams(amount("100")))
        let aggregate = try NutritionCalculator.aggregate([trace, unknown])
        XCTAssertEqual(aggregate[.fibre].completeness, .incomplete)
        XCTAssertNil(aggregate[.fibre].exclusiveTraceUpperBound)
    }
    func testUnitsStatusesAndInvalidBasisReject() throws {
        XCTAssertThrowsError(try NutrientValue(status: .derived, value: amount("1"), unit: .g, methodID: "x", inputRefs: [], estimated: false))
        XCTAssertThrowsError(try NutrientValue(status: .known, value: amount("0"), unit: .g))
        XCTAssertThrowsError(try NutrientValue(status: .unknown, value: amount("1"), unit: .g, reason: "unknown"))
        XCTAssertThrowsError(try NutritionBasis(quantity: amount("0"), unit: .g))
        XCTAssertThrowsError(try Density(gramsPerMillilitre: amount("0"), evidenceRef: "x", quality: .measured))
        XCTAssertThrowsError(try Portion(id: "p", names: [:], massGrams: nil, volumeMillilitres: nil, quality: .measured, evidenceRef: "x"))
        var nutrients = try profile("sausage").nutrients
        nutrients["energy.declared"] = try NutrientValue(status: .known, value: amount("1"), unit: .g)
        XCTAssertThrowsError(try with(profile("sausage"), nutrients: nutrients))
        XCTAssertThrowsError(try NutritionCalculator.calculate(profile: profile("sausage"), quantity: .grams(amount("0"))))
    }
    func testOverflowAndFinalHalfEvenRounding() throws {
        XCTAssertEqual(try DecimalAmount(calculated: Decimal(string: "1.0000000005")!).canonicalString, "1")
        XCTAssertEqual(try DecimalAmount(calculated: Decimal(string: "1.0000000015")!).canonicalString, "1.000000002")
        XCTAssertThrowsError(try NutritionCalculator.calculate(profile: profile("oil"), quantity: .millilitres(amount("999999999999"))))
    }
    func testAlphabeticGenerationUUIDEncodesLowercaseAndNullPortionLabel() throws {
        let path = Bundle.module.url(forResource: "fixture-v1", withExtension: "json", subdirectory: "Fixtures")!
        let original = try String(contentsOf: path, encoding: .utf8)
        let changed = original.replacingOccurrences(of: "00000000-0000-4000-8000-000000000001", with: "abcdefab-cdef-4abc-8def-abcdefabcdef")
        var object = try JSONSerialization.jsonObject(with: Data(changed.utf8)) as! [String: Any]
        var foods = object["foods"] as! [[String: Any]]
        var profile = foods[0]["profile"] as! [String: Any]
        var portions = profile["portions"] as! [[String: Any]]
        portions[0]["names"] = NSNull(); profile["portions"] = portions; foods[0]["profile"] = profile; object["foods"] = foods
        let pack = try JSONDecoder().decode(CatalogueFixture.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(pack.foods[0].profile.portions[0].names)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pack)) as! [String: Any]
        XCTAssertEqual(encoded["generationID"] as? String, "abcdefab-cdef-4abc-8def-abcdefabcdef")
    }
    func testExplicitNullWireShapeAndWriteSwiftFixture() throws {
        let pack = try fixture()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let foods = object["foods"] as! [[String: Any]]
        let profile = foods[0]["profile"] as! [String: Any]
        XCTAssertTrue(profile["density"] is NSNull)
        XCTAssertTrue((profile["basis"] as! [String: Any])["portionID"] is NSNull)
        let portion = (profile["portions"] as! [[String: Any]])[0]
        XCTAssertNotNil(portion["massGrams"])
        XCTAssertTrue(portion["volumeMillilitres"] is NSNull)
        let provenance = object["provenance"] as! [String: [String: Any]]
        XCTAssertTrue(provenance["synthetic-fixture"]!["sourceURL"] is NSNull)
        let trace = try NutrientValue(status: .trace, unit: .g)
        let traceObject = try JSONSerialization.jsonObject(with: encoder.encode(trace)) as! [String: Any]
        XCTAssertTrue(traceObject["upperBound"] is NSNull)
        if let output = ProcessInfo.processInfo.environment["MEALTRACKER_SWIFT_FIXTURE_OUTPUT"] {
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
    }
    func testDerivedFixtureReferencesMustResolveEvidence() throws {
        let path = Bundle.module.url(forResource: "fixture-v1", withExtension: "json", subdirectory: "Fixtures")!
        let source = try Data(contentsOf: path)
        var object = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        var foods = object["foods"] as! [[String: Any]]
        var profile = foods[0]["profile"] as! [String: Any]
        var nutrients = profile["nutrients"] as! [String: Any]
        nutrients["protein"] = ["status": "derived", "value": "10", "unit": "g", "methodID": "synthetic", "inputRefs": ["missing"], "estimated": false] as [String: Any]
        profile["nutrients"] = nutrients; foods[0]["profile"] = profile; object["foods"] = foods
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogueFixture.self, from: JSONSerialization.data(withJSONObject: object)).validate())
        nutrients["protein"] = ["status": "derived", "value": "10", "unit": "g", "methodID": "synthetic", "inputRefs": ["synthetic-measured"], "estimated": false] as [String: Any]
        profile["nutrients"] = nutrients; foods[0]["profile"] = profile; object["foods"] = foods
        try JSONDecoder().decode(CatalogueFixture.self, from: JSONSerialization.data(withJSONObject: object)).validate()
    }
    func testSaturatedFatExceedingParentWithheld() throws {
        let source = try profile("sausage")
        var nutrients = source.nutrients
        nutrients["fat.saturated"] = try NutrientValue(status: .known, value: amount("16"), unit: .g)
        let result = try NutritionCalculator.calculate(profile: with(source, nutrients: nutrients), quantity: .grams(amount("100")))
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.saturatedFat, totals: result), .semanticPolicyRequired)
    }
    func testAccumulatedSmallContributions() throws {
        let source = try profile("potato")
        var values = source.nutrients
        values["energy.declared"] = try NutrientValue(status: .known, value: amount("33.333"), unit: .kcal)
        let custom = try with(source, nutrients: values)
        let one = try NutritionCalculator.calculate(profile: custom, quantity: .grams(amount("1")))
        XCTAssertEqual(try NutritionCalculator.aggregate([one, one, one])[.energy].persistedAmount().canonicalString, "0.99999")
    }
    func testDerivedStatusRecurringDivisionAndNoIntermediateDisplayRounding() throws {
        let source = try profile("potato")
        var values = source.nutrients
        values["energy.declared"] = try NutrientValue(status: .derived, value: amount("1"), unit: .kcal, methodID: "synthetic-method", inputRefs: ["protein"], estimated: true)
        let custom = try with(source, basis: NutritionBasis(quantity: amount("3"), unit: .g), nutrients: values)
        let one = try NutritionCalculator.calculate(profile: custom, quantity: .grams(amount("1")))
        XCTAssertTrue(one[.energy].derived)
        XCTAssertTrue(one[.energy].estimated)
        XCTAssertEqual(try one[.energy].persistedAmount().canonicalString, "0.333333333")
        XCTAssertEqual(try NutritionCalculator.aggregate([one, one, one])[.energy].persistedAmount().canonicalString, "1")
    }
    func testUnresolvedEvidenceAndProviderMismatchRejected() throws {
        let path = Bundle.module.url(forResource: "fixture-v1", withExtension: "json", subdirectory: "Fixtures")!
        let source = try String(contentsOf: path, encoding: .utf8)
        let unresolved = source.replacingOccurrences(of: "\"evidenceRef\": \"synthetic-measured\"", with: "\"evidenceRef\": \"missing\"")
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogueFixture.self, from: Data(unresolved.utf8)).validate())
        let mismatch = source.replacingOccurrences(of: "\"providerID\": \"mealtracker.synthetic\"", with: "\"providerID\": \"other.provider\"")
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogueFixture.self, from: Data(mismatch.utf8)).validate())
    }
    func testSaturatedFatRequiresCompleteParent() throws {
        let source = try profile("sausage")
        var nutrients = source.nutrients
        nutrients["fat.saturated"] = try NutrientValue(status: .known, value: amount("2"), unit: .g)
        nutrients.removeValue(forKey: "fat.total")
        let result = try NutritionCalculator.calculate(profile: with(source, nutrients: nutrients), quantity: .grams(amount("100")))
        XCTAssertEqual(HealthSemanticPolicy.eligibility(.saturatedFat, totals: result), .semanticPolicyRequired)
    }
}
