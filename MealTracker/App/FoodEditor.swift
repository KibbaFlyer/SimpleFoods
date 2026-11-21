import SwiftUI
import MealTrackerCore
import MealTrackerDiary
import MealTrackerLocalization

/// A unit a food can be logged in: grams, millilitres, or one of the food's
/// own portions (such as a piece or a package), which carry their own weight.
struct FoodUnit: Hashable {
    static let pieceID = Portion.pieceID
    static let packageID = Portion.packageID
    static let servingID = Portion.servingID
    static let grams = FoodUnit(unit: .grams, portionID: nil)

    let unit: QuantityUnit
    let portionID: String?

    init(unit: QuantityUnit, portionID: String?) {
        self.unit = unit
        self.portionID = unit == .portions ? portionID : nil
    }

    init(_ quantity: LoggedQuantity) {
        self.init(unit: quantity.unit, portionID: quantity.portionID)
    }

    var isPortion: Bool { unit == .portions }

    /// The amount a newly selected unit starts with: 100 g/ml, or 1 piece/package.
    var defaultAmount: String { isPortion ? "1" : "100" }

    func quantity(_ amount: DecimalAmount) -> LoggedQuantity {
        LoggedQuantity(amount: amount, unit: unit, portionID: portionID)
    }

    /// Every unit the nutrition calculator can convert for this food.
    static func available(for food: CatalogueFood) -> [FoodUnit] {
        guard let one = try? DecimalAmount("1") else { return [] }
        let candidates = [FoodUnit.grams, FoodUnit(unit: .millilitres, portionID: nil)]
            + food.profile.portions.map { FoodUnit(unit: .portions, portionID: $0.id) }
        return candidates.filter { candidate in
            guard let consumed = try? candidate.quantity(one).consumed() else { return false }
            return (try? NutritionCalculator.calculate(profile: food.profile, quantity: consumed)) != nil
        }
    }

    func label(for food: CatalogueFood?, copy: AppCopy) -> String {
        switch unit {
        case .grams: return "g"
        case .millilitres: return "ml"
        case .portions:
            switch portionID {
            case Self.pieceID: return copy.text("piece")
            case Self.packageID: return copy.text("package")
            case Self.servingID: return copy.text("serving")
            default:
                let names = food?.profile.portions.first { $0.id == portionID }?.names
                return names?[copy.language.rawValue] ?? names?["en"] ?? copy.text("portions")
            }
        }
    }

    /// The label for unit pickers: portions also say how much one of them is,
    /// e.g. "serving (45 g)", so the user knows what they are choosing.
    func pickerLabel(for food: CatalogueFood, copy: AppCopy) -> String {
        let name = label(for: food, copy: copy)
        guard isPortion, let portion = food.profile.portions.first(where: { $0.id == portionID }) else { return name }
        if let grams = portion.massGrams { return name + " (" + copy.number(grams.value) + " g)" }
        if let millilitres = portion.volumeMillilitres { return name + " (" + copy.number(millilitres.value) + " ml)" }
        return name
    }
}

