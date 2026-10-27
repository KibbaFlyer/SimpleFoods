import Foundation

struct WidgetDay: Codable, Identifiable {
    let id: String
    var energy = 0.0
    var protein = 0.0
    var carbohydrate = 0.0
    var fat = 0.0
    var activeEnergy = 0.0
    var hasMeals = false
}

struct WidgetFoodTotal: Codable, Identifiable {
    let id: String
    let name: String
    var value: Double
    let unit: String
}

struct FoodWidgetSnapshot: Codable {
    var version = 1
    let updatedAt: Date
    let month: String
    let language: String
    let energyGoal: Double
    let proteinPercent: Int
    let carbohydratePercent: Int
    let fatPercent: Int
    let energyMinimum: Int
    let energyMaximum: Int
    let macroMinimum: Int
    let macroMaximum: Int
    let includesActivity: Bool
    let days: [WidgetDay]
    let mealEnergy: [WidgetFoodTotal]
    let foodAmount: [WidgetFoodTotal]
    let foodEnergy: [WidgetFoodTotal]
    let foodProtein: [WidgetFoodTotal]
    let foodCarbohydrate: [WidgetFoodTotal]
    let foodFat: [WidgetFoodTotal]

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func day(at date: Date) -> WidgetDay {
        days.first { $0.id == Self.dayKey(date) } ?? WidgetDay(id: Self.dayKey(date))
    }

    func goal(for day: WidgetDay) -> Double {
        max(1, energyGoal + (includesActivity ? day.activeEnergy : 0))
    }

    func isCurrentMonth(at date: Date) -> Bool {
        month == String(Self.dayKey(date).prefix(7))
    }
}

enum WidgetSnapshotStore {
    static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SimpleFoodsAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return directory.appendingPathComponent("widget-summary-v1.json")
    }

    static func read() -> FoodWidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(FoodWidgetSnapshot.self, from: data), snapshot.version == 1 else { return nil }
        return snapshot
    }

    static func write(_ snapshot: FoodWidgetSnapshot) throws -> Bool {
        guard let url = fileURL else { return false }
        // Only derived summaries are shared; the diary remains in its private container.
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        return true
    }
}

enum FoodWidgetRoute: String {
    case today, goals, graphs, meal, food, nutrition, recipe
    var url: URL {
        var components = URLComponents()
        components.scheme = "mealtracker"
        components.host = "widget"
        components.path = "/" + rawValue
        guard let url = components.url else { preconditionFailure("Invalid widget route") }
        return url
    }

    init?(url: URL) {
        guard url.scheme == "mealtracker", url.host == "widget",
              url.query == nil, url.fragment == nil else { return nil }
        self.init(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
