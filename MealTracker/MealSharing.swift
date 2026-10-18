import Foundation
import CoreTransferable
import MealTrackerCore
import MealTrackerDiary
import UniformTypeIdentifiers

extension UTType {
    static let mealTrackerShare = UTType(exportedAs: "com.mealtracker.shared-item", conformingTo: .json)
}

struct MealShareDocument: Transferable {
    let data: Data
    let filename: String

    init?(_ payload: MealSharePayload, filename: String) {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        self.data = data
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = filename.components(separatedBy: invalidCharacters).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.filename = safeName.isEmpty ? "Simple Foods Share" : safeName
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mealTrackerShare) { document in
            try document.exportedFile()
        }
        // Messages and some third-party share extensions filter out private
        // UTIs even when they conform to a standard type. Advertise the same
        // file as JSON as a compatibility fallback, after the precise type.
        FileRepresentation(exportedContentType: .json) { document in
            try document.exportedFile()
        }
    }

    private func exportedFile() throws -> SentTransferredFile {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension("mealtracker")
        try data.write(to: url, options: .atomic)
        return SentTransferredFile(url)
    }
}

struct SharedFood: Codable {
    let id: UUID
    let kind: String
    let names: [String: String]
    let authorLanguage: String
    let profile: NutritionProfile

    init(food: CatalogueFood, fallbackName: String, language: String) {
        if case let .personal(id) = food.id {
            self.id = id
        } else {
            self.id = UUID()
        }
        kind = food.kind == "ingredient" ? "ingredient" : "product"
        names = food.names.isEmpty ? [language: fallbackName] : food.names
        authorLanguage = names[language] == nil ? (names.keys.sorted().first ?? language) : language
        profile = food.profile
    }
}

struct SharedMealComponent: Codable {
    let food: SharedFood
    let displayName: String
    let language: String
    let quantity: LoggedQuantity
}

struct SharedMeal: Codable {
    let id: UUID
    let eatenAt: Date
    let category: MealCategory
    let components: [SharedMealComponent]
}

struct SharedRecipe: Codable {
    let name: String
    let tags: [String]
    let servingsProduced: DecimalAmount
    let ingredients: [SharedMealComponent]
}

struct MealSharePayload: Codable {
    let version: Int
    let food: SharedFood?
    let meal: SharedMeal?
    let recipe: SharedRecipe?

    static func food(_ food: CatalogueFood, displayName: String, language: String) -> MealSharePayload {
        MealSharePayload(version: 1, food: SharedFood(food: food, fallbackName: displayName, language: language), meal: nil, recipe: nil)
    }

    static func meal(_ event: MealEvent) -> MealSharePayload {
        MealSharePayload(
            version: 1,
            food: nil,
            meal: SharedMeal(
                id: event.id,
                eatenAt: event.eatenAt,
                category: event.category,
                components: event.components.map {
                    SharedMealComponent(
                        food: SharedFood(food: $0.food, fallbackName: $0.displayName, language: $0.language),
                        displayName: $0.displayName,
                        language: $0.language,
                        quantity: $0.quantity
                    )
                }
            ),
            recipe: nil
        )
    }

    static func recipe(_ recipe: SavedMeal) -> MealSharePayload {
        MealSharePayload(
            version: 1,
            food: nil,
            meal: nil,
            recipe: SharedRecipe(
                name: recipe.name,
                tags: recipe.tags,
                servingsProduced: recipe.servingsProduced,
                ingredients: recipe.ingredients.map {
                    SharedMealComponent(
                        food: SharedFood(food: $0.food, fallbackName: $0.displayName, language: $0.language),
                        displayName: $0.displayName,
                        language: $0.language,
                        quantity: $0.quantity
                    )
                }
            )
        )
    }

    static func decode(_ url: URL) throws -> MealSharePayload {
        if url.scheme == "mealtracker", url.host == "share" {
            var encoded = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded) else { throw ShareImportError.invalidPayload }
            return try decode(data)
        }
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> MealSharePayload {
        let payload = try JSONDecoder().decode(MealSharePayload.self, from: data)
        let itemCount = [payload.food != nil, payload.meal != nil, payload.recipe != nil].filter { $0 }.count
        guard payload.version == 1, itemCount == 1 else { throw ShareImportError.invalidPayload }
        return payload
    }
}

enum ShareImportError: Error {
    case invalidPayload
}

