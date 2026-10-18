import Foundation

public enum ConsumedQuantity: Equatable, Sendable {
    case grams(DecimalAmount), millilitres(DecimalAmount), portions(id: String, count: DecimalAmount)
}
public enum Completeness: String, Codable, Sendable { case complete, incomplete, traceBounded }
public struct NutrientTotal: Equatable, Sendable {
    /// Full Decimal precision until explicit persistedAmount call.
    public let knownSubtotal: Decimal
    public let unit: NutrientUnit
    public let completeness: Completeness
    public let estimated: Bool
    public let derived: Bool
    public let missingReasons: [String]
    /// Additional unknown trace contribution, exclusive; full total is subtotal + bound.
    /// Nil when any unrelated component is unknown or any trace lacks a bound.
    public let exclusiveTraceUpperBound: Decimal?
    public func persistedAmount() throws -> DecimalAmount { try DecimalAmount(calculated: knownSubtotal) }
}
public struct NutritionTotals: Equatable, Sendable {
    public let nutrients: [Nutrient: NutrientTotal]
    public subscript(_ nutrient: Nutrient) -> NutrientTotal { nutrients[nutrient]! }
}

public enum NutritionCalculator {
    /// Persist with snapshots so future calculation-policy changes are explicit.
    public static let calculationVersion = "nutrition-decimal-v1"

