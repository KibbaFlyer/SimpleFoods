import SwiftUI
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary
import MealTrackerLocalization

private struct RecipeCandidate: Identifiable {
    let food: CatalogueFood
    let overlayRevision: Int64?
    let fixture: Bool
    let provenance: [String: Provenance]
    let evidence: [String: FixtureEvidence]
    var id: FoodID { food.id }
}
private struct RecipeReviewRow: Identifiable {
    let id: Int
    let original: String
    var query: String
    var amount: String
    var unit: QuantityUnit
    var foodID: FoodID?
    var included = true
}

/// Local-only review sheet. Nothing is appended to the meal until every included
/// ingredient has an explicit food and a calculable, positive quantity.
struct RecipeImportView: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let completion: ([MealComponent]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var rows: [RecipeReviewRow] = []
    @State private var candidates: [RecipeCandidate] = []
    @State private var ignored: [String] = []
    @State private var analyzed = false
    @State private var busy = false
    @State private var error: String?
    @State private var mealName = ""
    @State private var tags = ""
    @State private var servings = "1"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(copy.text("recipeImportExperimental"), systemImage: "flask")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !analyzed {
                    Section(copy.text("recipePaste")) {
                        TextEditor(text: $text).frame(minHeight: 180).accessibilityIdentifier("recipe.text")
                        Text(copy.text("recipePrivacy")).font(.caption)
                        Button(copy.text("recipeAnalyze")) { Task { await analyze() } }.disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if busy { ProgressView() }
                    }
                } else {
                    Section(copy.text("savedMealDetails")) {
                        TextField(copy.text("mealName"), text: $mealName)
                        RecipeTagsField(text: $tags, copy: copy)
                        LabeledContent(copy.text("servingsProduced")) {
                            TextField("", text: $servings)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel(copy.text("servingsProduced"))
                        }
                    }
                    Section {
                        Text(copy.text("recipeReviewHelp")).font(.footnote)
                        Text(copy.text("recipeUnitsHelp")).font(.caption).foregroundStyle(.secondary)
                        Button(copy.text("recipeEditText")) { analyzed = false }
                    }
                    ForEach($rows) { $row in
                        Section {
                            Text(row.original).font(.headline)
                            Toggle(copy.text("recipeInclude"), isOn: $row.included)
                            if row.included {
                                NavigationLink {
                                    foodChoices(row: $row)
                                } label: {
                                    LabeledContent(copy.text("chooseFood"), value: selectedName(row))
                                }
                                TextField(copy.text("amount"), text: $row.amount).keyboardType(.decimalPad)
                                Picker(copy.text("unit"), selection: $row.unit) { Text("g").tag(QuantityUnit.grams); Text("ml").tag(QuantityUnit.millilitres) }
                                if !ready(row) { Text(copy.text("recipeNeedsReview")).font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }
                    if !ignored.isEmpty {
                        DisclosureGroup(copy.text("recipeIgnored")) {
                            ForEach(Array(ignored.enumerated()), id: \.offset) { _, line in Text(line).font(.caption) }
                        }
                    }
                    if rows.isEmpty { Text(copy.text("recipeNoIngredients")) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(copy.text("recipeImport"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if analyzed {
                        Button(copy.text("recipeAdd")) { add() }
                            .disabled(
                                mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                copy.canonicalQuantity(servings) == nil ||
                                rows.filter(\.included).isEmpty ||
                                rows.contains { $0.included && !ready($0) }
                            )
                    }
                }
            }
        }
    }
    private func name(_ food: CatalogueFood) -> String { model.name(food, language: copy.language.rawValue) }
    private func selectedName(_ row: RecipeReviewRow) -> String { candidates.first { $0.id == row.foodID }.map { name($0.food) } ?? copy.text("recipeChoose") }
    @ViewBuilder private func foodChoices(row: Binding<RecipeReviewRow>) -> some View {
        List {
            TextField(copy.text("search"), text: row.query)
            Button(copy.text("recipeChoose")) { row.wrappedValue.foodID = nil }
            let matches = RecipeFoodMatcher.suggestions(row.wrappedValue.query, foods: candidates.map(\.food))
            if matches.isEmpty { Text(copy.text("recipeNoMatch")) }
            ForEach(matches, id: \.id) { food in
                Button { row.wrappedValue.foodID = food.id } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(name(food))
                            Text(source(food)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.wrappedValue.foodID == food.id { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle(copy.text("chooseFood"))
    }
    private func source(_ food: CatalogueFood) -> String {
        if case .personal = food.id { return copy.text("userEntered") }
        if case let .catalogue(namespace, _) = food.id, namespace == "off" { return "Open Food Facts · " + food.salesCountries.joined(separator: ", ") }
        if case let .catalogue(namespace, _) = food.id, namespace == "livsmedelsverket" { return copy.text("livsmedelsverket") }
        return copy.text("source")
    }
    private func quantity(_ row: RecipeReviewRow) throws -> LoggedQuantity {
        guard let canonical = copy.canonicalQuantity(row.amount) else { throw CoreError.invalidQuantity }
        return LoggedQuantity(amount: try DecimalAmount(canonical), unit: row.unit)
    }
    private func ready(_ row: RecipeReviewRow) -> Bool {
        guard let candidate = candidates.first(where: { $0.id == row.foodID }), let quantity = try? quantity(row) else { return false }
        return (try? NutritionCalculator.calculate(profile: candidate.food.profile, quantity: quantity.consumed())) != nil
    }
    private func analyze() async {
        busy = true; defer { busy = false }
        do {
            let parsed = try RecipeTextParser.parse(text)
            var loaded: [RecipeCandidate] = []
            let local = try model.catalogue.search(query: "", language: copy.language.rawValue)
            for base in local {
                let resolved = try model.personal.resolve(base: base)
                loaded.append(.init(food: resolved.food, overlayRevision: resolved.overlayRevision, fixture: model.catalogue.fixtureOnly, provenance: model.catalogue.provenance, evidence: model.catalogue.evidence))
            }
            for product in try await model.off.cachedProducts() {
                guard let base = product.food else { continue }
                let resolved = try model.personal.resolve(base: base)
                loaded.append(.init(food: resolved.food, overlayRevision: resolved.overlayRevision, fixture: false, provenance: product.provenance, evidence: [:]))
            }
            for base in model.livsmedelsverketFoods {
                let resolved = try model.personal.resolve(base: base)
                loaded.append(.init(food: resolved.food, overlayRevision: resolved.overlayRevision, fixture: false, provenance: livsmedelsverketProvenance(for: base), evidence: [:]))
            }
            for personal in try model.personal.personalFoods() { loaded.append(.init(food: personal.food, overlayRevision: nil, fixture: false, provenance: [:], evidence: [:])) }
            candidates = loaded
            rows = parsed.ingredients.map { line in
                let amount = line.amount?.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",") ?? ""
                return RecipeReviewRow(id: line.id, original: line.original, query: line.name, amount: amount, unit: line.unit == .millilitres ? .millilitres : .grams, foodID: RecipeFoodMatcher.exactMatch(line.name, foods: loaded.map(\.food)))
            }
            ignored = parsed.ignoredLines; analyzed = true; error = nil
        } catch is RecipeImportError { error = copy.text("recipeInputError") }
        catch { self.error = appError(error, copy: copy) }
    }
    private func add() {
        do {
            let components = try rows.filter(\.included).map { row -> MealComponent in
                guard let candidate = candidates.first(where: { $0.id == row.foodID }) else { throw CoreError.invalidIdentity }
                return try MealComponent(food: candidate.food, generationID: model.catalogue.generationID, displayName: name(candidate.food), language: copy.language.rawValue, quantity: quantity(row), fixtureOnly: candidate.fixture, provenance: candidate.provenance, evidence: candidate.evidence, overlayRevision: candidate.overlayRevision)
            }
            guard !components.isEmpty else { return }
            guard let canonicalServings = copy.canonicalQuantity(servings) else { throw DiaryError.invalidInput }
            let meal = try SavedMealDraft(
                name: mealName,
                tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                servingsProduced: try DecimalAmount(canonicalServings),
                ingredients: components
            )
            _ = try model.diary.createSavedMeal(meal, operationID: UUID())
            model.reloadSavedMeals()
            RecipeEasterEgg.celebrateAfterDismissIfNeeded(name: meal.name)
            completion(components); dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }
}
