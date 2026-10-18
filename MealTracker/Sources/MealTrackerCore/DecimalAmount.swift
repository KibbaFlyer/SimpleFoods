import Foundation

public enum CoreError: Error, Equatable, Sendable {
    case invalidDecimal, arithmeticOverflow, invalidIdentity, invalidProfile(String)
    case invalidQuantity, missingConversion, missingYield, unsupportedNutrient(String)
}

/// Wire decimals: unsigned plain strings, <=12 integer and <=9 fractional digits.
/// Arithmetic uses Foundation Decimal (38 significant digits). Add/multiply precision
/// loss is rejected; recurring division may round within Decimal precision. Final
/// persistence rounding is half-even to nine fractional places, once.
public struct DecimalAmount: Codable, Hashable, Sendable {
    public let value: Decimal
    public init(_ string: String) throws {
        guard let match = string.range(of: #"^(0|[1-9][0-9]{0,11})(\.[0-9]{1,9})?$"#, options: .regularExpression), match == string.startIndex..<string.endIndex,
              let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else {
            throw CoreError.invalidDecimal
        }
        self.value = value
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }
    public var canonicalString: String { NSDecimalNumber(decimal: value).stringValue }
    public static let zero = try! DecimalAmount("0")
    /// Returns a persistence-safe product rounded once to the wire precision.
    public func multiplied(by other: DecimalAmount) throws -> DecimalAmount {
        try DecimalAmount(calculated: Arithmetic.multiply(value, other.value))
    }
    /// Returns a persistence-safe quotient rounded once to the wire precision.
    public func divided(by other: DecimalAmount) throws -> DecimalAmount {
        try DecimalAmount(calculated: Arithmetic.divide(value, other.value))
    }
    internal init(calculated value: Decimal) throws {
        guard !value.isNaN, value >= 0, value < Decimal(string: "1000000000000")! else { throw CoreError.arithmeticOverflow }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 9, .bankers)
        guard rounded < Decimal(string: "1000000000000")! else { throw CoreError.arithmeticOverflow }
        self.value = rounded
    }
}

internal enum Arithmetic {
    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var a = lhs, b = rhs, result = Decimal()
        guard NSDecimalAdd(&result, &a, &b, .bankers) == .noError else { throw CoreError.arithmeticOverflow }
        return result
    }
    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        var a = lhs, b = rhs, result = Decimal()
        guard NSDecimalMultiply(&result, &a, &b, .bankers) == .noError else { throw CoreError.arithmeticOverflow }
        return result
    }
    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs > 0 else { throw CoreError.invalidQuantity }
        var a = lhs, b = rhs, result = Decimal()
        let status = NSDecimalDivide(&result, &a, &b, .bankers)
        // Recurring ratios legitimately round within Decimal's precision. Never round
        // each ingredient to display precision; only persist final totals at 9 places.
        guard status == .noError || status == .lossOfPrecision else { throw CoreError.arithmeticOverflow }
        return result
    }
}
