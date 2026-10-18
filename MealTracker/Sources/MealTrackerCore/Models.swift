import Foundation

public enum Nutrient: String, Codable, CaseIterable, Sendable {
    case energy = "energy.declared", protein, carbohydrateAvailable = "carbohydrate.euAvailable"
    case carbohydrateTotal = "carbohydrate.total", totalFat = "fat.total", saturatedFat = "fat.saturated"
    case sugars, fibre, salt = "salt.equivalent", sodium
    public var unit: NutrientUnit {
        switch self { case .energy: return .kcal; case .sodium: return .mg; default: return .g }
    }
}
public enum NutrientUnit: String, Codable, Sendable { case kcal, g, mg }
public enum NutrientStatus: String, Codable, Sendable { case known, knownZero, unknown, trace, derived }
public struct NutrientValue: Codable, Equatable, Sendable {
    public let status: NutrientStatus
    public let value: DecimalAmount?
    public let unit: NutrientUnit
    public let reason: String?
    public let upperBound: DecimalAmount?
    public let methodID: String?
    public let inputRefs: [String]?
    public let estimated: Bool?
    public init(status: NutrientStatus, value: DecimalAmount? = nil, unit: NutrientUnit,
                reason: String? = nil, upperBound: DecimalAmount? = nil, methodID: String? = nil,
                inputRefs: [String]? = nil, estimated: Bool? = nil) throws {
        switch status {
        case .known: guard let value, value.value > 0 else { throw CoreError.invalidProfile("known requires positive value") }
        case .knownZero: guard value?.value == 0 else { throw CoreError.invalidProfile("knownZero requires zero") }
        case .unknown: guard value == nil, let reason, !reason.isEmpty else { throw CoreError.invalidProfile("unknown requires reason and no value") }
        case .trace: guard value == nil, upperBound == nil || upperBound!.value > 0 else { throw CoreError.invalidProfile("trace cannot have point value") }
        case .derived: guard value != nil, let methodID, !methodID.isEmpty, inputRefs?.isEmpty == false, inputRefs!.allSatisfy({ !$0.isEmpty }), estimated != nil else { throw CoreError.invalidProfile("derived requires method, inputs and estimate flag") }
        }
        guard status == .trace || upperBound == nil else { throw CoreError.invalidProfile("unexpected bound") }
        guard status == .derived || (methodID == nil && inputRefs == nil && estimated == nil) else { throw CoreError.invalidProfile("unexpected derivation") }
        guard status == .unknown || reason == nil else { throw CoreError.invalidProfile("unexpected unknown reason") }
        self.status = status; self.value = value; self.unit = unit; self.reason = reason
        self.upperBound = upperBound; self.methodID = methodID; self.inputRefs = inputRefs; self.estimated = estimated
    }
    enum CodingKeys: String, CodingKey { case status, value, unit, reason, upperBound, methodID, inputRefs, estimated }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(status: c.decode(NutrientStatus.self, forKey: .status), value: c.decodeIfPresent(DecimalAmount.self, forKey: .value), unit: c.decode(NutrientUnit.self, forKey: .unit), reason: c.decodeIfPresent(String.self, forKey: .reason), upperBound: c.decodeIfPresent(DecimalAmount.self, forKey: .upperBound), methodID: c.decodeIfPresent(String.self, forKey: .methodID), inputRefs: c.decodeIfPresent([String].self, forKey: .inputRefs), estimated: c.decodeIfPresent(Bool.self, forKey: .estimated))
    }
}