extension MealModel {
    func receiveSharedURL(_ url: URL) {
        do {
            let payload = try MealSharePayload.decode(url)
            if try sharedPayloadHasDuplicate(payload) {
                pendingShareImport = payload
            } else {
                try importSharedPayload(payload, updateExisting: false)
            }
        } catch {
            self.error = appError(error)
        }
    }

    func confirmPendingShareImport() {
        guard let payload = pendingShareImport else { return }
        do {
            try importSharedPayload(payload, updateExisting: true)
            pendingShareImport = nil
        } catch {
            self.error = appError(error)
        }
    }

    func cancelPendingShareImport() {
        pendingShareImport = nil
    }

    private func sharedPayloadHasDuplicate(_ payload: MealSharePayload) throws -> Bool {
        if let meal = payload.meal { return try diary.event(id: meal.id) != nil }
        if let recipe = payload.recipe {
            return try diary.savedMeals().contains {
                $0.name.localizedCaseInsensitiveCompare(recipe.name) == .orderedSame
            }
        }
        guard let food = payload.food else { return false }
        return try personal.personalFoods(includeHidden: true).contains { existing in
            existing.id == food.id || existing.food.names.values.contains { name in
                food.names.values.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
        }
    }

    private func importSharedPayload(_ payload: MealSharePayload, updateExisting: Bool) throws {
        if let food = payload.food {
            let duplicate = try matchingPersonalFood(food)
            _ = try personal.savePersonal(
                id: duplicate?.id ?? food.id,
                kind: food.kind,
                names: food.names,
                authorLanguage: food.authorLanguage,
                profile: food.profile,
                expectedRevision: updateExisting ? duplicate?.revision : nil,
                operationID: UUID()
            )
            Task { await loadOFF() }
            return
        }


        if let recipe = payload.recipe {
            let ingredients = try recipe.ingredients.map { shared in
                let food = CatalogueFood(
                    id: .personal(shared.food.id),
                    revision: "1",
                    kind: shared.food.kind,
                    lifecycle: "active",
                    names: shared.food.names,
                    salesCountries: [],
                    manufacturingCountries: [],
                    ingredientOrigins: [],
                    barcodes: [],
                    profile: shared.food.profile,
                    provenanceRef: "shared"
                )
                return try MealComponent(
                    food: food,
                    generationID: catalogue.generationID,
                    displayName: shared.displayName,
                    language: shared.language,
                    quantity: shared.quantity,
                    fixtureOnly: false
                )
            }
            let draft = try SavedMealDraft(
                name: recipe.name,
                tags: recipe.tags,
                servingsProduced: recipe.servingsProduced,
                ingredients: ingredients
            )
            if updateExisting,
               let existing = try diary.savedMeals().first(where: {
                   $0.name.localizedCaseInsensitiveCompare(recipe.name) == .orderedSame
               }) {
                _ = try diary.updateSavedMeal(
                    id: existing.id,
                    draft: draft,
                    expectedRevision: existing.revision,
                    operationID: UUID()
                )
            } else {
                _ = try diary.createSavedMeal(draft, operationID: UUID())
            }
            reloadSavedMeals()
            return
        }

        guard let meal = payload.meal else { throw ShareImportError.invalidPayload }
        let existing = try diary.event(id: meal.id)
        let components = try meal.components.map { shared in
            let food = CatalogueFood(
                id: .personal(shared.food.id),
                revision: "1",
                kind: shared.food.kind,
                lifecycle: "active",
                names: shared.food.names,
                salesCountries: [],
                manufacturingCountries: [],
                ingredientOrigins: [],
                barcodes: [],
                profile: shared.food.profile,
                provenanceRef: "shared"
            )
            return try MealComponent(
                food: food,
                generationID: catalogue.generationID,
                displayName: shared.displayName,
                language: shared.language,
                quantity: shared.quantity,
                fixtureOnly: false
            )
        }
        _ = try diary.save(
            MealDraft(
                id: meal.id,
                eatenAt: meal.eatenAt,
                zoneID: TimeZone.current.identifier,
                category: meal.category,
                components: components
            ),
            operationID: UUID(),
            expectedRevision: updateExisting ? existing?.revision : nil,
            confirmFuture: true
        )
        importedMealDate = meal.eatenAt
    }

    private func matchingPersonalFood(_ food: SharedFood) throws -> PersonalFood? {
        try personal.personalFoods(includeHidden: true).first { existing in
            existing.id == food.id || existing.food.names.values.contains { name in
                food.names.values.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
        }
    }
}
