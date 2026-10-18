import Foundation
import GRDB
import MealTrackerCore

public enum NameEdit: Codable, Equatable, Sendable {
    case inherit
    case set(String)
    case clear
}

public enum ProfileEdit: Codable, Equatable, Sendable {
    case unchanged
    case inherit
    case set(NutritionProfile)
}

public struct PersonalResolution: Codable, Equatable, Sendable {
    public let food: CatalogueFood
    public let overlayRevision: Int64?
    public let sourceChanged: Bool
    public let needsReview: Bool
}

public struct PersonalFood: Codable, Equatable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: UUID
    public let revision: Int64
    public let food: CatalogueFood
    public let authorLanguage: String
    public let hidden: Bool
}

private struct StoredOverlay: Codable {
    let schemaVersion: Int
    let target: FoodID
    let revision: Int64
    let acceptedBase: CatalogueFood
    let names: [String: NameEdit]
    let fullProfile: NutritionProfile?
    let acceptedProfileBase: NutritionProfile?
}

/// Private, per-diary customization layer. Source records are never mutated.
/// A nutrition edit is an atomic complete profile; it cannot mix two bases.
public final class PersonalLibrary: @unchecked Sendable {
    private let store: DiaryStore
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
    private var decoder: JSONDecoder { JSONDecoder() }
    public init(store: DiaryStore) { self.store = store }

    public func resolve(base: CatalogueFood) throws -> PersonalResolution {
        try store.writer.read { db in
            try resolution(base: base, overlay: overlay(db, target: base.id))
        }
    }