public enum FoodID: Codable, Equatable, Hashable, Sendable {
    case catalogue(namespace: String, recordID: String), personal(UUID)
    enum Keys: String, CodingKey { case scope, namespace, recordID, uuid }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .scope) {
        case "catalogue":
            let namespace = try c.decode(String.self, forKey: .namespace), record = try c.decode(String.self, forKey: .recordID)
            guard namespace.range(of: #"^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)*$"#, options: .regularExpression) != nil, !record.isEmpty,
                  !record.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw CoreError.invalidIdentity }
            self = .catalogue(namespace: namespace, recordID: record)
        case "personal":
            let string = try c.decode(String.self, forKey: .uuid)
            guard let uuid = UUID(uuidString: string), string == uuid.uuidString.lowercased() else { throw CoreError.invalidIdentity }
            self = .personal(uuid)
        default: throw CoreError.invalidIdentity
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .catalogue(namespace, recordID): try c.encode("catalogue", forKey: .scope); try c.encode(namespace, forKey: .namespace); try c.encode(recordID, forKey: .recordID)
        case let .personal(uuid): try c.encode("personal", forKey: .scope); try c.encode(uuid.uuidString.lowercased(), forKey: .uuid)
        }
    }
}
public enum BasisUnit: String, Codable, Sendable { case g, ml, definedPortion }
public struct NutritionBasis: Codable, Equatable, Sendable {
    public let quantity: DecimalAmount
    public let unit: BasisUnit
    public let portionID: String?
    public init(quantity: DecimalAmount, unit: BasisUnit, portionID: String? = nil) throws {
        guard quantity.value > 0, unit != .definedPortion || portionID?.isEmpty == false,
              unit == .definedPortion || portionID == nil else { throw CoreError.invalidProfile("invalid basis") }
        self.quantity = quantity; self.unit = unit; self.portionID = portionID
    }
    enum CodingKeys: String, CodingKey { case quantity, unit, portionID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(quantity: c.decode(DecimalAmount.self, forKey: .quantity), unit: c.decode(BasisUnit.self, forKey: .unit), portionID: c.decodeIfPresent(String.self, forKey: .portionID))
    }
}
public enum EvidenceQuality: String, Codable, Sendable { case measured, estimated }
public struct Density: Codable, Equatable, Sendable {
    public let gramsPerMillilitre: DecimalAmount
    public let evidenceRef: String
    public let quality: EvidenceQuality
    public init(gramsPerMillilitre: DecimalAmount, evidenceRef: String, quality: EvidenceQuality) throws {
        guard gramsPerMillilitre.value > 0, !evidenceRef.isEmpty else { throw CoreError.invalidProfile("invalid density") }
        self.gramsPerMillilitre = gramsPerMillilitre; self.evidenceRef = evidenceRef; self.quality = quality
    }
}
public struct Portion: Codable, Equatable, Sendable {
    public let id: String
    public let names: [String: String]?
    public let massGrams: DecimalAmount?
    public let volumeMillilitres: DecimalAmount?
    public let quality: EvidenceQuality
    public let evidenceRef: String
    public init(id: String, names: [String: String]?, massGrams: DecimalAmount?, volumeMillilitres: DecimalAmount?, quality: EvidenceQuality, evidenceRef: String) throws {
        guard !id.isEmpty, !evidenceRef.isEmpty, massGrams != nil || volumeMillilitres != nil,
              massGrams == nil || massGrams!.value > 0, volumeMillilitres == nil || volumeMillilitres!.value > 0 else { throw CoreError.invalidProfile("invalid portion") }
        self.id = id; self.names = names; self.massGrams = massGrams; self.volumeMillilitres = volumeMillilitres; self.quality = quality; self.evidenceRef = evidenceRef
    }
}
public struct NutritionProfile: Codable, Equatable, Sendable {
    public let profileRevision: String
    public let basis: NutritionBasis
    public let preparation: String
    public let density: Density?
    public let nutrients: [String: NutrientValue]
    public let portions: [Portion]
    public let provenanceRef: String
    public init(profileRevision: String, basis: NutritionBasis, preparation: String, density: Density?, nutrients: [String: NutrientValue], portions: [Portion], provenanceRef: String) throws {
        guard !profileRevision.isEmpty, !preparation.isEmpty, !provenanceRef.isEmpty else { throw CoreError.invalidProfile("missing metadata") }
        if let density { guard density.gramsPerMillilitre.value > 0, !density.evidenceRef.isEmpty else { throw CoreError.invalidProfile("invalid density") } }
        guard Set(portions.map(\.id)).count == portions.count else { throw CoreError.invalidProfile("duplicate portion") }
        for portion in portions {
            guard !portion.id.isEmpty, !portion.evidenceRef.isEmpty,
                  portion.massGrams != nil || portion.volumeMillilitres != nil,
                  portion.massGrams == nil || portion.massGrams!.value > 0,
                  portion.volumeMillilitres == nil || portion.volumeMillilitres!.value > 0 else { throw CoreError.invalidProfile("invalid portion") }
            if let mass = portion.massGrams, let volume = portion.volumeMillilitres {
                guard let density, try Arithmetic.multiply(volume.value, density.gramsPerMillilitre.value) == mass.value else { throw CoreError.invalidProfile("inconsistent portion equivalents") }
            }
        }
        if basis.unit == .definedPortion { guard portions.contains(where: { $0.id == basis.portionID }) else { throw CoreError.invalidProfile("missing basis portion") } }
        for (key, value) in nutrients {
            guard let nutrient = Nutrient(rawValue: key) else { throw CoreError.unsupportedNutrient(key) }
            guard value.unit == nutrient.unit else { throw CoreError.invalidProfile("wrong unit for \(key)") }
        }
        self.profileRevision = profileRevision; self.basis = basis; self.preparation = preparation; self.density = density
        self.nutrients = nutrients; self.portions = portions; self.provenanceRef = provenanceRef
    }
    enum CodingKeys: String, CodingKey { case profileRevision, basis, preparation, density, nutrients, portions, provenanceRef }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(profileRevision: c.decode(String.self, forKey: .profileRevision), basis: c.decode(NutritionBasis.self, forKey: .basis), preparation: c.decode(String.self, forKey: .preparation), density: c.decodeIfPresent(Density.self, forKey: .density), nutrients: c.decode([String: NutrientValue].self, forKey: .nutrients), portions: c.decode([Portion].self, forKey: .portions), provenanceRef: c.decode(String.self, forKey: .provenanceRef))
    }
}
public struct CatalogueFood: Codable, Equatable, Sendable {
    public let id: FoodID
    public let revision: String
    public let kind: String
    public let lifecycle: String
    public let names: [String: String]
    public let salesCountries: [String]
    public let manufacturingCountries: [String]
    public let ingredientOrigins: [String]
    public let barcodes: [String]
    public let profile: NutritionProfile
    public let provenanceRef: String

