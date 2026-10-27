import Foundation
import Testing
import MealTrackerOpenFoodFacts

struct FoodNameSearchIndexTests {
    @Test func indexedPrefixesSubstringsAccentsAndFilters() throws {
        let index = try FoodNameSearchIndex()
        try index.replace(with: [
            FoodSearchDocument(id: "bread", source: "off", names: ["en": "Bread", "sv": "Bröd"], brand: "Bakery", markets: ["SE"]),
            FoodSearchDocument(id: "crisp", source: "off", names: ["en": "Crispbread"], markets: ["DE"]),
            FoodSearchDocument(id: "milk", source: "personal", names: ["en": "Milk"], markets: ["SE"])
        ])
        #expect(try index.candidates(query: "br", language: "en", market: nil, source: nil, limit: 20).ids == ["bread"])
        #expect(try index.candidates(query: "bread", language: "en", market: nil, source: nil, limit: 20).ids == ["bread", "crisp"])
        #expect(try index.candidates(query: "BRÖD", language: "sv", market: "SE", source: "off", limit: 20).ids == ["bread"])
        #expect(try index.candidates(query: "bakery bread", language: "en", market: "SE", source: "off", limit: 20).ids.first == "bread")
        #expect(try index.candidates(query: "bread", language: "en", market: "DE", source: "off", limit: 20).ids == ["crisp"])
        #expect(try index.candidates(query: "bread", language: "en", market: nil, source: "personal", limit: 20).ids.isEmpty)
        #expect(try index.candidates(query: "%_\"*", language: "en", market: nil, source: nil, limit: 20).ids.isEmpty)
    }

    @Test func boundedSpellingFallbackAndRebuild() throws {
        let index = try FoodNameSearchIndex()
        try index.replace(with: [FoodSearchDocument(id: "bread", source: "off", names: ["en": "Bread"], markets: ["SE"])])
        let correction = try index.candidates(query: "braed", language: "en", market: nil, source: nil, limit: 20)
        #expect(correction.ids == ["bread"])
        #expect(correction.correctedQuery == "bread")
        #expect(try index.candidates(query: "bread", language: "en", market: nil, source: nil, limit: 20).correctedQuery == nil)
        try index.replace(with: [FoodSearchDocument(id: "milk", source: "personal", names: ["en": "Milk"], markets: ["DE"])])
        #expect(try index.candidates(query: "bread", language: "en", market: nil, source: nil, limit: 20).ids.isEmpty)
        #expect(try index.candidates(query: "milk", language: "en", market: "DE", source: nil, limit: 20).ids == ["milk"])
    }

    @Test func resultCountIsBoundedBeforeHydration() throws {
        let index = try FoodNameSearchIndex()
        try index.replace(with: (0..<1000).map { FoodSearchDocument(id: "\($0)", source: "off", names: ["en": "Bread \($0)"], markets: ["SE"]) })
        #expect(try index.candidates(query: "bread", language: "en", market: nil, source: nil, limit: 21).ids.count == 21)
    }
}