    /// `names` patches supplied language paths only. `.inherit` removes that
    /// operation. `.clear` is explicit absence, never inheritance or blank text.
    public func saveOverlay(
        base: CatalogueFood,
        names: [String: NameEdit],
        profile: ProfileEdit = .unchanged,
        expectedRevision: Int64? = nil,
        operationID: UUID
    ) throws -> PersonalResolution {
        struct Request: Encodable {
            let command = "saveOverlay"
            let base: CatalogueFood
            let names: [String: NameEdit]
            let profile: ProfileEdit
            let expectedRevision: Int64?
        }
        let request = try encoder.encode(Request(base: base, names: names, profile: profile, expectedRevision: expectedRevision))
        return try store.writer.write { db in
            if let result: PersonalResolution = try receipt(db, id: operationID, request: request) { return result }
            guard case .catalogue = base.id else { throw DiaryError.invalidInput }
            let old = try overlay(db, target: base.id)
            guard old?.revision == expectedRevision else { throw DiaryError.staleRevision }
            var operations = old?.names ?? [:]
            for (language, edit) in names {
                guard ["sv", "en", "de"].contains(language) else { throw DiaryError.invalidInput }
                switch edit {
                case .inherit: operations.removeValue(forKey: language)
                case let .set(value):
                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DiaryError.invalidInput }
                    operations[language] = edit
                case .clear: operations[language] = edit
                }
            }
            let fullProfile: NutritionProfile?
            let acceptedProfileBase: NutritionProfile?
            switch profile {
            case .unchanged:
                fullProfile = old?.fullProfile
                acceptedProfileBase = old?.acceptedProfileBase
            case .inherit:
                fullProfile = nil
                acceptedProfileBase = nil
            case let .set(value):
                fullProfile = try Self.completeProfile(value, missingReason: "userCleared")
                acceptedProfileBase = base.profile
            }
            let revision = try next(old?.revision)
            let updated = StoredOverlay(schemaVersion: 1, target: base.id, revision: revision, acceptedBase: base, names: operations, fullProfile: fullProfile, acceptedProfileBase: acceptedProfileBase)
            let result = try resolution(base: base, overlay: updated)
            try writeOverlay(db, overlay: updated)
            try recordOperation(db, id: operationID, request: request, result: result)
            try change(db, id: try key(base.id), revision: revision, reason: "overlay")
            return result
        }
    }

    public func resetOverlay(base: CatalogueFood, expectedRevision: Int64, operationID: UUID) throws -> PersonalResolution {
        struct Request: Encodable {
            let command = "resetOverlay"
            let base: CatalogueFood
            let expectedRevision: Int64
        }
        let request = try encoder.encode(Request(base: base, expectedRevision: expectedRevision))
        return try store.writer.write { db in
            if let result: PersonalResolution = try receipt(db, id: operationID, request: request) { return result }
            guard let old = try overlay(db, target: base.id), old.revision == expectedRevision else { throw DiaryError.staleRevision }
            let revision = try next(old.revision)
            let reset = StoredOverlay(schemaVersion: 1, target: base.id, revision: revision, acceptedBase: base, names: [:], fullProfile: nil, acceptedProfileBase: nil)
            let result = try resolution(base: base, overlay: reset)
            try writeOverlay(db, overlay: reset)
            try recordOperation(db, id: operationID, request: request, result: result)
            try change(db, id: try key(base.id), revision: revision, reason: "overlayReset")
            return result
        }
    }

    public func savePersonal(
        id: UUID = UUID(),
        kind: String,
        names: [String: String],
        authorLanguage: String,
        profile: NutritionProfile,
        expectedRevision: Int64? = nil,
        operationID: UUID
    ) throws -> PersonalFood {
        struct Request: Encodable {
            let command = "savePersonal"
            let id: UUID
            let kind: String
            let names: [String: String]
            let authorLanguage: String
            let profile: NutritionProfile
            let expectedRevision: Int64?
        }
        let request = try encoder.encode(Request(id: id, kind: kind, names: names, authorLanguage: authorLanguage, profile: profile, expectedRevision: expectedRevision))
        return try store.writer.write { db in
            if let result: PersonalFood = try receipt(db, id: operationID, request: request) { return result }
            guard ["ingredient", "product"].contains(kind), ["sv", "en", "de"].contains(authorLanguage),
                  names[authorLanguage]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  names.allSatisfy({ ["sv", "en", "de"].contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw DiaryError.invalidInput }
            let old = try personal(db, id: id)
            guard old?.revision == expectedRevision else { throw DiaryError.staleRevision }
            let revision = try next(old?.revision)
            let food = CatalogueFood(id: .personal(id), revision: String(revision), kind: kind, lifecycle: "active", names: names, salesCountries: [], manufacturingCountries: [], ingredientOrigins: [], barcodes: [], profile: try Self.completeProfile(profile, missingReason: "notProvided"), provenanceRef: "user-authored")
            let result = PersonalFood(schemaVersion: 1, id: id, revision: revision, food: food, authorLanguage: authorLanguage, hidden: false)
            try writePersonal(db, record: result)
            try recordOperation(db, id: operationID, request: request, result: result)
            try change(db, id: id.uuidString, revision: revision, reason: "personalFood")
            return result
        }
    }

    public func personalFoods(includeHidden: Bool = false) throws -> [PersonalFood] {
        try store.writer.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM personal_foods WHERE hidden=0 OR ? ORDER BY id", arguments: [includeHidden]).map { try decodePersonal($0) }
        }
    }

    public func personalFood(id: UUID) throws -> PersonalFood {
        try store.writer.read { db in
            guard let result = try personal(db, id: id) else { throw DiaryError.notFound }
            return result
        }
    }

    public func personalHistory(id: UUID) throws -> [PersonalFood] {
        try store.writer.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM personal_food_history WHERE id=? ORDER BY revision", arguments: [id.uuidString]).map { try decodePersonal($0) }
        }
    }

    /// Hiding always retains prior revisions, including foods referenced by logs.
    public func hidePersonal(id: UUID, expectedRevision: Int64, operationID: UUID) throws -> PersonalFood {
        struct Request: Encodable {
            let command = "hidePersonal"
            let id: UUID
            let expectedRevision: Int64
        }
        let request = try encoder.encode(Request(id: id, expectedRevision: expectedRevision))
        return try store.writer.write { db in
            if let result: PersonalFood = try receipt(db, id: operationID, request: request) { return result }
            guard let old = try personal(db, id: id) else { throw DiaryError.notFound }
            guard old.revision == expectedRevision, !old.hidden else { throw DiaryError.staleRevision }
            let revision = try next(old.revision)
            let food = Self.copy(old.food, revision: String(revision), lifecycle: "hiddenPersonal")
            let result = PersonalFood(schemaVersion: 1, id: id, revision: revision, food: food, authorLanguage: old.authorLanguage, hidden: true)
            try writePersonal(db, record: result)
            try recordOperation(db, id: operationID, request: request, result: result)
            try change(db, id: id.uuidString, revision: revision, reason: "personalFoodHidden")
            return result
        }
    }

    public static func clearingNutrient(_ nutrient: Nutrient, in profile: NutritionProfile) throws -> NutritionProfile {
        var nutrients = profile.nutrients
        nutrients[nutrient.rawValue] = try NutrientValue(status: .unknown, unit: nutrient.unit, reason: "userCleared")
        return try rebuild(profile, nutrients: nutrients)
    }

    private static func completeProfile(_ profile: NutritionProfile, missingReason: String) throws -> NutritionProfile {
        var nutrients = profile.nutrients
        for nutrient in Nutrient.allCases where nutrients[nutrient.rawValue] == nil {
            nutrients[nutrient.rawValue] = try NutrientValue(status: .unknown, unit: nutrient.unit, reason: missingReason)
        }
        return try rebuild(profile, nutrients: nutrients)
    }

    private static func rebuild(_ profile: NutritionProfile, nutrients: [String: NutrientValue]) throws -> NutritionProfile {
        try NutritionProfile(profileRevision: profile.profileRevision, basis: profile.basis, preparation: profile.preparation, density: profile.density, nutrients: nutrients, portions: profile.portions, provenanceRef: profile.provenanceRef)
    }

    private func resolution(base: CatalogueFood, overlay: StoredOverlay?) throws -> PersonalResolution {
        guard let overlay else { return PersonalResolution(food: base, overlayRevision: nil, sourceChanged: false, needsReview: false) }
        guard overlay.target == base.id, overlay.schemaVersion == 1 else { throw DiaryError.invalidInput }
        var names = base.names
        for (language, edit) in overlay.names {
            switch edit {
            case .inherit: break
            case let .set(value): names[language] = value
            case .clear: names.removeValue(forKey: language)
            }
        }
        var missingFallback = false
        if !names.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            // A source update can remove the last unedited fallback language.
            // Keep the last accepted names usable and request review instead of
            // silently undoing an explicit user clear or losing the selection.
            guard overlay.acceptedBase != base else { throw DiaryError.invalidInput }
            names = overlay.acceptedBase.names
            for (language, edit) in overlay.names {
                switch edit {
                case .inherit: break
                case let .set(value): names[language] = value
                case .clear: names.removeValue(forKey: language)
                }
            }
            guard names.values.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw DiaryError.invalidInput }
            missingFallback = true
        }
        let changed = overlay.acceptedBase != base || (overlay.acceptedProfileBase.map { $0 != base.profile } ?? false)
        let needsReview = missingFallback || (overlay.fullProfile != nil && overlay.acceptedProfileBase.map { !Self.compatible($0, base.profile) } == true)
        let food = Self.copy(base, names: names, profile: overlay.fullProfile ?? base.profile)
        return PersonalResolution(food: food, overlayRevision: overlay.revision, sourceChanged: changed, needsReview: needsReview)
    }

    private static func compatible(_ accepted: NutritionProfile, _ current: NutritionProfile) -> Bool {
        // Deliberately conservative: full profiles stay coherent even when this
        // flags a change that could later receive an explicit conversion review.
        accepted.basis == current.basis && accepted.preparation == current.preparation && accepted.density == current.density && accepted.portions == current.portions
    }

    private static func copy(_ food: CatalogueFood, revision: String? = nil, lifecycle: String? = nil, names: [String: String]? = nil, profile: NutritionProfile? = nil) -> CatalogueFood {
        CatalogueFood(id: food.id, revision: revision ?? food.revision, kind: food.kind, lifecycle: lifecycle ?? food.lifecycle, names: names ?? food.names, salesCountries: food.salesCountries, manufacturingCountries: food.manufacturingCountries, ingredientOrigins: food.ingredientOrigins, barcodes: food.barcodes, profile: profile ?? food.profile, provenanceRef: food.provenanceRef)
    }

    private func key(_ id: FoodID) throws -> String { String(decoding: try encoder.encode(id), as: UTF8.self) }
    private func next(_ revision: Int64?) throws -> Int64 {
        guard revision != Int64.max else { throw DiaryError.revisionOverflow }
        return (revision ?? 0) + 1
    }
    private func overlay(_ db: Database, target: FoodID) throws -> StoredOverlay? {
        guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM personal_overlays WHERE target=?", arguments: [key(target)]) else { return nil }
        let value = try decoder.decode(StoredOverlay.self, from: data)
        guard value.schemaVersion == 1, value.target == target, value.revision > 0 else { throw DiaryError.invalidInput }
        return value
    }
    private func personal(_ db: Database, id: UUID) throws -> PersonalFood? {
        try Data.fetchOne(db, sql: "SELECT payload FROM personal_foods WHERE id=?", arguments: [id.uuidString]).map { try decodePersonal($0) }
    }
    private func decodePersonal(_ data: Data) throws -> PersonalFood {
        let value = try decoder.decode(PersonalFood.self, from: data)
        guard value.schemaVersion == 1, value.food.id == .personal(value.id), value.revision > 0 else { throw DiaryError.invalidInput }
        return value
    }
    private func writeOverlay(_ db: Database, overlay: StoredOverlay) throws {
        let target = try key(overlay.target)
        let data = try encoder.encode(overlay)
        try db.execute(sql: "INSERT INTO personal_overlays VALUES (?,?,?) ON CONFLICT(target) DO UPDATE SET revision=excluded.revision,payload=excluded.payload", arguments: [target, overlay.revision, data])
        try db.execute(sql: "INSERT INTO overlay_history VALUES (?,?,?)", arguments: [target, overlay.revision, data])
    }
    private func writePersonal(_ db: Database, record: PersonalFood) throws {
        let data = try encoder.encode(record)
        try db.execute(sql: "INSERT INTO personal_foods VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,hidden=excluded.hidden,payload=excluded.payload", arguments: [record.id.uuidString, record.revision, record.hidden, data])
        try db.execute(sql: "INSERT INTO personal_food_history VALUES (?,?,?)", arguments: [record.id.uuidString, record.revision, data])
    }
    private func receipt<Result: Decodable>(_ db: Database, id: UUID, request: Data) throws -> Result? {
        guard try Int.fetchOne(db, sql: "SELECT count(*) FROM operations WHERE id=?", arguments: [id.uuidString]) == 0 else { throw DiaryError.operationConflict }
        guard let row = try Row.fetchOne(db, sql: "SELECT request,result FROM personal_operations WHERE id=?", arguments: [id.uuidString]) else { return nil }
        let original: Data = row["request"]
        guard original == request else { throw DiaryError.operationConflict }
        return try decoder.decode(Result.self, from: row["result"])
    }
    private func recordOperation<Result: Encodable>(_ db: Database, id: UUID, request: Data, result: Result) throws {
        try db.execute(sql: "INSERT INTO personal_operations VALUES (?,?,?)", arguments: [id.uuidString, request, encoder.encode(result)])
    }
    private func change(_ db: Database, id: String, revision: Int64, reason: String) throws {
        try db.execute(sql: "INSERT INTO changes(event_id,revision,reason) VALUES (?,?,?)", arguments: [id, revision, reason])
    }
}