    /// Construct an immutable record from an already validated profile. Repositories
    /// remain responsible for validating source identity, metadata and references.
    public init(id: FoodID, revision: String, kind: String, lifecycle: String,
                names: [String: String], salesCountries: [String],
                manufacturingCountries: [String], ingredientOrigins: [String],
                barcodes: [String], profile: NutritionProfile, provenanceRef: String) {
        self.id = id
        self.revision = revision
        self.kind = kind
        self.lifecycle = lifecycle
        self.names = names
        self.salesCountries = salesCountries
        self.manufacturingCountries = manufacturingCountries
        self.ingredientOrigins = ingredientOrigins
        self.barcodes = barcodes
        self.profile = profile
        self.provenanceRef = provenanceRef
    }
}
public struct Provenance: Codable, Equatable, Sendable {
    public let providerID: String
    public let sourceRecordID: String
    public let sourceURL: String?
    public let upstreamVersion: String
    public let retrievedAt: String
    public let sourceLanguage: String
    public let licenceReference: String
    public let transformationVersion: String
    public let reviewStatus: String
}
public struct FixtureEvidence: Codable, Equatable, Sendable {
    public let kind: String
    public let description: String
    public let provenanceRef: String
}
public struct CatalogueFixture: Codable, Sendable {
    public let schemaVersion: Int
    public let fixtureOnly: Bool
    public let generationID: UUID
    public let packID: String
    public let packVersion: String
    public let calculationVersion: String
    public let provenance: [String: Provenance]
    public let foods: [CatalogueFood]
    public let evidence: [String: FixtureEvidence]?
    public let retainedRevisions: [CatalogueFood]
    /// Call after decoding envelope; record/profile decoding validates numerical shapes.
    public func validate() throws {
        guard schemaVersion == 1, fixtureOnly, !packID.isEmpty, Set(foods.map(\.id)).count == foods.count else { throw CoreError.invalidProfile("invalid fixture envelope") }
        for item in (evidence ?? [:]).values {
            guard item.kind == "synthetic", !item.description.isEmpty, provenance[item.provenanceRef] != nil else { throw CoreError.invalidProfile("invalid evidence") }
        }
        for food in foods + retainedRevisions {
            guard let foodProvenance = provenance[food.provenanceRef], let profileProvenance = provenance[food.profile.provenanceRef], foodProvenance.providerID == profileProvenance.providerID else { throw CoreError.invalidProfile("cross-provider profile") }
            if case let .catalogue(namespace, _) = food.id { guard namespace == foodProvenance.providerID else { throw CoreError.invalidProfile("namespace/provider mismatch") } }
            for reference in food.profile.portions.map(\.evidenceRef) + (food.profile.density.map { [$0.evidenceRef] } ?? []) + food.profile.nutrients.values.flatMap({ $0.inputRefs ?? [] }) {
                guard let referencedEvidence = evidence?[reference], provenance[referencedEvidence.provenanceRef]?.providerID == profileProvenance.providerID else { throw CoreError.invalidProfile("unresolved or cross-provider evidence") }
            }
            guard !food.revision.isEmpty, ["ingredient", "product"].contains(food.kind), ["active", "retired"].contains(food.lifecycle), !food.names.isEmpty, provenance[food.provenanceRef] != nil, provenance[food.profile.provenanceRef] != nil else { throw CoreError.invalidProfile("invalid fixture food") }
        }
    }
}

