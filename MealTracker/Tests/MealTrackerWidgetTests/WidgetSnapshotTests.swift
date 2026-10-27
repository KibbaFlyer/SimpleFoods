import Foundation
import Testing
@testable import MealTrackerWidgetSupport

struct WidgetSnapshotTests {
    private func date(_ day: Int, month: Int = 10) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
    }

    private func snapshot(at date: Date) -> FoodWidgetSnapshot {
        FoodWidgetSnapshot(updatedAt: date, month: String(FoodWidgetSnapshot.dayKey(date).prefix(7)), language: "en", energyGoal: 2000, proteinPercent: 25, carbohydratePercent: 45, fatPercent: 30, energyMinimum: 90, energyMaximum: 110, macroMinimum: 80, macroMaximum: 120, includesActivity: true, days: [WidgetDay(id: FoodWidgetSnapshot.dayKey(date), energy: 1500, protein: 100, carbohydrate: 150, fat: 45, activeEnergy: 400, hasMeals: true)], mealEnergy: [], foodAmount: [], foodEnergy: [], foodProtein: [], foodCarbohydrate: [], foodFat: [])
    }

    @Test func midnightDoesNotReuseYesterday() throws {
        let today = try date(26)
        let data = snapshot(at: today)
        #expect(data.day(at: today).energy == 1500)
        let tomorrow = data.day(at: try date(27))
        #expect(tomorrow.energy == 0)
        #expect(tomorrow.activeEnergy == 0)
        #expect(!tomorrow.hasMeals)
        #expect(data.goal(for: tomorrow) == 2000)
        #expect(data.goal(for: data.day(at: today)) == 2400)
        #expect(data.isCurrentMonth(at: try date(27)))
        #expect(!data.isCurrentMonth(at: try date(1, month: 11)))
    }

    @Test func snapshotRoundTripsSeparateGoalRanges() throws {
        let original = snapshot(at: try date(26))
        let decoded = try JSONDecoder().decode(FoodWidgetSnapshot.self, from: JSONEncoder().encode(original))
        #expect(decoded.energyMinimum == 90)
        #expect(decoded.macroMinimum == 80)
        #expect(decoded.macroMaximum == 120)
        #expect(decoded.days.first?.protein == 100)
    }

    @Test func routesAreExplicitAndDoNotConsumeShares() throws {
        for route in [FoodWidgetRoute.today, .goals, .graphs, .meal, .food, .nutrition, .recipe] {
            #expect(FoodWidgetRoute(url: route.url) == route)
        }
        for text in ["https://widget/meal", "mealtracker://share/meal", "mealtracker://widget/unknown", "mealtracker://widget/meal?date=old", "mealtracker://widget/recipe#other"] {
            #expect(FoodWidgetRoute(url: try #require(URL(string: text))) == nil)
        }
    }
}
