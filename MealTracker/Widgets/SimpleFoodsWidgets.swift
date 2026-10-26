import SwiftUI
import Charts
import WidgetKit

private struct FoodEntry: TimelineEntry {
    let date: Date
    let snapshot: FoodWidgetSnapshot?
}

private struct FoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodEntry { FoodEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (FoodEntry) -> Void) {
        completion(FoodEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodEntry>) -> Void) {
        let now = Date()
        let nextDay = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Calendar.autoupdatingCurrent.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let snapshot = WidgetSnapshotStore.read()
        // The midnight entry prevents yesterday's energy appearing as today's.
        completion(Timeline(entries: [FoodEntry(date: now, snapshot: snapshot), FoodEntry(date: nextDay, snapshot: snapshot)], policy: .after(nextDay)))
    }
}

private enum WidgetGraph: String {
    case mealEnergy, foodAmount, foodEnergy, protein, carbohydrate, fat, dailyMacros
    var title: LocalizedStringKey {
        switch self {
        case .mealEnergy: "Energy by meal type"
        case .foodAmount: "Most eaten by amount"
        case .foodEnergy: "Most eaten by energy"
        case .protein: "Top foods · Protein"
        case .carbohydrate: "Top foods · Carbohydrates"
        case .fat: "Top foods · Fat"
        case .dailyMacros: "Daily macronutrients"
        }
    }
    var color: Color {
        switch self {
        case .protein: .green
        case .carbohydrate: .blue
        case .fat: .orange
        default: .teal
        }
    }
    func items(_ snapshot: FoodWidgetSnapshot) -> [WidgetFoodTotal] {
        switch self {
        case .mealEnergy: snapshot.mealEnergy
        case .foodAmount: snapshot.foodAmount
        case .foodEnergy: snapshot.foodEnergy
        case .protein: snapshot.foodProtein
        case .carbohydrate: snapshot.foodCarbohydrate
        case .fat: snapshot.foodFat
        case .dailyMacros: []
        }
    }
}

private struct WidgetHeader: View {
    let title: LocalizedStringKey
    let date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).lineLimit(2)
            Text(date, format: .dateTime.month(.wide).year()).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct WidgetEmpty: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Simple Foods", systemImage: "fork.knife").font(.headline)
            Text("Open Simple Foods to update your widgets.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct EnergyWidgetView: View {
    let entry: FoodEntry
    var body: some View {
        if let snapshot = entry.snapshot {
            let day = snapshot.day(at: entry.date)
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's energy").font(.headline)
                Text(entry.date, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(.secondary)
                Text(day.energy, format: .number.precision(.fractionLength(0))).font(.largeTitle.bold()).minimumScaleFactor(0.65)
                Text("kcal").font(.caption)
                Text("Until goal: \(max(0, snapshot.goal(for: day) - day.energy).formatted(.number.precision(.fractionLength(0)))) kcal")
                    .font(.caption).foregroundStyle(day.energy > snapshot.goal(for: day) ? .red : .secondary)
            }
            .privacySensitive()
        } else { WidgetEmpty() }
    }
}

