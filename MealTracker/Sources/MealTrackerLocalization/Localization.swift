import Foundation
import MealTrackerCore

public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case sv, en, de
    public var id: String { rawValue }
    public var name: String { switch self { case .sv: "Svenska"; case .en: "English"; case .de: "Deutsch" } }
    public var locale: Locale { Locale(identifier: rawValue) }
}

public struct AppCopy: Sendable {
    public let language: AppLanguage
    public init(language: AppLanguage) { self.language = language }
    public func text(_ key: String) -> String {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func resourceKeys(language: AppLanguage) throws -> Set<String> {
        guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path), let url = bundle.url(forResource: "Localizable", withExtension: "strings") else { throw CocoaError(.fileNoSuchFile) }
        let data = try Data(contentsOf: url)
        let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        guard let dictionary else { throw CocoaError(.propertyListReadCorrupt) }
        return Set(dictionary.keys)
    }
    public func number(_ value: Decimal) -> String {
        formattedNumber(value, minimumFractionDigits: 0, maximumFractionDigits: 2)
    }
    public func kilocalories(_ value: Decimal) -> String {
        formattedNumber(value, minimumFractionDigits: 0, maximumFractionDigits: 0)
    }
    public func macronutrient(_ value: Decimal) -> String {
        formattedNumber(value, minimumFractionDigits: 1, maximumFractionDigits: 1)
    }
    public func nutrientNumber(_ value: Decimal, nutrient: Nutrient) -> String {
        switch nutrient {
        case .energy:
            kilocalories(value)
        case .protein, .carbohydrateAvailable, .totalFat:
            macronutrient(value)
        default:
            number(value)
        }
    }
    private func formattedNumber(_ value: Decimal, minimumFractionDigits: Int, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }
    /// Accept only the selected language's decimal separator, never grouping/exponents/signs.
    public func canonicalQuantity(_ text: String, allowZero: Bool = false) -> String? {
        let separator = language == .en ? "." : ","
        let expression = "^(0|[1-9][0-9]{0,11})(" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]{1,9})?$"
        guard let range = text.range(of: expression, options: .regularExpression), range == text.startIndex..<text.endIndex else { return nil }
        let canonical = text.replacingOccurrences(of: separator, with: ".")
        guard let value = Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX")), (allowZero ? value >= 0 : value > 0) else { return nil }
        return canonical
    }
}

public enum BarcodeInput {
    public static func normalized(_ raw: String) -> String? {
        guard [8, 12, 13].contains(raw.count), raw.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return raw
    }
}