// Encode the portable wire shape rather than Swift's omit-nil synthesis.
extension NutrientValue {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encode(unit, forKey: .unit)
        switch status {
        case .known, .knownZero: try c.encode(value, forKey: .value)
        case .unknown: try c.encode(reason, forKey: .reason)
        case .trace: try c.encode(upperBound, forKey: .upperBound)
        case .derived:
            try c.encode(value, forKey: .value); try c.encode(methodID, forKey: .methodID)
            try c.encode(inputRefs, forKey: .inputRefs); try c.encode(estimated, forKey: .estimated)
        }
    }
}
extension NutritionBasis {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(quantity, forKey: .quantity); try c.encode(unit, forKey: .unit)
        try c.encode(portionID, forKey: .portionID)
    }
}
extension Portion {
    enum CodingKeys: String, CodingKey { case id, names, massGrams, volumeMillilitres, quality, evidenceRef }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(names, forKey: .names)
        try c.encode(massGrams, forKey: .massGrams); try c.encode(volumeMillilitres, forKey: .volumeMillilitres)
        try c.encode(quality, forKey: .quality); try c.encode(evidenceRef, forKey: .evidenceRef)
    }
}
extension NutritionProfile {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(profileRevision, forKey: .profileRevision); try c.encode(basis, forKey: .basis)
        try c.encode(preparation, forKey: .preparation); try c.encode(density, forKey: .density)
        try c.encode(nutrients, forKey: .nutrients); try c.encode(portions, forKey: .portions)
        try c.encode(provenanceRef, forKey: .provenanceRef)
    }
}
extension Provenance {
    enum CodingKeys: String, CodingKey { case providerID, sourceRecordID, sourceURL, upstreamVersion, retrievedAt, sourceLanguage, licenceReference, transformationVersion, reviewStatus }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(providerID, forKey: .providerID); try c.encode(sourceRecordID, forKey: .sourceRecordID)
        try c.encode(sourceURL, forKey: .sourceURL); try c.encode(upstreamVersion, forKey: .upstreamVersion)
        try c.encode(retrievedAt, forKey: .retrievedAt); try c.encode(sourceLanguage, forKey: .sourceLanguage)
        try c.encode(licenceReference, forKey: .licenceReference); try c.encode(transformationVersion, forKey: .transformationVersion)
        try c.encode(reviewStatus, forKey: .reviewStatus)
    }
}

extension CatalogueFixture {
    enum CodingKeys: String, CodingKey { case schemaVersion, fixtureOnly, generationID, packID, packVersion, calculationVersion, provenance, foods, evidence, retainedRevisions }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(fixtureOnly, forKey: .fixtureOnly)
        try c.encode(generationID.uuidString.lowercased(), forKey: .generationID)
        try c.encode(packID, forKey: .packID); try c.encode(packVersion, forKey: .packVersion)
        try c.encode(calculationVersion, forKey: .calculationVersion); try c.encode(provenance, forKey: .provenance)
        try c.encode(foods, forKey: .foods); try c.encode(retainedRevisions, forKey: .retainedRevisions)
        if let evidence { try c.encode(evidence, forKey: .evidence) }
    }
}
