import XCTest
import MealTrackerCore

final class SodiumClearTests: XCTestCase {
    func testExplicitlyClearedSodiumRemainsUnknownDespiteKnownSalt() throws {
        let profile = try NutritionProfile(
            profileRevision: "clear-regression-1",
            basis: NutritionBasis(quantity: DecimalAmount("100"), unit: .g),
            preparation: "asEntered", density: nil,
            nutrients: [
                "salt.equivalent": try NutrientValue(status: .known, value: DecimalAmount("1"), unit: .g),
                "sodium": try NutrientValue(status: .unknown, unit: .mg, reason: "userCleared")
            ],
            portions: [], provenanceRef: "user-authored"
        )
        let total = try NutritionCalculator.calculate(profile: profile, quantity: .grams(DecimalAmount("100")))
        XCTAssertEqual(total[.sodium].knownSubtotal, 0)
        XCTAssertEqual(total[.sodium].completeness, .incomplete)
        XCTAssertEqual(total[.sodium].missingReasons, ["userCleared"])
        XCTAssertFalse(total[.sodium].derived)
    }
}
