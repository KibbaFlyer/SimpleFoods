import Foundation
import MealTrackerCore

public enum DiaryError: Error, Equatable { case invalidZone, invalidInput, futureRequiresConfirmation, staleRevision, operationConflict, notFound, revisionOverflow, injectedFailure }
public enum MealCategory: String, Codable, CaseIterable, Sendable { case breakfast, lunch, dinner, snack }
public enum QuantityUnit: String, Codable, CaseIterable, Sendable { case grams, millilitres, portions }
public struct LoggedQuantity: Codable, Equatable, Sendable {
    public var amount: DecimalAmount
    public var unit: QuantityUnit
    public var portionID: String?
    public init(amount:DecimalAmount,unit:QuantityUnit,portionID:String?=nil) { self.amount=amount;self.unit=unit;self.portionID=portionID }
    public func consumed() throws -> ConsumedQuantity {
        guard amount.value > 0, unit == .portions || portionID == nil else { throw DiaryError.invalidInput }
        switch unit { case .grams:return .grams(amount);case .millilitres:return .millilitres(amount);case .portions:guard let portionID else { throw CoreError.missingConversion };return .portions(id:portionID,count:amount) }
    }
}
public struct StoredNutrientTotal: Codable, Equatable, Sendable {
    public let knownSubtotal: DecimalAmount
    public let completeness: Completeness
    public let estimated: Bool
    public let derived: Bool
    public let missingReasons: [String]
    public let exclusiveTraceUpperBound: String?
    init(_ total:NutrientTotal) throws { knownSubtotal=try total.persistedAmount();completeness=total.completeness;estimated=total.estimated;derived=total.derived;missingReasons=total.missingReasons;exclusiveTraceUpperBound=total.exclusiveTraceUpperBound.map { NSDecimalNumber(decimal:$0).stringValue } }
}
public struct MealComponent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let food: CatalogueFood
    public let generationID: UUID
    public let displayName: String
    public let language: String
    public var quantity: LoggedQuantity
    public let fixtureOnly: Bool
    public let calculationVersion: String
    public let overlayRevision: Int64?
    public let provenance: [String:Provenance]
    public let evidence: [String:FixtureEvidence]
    public init(food:CatalogueFood,generationID:UUID,displayName:String,language:String,quantity:LoggedQuantity,fixtureOnly:Bool=true,provenance:[String:Provenance]=[:],evidence:[String:FixtureEvidence]=[:],overlayRevision:Int64?=nil) throws {
        _ = try NutritionCalculator.calculate(profile:food.profile,quantity:quantity.consumed())
        self.overlayRevision=overlayRevision
        self.provenance=provenance;self.evidence=evidence
        self.id=UUID();self.food=food;self.generationID=generationID;self.displayName=displayName;self.language=language;self.quantity=quantity;self.fixtureOnly=fixtureOnly;self.calculationVersion=NutritionCalculator.calculationVersion
    }

    /// Creates an independent component whose quantity is multiplied by `factor`.
    public func scaled(by factor: DecimalAmount) throws -> MealComponent {
        guard factor.value > 0 else { throw DiaryError.invalidInput }
        return try MealComponent(
            food: food,
            generationID: generationID,
            displayName: displayName,
            language: language,
            quantity: LoggedQuantity(amount: try quantity.amount.multiplied(by: factor), unit: quantity.unit, portionID: quantity.portionID),
            fixtureOnly: fixtureOnly,
            provenance: provenance,
            evidence: evidence,
            overlayRevision: overlayRevision
        )
    }
}

/// An editable complete meal. Ingredient quantities describe the whole produced meal.
public struct SavedMealDraft: Codable, Equatable, Sendable {
    public let name: String
    public let tags: [String]
    public let servingsProduced: DecimalAmount
    public let ingredients: [MealComponent]

    public init(name: String, tags: [String] = [], servingsProduced: DecimalAmount, ingredients: [MealComponent]) throws {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty,
              cleanedName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              servingsProduced.value > 0,
              !ingredients.isEmpty,
              Set(ingredients.map(\.id)).count == ingredients.count,
              tags.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } }),
              Set(tags.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == tags.count else {
            throw DiaryError.invalidInput
        }
        self.name = cleanedName
        self.tags = tags
        self.servingsProduced = servingsProduced
        self.ingredients = ingredients
    }
}

/// A versioned, locally saved complete meal. Deleted revisions are retained for idempotency.
public struct SavedMeal: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let revision: Int64
    public let name: String
    public let tags: [String]
    public let servingsProduced: DecimalAmount
    public let ingredients: [MealComponent]
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?

    init(id: UUID, revision: Int64, draft: SavedMealDraft, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        schemaVersion = 1
        self.id = id
        self.revision = revision
        name = draft.name
        tags = draft.tags
        servingsProduced = draft.servingsProduced
        ingredients = draft.ingredients
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Returns fresh diary components for a decimal number of servings.
    public func components(forServings servings: DecimalAmount) throws -> [MealComponent] {
        guard deletedAt == nil, servings.value > 0 else { throw DiaryError.invalidInput }
        let factor = try servings.divided(by: servingsProduced)
        return try ingredients.map { try $0.scaled(by: factor) }
    }
}
public struct MealDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var eatenAt: Date
    public var zoneID: String
    /// Nil chooses automatic category; a concrete value stays manual across time edits.
    public var category: MealCategory?
    public var components: [MealComponent]
    public var workingState: Data?
    public var expectedEventRevision: Int64?
    public init(id:UUID=UUID(),eatenAt:Date,zoneID:String,category:MealCategory?=nil,components:[MealComponent],workingState:Data?=nil,expectedEventRevision:Int64?=nil) { self.id=id;self.eatenAt=eatenAt;self.zoneID=zoneID;self.category=category;self.components=components;self.workingState=workingState;self.expectedEventRevision=expectedEventRevision }
}
public struct MealEvent: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let diaryIdentity: UUID
    public let revision: Int64
    public let eatenAt: Date
    public let zoneID: String
    public let utcOffsetSeconds: Int
    public let localDate: String
    public let category: MealCategory
    public let categoryMode: String
    public let components: [MealComponent]
    public let totals: [String:StoredNutrientTotal]
    public let calculationVersion: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
}
public enum DiaryTime {
    public static func validate(_ date:Date)throws { guard date.timeIntervalSince1970.isFinite, (-62135596800...253402300799).contains(date.timeIntervalSince1970) else { throw DiaryError.invalidInput } }
    public static func calendar(zoneID:String)throws->Calendar { guard let zone=TimeZone(identifier:zoneID) else { throw DiaryError.invalidZone };var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone;return calendar }
    public static func localDate(_ date:Date,zoneID:String)throws->String { try validate(date);let c=try calendar(zoneID:zoneID).dateComponents([.year,.month,.day],from:date);return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!) }
    public static func category(_ date: Date, zoneID: String) throws -> MealCategory {
        try validate(date)
        let hour = try calendar(zoneID: zoneID).component(.hour, from: date)
        switch hour {
        case ..<11: return .breakfast
        case ..<17: return .lunch
        default: return .dinner
        }
    }
    public static func dayInterval(containing date:Date,zoneID:String)throws->DateInterval { try validate(date);guard let interval=try calendar(zoneID:zoneID).dateInterval(of:.day,for:date) else { throw DiaryError.invalidInput };return interval }
}