/// Overrides replace one whole validated nutrition profile. Sync only updates the base.
struct FoodEditor: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let base: CatalogueFood?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var initialName = ""
    @State private var kind = "ingredient"
    @State private var basis = "100"
    @State private var unit = BasisUnit.g
    @State private var pieceSize = ""
    @State private var packageSize = ""
    @State private var portionsDirty = false
    @State private var values: [String: String] = [:]
    @State private var dirtyNutrients: Set<String> = []
    @State private var originalProfile: NutritionProfile?
    @State private var revision: Int64?
    @State private var personalRecord: PersonalFood?
    @State private var error: String?
    @State private var operationID = UUID()
    @State private var newID = UUID()
    @State private var profileRevision = UUID().uuidString
    @State private var reset = false

    private let nutrientOrder: [Nutrient] = [
        .energy, .protein, .carbohydrateAvailable, .sugars, .carbohydrateTotal,
        .totalFat, .saturatedFat, .fibre, .salt, .sodium
    ]

    var body: some View {
        NavigationStack {
            Form {
                TextField(copy.text("name"), text: $name)
                if base == nil { Picker(copy.text("kind"), selection: $kind) { Text(copy.text("ingredient")).tag("ingredient"); Text(copy.text("product")).tag("product") } }
                Text(copy.text("overrideExplanation")).font(.footnote).foregroundStyle(.secondary)
                Section(copy.text("basis")) {
                    TextField(copy.text("amount"), text: $basis).keyboardType(.decimalPad).disabled(base != nil)
                    Picker(copy.text("unit"), selection: $unit) { Text("g").tag(BasisUnit.g); Text("ml").tag(BasisUnit.ml); if originalProfile?.basis.unit == .definedPortion { Text(copy.text("definedPortion")).tag(BasisUnit.definedPortion) } }.disabled(base != nil)
                }
                if unit != .definedPortion {
                    Section {
                        portionSizeField("pieceSize", text: $pieceSize)
                        portionSizeField("packageSize", text: $packageSize)
                    } header: {
                        Text(copy.text("portionSizes"))
                    } footer: {
                        Text(copy.text("portionSizesHelp"))
                    }
                }
                Section(copy.text("nutrition")) {
                    Text(copy.text("blankUnknown")).font(.footnote)
                    ForEach(nutrientOrder, id: \.rawValue) { nutrient in
                        VStack(alignment: .leading) {
                            Text(copy.text(nutrient.rawValue) + " (" + nutrient.unit.rawValue + ")")
                            if nutrient == .carbohydrateTotal, base == nil {
                                Text(calculatedCarbohydrateTotal ?? "—")
                                    .foregroundStyle(.secondary)
                            } else {
                                TextField("—", text: Binding(get: { values[nutrient.rawValue] ?? "" }, set: { values[nutrient.rawValue] = $0; dirtyNutrients.insert(nutrient.rawValue) })).keyboardType(.decimalPad)
                            }
                        }
                    }
                }
                if base != nil, revision != nil { Button(copy.text("reset"), role: .destructive) { reset = true } }

            }.navigationTitle(copy.text(base == nil ? "createFood" : "customize"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(copy.text("saveFood")) { save() } }
                }.onAppear(perform: load)
                .confirmationDialog(copy.text("reset"), isPresented: $reset, titleVisibility: .visible) { Button(copy.text("reset"), role: .destructive) { do { if let base, let revision { _ = try model.personal.resetOverlay(base: base, expectedRevision: revision, operationID: operationID) }; dismiss() } catch { self.error = appError(error, copy: copy) } } }
        }
        .temporaryErrorBanner($error)
    }
    func load() {
        guard let base else { return }
        do {
            if case let .personal(id) = base.id { personalRecord = try model.personal.personalFood(id: id); kind = base.kind }
            let effectiveBase = personalRecord?.food ?? base
            let resolution = try model.personal.resolve(base: effectiveBase); revision = resolution.overlayRevision
            let food = resolution.food; name = food.names[copy.language.rawValue] ?? food.names["en"] ?? food.names.sorted(by: { $0.key < $1.key }).first?.value ?? ""
            initialName = name
            originalProfile = food.profile; basis = localized(food.profile.basis.quantity); unit = food.profile.basis.unit
            for nutrient in Nutrient.allCases { values[nutrient.rawValue] = food.profile.nutrients[nutrient.rawValue]?.value.map(localized) ?? "" }
            pieceSize = portionSize(FoodUnit.pieceID, in: food.profile)
            packageSize = portionSize(FoodUnit.packageID, in: food.profile)
        } catch { self.error = appError(error, copy: copy) }
    }
    func localized(_ amount: DecimalAmount) -> String { amount.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",") }

    private var basisUnitLabel: String { unit == .ml ? "ml" : "g" }

    private func portionSizeField(_ key: String, text: Binding<String>) -> some View {
        LabeledContent(copy.text(key) + " (" + basisUnitLabel + ")") {
            TextField("—", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; portionsDirty = true }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func portionSize(_ id: String, in profile: NutritionProfile) -> String {
        guard let portion = profile.portions.first(where: { $0.id == id }) else { return "" }
        return (portion.massGrams ?? portion.volumeMillilitres).map(localized) ?? ""
    }

    /// Keeps portions from the source (and any defined-portion basis) and
    /// replaces the piece/package portions with what the user entered. Sizes
    /// are stored in the basis unit so no density conversion is needed.
    private func editedPortions() throws -> [Portion]? {
        let original = originalProfile?.portions ?? []
        // A changed basis unit (g ↔ ml) also rebuilds the sizes in the new unit.
        guard portionsDirty || unit != originalProfile?.basis.unit, unit != .definedPortion else { return original }
        var portions = original.filter { $0.id != FoodUnit.pieceID && $0.id != FoodUnit.packageID }
        for (id, raw) in [(FoodUnit.pieceID, pieceSize), (FoodUnit.packageID, packageSize)] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let canonical = copy.canonicalQuantity(trimmed) else { return nil }
            let size = try DecimalAmount(canonical)
            portions.append(try Portion(
                id: id,
                names: nil,
                massGrams: unit == .ml ? nil : size,
                volumeMillilitres: unit == .ml ? size : nil,
                quality: .measured,
                evidenceRef: "personal.user"
            ))
        }
        return portions
    }

    private var calculatedCarbohydrateTotal: String? {
        let carbohydrate = decimalValue(for: .carbohydrateAvailable)
        let sugars = decimalValue(for: .sugars)
        guard carbohydrate != nil || sugars != nil else { return nil }
        let total = NSDecimalNumber(decimal: (carbohydrate ?? 0) + (sugars ?? 0)).stringValue
        guard let amount = try? DecimalAmount(total) else { return nil }
        return localized(amount)
    }

    private func decimalValue(for nutrient: Nutrient) -> Decimal? {
        guard let raw = values[nutrient.rawValue],
              let canonical = copy.canonicalQuantity(raw, allowZero: true),
              let amount = try? DecimalAmount(canonical) else { return nil }
        return amount.value
    }

    func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let quantity = copy.canonicalQuantity(basis) else { error = copy.text("foodValidation"); return }
        do {
            var nutrients: [String: NutrientValue] = [:]
            for nutrient in Nutrient.allCases {
                if nutrient == .carbohydrateTotal, base == nil {
                    let carbohydrate = decimalValue(for: .carbohydrateAvailable)
                    let sugars = decimalValue(for: .sugars)
                    if carbohydrate != nil || sugars != nil,
                       let amount = try? DecimalAmount(NSDecimalNumber(decimal: (carbohydrate ?? 0) + (sugars ?? 0)).stringValue) {
                        nutrients[nutrient.rawValue] = try NutrientValue(
                            status: amount.value == 0 ? .knownZero : .known,
                            value: amount,
                            unit: nutrient.unit
                        )
                    } else {
                        nutrients[nutrient.rawValue] = try NutrientValue(status: .unknown, unit: nutrient.unit, reason: "carbohydrateInputsUnknown")
                    }
                    continue
                }
                let raw = values[nutrient.rawValue] ?? ""
                if !dirtyNutrients.contains(nutrient.rawValue), let original = originalProfile?.nutrients[nutrient.rawValue] { nutrients[nutrient.rawValue] = original }
                else if raw.isEmpty { nutrients[nutrient.rawValue] = try NutrientValue(status: .unknown, unit: nutrient.unit, reason: "userCleared") }
                else {
                    guard let canonical = copy.canonicalQuantity(raw, allowZero: true) else { error = copy.text("quantityError"); return }
                    let amount = try DecimalAmount(canonical)
                    // Preserve trace/derived metadata when the user leaves an existing exact value unchanged.
                    if let old = originalProfile?.nutrients[nutrient.rawValue], old.value == amount { nutrients[nutrient.rawValue] = old }
                    else { nutrients[nutrient.rawValue] = try NutrientValue(status: amount.value == 0 ? .knownZero : .known, value: amount, unit: nutrient.unit) }
                }
            }
            guard let portions = try editedPortions() else { error = copy.text("quantityError"); return }
            let reference = originalProfile?.provenanceRef ?? "personal.user"
            let profile = try NutritionProfile(profileRevision: profileRevision, basis: NutritionBasis(quantity: DecimalAmount(quantity), unit: unit, portionID: unit == .definedPortion ? originalProfile?.basis.portionID : nil), preparation: originalProfile?.preparation ?? "asEntered", density: originalProfile?.density, nutrients: nutrients, portions: portions, provenanceRef: reference)
            if let personalRecord { var names = personalRecord.food.names; names[copy.language.rawValue] = name; _ = try model.personal.savePersonal(id: personalRecord.id, kind: kind, names: names, authorLanguage: personalRecord.authorLanguage, profile: profile, expectedRevision: personalRecord.revision, operationID: operationID) }
            else if let base { _ = try model.personal.saveOverlay(base: base, names: name == initialName ? [:] : [copy.language.rawValue: .set(name)], profile: dirtyNutrients.isEmpty && !portionsDirty ? .unchanged : .set(profile), expectedRevision: revision, operationID: operationID) }
            else { _ = try model.personal.savePersonal(id: newID, kind: kind, names: [copy.language.rawValue: name], authorLanguage: copy.language.rawValue, profile: profile, operationID: operationID) }
            dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }
}
