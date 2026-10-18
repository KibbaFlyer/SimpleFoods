import XCTest
@testable import MealTrackerLocalization
final class LocalizationTests: XCTestCase {
    func testStrictSelectedLanguageQuantity() {
        let sv = AppCopy(language: .sv), en = AppCopy(language: .en)
        XCTAssertEqual(sv.canonicalQuantity("12,5"), "12.5")
        XCTAssertEqual(en.canonicalQuantity("12.5"), "12.5")
        for invalid in ["0", "-1", " 1", "1 ", "1e2", "1,000.5", "01", "1,", "NaN"] { XCTAssertNil(en.canonicalQuantity(invalid)) }
        XCTAssertNil(sv.canonicalQuantity("1.5")); XCTAssertNil(en.canonicalQuantity("1,5"))
    }
    func testResourcesAndFallback() {
        XCTAssertEqual(AppCopy(language: .sv).text("today"), "Idag")
        XCTAssertEqual(AppCopy(language: .en).text("today"), "Today")
        XCTAssertEqual(AppCopy(language: .de).text("today"), "Heute")
        XCTAssertEqual(AppCopy(language: .de).text("missing-key"), "missing-key")
    }
    func testNutritionNumberFormatting() throws {
        let english = AppCopy(language: .en)
        let swedish = AppCopy(language: .sv)
        XCTAssertEqual(english.kilocalories(try XCTUnwrap(Decimal(string: "1234.6"))), "1,235")
        XCTAssertEqual(english.macronutrient(try XCTUnwrap(Decimal(string: "12"))), "12.0")
        XCTAssertEqual(swedish.macronutrient(try XCTUnwrap(Decimal(string: "12.34"))), "12,3")
    }
    func testResourceKeyParity() throws {
        let english = try AppCopy.resourceKeys(language: .en)
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(english, try AppCopy.resourceKeys(language: .sv))
        XCTAssertEqual(english, try AppCopy.resourceKeys(language: .de))
    }
    func testBarcodeRejectsUnicodeAndNoise() {
        XCTAssertEqual(BarcodeInput.normalized("12345678"), "12345678")
        XCTAssertNil(BarcodeInput.normalized("１２３４５６７８"))
        XCTAssertNil(BarcodeInput.normalized("1234567"))
        XCTAssertNil(BarcodeInput.normalized("12345678\n"))
    }
}