private struct GoalsWidgetView: View {
    let entry: FoodEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if let snapshot = entry.snapshot {
            let day = snapshot.day(at: entry.date)
            VStack(alignment: .leading, spacing: family == .systemMedium ? 6 : 10) {
                WidgetHeader(title: "Goals", date: entry.date)
                goalRow("Energy", value: day.energy, target: snapshot.goal(for: day), minimum: snapshot.energyMinimum, maximum: snapshot.energyMaximum, unit: "kcal", hasData: day.hasMeals)
                if family != .systemSmall {
                    goalRow("Protein", value: day.protein, target: snapshot.goal(for: day) * Double(snapshot.proteinPercent) / 400, minimum: snapshot.macroMinimum, maximum: snapshot.macroMaximum, unit: "g", hasData: day.hasMeals)
                    goalRow("Carbohydrates", value: day.carbohydrate, target: snapshot.goal(for: day) * Double(snapshot.carbohydratePercent) / 400, minimum: snapshot.macroMinimum, maximum: snapshot.macroMaximum, unit: "g", hasData: day.hasMeals)
                    goalRow("Fat", value: day.fat, target: snapshot.goal(for: day) * Double(snapshot.fatPercent) / 900, minimum: snapshot.macroMinimum, maximum: snapshot.macroMaximum, unit: "g", hasData: day.hasMeals)
                }
                if family == .systemLarge { monthCalendar(snapshot) }
            }
            .padding(.horizontal, family == .systemMedium ? 8 : 0)
            .padding(.vertical, family == .systemMedium ? 6 : 0)
            .privacySensitive()
        } else { WidgetEmpty() }
    }

    private func goalRow(_ label: LocalizedStringKey, value: Double, target: Double, minimum: Int, maximum: Int, unit: String, hasData: Bool) -> some View {
        let ratio = value / max(target, 1)
        let met = ratio >= Double(minimum) / 100 && ratio <= Double(maximum) / 100
        return HStack {
            Image(systemName: met && hasData ? "checkmark.circle.fill" : "circle.fill")
                .foregroundStyle(!hasData ? Color.secondary : met ? .green : .orange)
            Text(label).font(.caption)
            Spacer(minLength: 4)
            Text("\(value.formatted(.number.precision(.fractionLength(0)))) / \(target.formatted(.number.precision(.fractionLength(0)))) \(unit)")
                .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func monthCalendar(_ snapshot: FoodWidgetSnapshot) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let first = calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 31
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 4) {
            ForEach(0..<(leading + count), id: \.self) { index in
                if index < leading { Color.clear.frame(height: 20) }
                else {
                    let date = calendar.date(byAdding: .day, value: index - leading, to: first) ?? first
                    let day = snapshot.day(at: date)
                    let ratio = day.energy / snapshot.goal(for: day)
                    let met = ratio >= Double(snapshot.energyMinimum) / 100 && ratio <= Double(snapshot.energyMaximum) / 100
                    Text("\(index - leading + 1)")
                        .font(.caption2).frame(maxWidth: .infinity, minHeight: 20)
                        .background((!day.hasMeals ? Color.secondary : met ? .green : .orange).opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

private struct GraphWidgetView: View {
    let entry: FoodEntry
    let graph: WidgetGraph
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: graph.title, date: entry.date)
            if let snapshot = entry.snapshot, snapshot.isCurrentMonth(at: entry.date) {
                if graph == .dailyMacros {
                    dailyChart(snapshot)
                } else {
                    let items = Array(graph.items(snapshot).prefix(family == .systemLarge ? 7 : 4))
                    if items.isEmpty { Text("No meals logged yet.").font(.caption).foregroundStyle(.secondary) }
                    else {
                        Chart(items) { item in
                            BarMark(x: .value("Amount", item.value), y: .value("Food", item.id))
                                .foregroundStyle(graph.color)
                                .annotation(position: .trailing) {
                                    Text("\(item.value.formatted(.number.precision(.fractionLength(0)))) \(item.unit)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.primary)
                                }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { axis in
                                AxisValueLabel {
                                    if let id = axis.as(String.self), let item = items.first(where: { $0.id == id }) {
                                        if graph == .mealEnergy { Text(mealLabel(item.id)).font(.caption2).foregroundStyle(Color.primary) }
                                        else { Text(item.name).font(.caption2).foregroundStyle(Color.primary).lineLimit(1) }
                                    }
                                }
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartXScale(range: .plotDimension(endPadding: 65))
                    }
                }
            } else { Text("Open Simple Foods to update your widgets.").font(.caption).foregroundStyle(.secondary) }
        }
        .privacySensitive()
    }

    private func mealLabel(_ key: String) -> LocalizedStringKey {
        switch key {
        case "breakfast": "Breakfast"
        case "lunch": "Lunch"
        case "dinner": "Dinner"
        default: "Snacks"
        }
    }

    private func dailyChart(_ snapshot: FoodWidgetSnapshot) -> some View {
        Chart(snapshot.days) { day in
            BarMark(x: .value("g", day.protein), y: .value("Day", String(day.id.suffix(2))))
                .foregroundStyle(by: .value("Nutrient", String(localized: "Protein", locale: Locale(identifier: snapshot.language))))
            BarMark(x: .value("g", day.carbohydrate), y: .value("Day", String(day.id.suffix(2))))
                .foregroundStyle(by: .value("Nutrient", String(localized: "Carbohydrates", locale: Locale(identifier: snapshot.language))))
            BarMark(x: .value("g", day.fat), y: .value("Day", String(day.id.suffix(2))))
                .foregroundStyle(by: .value("Nutrient", String(localized: "Fat", locale: Locale(identifier: snapshot.language))))
        }
        .chartForegroundStyleScale(domain: [String(localized: "Protein", locale: Locale(identifier: snapshot.language)), String(localized: "Carbohydrates", locale: Locale(identifier: snapshot.language)), String(localized: "Fat", locale: Locale(identifier: snapshot.language))], range: [.green, .blue, .orange])
        .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel().font(.system(size: 8)).foregroundStyle(Color.primary) } }
        .chartXAxis {
            AxisMarks {
                AxisGridLine()
                AxisTick()
                AxisValueLabel().foregroundStyle(Color.primary)
            }
        }
        .chartXAxisLabel { Text("g").foregroundStyle(Color.primary) }
        .chartLegend(position: .bottom, spacing: 2)
    }
}

private struct QuickAddWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick add", systemImage: "plus.circle.fill").font(.headline)
            HStack(spacing: 8) {
                action("Meal", symbol: "fork.knife", route: .meal)
                action("Food", symbol: "carrot", route: .food)
            }
            HStack(spacing: 8) {
                action("Manual nutrition", symbol: "pencil", route: .nutrition)
                action("Recipe", symbol: "book", route: .recipe)
            }
        }
    }
    private func action(_ title: LocalizedStringKey, symbol: String, route: FoodWidgetRoute) -> some View {
        Link(destination: route.url) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .padding(.horizontal, 8)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct EnergyTotalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleFoods.Energy", provider: FoodProvider()) { entry in
            EnergyWidgetView(entry: entry).environment(\.locale, Locale(identifier: entry.snapshot?.language ?? Locale.current.identifier)).containerBackground(.background, for: .widget).widgetURL(FoodWidgetRoute.today.url)
        }
        .configurationDisplayName("Energy total")
        .description("Today's logged kcal and remaining energy goal.")
        .supportedFamilies([.systemSmall])
    }
}

