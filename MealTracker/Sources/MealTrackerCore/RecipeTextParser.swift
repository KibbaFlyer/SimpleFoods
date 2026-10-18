import Foundation

public enum RecipeImportError: Error { case tooLarge, empty }
public enum RecipeQuantityUnit: String, Sendable { case grams, millilitres }
public struct RecipeIngredientLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let original: String
    public let name: String
    public let amount: DecimalAmount?
    public let unit: RecipeQuantityUnit?
}
public struct ParsedRecipe: Sendable {
    public let ingredients: [RecipeIngredientLine]
    public let ignoredLines: [String]
}

/// Offline, conservative extraction. Counts, ranges, packages and cups require
/// manual quantities. It never guesses density, edible weight, or serving yield.
public enum RecipeTextParser {
    public static func parse(_ text: String) throws -> ParsedRecipe {
        guard text.utf8.count <= 50_000, text.components(separatedBy: .newlines).count <= 250 else { throw RecipeImportError.tooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RecipeImportError.empty }
        var lines: [RecipeIngredientLine] = [], ignored: [String] = []
        var instructions = false
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { continue }
            let line = original.replacingOccurrences(of: #"^[•*–]\s*|^-\s+"#, with: "", options: .regularExpression)
            let key = normalized(line).trimmingCharacters(in: .whitespaces)
            if ["ingredients", "ingredienser", "zutaten"].contains(key) { instructions = false; ignored.append(original); continue }
            if ["instructions", "method", "directions", "preparation", "gör så här", "gor sa har", "tillagning", "zubereitung", "anleitung"].contains(key) { instructions = true; ignored.append(original); continue }
            if instructions || isInstruction(key) || key.range(of: #"^(serves|servings|portioner|portionen|for|för)\s+\d"#, options: .regularExpression) != nil {
                ignored.append(original); continue
            }
            let expanded = expandFractions(line)
            let pattern = #"^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?)(?:\s*)(.*)$"#
            guard let match = captures(pattern, expanded), let quantity = number(match[0]) else {
                lines.append(.init(id: index, original: original, name: line, amount: nil, unit: nil)); continue
            }
            let remainder = match[1].trimmingCharacters(in: .whitespaces)
            // A range or multiplier is not one precise quantity.
            if remainder.range(of: #"^([-–—/x×]|to\b|bis\b)"#, options: [.regularExpression, .caseInsensitive]) != nil {
                lines.append(.init(id: index, original: original, name: line, amount: nil, unit: nil)); continue
            }
            let split = remainder.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            let token = split.first.map(String.init) ?? ""
            let rest = split.count > 1 ? String(split[1]) : ""
            if let conversion = unit(token), !rest.isEmpty,
               let amount = try? DecimalAmount(calculated: Arithmetic.multiply(quantity, conversion.1)), amount.value > 0 {
                lines.append(.init(id: index, original: original, name: rest, amount: amount, unit: conversion.0))
            } else {
                let countUnits = ["st", "st.", "stk", "stück", "stuck", "pieces", "piece", "cup", "cups", "burk", "burkar", "pack", "packet", "packung", "dose", "dosen"]
                let name = countUnits.contains(token.lowercased()) && !rest.isEmpty ? rest : remainder
                lines.append(.init(id: index, original: original, name: name.isEmpty ? line : name, amount: nil, unit: nil))
            }
        }
        return ParsedRecipe(ingredients: lines, ignoredLines: ignored)
    }
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func isInstruction(_ text: String) -> Bool {
        text.range(of: #"^(?:\d+\s+)?(preheat|bake|stir|mix|heat|cook|blanda|grädda|gradda|stek|koka|värm|varm|hacka|mischen|backen|erhitzen|kochen|verrühren|verruhren)\b"#, options: .regularExpression) != nil
    }
    private static func unit(_ raw: String) -> (RecipeQuantityUnit, Decimal)? {
        switch raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "g", "gram", "grams", "gramm": return (.grams, 1)
        case "kg", "kilogram", "kilograms", "kilogramm": return (.grams, 1000)
        case "mg": return (.grams, Decimal(string: "0.001")!)
        case "ml", "milliliter", "millilitres", "milliliters": return (.millilitres, 1)
        case "cl": return (.millilitres, 10)
        case "dl": return (.millilitres, 100)
        case "l", "liter", "litre", "litres", "liters": return (.millilitres, 1000)
        case "tsk", "tsp", "teaspoon", "teaspoons", "tl", "teelöffel": return (.millilitres, 5)
        case "msk", "tbsp", "tablespoon", "tablespoons", "el", "esslöffel": return (.millilitres, 15)
        default: return nil
        }
    }
    private static func number(_ value: String) -> Decimal? {
        let parts = value.split(separator: " ")
        let fraction = String(parts.last ?? "")
        if fraction.contains("/") {
            let pair = fraction.split(separator: "/")
            guard pair.count == 2, let numerator = try? DecimalAmount(String(pair[0])), let denominator = try? DecimalAmount(String(pair[1])),
                  denominator.value > 0, let ratio = try? Arithmetic.divide(numerator.value, denominator.value) else { return nil }
            let whole = parts.count > 1 ? (Decimal(string: String(parts[0])) ?? 0) : 0
            return try? Arithmetic.add(whole, ratio)
        }
        // A separator followed by three digits could be grouping in another locale.
        // Keep it unresolved instead of changing a 1,000 g quantity into 1 g.
        if value.range(of: #"^[1-9][0-9]*[.,][0-9]{3}$"#, options: .regularExpression) != nil { return nil }
        return (try? DecimalAmount(value.replacingOccurrences(of: ",", with: ".")))?.value
    }
    private static func expandFractions(_ text: String) -> String {
        var result = text
        for (character, fraction) in [("½", "1/2"), ("¼", "1/4"), ("¾", "3/4"), ("⅓", "1/3"), ("⅔", "2/3"), ("⅛", "1/8")] {
            result = result.replacingOccurrences(of: "(?<=[0-9])" + character, with: " " + fraction, options: .regularExpression)
            result = result.replacingOccurrences(of: character, with: fraction)
        }
        return result
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

public enum RecipeFoodMatcher {
    /// Only a unique exact localized name is preselected. Ranked partial matches
    /// are suggestions; duplicate names always require a choice.
    public static func exactMatch(_ name: String, foods: [CatalogueFood]) -> FoodID? {
        let key = RecipeTextParser.normalized(name)
        let matches = foods.filter { $0.names.values.contains { RecipeTextParser.normalized($0) == key } }
        let ids = Set(matches.map(\.id))
        return ids.count == 1 ? ids.first : nil
    }
    public static func suggestions(_ name: String, foods: [CatalogueFood]) -> [CatalogueFood] {
        let tokens = Set(RecipeTextParser.normalized(name).split(separator: " ").map(String.init))
        guard !tokens.isEmpty else { return foods }
        return foods.compactMap { food -> (CatalogueFood, Int)? in
            let scores = food.names.values.map { value -> Int in
                let other = Set(RecipeTextParser.normalized(value).split(separator: " ").map(String.init))
                return other == tokens ? 1000 : tokens.intersection(other).count
            }
            let score = scores.max() ?? 0
            return score > 0 ? (food, score) : nil
        }.sorted { $0.1 == $1.1 ? String(describing: $0.0.id) < String(describing: $1.0.id) : $0.1 > $1.1 }.map(\.0)
    }
}
