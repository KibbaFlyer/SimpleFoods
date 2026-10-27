import Foundation
import WidgetKit
import MealTrackerCore
import MealTrackerDiary

extension MealModel {
    func publishWidgetSnapshot() {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        guard let interval = calendar.dateInterval(of: .month, for: now),
              let range = calendar.range(of: .day, in: .month, for: now) else { return }
        let settings = UserDefaults.standard
        func integer(_ key: String, default fallback: Int) -> Int {
            settings.object(forKey: key) == nil ? fallback : settings.integer(forKey: key)
        }
        func number(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
        var days: [WidgetDay] = []
        var mealEnergy: [String: Double] = [:]
        var amounts: [String: WidgetFoodTotal] = [:]
        var foods: [String: [String: WidgetFoodTotal]] = [:]
        do {
            for day in range {
                guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { continue }
                let key = Self.day(date)
                let events = try diary.events(localDate: key)
                var summary = WidgetDay(id: key)
                summary.hasMeals = !events.isEmpty
                summary.activeEnergy = activeEnergyByDay[key]?.kcal ?? 0
                for event in events {
                    func total(_ nutrient: Nutrient) -> Double { number(event.totals[nutrient.rawValue]?.knownSubtotal.value ?? .zero) }
                    summary.energy += total(.energy)
                    summary.protein += total(.protein)
                    summary.carbohydrate += total(.carbohydrateAvailable)
                    summary.fat += total(.totalFat)
                    mealEnergy[event.category.rawValue, default: 0] += total(.energy)
                    for component in event.components {
                        let id = String(describing: component.food.id)
                        let amountID = id + "|" + component.quantity.unit.rawValue
                        let unit = component.quantity.unit == .grams ? "g" : component.quantity.unit == .millilitres ? "ml" : "portions"
                        var amount = amounts[amountID] ?? WidgetFoodTotal(id: amountID, name: component.displayName, value: 0, unit: unit)
                        amount.value += number(component.quantity.amount.value)
                        amounts[amountID] = amount
                        guard let totals = try? NutritionCalculator.calculate(profile: component.food.profile, quantity: component.quantity.consumed()) else { continue }
                        for nutrient in [Nutrient.energy, .protein, .carbohydrateAvailable, .totalFat] {
                            var food = foods[nutrient.rawValue]?[id] ?? WidgetFoodTotal(id: id, name: component.displayName, value: 0, unit: nutrient == .energy ? "kcal" : "g")
                            food.value += number(totals[nutrient].knownSubtotal)
                            foods[nutrient.rawValue, default: [:]][id] = food
                        }
                    }
                }
                days.append(summary)
            }
            func ranked(_ values: [WidgetFoodTotal]) -> [WidgetFoodTotal] {
                Array(values.filter { $0.value > 0 }.sorted { $0.value == $1.value ? $0.id < $1.id : $0.value > $1.value }.prefix(7))
            }
            func nutrients(_ nutrient: Nutrient) -> [WidgetFoodTotal] { ranked(Array(foods[nutrient.rawValue, default: [:]].values)) }
            let snapshot = FoodWidgetSnapshot(
                updatedAt: now, month: String(Self.day(now).prefix(7)), language: settings.string(forKey: "appLanguage") ?? "sv",
                energyGoal: settings.object(forKey: "dailyEnergyGoalKcal") == nil ? 2000 : settings.double(forKey: "dailyEnergyGoalKcal"),
                proteinPercent: integer("proteinEnergyPercent", default: 25), carbohydratePercent: integer("carbohydrateEnergyPercent", default: 45), fatPercent: integer("fatEnergyPercent", default: 30),
                energyMinimum: integer("goalRangeMinimumPercent", default: 90), energyMaximum: integer("goalRangeMaximumPercent", default: 110),
                macroMinimum: integer("macroGoalRangeMinimumPercent", default: 90), macroMaximum: integer("macroGoalRangeMaximumPercent", default: 110),
                includesActivity: settings.bool(forKey: "includeEnergyExpenditureInGoal"), days: days,
                mealEnergy: MealCategory.allCases.map { WidgetFoodTotal(id: $0.rawValue, name: $0.rawValue, value: mealEnergy[$0.rawValue] ?? 0, unit: "kcal") },
                foodAmount: ranked(Array(amounts.values)), foodEnergy: nutrients(.energy), foodProtein: nutrients(.protein), foodCarbohydrate: nutrients(.carbohydrateAvailable), foodFat: nutrients(.totalFat)
            )
            if try WidgetSnapshotStore.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
        } catch {
            // Retain the previous atomic snapshot if protected data is unavailable.
            // Widget publication must not prevent saving or viewing meals.
        }
    }
}