struct GoalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleFoods.Goals", provider: FoodProvider()) { entry in
            GoalsWidgetView(entry: entry).environment(\.locale, Locale(identifier: entry.snapshot?.language ?? Locale.current.identifier)).containerBackground(.background, for: .widget).widgetURL(FoodWidgetRoute.goals.url)
        }
        .configurationDisplayName("Goals")
        .description("Daily energy and macro goals, with a monthly overview in the large widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct FoodGraphWidget: Widget {
    let graph: WidgetGraph
    init() { graph = .mealEnergy }
    init(graph: WidgetGraph) { self.graph = graph }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleFoods.Graph." + graph.rawValue, provider: FoodProvider()) { entry in
            GraphWidgetView(entry: entry, graph: graph).environment(\.locale, Locale(identifier: entry.snapshot?.language ?? Locale.current.identifier)).containerBackground(.background, for: .widget).widgetURL(FoodWidgetRoute.graphs.url)
        }
        .configurationDisplayName(graph.title)
        .description("This month's nutrition graph. Tap to open Graphs.")
        .supportedFamilies(graph == .dailyMacros ? [.systemLarge] : [.systemMedium, .systemLarge])
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SimpleFoods.QuickAdd", provider: FoodProvider()) { entry in
            QuickAddWidgetView().environment(\.locale, Locale(identifier: entry.snapshot?.language ?? Locale.current.identifier)).containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick add")
        .description("Open Today to add a meal, food, manual nutrition, or recipe.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct SimpleFoodsWidgets: WidgetBundle {
    var body: some Widget {
        EnergyTotalWidget()
        GoalsWidget()
        QuickAddWidget()
        FoodGraphWidget(graph: .mealEnergy)
        FoodGraphWidget(graph: .foodAmount)
        FoodGraphWidget(graph: .foodEnergy)
        FoodGraphWidget(graph: .protein)
        FoodGraphWidget(graph: .carbohydrate)
        FoodGraphWidget(graph: .fat)
        FoodGraphWidget(graph: .dailyMacros)
    }
}
