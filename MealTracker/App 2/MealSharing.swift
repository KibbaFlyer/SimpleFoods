import Foundation
import MealTrackerCore
import MealTrackerDiary

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

struct MealSharePayload: Codable {
    let version: Int
    let food: SharedFood?
    let meal: SharedMeal?

    static func food(_ food: CatalogueFood, displayName: String, language: String) -> MealSharePayload {
        MealSharePayload(version: 1, food: SharedFood(food: food, fallbackName: displayName, language: language), meal: nil)
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
            )
        )
    }

    var url: URL? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "mealtracker://share/\(encoded)")
    }

    static func decode(_ url: URL) throws -> MealSharePayload {
        guard url.scheme == "mealtracker", url.host == "share" else { throw ShareImportError.invalidPayload }
        var encoded = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw ShareImportError.invalidPayload }
        let payload = try JSONDecoder().decode(MealSharePayload.self, from: data)
        guard payload.version == 1, (payload.food == nil) != (payload.meal == nil) else { throw ShareImportError.invalidPayload }
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
