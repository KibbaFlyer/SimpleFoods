import SwiftUI
import MealTrackerHealth
import MealTrackerLocalization

struct HealthEnergySection: View {
    let state: EnergyReadState
    let copy: AppCopy
    var body: some View {
        Section(copy.text("reportedEnergy")) {
            stateView(state, title: "activeEnergy")
            Text(copy.text("healthCoverage")).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder func stateView(_ state: EnergyReadState, title: String) -> some View {
        switch state {
        case .notRequested: Text(copy.text(title) + ": " + copy.text("notRequested"))
        case .loading: HStack { Text(copy.text(title)); ProgressView() }
        case .noReadableData: Text(copy.text(title) + ": " + copy.text("noReadableEnergy"))
        case let .value(value): valueRow(value, title: title)
        case .error: Text(copy.text(title) + ": " + copy.text("energyError"))
        case let .stale(value, _): valueRow(value, title: title); Text(copy.text("energyStale")).foregroundStyle(.orange)
        }
    }
    func valueRow(_ value: EnergyValue, title: String) -> some View {
        VStack(alignment: .leading) {
            Text(copy.text(title) + ": " + copy.kilocalories(Decimal(value.kcal)) + " kcal")
            Text(value.window.start.formatted(.dateTime.year().month().day().locale(copy.language.locale))).font(.caption)
            if value.window.isSoFar { Text(copy.text("soFar")).font(.caption) }
            Text(copy.text("checked") + ": " + value.fetchedAt.formatted(.dateTime.locale(copy.language.locale))).font(.caption)
        }
    }
}
