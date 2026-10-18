import Foundation
import XCTest
@testable import MealTrackerCore

final class FoodSearchRankingTests: XCTestCase {
    func testDisplayNamePrefixRanksAboveWordAndSubstringMatches() {
        let locale = Locale(identifier: "en")
        let prefix = FoodSearchRanking.rank(displayName: "Apple juice", searchableNames: ["Apple juice"], query: "app", locale: locale)
        let word = FoodSearchRanking.rank(displayName: "Fresh apple juice", searchableNames: ["Fresh apple juice"], query: "app", locale: locale)
        let substring = FoodSearchRanking.rank(displayName: "Pineapple juice", searchableNames: ["Pineapple juice"], query: "app", locale: locale)

        XCTAssertEqual(prefix, 0)
        XCTAssertEqual(word, 1)
        XCTAssertEqual(substring, 2)
    }

    func testSearchUsesCaseAndDiacriticInsensitiveMatching() {
        let rank = FoodSearchRanking.rank(
            displayName: "Crème brûlée",
            searchableNames: ["Crème brûlée"],
            query: "creme",
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(rank, 0)
    }

    func testMultiWordSearchFallsBackToMatchingTerms() {
        let locale = Locale(identifier: "sv")
        let kvarg = FoodSearchRanking.rank(
            displayName: "Kvarg vanilj",
            searchableNames: ["Kvarg vanilj"],
            query: "Arla kvarg",
            locale: locale
        )
        let unrelated = FoodSearchRanking.rank(
            displayName: "Muffins von Kathi",
            searchableNames: ["Muffins von Kathi"],
            query: "Arla kvarg",
            locale: locale
        )

        XCTAssertNotNil(kvarg)
        XCTAssertNil(unrelated)
    }

    func testDisplayedTokenMatchRanksAboveAlternateNameMatch() throws {
        let locale = Locale(identifier: "sv")
        let displayedMatch = FoodSearchRanking.rank(
            displayName: "Kvarg naturell",
            searchableNames: ["Kvarg naturell"],
            query: "Arla kvarg",
            locale: locale
        )
        let alternateMatch = FoodSearchRanking.rank(
            displayName: "Muffins von Kathi",
            searchableNames: ["Muffins von Kathi", "Arla kvarg"],
            query: "Arla kvarg",
            locale: locale
        )

        XCTAssertLessThan(try XCTUnwrap(displayedMatch), try XCTUnwrap(alternateMatch))
    }
}
