import Foundation

/// Shared relevance rules for food-name searches.
///
/// A match at the beginning of the displayed name is most useful, followed by
/// a match at the beginning of any word, then a general substring match.
public enum FoodSearchRanking {
    public static func rank(
        displayName: String,
        searchableNames: some Sequence<String>,
        query: String,
        locale: Locale
    ) -> Int? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return 0 }

        if startsWithQuery(displayName, query: query, locale: locale) {
            return 0
        }
        if hasWordStartingWithQuery(displayName, query: query, locale: locale) {
            return 1
        }
        if containsQuery(displayName, query: query, locale: locale) {
            return 2
        }

        let queryTerms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { $0.count > 1 }
        if queryTerms.count > 1, let tokenRank = tokenRank(in: displayName, terms: queryTerms, locale: locale) {
            return 10 + tokenRank
        }

        let alternateNames = searchableNames.filter {
            $0.compare(displayName, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: locale) != .orderedSame
        }
        if alternateNames.contains(where: { startsWithQuery($0, query: query, locale: locale) }) {
            return 100
        }
        if alternateNames.contains(where: { hasWordStartingWithQuery($0, query: query, locale: locale) }) {
            return 101
        }
        if alternateNames.contains(where: { containsQuery($0, query: query, locale: locale) }) {
            return 102
        }
        if queryTerms.count > 1,
           let alternateTokenRank = alternateNames.compactMap({ tokenRank(in: $0, terms: queryTerms, locale: locale) }).min() {
            return 110 + alternateTokenRank
        }
        return nil
    }

    private static func containsQuery(_ name: String, query: String, locale: Locale) -> Bool {
        name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
    }

    private static func tokenRank(in name: String, terms: [String], locale: Locale) -> Int? {
        let qualities = terms.compactMap { term -> Int? in
            if startsWithQuery(name, query: term, locale: locale) { return 0 }
            if hasWordStartingWithQuery(name, query: term, locale: locale) { return 1 }
            if containsQuery(name, query: term, locale: locale) { return 2 }
            return nil
        }
        guard !qualities.isEmpty else { return nil }
        return (terms.count - qualities.count) * 10 + qualities.reduce(0, +)
    }

    private static func startsWithQuery(_ name: String, query: String, locale: Locale) -> Bool {
        name.range(
            of: query,
            options: [.anchored, .caseInsensitive, .diacriticInsensitive],
            range: name.startIndex..<name.endIndex,
            locale: locale
        ) != nil
    }

    private static func hasWordStartingWithQuery(_ name: String, query: String, locale: Locale) -> Bool {
        var found = false
        name.enumerateSubstrings(in: name.startIndex..<name.endIndex, options: .byWords) { _, range, _, stop in
            guard name.range(
                of: query,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive],
                range: range,
                locale: locale
            ) != nil else { return }
            found = true
            stop = true
        }
        return found
    }
}
