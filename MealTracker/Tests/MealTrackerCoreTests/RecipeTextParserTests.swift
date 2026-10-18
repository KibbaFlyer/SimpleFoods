import Foundation
import XCTest
@testable import MealTrackerCore

final class RecipeTextParserTests: XCTestCase {
    func testSwedishMetricAndInstructions() throws {
        let recipe = try RecipeTextParser.parse("Ingredienser:\n200g mjöl\n2,5 dl mjölk\n1 msk olja\nGör så här:\nBlanda allt.\nGrädda 20 minuter.")
        XCTAssertEqual(recipe.ingredients.map(\.name), ["mjöl", "mjölk", "olja"])
        XCTAssertEqual(recipe.ingredients.map { $0.amount?.canonicalString }, ["200", "250", "15"])
        XCTAssertEqual(recipe.ingredients.map(\.unit), [.grams, .millilitres, .millilitres])
        XCTAssertEqual(recipe.ignoredLines.count, 4)
    }
    func testEnglishAndGermanFractions() throws {
        let recipe = try RecipeTextParser.parse("Zutaten\n½ kg Kartoffeln\n1½ EL Öl\n1 1/2 tsp salt\n0.25 l milk\n250 mg spice")
        XCTAssertEqual(recipe.ingredients.map { $0.amount?.canonicalString }, ["500", "22.5", "7.5", "250", "0.25"])
        XCTAssertEqual(recipe.ingredients.map(\.name), ["Kartoffeln", "Öl", "salt", "milk", "spice"])
    }
    func testCountsRangesPackagesAndGroupingStayUnresolved() throws {
        let source = "2 eggs\n1 cup flour\n1-2 g salt\n2 x 400 g tomatoes\n1,000 g flour\n1.000 g Mehl\n1/0 g sugar\n-5 g salt\nsalt to taste"
        let recipe = try RecipeTextParser.parse(source)
        XCTAssertEqual(recipe.ingredients.count, 9)
        XCTAssertTrue(recipe.ingredients.allSatisfy { $0.amount == nil && $0.unit == nil })
        XCTAssertEqual(recipe.ingredients[0].name, "eggs")
        XCTAssertEqual(recipe.ingredients[1].name, "flour")
        XCTAssertEqual(recipe.ingredients[2].original, "1-2 g salt")
    }
    func testTitleRetainedForReviewAndBoundedInput() throws {
        let recipe = try RecipeTextParser.parse("My favourite soup\nIngredients\n• 100 g potato\nInstructions\n1. Cook gently")
        XCTAssertEqual(recipe.ingredients.count, 2)
        XCTAssertNil(recipe.ingredients[0].amount)
        XCTAssertEqual(recipe.ingredients[1].amount?.canonicalString, "100")
        XCTAssertThrowsError(try RecipeTextParser.parse(" "))
        XCTAssertThrowsError(try RecipeTextParser.parse(String(repeating: "x", count: 50_001)))
        XCTAssertThrowsError(try RecipeTextParser.parse(String(repeating: "x\n", count: 251)))
    }
    func testMatchingOnlyPreselectsUniqueExactNames() throws {
        let url = Bundle.module.url(forResource: "fixture-v1", withExtension: "json", subdirectory: "Fixtures")!
        let base = try JSONDecoder().decode(CatalogueFixture.self, from: Data(contentsOf: url)).foods[0]
        func food(_ id: String, _ names: [String: String]) -> CatalogueFood {
            CatalogueFood(id: .catalogue(namespace: "test", recordID: id), revision: "1", kind: "ingredient", lifecycle: "active", names: names, salesCountries: [], manufacturingCountries: [], ingredientOrigins: [], barcodes: [], profile: base.profile, provenanceRef: base.provenanceRef)
        }
        let plain = food("plain", ["sv":"Mjöl", "en":"Flour", "de":"Mehl"])
        let whole = food("whole", ["en":"Whole wheat flour"])
        XCTAssertEqual(RecipeFoodMatcher.exactMatch("MJÖL", foods: [plain, whole]), plain.id)
        XCTAssertNil(RecipeFoodMatcher.exactMatch("wheat", foods: [plain, whole]))
        XCTAssertEqual(RecipeFoodMatcher.suggestions("wheat", foods: [plain, whole]).map(\.id), [whole.id])
        XCTAssertNil(RecipeFoodMatcher.exactMatch("flour", foods: [plain, food("other", ["en":"Flour"])]))
        XCTAssertEqual(RecipeFoodMatcher.exactMatch("flour", foods: [plain, plain]), plain.id)
    }
}