    public static func calculate(profile: NutritionProfile, quantity: ConsumedQuantity) throws -> NutritionTotals {
        let (consumed, unit, estimated) = try referenceQuantity(profile, quantity)
        let converted: Decimal
        var conversionEstimated = estimated
        if unit == profile.basis.unit {
            converted = consumed
        } else if profile.basis.unit == .definedPortion {
            guard let portion = profile.portions.first(where: { $0.id == profile.basis.portionID }) else { throw CoreError.missingConversion }
            let equivalent: Decimal
            let physicalUnit: BasisUnit
            if let mass = portion.massGrams { equivalent = mass.value; physicalUnit = .g }
            else if let volume = portion.volumeMillilitres { equivalent = volume.value; physicalUnit = .ml }
            else { throw CoreError.missingConversion }
            converted = try Arithmetic.divide(convert(consumed, from: unit, to: physicalUnit, density: profile.density), equivalent)
            conversionEstimated = conversionEstimated || portion.quality == .estimated || (unit != physicalUnit && profile.density?.quality == .estimated)
        } else {
            converted = try convert(consumed, from: unit, to: profile.basis.unit, density: profile.density)
            conversionEstimated = conversionEstimated || profile.density?.quality == .estimated
        }
        var values = profile.nutrients
        // A directly declared sodium amount wins; if unavailable, exact salt conversion
        // supplies one alternative representation, never an additive contribution.
        let sodium = values[Nutrient.sodium.rawValue]
        if sodium == nil || (sodium?.status == .unknown && sodium?.reason != "userCleared") {
            if let salt = values[Nutrient.salt.rawValue], let amount = salt.value {
                let result = try DecimalAmount(calculated: Arithmetic.multiply(amount.value, 400))
                values[Nutrient.sodium.rawValue] = try NutrientValue(status: .derived, value: result, unit: .mg, methodID: "eu-salt-to-sodium-v1", inputRefs: ["salt.equivalent"], estimated: salt.estimated ?? false)
            }
        }
        var totals: [Nutrient: NutrientTotal] = [:]
        for nutrient in Nutrient.allCases {
            let value = values[nutrient.rawValue]
            let subtotal = try value?.value.map { try Arithmetic.divide(Arithmetic.multiply($0.value, converted), profile.basis.quantity.value) } ?? 0
            guard subtotal < Decimal(string: "1000000000000")! else { throw CoreError.arithmeticOverflow }
            let bound = try value?.upperBound.map { try Arithmetic.divide(Arithmetic.multiply($0.value, converted), profile.basis.quantity.value) }
            let complete = value?.status == .known || value?.status == .knownZero || value?.status == .derived
            totals[nutrient] = NutrientTotal(knownSubtotal: subtotal, unit: nutrient.unit,
                completeness: complete ? .complete : (value?.status == .trace ? .traceBounded : .incomplete),
                estimated: conversionEstimated || (value?.estimated ?? false), derived: value?.status == .derived,
                missingReasons: complete ? [] : [value?.reason ?? (value?.status == .trace ? "trace" : "notProvided")], exclusiveTraceUpperBound: bound)
        }
        return NutritionTotals(nutrients: totals)
    }
    public static func aggregate(_ components: [NutritionTotals]) throws -> NutritionTotals {
        guard !components.isEmpty else { throw CoreError.invalidQuantity }
        var output: [Nutrient: NutrientTotal] = [:]
        for nutrient in Nutrient.allCases {
            let values = components.map { $0[nutrient] }
            var sum: Decimal = 0, bound: Decimal = 0
            for value in values {
                sum = try Arithmetic.add(sum, value.knownSubtotal)
                if let upper = value.exclusiveTraceUpperBound { bound = try Arithmetic.add(bound, upper) }
            }
            guard sum < Decimal(string: "1000000000000")! else { throw CoreError.arithmeticOverflow }
            let completeness: Completeness = values.contains { $0.completeness == .incomplete } ? .incomplete : (values.contains { $0.completeness == .traceBounded } ? .traceBounded : .complete)
            let traceValues = values.filter { $0.completeness == .traceBounded }
            output[nutrient] = NutrientTotal(knownSubtotal: sum, unit: nutrient.unit, completeness: completeness,
                estimated: values.contains { $0.estimated }, derived: values.contains { $0.derived }, missingReasons: values.flatMap(\.missingReasons),
                exclusiveTraceUpperBound: completeness != .incomplete && !traceValues.isEmpty && traceValues.allSatisfy { $0.exclusiveTraceUpperBound != nil } ? bound : nil)
        }
        return NutritionTotals(nutrients: output)
    }
    public enum RecipeAmount: Sendable { case servings(DecimalAmount), grams(DecimalAmount) }
    public static func recipe(total: NutritionTotals, servings: DecimalAmount, finishedYieldGrams: DecimalAmount?, consumed: RecipeAmount) throws -> NutritionTotals {
        guard servings.value > 0 else { throw CoreError.invalidQuantity }
        let amount: Decimal, denominator: Decimal
        switch consumed {
        case let .servings(count): amount = count.value; denominator = servings.value
        case let .grams(grams):
            guard let yield = finishedYieldGrams, yield.value > 0 else { throw CoreError.missingYield }
            amount = grams.value; denominator = yield.value
        }
        guard amount > 0 else { throw CoreError.invalidQuantity }
        var result: [Nutrient: NutrientTotal] = [:]
        for (nutrient, value) in total.nutrients {
            let subtotal = try Arithmetic.divide(Arithmetic.multiply(value.knownSubtotal, amount), denominator)
            guard subtotal < Decimal(string: "1000000000000")! else { throw CoreError.arithmeticOverflow }
            result[nutrient] = NutrientTotal(knownSubtotal: subtotal, unit: value.unit, completeness: value.completeness, estimated: value.estimated, derived: value.derived, missingReasons: value.missingReasons,
                exclusiveTraceUpperBound: try value.exclusiveTraceUpperBound.map { try Arithmetic.divide(Arithmetic.multiply($0, amount), denominator) })
        }
        return NutritionTotals(nutrients: result)
    }
    private static func referenceQuantity(_ profile: NutritionProfile, _ quantity: ConsumedQuantity) throws -> (Decimal, BasisUnit, Bool) {
        switch quantity {
        case let .grams(amount): guard amount.value > 0 else { throw CoreError.invalidQuantity }; return (amount.value, .g, false)
        case let .millilitres(amount): guard amount.value > 0 else { throw CoreError.invalidQuantity }; return (amount.value, .ml, false)
        case let .portions(id, count):
            guard count.value > 0 else { throw CoreError.invalidQuantity }
            guard let portion = profile.portions.first(where: { $0.id == id }) else { throw CoreError.missingConversion }
            if profile.basis.unit == .definedPortion && profile.basis.portionID == id { return (count.value, .definedPortion, portion.quality == .estimated) }
            if let mass = portion.massGrams { return (try Arithmetic.multiply(mass.value, count.value), .g, portion.quality == .estimated) }
            if let volume = portion.volumeMillilitres { return (try Arithmetic.multiply(volume.value, count.value), .ml, portion.quality == .estimated) }
            throw CoreError.missingConversion
        }
    }
    private static func convert(_ amount: Decimal, from: BasisUnit, to: BasisUnit, density: Density?) throws -> Decimal {
        if from == to { return amount }
        guard from != .definedPortion, to != .definedPortion, let density else { throw CoreError.missingConversion }
        if from == .ml { return try Arithmetic.multiply(amount, density.gramsPerMillilitre.value) }
        return try Arithmetic.divide(amount, density.gramsPerMillilitre.value)
    }
}

public enum ExportEligibility: Equatable, Sendable { case eligible, incomplete, semanticPolicyRequired, estimatedPolicyRequired, unsupported }
public enum HealthSemanticPolicy {
    /// No HealthKit dependency or side effect. Parent carbohydrate definition and
    /// standalone sugar/fibre policy remain blocked pending explicit review.
    public static func eligibility(_ nutrient: Nutrient, totals: NutritionTotals) -> ExportEligibility {
        let total = totals[nutrient]
        guard total.completeness == .complete else { return .incomplete }
        switch nutrient {
        case .carbohydrateAvailable, .carbohydrateTotal, .sugars, .fibre: return .semanticPolicyRequired
        case .saturatedFat:
            let parent = totals[.totalFat]
            guard parent.completeness == .complete, parent.knownSubtotal >= total.knownSubtotal else { return .semanticPolicyRequired }
            return total.estimated || parent.estimated ? .estimatedPolicyRequired : .eligible
        case .salt: return .unsupported
        default: return total.estimated ? .estimatedPolicyRequired : .eligible
        }
    }
}
