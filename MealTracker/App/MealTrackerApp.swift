import Charts
import QuartzCore
import SwiftUI
import StoreKit
import MealTrackerCore
import MealTrackerCatalog
import MealTrackerDiary
import MealTrackerOpenFoodFacts
import MealTrackerLocalization
import MealTrackerHealth

enum MacronutrientColors {
    static let order: [Nutrient] = [.protein, .carbohydrateAvailable, .totalFat]
    static let protein = Color.green
    static let carbohydrate = Color.blue
    static let fat = Color.orange

    static func color(for nutrient: Nutrient) -> Color {
        switch nutrient {
        case .protein:
            protein
        case .carbohydrateAvailable:
            carbohydrate
        case .totalFat:
            fat
        default:
            .secondary
        }
    }
}

private enum AppConfiguration {
    private static func string(forInfoDictionaryKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var tipProductID: String? {
        string(forInfoDictionaryKey: "SimpleFoodsTipProductID")
    }

    static var repositoryURL: URL? {
        guard let repository = string(forInfoDictionaryKey: "SimpleFoodsRepository") else { return nil }
        return URL(string: "https://github.com/\(repository)")
    }
}

enum RecipeEasterEgg {
    static let notification = Notification.Name("MealTracker.recipeConfetti")

    static func celebrateAfterDismissIfNeeded(name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let specialNames = ["kaiserschmarrn", "renskav"]
        guard specialNames.contains(normalizedName) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            NotificationCenter.default.post(name: notification, object: nil)
        }
    }
}

private enum FoodEasterEgg {
    static func isLebkuchen(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) == "lebkuchen"
    }
}

private struct GingerbreadFoodLabel: View {
    let text: String
    let celebrate: Bool

    var body: some View {
        Text(text)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .task(id: celebrate) {
                            guard celebrate else { return }
                            try? await Task.sleep(for: .milliseconds(50))
                            GingerbreadOverlayPresenter.show(above: proxy.frame(in: .global))
                        }
                }
            }
    }
}

@MainActor
private enum GingerbreadOverlayPresenter {
    static func show(above labelFrame: CGRect) {
        guard labelFrame.width > 0,
              labelFrame.height > 0,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) else { return }

        let host = UIHostingController(
            rootView: GingerbreadMan()
                .frame(width: 24, height: 30)
        )
        guard let view = host.view else { return }
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.bounds = CGRect(x: 0, y: 0, width: 24, height: 30)
        view.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        view.layer.position = CGPoint(x: labelFrame.midX, y: labelFrame.minY - 4)
        view.layer.zPosition = 10_000
        window.addSubview(view)

        UIView.animate(
            withDuration: 1.5,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            view.transform = CGAffineTransform(scaleX: 2, y: 2)
        }
        UIView.animate(
            withDuration: 0.5,
            delay: 2.5,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            view.alpha = 0
        } completion: { _ in
            view.removeFromSuperview()
            _ = host
        }
    }
}

private struct GingerbreadMan: View {
    private let cookie = Color(red: 0.62, green: 0.31, blue: 0.12)

    var body: some View {
        ZStack {
            Capsule()
                .fill(cookie)
                .frame(width: 10, height: 17)
                .offset(y: 6)
            Capsule()
                .fill(cookie)
                .frame(width: 7, height: 19)
                .rotationEffect(.degrees(52))
                .offset(x: -7, y: 5)
            Capsule()
                .fill(cookie)
                .frame(width: 7, height: 19)
                .rotationEffect(.degrees(-52))
                .offset(x: 7, y: 5)
            Capsule()
                .fill(cookie)
                .frame(width: 7, height: 17)
                .rotationEffect(.degrees(18))
                .offset(x: -4, y: 15)
            Capsule()
                .fill(cookie)
                .frame(width: 7, height: 17)
                .rotationEffect(.degrees(-18))
                .offset(x: 4, y: 15)
            Circle()
                .fill(cookie)
                .frame(width: 15, height: 15)
                .offset(y: -7)
            Circle().fill(.white).frame(width: 2.2, height: 2.2).offset(x: -3, y: -9)
            Circle().fill(.white).frame(width: 2.2, height: 2.2).offset(x: 3, y: -9)
            Capsule().fill(.white).frame(width: 6, height: 1.8).offset(y: -4)
            Circle().fill(.red).frame(width: 2.5, height: 2.5).offset(y: 4)
            Circle().fill(.green).frame(width: 2.5, height: 2.5).offset(y: 9)
        }
        .accessibilityHidden(true)
    }
}

private struct ConfettiRainView: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfettiEmitterView {
        ConfettiEmitterView()
    }

    func updateUIView(_ view: ConfettiEmitterView, context: Context) {}
}

private final class ConfettiEmitterView: UIView {
    private let emitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configureEmitter()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configureEmitter()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -12)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }

    private func configureEmitter() {
        emitter.emitterShape = .line
        emitter.emitterMode = .surface
        emitter.renderMode = .unordered
        emitter.preservesDepth = true
        emitter.seed = UInt32.random(in: UInt32.min...UInt32.max)
        emitter.birthRate = UIAccessibility.isReduceMotionEnabled ? 0.35 : 1.7
        emitter.emitterCells = makeCells()
        layer.addSublayer(emitter)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak emitter] in
            emitter?.birthRate = UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.72
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.05) { [weak emitter] in
            emitter?.birthRate = 0
        }
    }

    private func makeCells() -> [CAEmitterCell] {
        let colors: [UIColor] = [
            .systemPink, .systemRed, .systemOrange, .systemYellow,
            .systemGreen, .systemTeal, .systemBlue, .systemPurple
        ]
        return colors.enumerated().map { index, color in
            let cell = CAEmitterCell()
            cell.contents = Self.particleImage(isRibbon: index.isMultiple(of: 3)).cgImage
            cell.color = color.cgColor
            cell.birthRate = 12
            cell.lifetime = 4.7
            cell.lifetimeRange = 1.1
            cell.velocity = 0
            cell.velocityRange = 0
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = 0
            cell.xAcceleration = 0
            cell.yAcceleration = 210
            cell.spin = CGFloat(index.isMultiple(of: 2) ? 4.5 : -4.5)
            cell.spinRange = 8
            cell.scale = index.isMultiple(of: 3) ? 0.72 : 0.62
            cell.scaleRange = 0.28
            cell.scaleSpeed = -0.035
            cell.alphaRange = 0.12
            cell.alphaSpeed = -0.28
            return cell
        }
    }

    private static func particleImage(isRibbon: Bool) -> UIImage {
        let size = isRibbon ? CGSize(width: 5, height: 18) : CGSize(width: 13, height: 8)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1.5).fill()
        }
    }
}

@main
struct MealTrackerApp: App {
    @AppStorage("appLanguage") private var language: AppLanguage = .sv
    var body: some Scene {
        WindowGroup {
            MealTrackerRoot(language: $language)
                .environment(\.locale, language.locale)
        }
    }
}

@MainActor final class MealModel: ObservableObject {
    private static let healthConnectionRequestedKey = "healthConnectionRequested"

    @Published var pendingWidgetRoute: FoodWidgetRoute?
    private var widgetPublishTask: Task<Void, Never>?

    func scheduleWidgetSnapshot() {
        widgetPublishTask?.cancel()
        widgetPublishTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.publishWidgetSnapshot()
        }
    }

    @Published var events: [MealEvent] = []
    @Published private var eventsByDay: [String: [MealEvent]] = [:]
    @Published var savedMeals: [SavedMeal] = []
    @Published private(set) var foodPreferences: [FoodID: FoodSearchPreference] = [:]
    @Published private(set) var favoriteRevision = 0
    private var foodSearchQuery = ""
    private var foodSearchLanguage = "en"
    @Published var foods: [CatalogueFood] = []
    @Published var effectiveNames: [FoodID: [String: String]] = [:]
    @Published var personalFoods: [PersonalFood] = []
    @Published var offProducts: [OFFProduct] = []
    @Published var livsmedelsverketFoods: [CatalogueFood] = []
    @Published var error: String?
    @Published var offSyncBusy = false
    @Published var livsmedelsverketSyncBusy = false
    @Published var healthBusy = false
    @Published var healthConnected = false
    @Published private(set) var activeEnergyByDay: [String: MealTrackerHealth.EnergyValue] = [:]
    let energy = EnergyReader(gateway: NativeHealthEnergyGateway())
    @Published var syncReport: OFFSyncReport?
    @Published var livsmedelsverketSyncReport: LivsmedelsverketSyncReport?
    @Published var pendingShareImport: MealSharePayload?
    @Published var importedMealDate: Date?
    let catalogue: CatalogueRepository
    let diary: DiaryStore
    let off: OFFLibrary
    let personal: PersonalLibrary
    let livsmedelsverket: LivsmedelsverketLibrary
    let foodSearch: FoodSearchService
    init() throws {
        catalogue = try CatalogueRepository.bundledDevelopment()
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let privateDirectory = directory.appendingPathComponent("MealTrackerPrivate", isDirectory: true)
        let offDirectory = directory.appendingPathComponent("MealTrackerOFF", isDirectory: true)
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let repository = AppConfiguration.repositoryURL.map { " (\($0.absoluteString))" } ?? ""
        let userAgent = "SimpleFoods/\(appVersion)\(repository)"
        try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: offDirectory, withIntermediateDirectories: true)
        diary = try DiaryStore(databaseURL: privateDirectory.appendingPathComponent("diary.sqlite"))
        personal = PersonalLibrary(store: diary)
        off = try OFFLibrary(databaseURL: offDirectory.appendingPathComponent("openfoodfacts.sqlite"), userAgent: userAgent)
        livsmedelsverket = try LivsmedelsverketLibrary(databaseURL: offDirectory.appendingPathComponent("livsmedelsverket.sqlite"), userAgent: userAgent)
        foodSearch = FoodSearchService(catalogue: catalogue, personal: personal, diary: diary, off: off, livsmedelsverket: livsmedelsverket)
        Task(priority: .utility) { [off] in
            // A canceled keystroke must not restart the one-time catalog build.
            try? await off.prepareSearchIndex()
        }
    }
    func connectHealth(day: Date) async {
        await establishHealthConnection(day: day, rememberConnection: true, reportError: true)
    }
    func restoreHealthConnection(day: Date) async {
        guard UserDefaults.standard.bool(forKey: Self.healthConnectionRequestedKey) else { return }
        await establishHealthConnection(day: day, rememberConnection: false, reportError: false)
    }
    private func establishHealthConnection(day: Date, rememberConnection: Bool, reportError: Bool) async {
        guard !healthBusy else { return }
        healthBusy = true
        defer { healthBusy = false }
        do {
            try await energy.connect()
            healthConnected = true
            if rememberConnection {
                UserDefaults.standard.set(true, forKey: Self.healthConnectionRequestedKey)
            }
            await energy.refresh(day: day, timeZone: .current)
            cacheActiveEnergy(for: day)
            objectWillChange.send()
        } catch {
            healthConnected = false
            if reportError { self.error = appError(error) }
        }
    }
    func refreshHealth(day: Date) async {
        guard healthConnected else { return }
        healthBusy = true
        await energy.refresh(day: day, timeZone: .current)
        cacheActiveEnergy(for: day)
        healthBusy = false
        objectWillChange.send()
    }
    func preloadHealthDays(around selectedDay: Date) async {
        guard healthConnected else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let days = (-1...1).compactMap {
            calendar.date(byAdding: .day, value: $0, to: selectedDay)
        }

        healthBusy = true
        defer {
            healthBusy = false
            objectWillChange.send()
        }

        for day in days where calendar.startOfDay(for: day) <= today {
            guard !Task.isCancelled else { return }
            let key = Self.day(day)
            guard activeEnergyByDay[key] == nil else { continue }
            await energy.refresh(day: day, timeZone: .current)
            cacheActiveEnergy(for: day)
        }

        guard !Task.isCancelled,
              calendar.startOfDay(for: selectedDay) <= today else { return }
        await energy.refresh(day: selectedDay, timeZone: .current)
        cacheActiveEnergy(for: selectedDay)
    }
    func refreshGoalHealth(days: [Date], restoring selectedDay: Date) async {
        guard healthConnected else { return }
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let readableDays = days
            .filter { calendar.startOfDay(for: $0) <= today }
            .sorted()

        healthBusy = true
        for day in readableDays {
            guard !Task.isCancelled else {
                healthBusy = false
                return
            }
            await energy.refresh(day: day, timeZone: .current)
            cacheActiveEnergy(for: day)
        }

        if calendar.startOfDay(for: selectedDay) <= today {
            await energy.refresh(day: selectedDay, timeZone: .current)
            cacheActiveEnergy(for: selectedDay)
        }
        healthBusy = false
        objectWillChange.send()
    }
    private func cacheActiveEnergy(for day: Date) {
        guard let value = energy.active.previousValue else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: value.window.timeZoneID) ?? .current
        guard calendar.isDate(day, inSameDayAs: value.window.start) else { return }
        activeEnergyByDay[Self.day(day)] = value
        scheduleWidgetSnapshot()
    }
    func syncMealToHealth(_ event: MealEvent) async {
        guard healthConnected else { return }
        func amount(_ nutrient: Nutrient) -> Double {
            let value = event.totals[nutrient.rawValue]?.knownSubtotal.value ?? .zero
            return NSDecimalNumber(decimal: value).doubleValue
        }
        do {
            let entry = try NutritionEntry(
                id: event.id,
                revision: event.revision,
                date: event.eatenAt,
                foodName: event.components.map(\.displayName).joined(separator: ", "),
                energyKcal: amount(.energy),
                proteinGrams: amount(.protein),
                carbohydrateGrams: amount(.carbohydrateAvailable),
                fatGrams: amount(.totalFat)
            )
            try await energy.saveNutrition(entry)
        } catch {
            self.error = appError(error)
        }
    }
    func reload(_ date: Date) {
        defer { scheduleWidgetSnapshot() }
        let calendar = Calendar.autoupdatingCurrent
        do {
            var loadedDays: Set<String> = []
            for offset in -1...1 {
                guard let nearbyDate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                let day = Self.day(nearbyDate)
                loadedDays.insert(day)
                eventsByDay[day] = try diary.events(localDate: day)
            }
            eventsByDay = eventsByDay.filter { loadedDays.contains($0.key) }
            events = eventsByDay[Self.day(date)] ?? []
        } catch {
            self.error = appError(error)
        }
    }
    func events(on date: Date) -> [MealEvent] {
        eventsByDay[Self.day(date)] ?? []
    }
    func reloadSavedMeals() {
        do { savedMeals = try diary.savedMeals() } catch { self.error = appError(error) }
    }
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
    func loadOFF() async {
        await foodSearch.invalidateSources()
        do {
            personalFoods = try personal.personalFoods()
            // Raw OFF records that could not be mapped to a validated food are
            // retained in the cache for diagnostics, but never exposed in UI.
            offProducts = try await off.cachedProducts().filter { $0.food != nil }
            livsmedelsverketFoods = try await livsmedelsverket.foods()
            for food in personalFoods.map(\.food) + offProducts.compactMap(\.food) + livsmedelsverketFoods { effectiveNames[food.id] = try personal.resolve(base: food).food.names }
        } catch { self.error = appError(error) }
    }
    func name(_ food: CatalogueFood, language: String) -> String {
        let names = effectiveNames[food.id] ?? food.names
        return names[language] ?? names["en"] ?? names.sorted(by: { $0.key < $1.key }).first?.value ?? "—"
    }
    func matches(_ food: CatalogueFood, query: String, language: String) throws -> Bool {
        let resolved = try personal.resolve(base: food).food
        effectiveNames[food.id] = resolved.names
        return query.isEmpty || name(food, language: language).range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: language)) != nil
    }
    func search(_ query: String, language: AppLanguage, market: String) {
        do { let candidates = try catalogue.search(query: "", language: language.rawValue, market: market.isEmpty ? nil : market); foods = try candidates.filter { try matches($0, query: query, language: language.rawValue) } } catch { self.error = appError(error) }
    }

    func recordFoodSelection(_ food: CatalogueFood, query: String, language: AppLanguage) {
        do {
            try FoodSearchHistory(store: diary).recordSelection(food: food, query: query, language: language.rawValue)
        } catch { self.error = appError(error) }
    }

    func productForLogging(_ food: CatalogueFood, language: AppLanguage) async throws -> OFFProduct? {
        guard case let .catalogue(namespace, barcode) = food.id, namespace == "off" else { return nil }
        if let cached = offProducts.first(where: { $0.food?.id == food.id }) { return cached }
        // History can outlive the in-memory product list or the persistent OFF cache.
        let product = try await off.lookup(barcode: barcode, language: language.rawValue)
        guard product.food?.id == food.id else { throw OFFError.notFound }
        await loadOFF()
        return product
    }

    func foodPreferencesForDisplay() {
        do { foodPreferences = try FoodSearchHistory(store: diary).preferences(query: foodSearchQuery, language: foodSearchLanguage) }
        catch { self.error = appError(error) }
    }

    func toggleFavorite(_ food: CatalogueFood) {
        do {
            let history = FoodSearchHistory(store: diary)
            let current = try history.preferences(query: foodSearchQuery, language: foodSearchLanguage)
            try history.setFavorite(!(current[food.id]?.isFavorite ?? false), food: food)
            foodPreferences = try history.preferences(query: foodSearchQuery, language: foodSearchLanguage)
            favoriteRevision += 1
        } catch { self.error = appError(error) }
    }

    func sync() async {
        guard !offSyncBusy else { return }
        offSyncBusy = true
        defer { offSyncBusy = false }
        // The country name catalogue is bundled at build time. Manual sync only
        // refreshes products this device has actually opened and cached.
        syncReport = await off.sync()
        await loadOFF()
    }
    fileprivate func searchFoods(
        query: String,
        language: AppLanguage,
        market: String,
        origin: FoodOriginFilter,
        favoritesOnly: Bool = false,
        limit: Int
    ) async throws -> FoodSearchPage {
        let result = try await foodSearch.search(query: query, language: language.rawValue, market: market.isEmpty ? nil : market, source: origin, favoritesOnly: favoritesOnly, limit: limit)
        try Task.checkCancellation()
        foodSearchQuery = query
        foodSearchLanguage = language.rawValue
        foodPreferences = result.preferences
        return result
    }
    func syncLivsmedelsverket() async {
        guard !livsmedelsverketSyncBusy else { return }
        livsmedelsverketSyncBusy = true
        defer { livsmedelsverketSyncBusy = false }
        livsmedelsverketSyncReport = await livsmedelsverket.sync()
        await loadOFF()
    }
}

struct MealTrackerRoot: View {
    @Binding var language: AppLanguage
    @State private var model: MealModel?
    @State private var startupError: String?
    @State private var pendingURL: URL?
    var body: some View {
        Group {
            if let model { MealShell(model: model, language: $language) }
            else if startupError != nil { VStack { ContentUnavailableView("Simple Foods", systemImage: "exclamationmark.triangle", description: Text(AppCopy(language: language).text("retry"))); Button(AppCopy(language: language).text("retry")) { self.startupError = nil } } }
            else { ProgressView().task {
                do {
                    let loadedModel = try MealModel()
                    model = loadedModel
                    if let pendingURL {
                        loadedModel.receiveSharedURL(pendingURL)
                        self.pendingURL = nil
                    }
                } catch {
                    startupError = appError(error)
                }
            } }
        }
        .temporaryErrorBanner(startupError)
        .onOpenURL { url in
            if let model {
                model.receiveSharedURL(url)
            } else {
                pendingURL = url
            }
        }
    }
}

private typealias FoodOriginFilter = FoodSearchSource

private extension FoodSearchSource {
    var localizationKey: String {
        switch self {
        case .all:
            "allSources"
        case .openFoodFacts:
            "openFoodFacts"
        case .personal:
            "yourFoods"
        case .livsmedelsverket:
            "livsmedelsverket"
        }
    }
}

private func matchesSource(_ food: CatalogueFood, origin: FoodOriginFilter) -> Bool {
    guard origin != .all else { return true }
    switch food.id {
    case .personal:
        return origin == .personal
    case let .catalogue(namespace, _):
        if namespace == "off" { return origin == .openFoodFacts }
        if namespace == "livsmedelsverket" { return origin == .livsmedelsverket }
        return false
    }
}

private struct FoodPersonalizedName: View {
    let food: CatalogueFood
    @ObservedObject var model: MealModel
    let copy: AppCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.name(food, language: copy.language.rawValue))
            FoodPersonalizationTags(food: food, model: model, copy: copy)
        }
        .contextMenu { FoodFavoriteButton(food: food, model: model, copy: copy) }
    }
}

private struct FoodFavoriteButton: View {
    let food: CatalogueFood
    @ObservedObject var model: MealModel
    let copy: AppCopy

    var body: some View {
        let favorite = model.foodPreferences[food.id]?.isFavorite == true
        Button { model.toggleFavorite(food) } label: {
            Label(copy.text(favorite ? "removeFavorite" : "addFavorite"), systemImage: favorite ? "star.fill" : "star")
        }
    }
}

private struct FoodPersonalizationTags: View {
    let food: CatalogueFood
    @ObservedObject var model: MealModel
    let copy: AppCopy

    var body: some View {
        HStack {
            if model.foodPreferences[food.id]?.isFavorite == true {
                Label(copy.text("favoriteFood"), systemImage: "star.fill")
                    .foregroundStyle(.orange)
            }
            if model.foodPreferences[food.id]?.isRecentlyUsed() == true {
                Label(copy.text("recentlyUsed"), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

private struct FoodOriginBadge: View {
    let origin: FoodOriginFilter
    let copy: AppCopy

    var body: some View {
        Text(copy.text(origin.localizationKey))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}

private struct UnsyncedBadge: View {
    let copy: AppCopy

    var body: some View {
        Text(copy.text("notSynced"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.12), in: Capsule())
    }
}

private struct ApproximateNutritionBadge: View {
    let copy: AppCopy

    var body: some View {
        Text(copy.text("approximateNutrition"))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.12), in: Capsule())
    }
}

private enum MealTrackerTab: Hashable {
    case today
    case goals
    case foods
    case savedMeals
    case settings
}

private struct OFFNameEntryLabel: View {
    let entry: OFFNameEntry
    let copy: AppCopy

    private var details: String? {
        var values: [String] = []
        if let brand = entry.brand, !brand.isEmpty {
            values.append(brand)
        }
        if let energy = entry.energyKcal100g {
            values.append("\(copy.kilocalories(Decimal(energy))) kcal / 100 g")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName(language: copy.language.rawValue))
            if let details {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.isApproximate == true {
                ApproximateNutritionBadge(copy: copy)
            }
        }
    }
}

/// Observes tab reselection, which does not trigger SwiftUI's selection onChange.
private struct TodayTabReselectionObserver: UIViewControllerRepresentable {
    let onReselect: () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onReselect = onReselect
        return controller
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onReselect = onReselect
        controller.install()
    }

    static func dismantleUIViewController(_ controller: ObserverController, coordinator: ()) {
        controller.uninstall()
    }

    final class ObserverController: UIViewController, UITabBarControllerDelegate {
        var onReselect: (() -> Void)?
        private weak var observedTabController: UITabBarController?
        private weak var originalDelegate: (any UITabBarControllerDelegate)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let controller = tabBarController, controller.delegate !== self else { return }
            uninstall()
            observedTabController = controller
            originalDelegate = controller.delegate
            controller.delegate = self
        }

        func uninstall() {
            if let controller = observedTabController, controller.delegate === self {
                controller.delegate = originalDelegate
            }
            observedTabController = nil
            originalDelegate = nil
        }

        func tabBarController(_ controller: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            let allowed = originalDelegate?.tabBarController?(controller, shouldSelect: viewController) ?? true
            if allowed, controller.selectedViewController === viewController {
                onReselect?()
            }
            return allowed
        }

        @available(iOS 18.0, *)
        func tabBarController(_ controller: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            let allowed = originalDelegate?.tabBarController?(controller, shouldSelectTab: tab) ?? true
            if allowed, controller.selectedTab === tab {
                onReselect?()
            }
            return allowed
        }

        // Preserve SwiftUI's existing selection, customization and navigation behavior.
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }
    }
}

private enum DaySwipeAxis {
    case horizontal
    case vertical
}

struct MealShell: View {
    private struct AddRequest: Identifiable {
        enum Kind {
            case meal, quickFood, customNutrition, recipe
        }

        let id = UUID()
        let kind: Kind
        let date: Date
    }

    @ObservedObject var model: MealModel
    @Binding var language: AppLanguage
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dailyEnergyGoalKcal") private var dailyEnergyGoal = 2_000.0
    @AppStorage("proteinEnergyPercent") private var proteinEnergyPercent = 25
    @AppStorage("carbohydrateEnergyPercent") private var carbohydrateEnergyPercent = 45
    @AppStorage("fatEnergyPercent") private var fatEnergyPercent = 30
    @AppStorage("includeEnergyExpenditureInGoal") private var includeEnergyExpenditureInGoal = true
    @AppStorage("goalRangeMinimumPercent") private var goalRangeMinimumPercent = 90
    @AppStorage("goalRangeMaximumPercent") private var goalRangeMaximumPercent = 110
    @AppStorage("macroGoalRangeMinimumPercent") private var macroGoalRangeMinimumPercent = 90
    @AppStorage("macroGoalRangeMaximumPercent") private var macroGoalRangeMaximumPercent = 110
    @State private var date = Date()
    @State private var addRequest: AddRequest?
    @State private var deleting: MealEvent?
    @State private var editing: MealEvent?
    @State private var duplicating: MealEvent?
    @State private var choosingDate = false
    @State private var selectedTab = MealTrackerTab.today
    @State private var goalCalendarRefreshID = 0
    @State private var widgetShowsGraphs = false
    @State private var widgetGoalsNavigationID = 0
    @State private var dayPageOffset: CGFloat = 0
    @State private var isChangingDay = false
    @State private var daySwipeAxis: DaySwipeAxis?
    @State private var selectedMacroValue: Double?
    @State private var selectedMacroComparisonNutrient: Nutrient?
    @State private var selectedEnergyComponent: String?
    @State private var confettiRunID: UUID?
    var copy: AppCopy { AppCopy(language: language) }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(-1...1, id: \.self) { offset in
                            if let pageDate = dateByAddingDays(offset) {
                                todayPage(for: pageDate)
                                    .frame(width: proxy.size.width)
                            }
                        }
                    }
                    .offset(x: -proxy.size.width + dayPageOffset)
                    .contentShape(Rectangle())
                    .simultaneousGesture(daySwipe(pageWidth: proxy.size.width))
                }
                    .clipped()
                    .background(TodayTabReselectionObserver {
                        guard selectedTab == .today else { return }
                        dismissChartTooltips()
                        date = Calendar.autoupdatingCurrent.startOfDay(for: Date())
                    })
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Button { choosingDate = true } label: {
                                HStack(spacing: 4) {
                                    Text(dateTitle).font(.headline)
                                    Image(systemName: "chevron.down").font(.caption)
                                }
                            }
                            .accessibilityIdentifier("diary.date")
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button(copy.text("addMeal")) {
                                    addRequest = AddRequest(kind: .meal, date: newMealDate)
                                }
                                Button(copy.text("quickAdd")) {
                                    addRequest = AddRequest(kind: .quickFood, date: newMealDate)
                                }
                                Button(copy.text("addCustomNutrition")) {
                                    addRequest = AddRequest(kind: .customNutrition, date: newMealDate)
                                }
                                Button(copy.text("addSavedMeal")) {
                                    addRequest = AddRequest(kind: .recipe, date: newMealDate)
                                }
                            } label: {
                                Label(copy.text("add"), systemImage: "plus")
                            }
                            .accessibilityIdentifier("diary.add")
                        }
                    }
                    .onChange(of: date) { _, value in
                        dismissChartTooltips()
                        model.reload(value)
                        Task { await model.preloadHealthDays(around: value) }
                    }
                    .onAppear { model.reload(date) }
                    .sheet(isPresented: $choosingDate) {
                        NavigationStack {
                            VStack {
                                DatePicker(copy.text("date"), selection: $date, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                Spacer()
                            }
                                .navigationTitle(copy.text("chooseDate"))
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button(copy.text("today")) {
                                            date = Calendar.current.startOfDay(for: Date())
                                        }
                                    }
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button(copy.text("done")) { choosingDate = false }
                                    }
                                }
                        }
                        .presentationDetents([.large])
                    }
            }
            .tabItem { Label(copy.text("today"), systemImage: "sun.max") }
            .tag(MealTrackerTab.today)
            NavigationStack {
                GoalCalendarView(
                    diary: model.diary,
                    copy: copy,
                    energyGoal: dailyEnergyGoal,
                    proteinPercent: proteinEnergyPercent,
                    carbohydratePercent: carbohydrateEnergyPercent,
                    fatPercent: fatEnergyPercent,
                    goalRangeMinimumPercent: goalRangeMinimumPercent,
                    goalRangeMaximumPercent: goalRangeMaximumPercent,
                    macroGoalRangeMinimumPercent: macroGoalRangeMinimumPercent,
                    macroGoalRangeMaximumPercent: macroGoalRangeMaximumPercent,
                    activeEnergyByDay: includeEnergyExpenditureInGoal ? model.activeEnergyByDay : [:],
                    refreshID: goalCalendarRefreshID,
                    showGraphs: widgetShowsGraphs,
                    widgetNavigationID: widgetGoalsNavigationID,
                    refreshActivity: { days in
                        guard includeEnergyExpenditureInGoal else { return }
                        await model.refreshGoalHealth(days: days, restoring: date)
                    },
                    viewInToday: { selectedDate in
                        date = selectedDate
                        selectedTab = .today
                    }
                )
            }
            .tabItem { Label(copy.text("goals"), systemImage: "calendar") }
            .tag(MealTrackerTab.goals)
            FoodLibraryTab(model: model, language: $language)
                .tabItem { Label(copy.text("foods"), systemImage: "carrot") }
                .tag(MealTrackerTab.foods)
            SavedMealsTab(model: model, copy: copy)
                .tabItem { Label(copy.text("savedMeals"), systemImage: "fork.knife") }
                .tag(MealTrackerTab.savedMeals)
            SettingsTab(
                model: model,
                language: $language,
                dailyEnergyGoal: $dailyEnergyGoal,
                proteinEnergyPercent: $proteinEnergyPercent,
                carbohydrateEnergyPercent: $carbohydrateEnergyPercent,
                fatEnergyPercent: $fatEnergyPercent,
                includeEnergyExpenditureInGoal: $includeEnergyExpenditureInGoal,
                goalRangeMinimumPercent: $goalRangeMinimumPercent,
                goalRangeMaximumPercent: $goalRangeMaximumPercent,
                macroGoalRangeMinimumPercent: $macroGoalRangeMinimumPercent,
                macroGoalRangeMaximumPercent: $macroGoalRangeMaximumPercent,
                date: date
            )
            .tabItem { Label(copy.text("settings"), systemImage: "gearshape") }
            .tag(MealTrackerTab.settings)
        }
        .tint(.teal)
        .overlay {
            if confettiRunID != nil {
                ConfettiRainView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: RecipeEasterEgg.notification) {
                confettiRunID = UUID()
            }
        }
        .task(id: confettiRunID) {
            guard let runID = confettiRunID else { return }
            try? await Task.sleep(for: .seconds(3.7))
            guard confettiRunID == runID else { return }
            confettiRunID = nil
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            model.reload(date)
            if !model.healthConnected {
                await model.restoreHealthConnection(day: date)
            }
            guard !Task.isCancelled else { return }
            // Refresh the selected day's Health data even if it is already cached.
            await model.preloadHealthDays(around: date)
        }
        .onChange(of: selectedTab) { _, selectedTab in
            dismissChartTooltips()
            if selectedTab == .goals {
                goalCalendarRefreshID += 1
            }
        }
        .sheet(item: $addRequest, onDismiss: { model.reload(date) }) { request in
            switch request.kind {
            case .meal:
                MealComposer(model: model, copy: copy, selectedDate: request.date)
            case .quickFood:
                QuickFoodAdd(model: model, copy: copy, selectedDate: request.date)
            case .customNutrition:
                CustomNutritionAdd(model: model, copy: copy, selectedDate: request.date)
            case .recipe:
                SavedMealLogSheet(model: model, copy: copy, selectedDate: request.date)
            }
        }
        .sheet(item: $editing, onDismiss: { model.reload(date) }) { event in MealComposer(model: model, copy: copy, selectedDate: event.eatenAt, editing: event) }
        .sheet(item: $duplicating, onDismiss: { model.reload(date) }) { event in MealComposer(model: model, copy: copy, selectedDate: date, duplicate: event) }
        .confirmationDialog(copy.text("deleteConfirm"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(copy.text("delete"), role: .destructive) {
                guard let event = deleting else { return }
                do { _ = try model.diary.delete(id: event.id, operationID: UUID(), expectedRevision: event.revision); model.reload(date) } catch { model.error = appError(error) }; deleting = nil
            }
        }
        .temporaryErrorBanner(model.error)
        .task(id: model.error) {
            guard model.error != nil else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                model.error = nil
            } catch { }
        }
        .confirmationDialog(
            copy.text("sharedDuplicateTitle"),
            isPresented: Binding(
                get: { model.pendingShareImport != nil },
                set: { if !$0 { model.cancelPendingShareImport() } }
            ),
            titleVisibility: .visible
        ) {
            Button(copy.text("update")) { model.confirmPendingShareImport() }
            Button(copy.text("cancel"), role: .cancel) { model.cancelPendingShareImport() }
        } message: {
            Text(copy.text("sharedDuplicateMessage"))
        }
        .task(id: model.pendingWidgetRoute) {
            guard let route = model.pendingWidgetRoute else { return }
            let hadPresentedSheet = addRequest != nil || editing != nil || duplicating != nil || choosingDate
            addRequest = nil
            editing = nil
            duplicating = nil
            choosingDate = false
            if hadPresentedSheet {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            date = Date()
            dismissChartTooltips()
            switch route {
            case .goals, .graphs:
                widgetShowsGraphs = route == .graphs
                widgetGoalsNavigationID += 1
                goalCalendarRefreshID += 1
                selectedTab = .goals
            case .today:
                selectedTab = .today
            case .meal, .food, .nutrition, .recipe:
                selectedTab = .today
                let kind: AddRequest.Kind
                switch route {
                case .food: kind = .quickFood
                case .nutrition: kind = .customNutrition
                case .recipe: kind = .recipe
                default: kind = .meal
                }
                addRequest = AddRequest(kind: kind, date: Date())
            }
            model.pendingWidgetRoute = nil
        }
        .task(id: "\(language.rawValue)|\(dailyEnergyGoal)|\(proteinEnergyPercent)|\(carbohydrateEnergyPercent)|\(fatEnergyPercent)|\(goalRangeMinimumPercent)|\(goalRangeMaximumPercent)|\(macroGoalRangeMinimumPercent)|\(macroGoalRangeMaximumPercent)|\(includeEnergyExpenditureInGoal)") {
            model.scheduleWidgetSnapshot()
        }
        .onChange(of: model.importedMealDate) { _, importedDate in
            guard let importedDate else { return }
            date = importedDate
            model.reload(importedDate)
            model.importedMealDate = nil
        }
    }

    private var newMealDate: Date {
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDate(date, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: date
        ) ?? date
    }

    private var dateTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return copy.text("today") }
        if calendar.isDateInYesterday(date) { return copy.text("yesterday") }
        if calendar.isDateInTomorrow(date) { return copy.text("tomorrow") }
        return date.formatted(.dateTime.day().month(.wide).year().locale(copy.language.locale))
    }

    private func dismissChartTooltips() {
        selectedEnergyComponent = nil
        selectedMacroValue = nil
        selectedMacroComparisonNutrient = nil
    }

    private func dateByAddingDays(_ offset: Int) -> Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: offset, to: date)
    }

    private func daySwipe(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isChangingDay else { return }
                if daySwipeAxis == nil {
                    daySwipeAxis = abs(value.translation.width) > abs(value.translation.height)
                        ? .horizontal
                        : .vertical
                }
                guard daySwipeAxis == .horizontal else { return }
                dayPageOffset = value.translation.width
            }
            .onEnded { value in
                guard !isChangingDay else { return }
                guard daySwipeAxis == .horizontal else {
                    daySwipeAxis = nil
                    dayPageOffset = 0
                    return
                }
                let horizontalDistance = value.translation.width
                let predictedDistance = value.predictedEndTranslation.width
                let shouldChangeDay = (
                    abs(horizontalDistance) > pageWidth * 0.2 ||
                    abs(predictedDistance) > pageWidth * 0.45
                )

                guard shouldChangeDay else {
                    withAnimation(
                        .interactiveSpring(response: 0.3, dampingFraction: 0.9),
                        completionCriteria: .logicallyComplete
                    ) {
                        dayPageOffset = 0
                    } completion: {
                        daySwipeAxis = nil
                    }
                    return
                }

                isChangingDay = true
                let dayOffset = horizontalDistance < 0 ? 1 : -1
                let destinationOffset = dayOffset > 0 ? -pageWidth : pageWidth
                withAnimation(
                    .interactiveSpring(response: 0.32, dampingFraction: 0.92),
                    completionCriteria: .logicallyComplete
                ) {
                    dayPageOffset = destinationOffset
                } completion: {
                    guard let selectedDate = dateByAddingDays(dayOffset) else {
                        dayPageOffset = 0
                        daySwipeAxis = nil
                        isChangingDay = false
                        return
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        date = selectedDate
                        dayPageOffset = 0
                    }
                    daySwipeAxis = nil
                    isChangingDay = false
                }
            }
    }

    private func todayPage(for pageDate: Date) -> some View {
        let events = model.events(on: pageDate)
        let eventsByRegistration = events.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let cachedActiveEnergy = model.activeEnergyByDay[MealModel.day(pageDate)]
        return List {
            DailyNutritionCharts(
                events: events,
                dailyEnergyGoal: dailyEnergyGoal,
                goalRangeMinimumPercent: goalRangeMinimumPercent,
                goalRangeMaximumPercent: goalRangeMaximumPercent,
                proteinEnergyPercent: proteinEnergyPercent,
                carbohydrateEnergyPercent: carbohydrateEnergyPercent,
                fatEnergyPercent: fatEnergyPercent,
                activeEnergyKcal: includeEnergyExpenditureInGoal ? cachedActiveEnergy?.kcal : nil,
                copy: copy,
                selectedMacroValue: $selectedMacroValue,
                selectedMacroComparisonNutrient: $selectedMacroComparisonNutrient,
                selectedEnergyComponent: $selectedEnergyComponent
            )
            Section(copy.text("nutrition")) { totals(for: events) }
                .onTapGesture(perform: dismissChartTooltips)
            HealthEnergySection(
                state: cachedActiveEnergy.map(EnergyReadState.value) ?? (model.healthConnected ? .noReadableData : model.energy.active),
                copy: copy
            )
                .onTapGesture(perform: dismissChartTooltips)
            if events.isEmpty {
                Text(copy.text("empty"))
                    .foregroundStyle(.secondary)
                    .onTapGesture(perform: dismissChartTooltips)
            }
            ForEach(eventsByRegistration, id: \.id) { event in
                TodayMealSection(
                    event: event,
                    model: model,
                    copy: copy,
                    edit: { editing = event },
                    duplicate: { duplicating = event },
                    delete: { deleting = event }
                )
            }
        }
        .scrollDisabled(daySwipeAxis == .horizontal || isChangingDay)
        // Each pager slot gets a fresh scroll position when it displays a new day.
        .id(MealModel.day(pageDate))
    }

    @ViewBuilder private func totals(for events: [MealEvent]) -> some View {
        ForEach([Nutrient.energy, .protein, .totalFat, .carbohydrateAvailable], id: \.rawValue) { nutrient in
            let values = events.compactMap { $0.totals[nutrient.rawValue] }
            let amount = values.reduce(Decimal.zero) { $0 + $1.knownSubtotal.value }
            VStack(alignment: .leading) {
                Text("\(copy.text(nutrient.rawValue)): \(copy.nutrientNumber(amount, nutrient: nutrient)) \(nutrient.unit.rawValue)")
                if values.contains(where: { $0.completeness != .complete }) { Text(copy.text("incomplete")).font(.caption).foregroundStyle(.secondary) }
                if values.contains(where: \.estimated) { Text(copy.text("estimated")).font(.caption) }
            }
        }
    }
    var syncSection: some View {
        Section {
            if model.offSyncBusy { Text(copy.text("syncingOpenFoodFacts")).font(.caption) }
            Button { Task { await model.sync() } } label: { HStack { Text(copy.text("sync")); if model.offSyncBusy { ProgressView() } } }.disabled(model.offSyncBusy).accessibilityIdentifier("off.sync")
            if let report = model.syncReport {
                Text("\(copy.text("changed")): \(report.items.filter(\.changed).count)")
                Text("\(copy.text("failures")): \(report.failedCount)").foregroundStyle(report.failedCount > 0 ? .red : .secondary)
                ForEach(Array(report.items.filter { $0.error != nil }.enumerated()), id: \.offset) { _, item in Text(item.barcode + ": " + copy.text("offError")).font(.caption) }
            }
        }
    }
}

private enum RecipeSortOrder: String, CaseIterable {
    case recentlyModified, leastRecentlyModified, name

    func sorted(_ meals: [SavedMeal], locale: Locale) -> [SavedMeal] {
        meals.sorted { left, right in
            switch self {
            case .recentlyModified, .leastRecentlyModified:
                if left.updatedAt != right.updatedAt {
                    return self == .recentlyModified
                        ? left.updatedAt > right.updatedAt
                        : left.updatedAt < right.updatedAt
                }
            case .name:
                break
            }
            let comparison = left.name.compare(
                right.name,
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.id.uuidString < right.id.uuidString
        }
    }
}

private struct SavedMealsTab: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    @State private var editing: SavedMeal?
    @State private var deleting: SavedMeal?
    @State private var selectedTag: String?
    @State private var importingRecipe = false
    @State private var creatingRecipe = false
    @State private var query = ""
    @State private var sortOrder: RecipeSortOrder = .recentlyModified

    private var sortedMeals: [SavedMeal] {
        sortOrder.sorted(filteredMeals, locale: copy.language.locale)
    }

    private var availableTags: [String] {
        var tagsByComparisonKey: [String: String] = [:]
        for tag in model.savedMeals.flatMap(\.tags) {
            let comparisonKey = tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: copy.language.locale)
            tagsByComparisonKey[comparisonKey, default: tag] = tag
        }
        return tagsByComparisonKey.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredMeals: [SavedMeal] {
        let tagFilteredMeals = model.savedMeals.filter { meal in
            guard let selectedTag else { return true }
            return meal.tags.contains { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame }
        }
        let searchTerms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !searchTerms.isEmpty else { return tagFilteredMeals }
        return tagFilteredMeals.filter { meal in
            let searchableValues = [meal.name] + meal.tags + meal.ingredients.map(\.displayName)
            return searchTerms.allSatisfy { searchTerm in
                searchableValues.contains { value in
                    value.range(
                        of: searchTerm,
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: copy.language.locale
                    ) != nil
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !availableTags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            SavedMealTagFilter(
                                title: copy.text("allTags"),
                                isSelected: selectedTag == nil,
                                action: { selectedTag = nil }
                            )
                            ForEach(availableTags, id: \.self) { tag in
                                SavedMealTagFilter(
                                    title: tag,
                                    isSelected: selectedTag == tag,
                                    action: { selectedTag = tag }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                if model.savedMeals.isEmpty {
                    ContentUnavailableView(copy.text("noSavedMeals"), systemImage: "fork.knife")
                }
                ForEach(sortedMeals) { meal in
                    Button { editing = meal } label: {
                        SavedMealRow(meal: meal, copy: copy)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(copy.text("delete"), role: .destructive) { deleting = meal }
                    }
                }
            }
            .navigationTitle(copy.text("savedMeals"))
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: copy.text("searchRecipes")
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(copy.text("sortRecipes"), selection: $sortOrder) {
                            Text(copy.text("recentlyModified")).tag(RecipeSortOrder.recentlyModified)
                            Text(copy.text("leastRecentlyModified")).tag(RecipeSortOrder.leastRecentlyModified)
                            Text(copy.text("name")).tag(RecipeSortOrder.name)
                        }
                    } label: {
                        Label(copy.text("sortRecipes"), systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            creatingRecipe = true
                        } label: {
                            Label(copy.text("createRecipe"), systemImage: "square.and.pencil")
                        }
                        Button {
                            importingRecipe = true
                        } label: {
                            Label(copy.text("recipeImport"), systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Label(copy.text("createRecipe"), systemImage: "plus")
                    }
                }
            }
            .task { model.reloadSavedMeals() }
            .onChange(of: availableTags) { _, tags in
                guard let selectedTag else { return }
                if !tags.contains(where: { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame }) {
                    self.selectedTag = nil
                }
            }
            .sheet(item: $editing, onDismiss: model.reloadSavedMeals) { meal in
                SavedMealEditor(model: model, copy: copy, meal: meal)
            }
            .sheet(isPresented: $importingRecipe, onDismiss: model.reloadSavedMeals) {
                RecipeImportView(model: model, copy: copy) { _ in }
            }
            .sheet(isPresented: $creatingRecipe, onDismiss: model.reloadSavedMeals) {
                SavedMealCreator(model: model, copy: copy)
            }
            .confirmationDialog(
                copy.text("deleteSavedMealConfirm"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button(copy.text("delete"), role: .destructive) {
                    guard let meal = deleting else { return }
                    do {
                        _ = try model.diary.deleteSavedMeal(id: meal.id, expectedRevision: meal.revision, operationID: UUID())
                        model.reloadSavedMeals()
                    } catch { model.error = appError(error, copy: copy) }
                    deleting = nil
                }
            }
        }
    }
}

/// Adds a dismissal control to decimal keyboards, which have no Return key.
private struct AmountKeyboardDone: ViewModifier {
    let title: String
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isFocused {
                        Spacer()
                        Button(title) { isFocused = false }
                    }
                }
            }
    }
}

private struct RecipeServingsField: View {
    @Binding var text: String
    let accessibilityLabel: String
    let doneTitle: String

    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, selection: $selection)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .accessibilityLabel(accessibilityLabel)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isFocused {
                        Spacer()
                        Button(doneTitle) { isFocused = false }
                    }
                }
            }
            .onChange(of: isFocused) { _, isFocused in
                guard isFocused else { return }
                Task {
                    await Task.yield()
                    guard self.isFocused else { return }
                    selection = TextSelection(range: text.startIndex..<text.endIndex)
                }
            }
    }
}

struct RecipeTagsField: View {
    @Binding var text: String
    let copy: AppCopy

    var body: some View {
        LabeledContent(copy.text("tags")) {
            TextField(copy.text("tagsHint"), text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct RecipeNutritionValues {
    let total: [Nutrient: Decimal]
    let perPortion: [Nutrient: Decimal]
}

private func recipeNutritionValues(
    ingredients: [MealComponent],
    servings: Decimal
) -> RecipeNutritionValues? {
    guard servings > 0, !ingredients.isEmpty else { return nil }
    let nutrients: [Nutrient] = [.energy, .protein, .carbohydrateAvailable, .totalFat]
    var total = Dictionary(uniqueKeysWithValues: nutrients.map { ($0, Decimal.zero) })
    for ingredient in ingredients {
        guard let nutrition = try? NutritionCalculator.calculate(
            profile: ingredient.food.profile,
            quantity: ingredient.quantity.consumed()
        ) else { return nil }
        for nutrient in nutrients {
            total[nutrient, default: .zero] += nutrition[nutrient].knownSubtotal
        }
    }
    return RecipeNutritionValues(
        total: total,
        perPortion: total.mapValues { $0 / servings }
    )
}

private struct RecipeNutritionSummary: View {
    let values: RecipeNutritionValues?
    let copy: AppCopy

    var body: some View {
        RecipeNutrientValuesView(
            title: copy.text("recipeTotalEnergy"),
            values: values?.total,
            copy: copy
        )
        RecipeNutrientValuesView(
            title: copy.text("energyPerPortion"),
            values: values?.perPortion,
            copy: copy
        )
    }
}

private struct RecipeNutrientValuesView: View {
    let title: String
    let values: [Nutrient: Decimal]?
    let copy: AppCopy

    private let nutrients: [Nutrient] = [.energy, .protein, .carbohydrateAvailable, .totalFat]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(nutrients, id: \.rawValue) { nutrient in
                LabeledContent(copy.text(nutrient.rawValue)) {
                    if let value = values?[nutrient] {
                        Text("\(copy.nutrientNumber(value, nutrient: nutrient)) \(nutrient.unit.rawValue)")
                    } else {
                        Text("—")
                    }
                }
            }
        }
    }
}

private struct SavedMealCreator: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tags = ""
    @State private var servings = "1"
    @State private var ingredients: [MealComponent] = []
    @State private var amounts: [UUID: String] = [:]
    @State private var error: String?
    @State private var addingFood = false
    @State private var gingerbreadIngredientID: UUID?

    private var nutritionValues: RecipeNutritionValues? {
        guard let canonicalServings = copy.canonicalQuantity(servings),
              let servingAmount = Decimal(string: canonicalServings, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var previewIngredients = ingredients
        for index in previewIngredients.indices {
            guard let rawAmount = amounts[previewIngredients[index].id],
                  let canonicalAmount = copy.canonicalQuantity(rawAmount),
                  let amount = try? DecimalAmount(canonicalAmount) else {
                return nil
            }
            previewIngredients[index].quantity.amount = amount
        }
        return recipeNutritionValues(ingredients: previewIngredients, servings: servingAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.text("savedMealDetails")) {
                    TextField(copy.text("mealName"), text: $name)
                    RecipeTagsField(text: $tags, copy: copy)
                    LabeledContent(copy.text("servingsProduced")) {
                        RecipeServingsField(
                            text: $servings,
                            accessibilityLabel: copy.text("servingsProduced"),
                            doneTitle: copy.text("done")
                        )
                    }
                }
                Section(copy.text("nutrition")) {
                    RecipeNutritionSummary(values: nutritionValues, copy: copy)
                }
                Section(copy.text("ingredients")) {
                    ForEach($ingredients) { $ingredient in
                        HStack {
                            VStack(alignment: .leading) {
                                GingerbreadFoodLabel(text: ingredient.displayName, celebrate: gingerbreadIngredientID == ingredient.id)
                                if let raw = amounts[ingredient.id],
                                   let canonical = copy.canonicalQuantity(raw),
                                   let amount = try? DecimalAmount(canonical),
                                   let consumed = try? LoggedQuantity(amount: amount, unit: ingredient.quantity.unit).consumed(),
                                   let totals = try? NutritionCalculator.calculate(profile: ingredient.food.profile, quantity: consumed) {
                                    Text("\(copy.kilocalories(totals[.energy].knownSubtotal)) kcal")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            TextField(copy.text("amount"), text: amountBinding(for: $ingredient))
                                .keyboardType(.decimalPad)
                                .modifier(AmountKeyboardDone(title: copy.text("done")))
                                .multilineTextAlignment(.trailing)
                            Text(ingredient.quantity.unit == .millilitres ? "ml" : "g")
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            amounts.removeValue(forKey: ingredients[index].id)
                        }
                        ingredients.remove(atOffsets: offsets)
                    }
                    Button {
                        addingFood = true
                    } label: {
                        Label(copy.text("addFood"), systemImage: "plus")
                    }
                }

            }
            .navigationTitle(copy.text("createRecipe"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.text("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text("saveRecipe")) { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            copy.canonicalQuantity(servings) == nil ||
                            ingredients.isEmpty
                        )
                }
            }
            .sheet(isPresented: $addingFood) {
                RecipeFoodPicker(model: model, copy: copy) { component in
                    ingredients.append(component)
                    amounts[component.id] = localizedAmount(component.quantity.amount)
                    if FoodEasterEgg.isLebkuchen(component.displayName) {
                        gingerbreadIngredientID = component.id
                    }
                }
            }
        }
        .temporaryErrorBanner(error)
    }

    private func amountBinding(for ingredient: Binding<MealComponent>) -> Binding<String> {
        Binding(
            get: { amounts[ingredient.wrappedValue.id] ?? "" },
            set: { amounts[ingredient.wrappedValue.id] = $0 }
        )
    }

    private func localizedAmount(_ amount: DecimalAmount) -> String {
        amount.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",")
    }

    private func save() {
        do {
            guard let canonicalServings = copy.canonicalQuantity(servings) else {
                throw DiaryError.invalidInput
            }
            var savedIngredients = ingredients
            for index in savedIngredients.indices {
                guard let rawAmount = amounts[savedIngredients[index].id],
                      let canonicalAmount = copy.canonicalQuantity(rawAmount) else {
                    throw DiaryError.invalidInput
                }
                savedIngredients[index].quantity.amount = try DecimalAmount(canonicalAmount)
                _ = try savedIngredients[index].quantity.consumed()
            }
            let parsedTags = tags
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let draft = try SavedMealDraft(
                name: name,
                tags: parsedTags,
                servingsProduced: try DecimalAmount(canonicalServings),
                ingredients: savedIngredients
            )
            _ = try model.diary.createSavedMeal(draft, operationID: UUID())
            model.reloadSavedMeals()
            RecipeEasterEgg.celebrateAfterDismissIfNeeded(name: draft.name)
            dismiss()
        } catch {
            self.error = appError(error, copy: copy)
        }
    }
}

private struct SavedMealRow: View {
    let meal: SavedMeal
    let copy: AppCopy

    private var nutritionValues: RecipeNutritionValues? {
        recipeNutritionValues(ingredients: meal.ingredients, servings: meal.servingsProduced.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meal.name).font(.headline)
            Text("\(copy.number(meal.servingsProduced.value)) \(copy.text("servings")) · \(meal.ingredients.count) \(copy.text("ingredients"))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nutritionValues {
                RecipeMacroRow(values: nutritionValues, copy: copy)
            }
            if !meal.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(meal.tags, id: \.self) { tag in
                            SavedMealTagBadge(title: tag)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct RecipeMacroRow: View {
    let values: RecipeNutritionValues
    let copy: AppCopy

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RecipeCompactNutrientColumn(
                title: copy.text("recipeTotalEnergy"),
                values: values.total,
                copy: copy
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            RecipeCompactNutrientColumn(
                title: copy.text("energyPerPortion"),
                values: values.perPortion,
                copy: copy
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct RecipeCompactNutrientColumn: View {
    let title: String
    let values: [Nutrient: Decimal]
    let copy: AppCopy

    private let nutrients: [Nutrient] = [.energy, .protein, .carbohydrateAvailable, .totalFat]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            ForEach(nutrients, id: \.rawValue) { nutrient in
                if let value = values[nutrient] {
                    Text("\(copy.text(nutrient.rawValue)): \(copy.nutrientNumber(value, nutrient: nutrient)) \(nutrient.unit.rawValue)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }
}

private struct SavedMealTagBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}

private struct SavedMealTagFilter: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.teal : Color.teal.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SavedMealMetadataSheet: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let ingredients: [MealComponent]
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var tags = ""
    @State private var servings = "1"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.text("savedMealDetails")) {
                    TextField(copy.text("mealName"), text: $name)
                    RecipeTagsField(text: $tags, copy: copy)
                    LabeledContent(copy.text("servingsProduced")) {
                        RecipeServingsField(
                            text: $servings,
                            accessibilityLabel: copy.text("servingsProduced"),
                            doneTitle: copy.text("done")
                        )
                    }
                }

            }
            .navigationTitle(copy.text("saveAsMeal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text("save")) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || copy.canonicalQuantity(servings) == nil)
                }
            }
        }
        .temporaryErrorBanner(error)
    }

    private func save() {
        do {
            guard let canonical = copy.canonicalQuantity(servings) else { throw DiaryError.invalidInput }
            let draft = try SavedMealDraft(name: name, tags: parsedTags, servingsProduced: try DecimalAmount(canonical), ingredients: ingredients)
            _ = try model.diary.createSavedMeal(draft, operationID: UUID())
            model.reloadSavedMeals()
            RecipeEasterEgg.celebrateAfterDismissIfNeeded(name: draft.name)
            dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }

    private var parsedTags: [String] {
        tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct SavedMealEditor: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let meal: SavedMeal
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var tags: String
    @State private var servings: String
    @State private var ingredients: [MealComponent]
    @State private var amounts: [UUID: String]
    @State private var error: String?
    @State private var addingFood = false
    @State private var gingerbreadIngredientID: UUID?

    init(model: MealModel, copy: AppCopy, meal: SavedMeal) {
        self.model = model
        self.copy = copy
        self.meal = meal
        _name = State(initialValue: meal.name)
        _tags = State(initialValue: meal.tags.joined(separator: ", "))
        _servings = State(initialValue: meal.servingsProduced.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ","))
        _ingredients = State(initialValue: meal.ingredients)
        _amounts = State(initialValue: Dictionary(uniqueKeysWithValues: meal.ingredients.map { ($0.id, $0.quantity.amount.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",")) }))
    }

    private var nutritionValues: RecipeNutritionValues? {
        guard let canonicalServings = copy.canonicalQuantity(servings),
              let servingAmount = Decimal(string: canonicalServings, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var previewIngredients = ingredients
        for index in previewIngredients.indices {
            guard let rawAmount = amounts[previewIngredients[index].id],
                  let canonicalAmount = copy.canonicalQuantity(rawAmount),
                  let amount = try? DecimalAmount(canonicalAmount) else {
                return nil
            }
            previewIngredients[index].quantity.amount = amount
        }
        return recipeNutritionValues(ingredients: previewIngredients, servings: servingAmount)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.text("savedMealDetails")) {
                    TextField(copy.text("mealName"), text: $name)
                    RecipeTagsField(text: $tags, copy: copy)
                    LabeledContent(copy.text("servingsProduced")) {
                        RecipeServingsField(
                            text: $servings,
                            accessibilityLabel: copy.text("servingsProduced"),
                            doneTitle: copy.text("done")
                        )
                    }
                }
                Section(copy.text("nutrition")) {
                    RecipeNutritionSummary(values: nutritionValues, copy: copy)
                }
                Section(copy.text("ingredients")) {
                    ForEach($ingredients) { $ingredient in
                        HStack {
                            GingerbreadFoodLabel(
                                text: ingredient.displayName,
                                celebrate: gingerbreadIngredientID == ingredient.id
                            )
                            Spacer()
                            TextField(copy.text("amount"), text: amountBinding(for: $ingredient))
                                .keyboardType(.decimalPad)
                                .modifier(AmountKeyboardDone(title: copy.text("done")))
                                .multilineTextAlignment(.trailing)
                            Text(ingredient.quantity.unit == .millilitres ? "ml" : "g")
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { amounts.removeValue(forKey: ingredients[index].id) }
                        ingredients.remove(atOffsets: offsets)
                    }
                    Button {
                        addingFood = true
                    } label: {
                        Label(copy.text("addFood"), systemImage: "plus")
                    }
                }
                if let shareDocument = MealShareDocument(
                    MealSharePayload.recipe(meal),
                    filename: meal.name
                ) {
                    Section {
                        ShareLink(
                            item: shareDocument,
                            subject: Text(copy.text("shareRecipe")),
                            preview: SharePreview(meal.name)
                        ) {
                            Label(copy.text("shareRecipe"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }

            }
            .navigationTitle(copy.text("editMeal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text("saveRecipe")) { save() }
                        .disabled(ingredients.isEmpty)
                }
            }
            .sheet(isPresented: $addingFood) {
                RecipeFoodPicker(model: model, copy: copy, nutritionValues: nutritionValues) { component in
                    ingredients.append(component)
                    amounts[component.id] = component.quantity.amount.canonicalString
                        .replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",")
                    if FoodEasterEgg.isLebkuchen(component.displayName) {
                        gingerbreadIngredientID = component.id
                    }
                }
            }
        }
        .temporaryErrorBanner(error)
    }

    private func amountBinding(for ingredient: Binding<MealComponent>) -> Binding<String> {
        Binding(
            get: { amounts[ingredient.wrappedValue.id] ?? "" },
            set: { amounts[ingredient.wrappedValue.id] = $0 }
        )
    }

    private func save() {
        do {
            guard let canonicalServings = copy.canonicalQuantity(servings) else { throw DiaryError.invalidInput }
            var updated = ingredients
            for index in updated.indices {
                guard let raw = amounts[updated[index].id], let canonical = copy.canonicalQuantity(raw) else { throw DiaryError.invalidInput }
                updated[index].quantity.amount = try DecimalAmount(canonical)
                _ = try updated[index].quantity.consumed()
            }
            let parsedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let draft = try SavedMealDraft(name: name, tags: parsedTags, servingsProduced: try DecimalAmount(canonicalServings), ingredients: updated)
            _ = try model.diary.updateSavedMeal(id: meal.id, draft: draft, expectedRevision: meal.revision, operationID: UUID())
            model.reloadSavedMeals()
            RecipeEasterEgg.celebrateAfterDismissIfNeeded(name: draft.name)
            dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }
}

private struct RecipeFoodPicker: View {
    private struct AmountSelection: Identifiable {
        let food: CatalogueFood
        var id: FoodID { food.id }
    }

    @ObservedObject var model: MealModel
    let copy: AppCopy
    var nutritionValues: RecipeNutritionValues? = nil
    let completion: (MealComponent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var market = ""
    @State private var origin = FoodOriginFilter.all
    @State private var favoritesOnly = false
    @State private var searchResults: [FoodSearchHit] = []
    @State private var correctedQuery: String?
    private var matches: [CatalogueFood] {
        get { searchResults.compactMap(\.food) }
        nonmutating set { searchResults = newValue.map(FoodSearchHit.init(food:)) }
    }
    private var offNameMatches: [OFFNameEntry] {
        get { searchResults.compactMap(\.nameEntry) }
        nonmutating set {
            let kept = Set(newValue.map(\.barcode))
            searchResults.removeAll { $0.nameEntry.map { !kept.contains($0.barcode) } ?? false }
            let existing = Set(searchResults.compactMap { $0.nameEntry?.barcode })
            searchResults += newValue.filter { !existing.contains($0.barcode) }.map(FoodSearchHit.init(nameEntry:))
        }
    }
    @State private var product: OFFProduct?
    @State private var amountSelection: AmountSelection?
    @State private var amount = "100"
    @State private var unit = QuantityUnit.grams
    @State private var error: String?
    @State private var showingUnsupportedProduct = false
    @State private var unsupportedProductBarcode: String?
    @State private var isSearching = false
    @State private var activeSearchID = UUID()

    var body: some View {
        NavigationStack {
            List {
                if let nutritionValues {
                    Section(copy.text("nutrition")) {
                        RecipeNutritionSummary(values: nutritionValues, copy: copy)
                    }
                }
                BarcodeFoodSearchSection(model: model, copy: copy) { result in
                    if result.foods.count == 1, let food = result.foods.first {
                        product = result.product
                        select(food)
                    } else {
                        matches = result.foods
                        offNameMatches = []
                    }
                }

                Section {
                    if let correctedQuery {
                        Text(copy.text("searchCorrection") + " “" + correctedQuery + "”")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    FoodFilterTags(market: $market, origin: $origin, favoritesOnly: $favoritesOnly, copy: copy)

                    if isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(copy.text("search"))
                    }
                }

                ForEach(searchResults.prefix(20)) { result in
                    if let food = result.food {
                        Button { select(food) } label: {
                            VStack(alignment: .leading) {
                                FoodPersonalizedName(food: food, model: model, copy: copy)
                                Text(sourceLabel(food)).font(.caption).foregroundStyle(.secondary)
                                if model.offProducts.first(where: { $0.food?.id == food.id })?.hasApproximateNutrition == true {
                                    ApproximateNutritionBadge(copy: copy)
                                }
                            }
                        }
                    } else if let entry = result.nameEntry {
                        Button { Task { await selectOFF(entry) } } label: {
                            VStack(alignment: .leading) {
                                OFFNameEntryLabel(entry: entry, copy: copy)
                                UnsyncedBadge(copy: copy)
                            }
                        }
                    }
                }
                if !isSearching,
                   matches.isEmpty,
                   offNameMatches.isEmpty,
                   (!query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !market.isEmpty || origin != .all || favoritesOnly) {
                    ContentUnavailableView(copy.text("noSearchResults"), systemImage: "magnifyingglass")
                }

                Color.clear
                    .frame(height: 64)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityHidden(true)
            }
            .navigationTitle(copy.text("addFood"))
            .searchable(text: $query, prompt: copy.text("search"))
            .task(id: "\(origin.rawValue)|\(market)|\(favoritesOnly)|\(model.favoriteRevision)|\(query)") {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                await search()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
            }
            .onChange(of: showingUnsupportedProduct) { _, showing in
                guard showing else { return }
                error = copy.text("unsupported")
                purgeUnsupportedProduct()
                showingUnsupportedProduct = false
            }
            .sheet(item: $amountSelection) { selection in
                MealFoodAmountSheet(
                    food: selection.food,
                    foodName: model.name(selection.food, language: copy.language.rawValue),
                    amount: $amount,
                    unit: $unit,
                    availableUnits: availableQuantityUnits(for: selection.food),
                    copy: copy,
                    error: $error,
                    add: { await add(selection.food) }
                )
            }
        }
        .temporaryErrorBanner(error)
    }

    private func search() async {
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedMarket = market
        let selectedFavoritesOnly = favoritesOnly
        let selectedOrigin = origin
        let searchID = UUID()
        activeSearchID = searchID
        guard !searchQuery.isEmpty || !selectedMarket.isEmpty || selectedOrigin != .all || selectedFavoritesOnly else {
            matches = []
            offNameMatches = []
            correctedQuery = nil
            isSearching = false
            return
        }

        isSearching = true
        defer {
            if activeSearchID == searchID {
                isSearching = false
            }
        }
        error = nil

        do {
            let result = try await model.searchFoods(
                query: searchQuery,
                language: copy.language,
                market: selectedMarket,
                origin: selectedOrigin,
                favoritesOnly: selectedFavoritesOnly,
                limit: 20
            )
            guard activeSearchID == searchID, !Task.isCancelled else { return }
            searchResults = result.hits
            correctedQuery = result.correctedQuery
        } catch is CancellationError {
            return
        } catch {
            guard activeSearchID == searchID, !Task.isCancelled else { return }
            self.error = appError(error, copy: copy)
        }
    }

    private func select(_ food: CatalogueFood) {
        amount = "100"
        unit = .grams
        model.recordFoodSelection(food, query: query, language: copy.language)
        if case let .catalogue(namespace, _) = food.id, namespace == "off" {
            if let loadedProduct = model.offProducts.first(where: { $0.food?.id == food.id }) {
                product = loadedProduct
            } else if product?.food?.id != food.id {
                product = nil
            }
        } else {
            product = nil
        }
        let units = availableQuantityUnits(for: food)
        if !units.contains(unit) { unit = units.first ?? .grams }
        amountSelection = AmountSelection(food: food)
    }

    private func selectOFF(_ entry: OFFNameEntry) async {
        do {
            let fetched = try await model.off.lookup(barcode: entry.barcode, language: copy.language.rawValue)
            await model.loadOFF()
            guard let food = fetched.food else {
                unsupportedProductBarcode = fetched.barcode
                showingUnsupportedProduct = true
                return
            }
            product = fetched
            select(food)
        } catch { self.error = appError(error, copy: copy) }
    }

    private func availableQuantityUnits(for food: CatalogueFood) -> [QuantityUnit] {
        [QuantityUnit.grams, .millilitres].filter { quantityUnit in
            guard let one = try? DecimalAmount("1") else { return false }
            return (try? NutritionCalculator.calculate(
                profile: food.profile,
                quantity: LoggedQuantity(amount: one, unit: quantityUnit).consumed()
            )) != nil
        }
    }

    private func purgeUnsupportedProduct() {
        guard let barcode = unsupportedProductBarcode else { return }
        unsupportedProductBarcode = nil
        offNameMatches.removeAll { $0.barcode == barcode }
        Task {
            do {
                try await model.off.purgeCachedProduct(barcode: barcode)
                await model.loadOFF()
            } catch {
                self.error = appError(error, copy: copy)
            }
        }
    }

    private func add(_ food: CatalogueFood) async {
        do {
            error = nil
            product = try await model.productForLogging(food, language: copy.language)
            let food = product?.food ?? food
            guard let canonical = copy.canonicalQuantity(amount) else { throw DiaryError.invalidInput }
            let resolution = try model.personal.resolve(base: food)
            let namespace: String? = {
                if case let .catalogue(namespace, _) = food.id { return namespace }
                return nil
            }()
            let isOFF = namespace == "off"
            let isSLV = namespace == "livsmedelsverket"
            guard !isOFF || product != nil else { throw DiaryError.invalidInput }
            let component = try MealComponent(
                food: resolution.food,
                generationID: model.catalogue.generationID,
                displayName: model.name(resolution.food, language: copy.language.rawValue),
                language: copy.language.rawValue,
                quantity: LoggedQuantity(amount: try DecimalAmount(canonical), unit: unit),
                fixtureOnly: !isOFF && !isSLV && { if case .personal = food.id { return false }; return model.catalogue.fixtureOnly }(),
                provenance: isOFF ? (product?.provenance ?? [:]) : isSLV ? livsmedelsverketProvenance(for: food) : model.catalogue.provenance,
                evidence: isOFF || isSLV ? [:] : model.catalogue.evidence,
                overlayRevision: resolution.overlayRevision
            )
            completion(component)
            amountSelection = nil
            dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }

    private func sourceLabel(_ food: CatalogueFood) -> String {
        switch food.id {
        case .personal: copy.text("userEntered")
        case let .catalogue(namespace, _): copy.text(namespace == "off" ? "community" : namespace == "livsmedelsverket" ? "livsmedelsverket" : "source")
        }
    }
}

private struct SavedMealLogSheet: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sortOrder = RecipeSortOrder.recentlyModified
    @State private var selectedMealID: UUID?
    @State private var servings = "1"
    @State private var category = MealCategory.snack
    @State private var error: String?

    private var filteredMeals: [SavedMeal] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return model.savedMeals }
        return model.savedMeals.filter { meal in
            let values = [meal.name] + meal.tags + meal.ingredients.map(\.displayName)
            return terms.allSatisfy { term in
                values.contains {
                    $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], locale: copy.language.locale) != nil
                }
            }
        }
    }

    var body: some View {
        let meals = sortOrder.sorted(filteredMeals, locale: copy.language.locale)
        NavigationStack {
            Form {
                Section {
                    LabeledContent(copy.text("servingsToLog")) {
                        RecipeServingsField(
                            text: $servings,
                            accessibilityLabel: copy.text("servingsToLog"),
                            doneTitle: copy.text("done")
                        )
                    }
                    Picker(copy.text("category"), selection: $category) {
                        ForEach(MealCategory.allCases, id: \.rawValue) { Text(copy.text($0.rawValue)).tag($0) }
                    }
                }
                Section(copy.text("savedMeals")) {
                    if model.savedMeals.isEmpty {
                        Text(copy.text("noSavedMeals"))
                    } else if meals.isEmpty {
                        Text(copy.text("noSearchResults"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(meals) { meal in
                        Button { selectedMealID = meal.id } label: {
                            HStack {
                                SavedMealRow(meal: meal, copy: copy)
                                Spacer()
                                if selectedMealID == meal.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .navigationTitle(copy.text("addSavedMeal"))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: copy.text("search"))
            .onChange(of: query) { _, _ in
                if let selectedMealID, !filteredMeals.contains(where: { $0.id == selectedMealID }) {
                    self.selectedMealID = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker(copy.text("sortRecipes"), selection: $sortOrder) {
                            ForEach(RecipeSortOrder.allCases, id: \.rawValue) { order in
                                Text(copy.text(order.rawValue)).tag(order)
                            }
                        }
                    } label: {
                        Label(copy.text("sortRecipes"), systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button(copy.text("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text("add")) { add() }
                        .disabled(selectedMealID == nil || copy.canonicalQuantity(servings) == nil)
                }
            }
            .task {
                model.reloadSavedMeals()
                category = (try? DiaryTime.category(selectedDate, zoneID: TimeZone.current.identifier)) ?? .snack
            }
        }
        .temporaryErrorBanner(error)
    }

    private func add() {
        do {
            guard let id = selectedMealID,
                  let meal = model.savedMeals.first(where: { $0.id == id }),
                  let canonical = copy.canonicalQuantity(servings) else { throw DiaryError.invalidInput }
            let components = try meal.components(forServings: DecimalAmount(canonical))
            let existing = model.events.last(where: {
                $0.category == category && $0.localDate == MealModel.day(selectedDate)
            })
            let draft: MealDraft
            if let existing {
                draft = MealDraft(
                    id: existing.id,
                    eatenAt: existing.eatenAt,
                    zoneID: existing.zoneID,
                    category: existing.categoryMode == "manual" ? existing.category : nil,
                    components: existing.components + components,
                    expectedEventRevision: existing.revision
                )
            } else {
                draft = MealDraft(eatenAt: selectedDate, zoneID: TimeZone.current.identifier, category: category, components: components)
            }
            let event = try model.diary.save(draft, operationID: UUID(), expectedRevision: draft.expectedEventRevision)
            Task { await model.syncMealToHealth(event) }
            model.reload(selectedDate)
            dismiss()
        } catch { self.error = appError(error, copy: copy) }
    }
}

private struct SettingsTab: View {
    @ObservedObject var model: MealModel
    @Binding var language: AppLanguage
    @Binding var dailyEnergyGoal: Double
    @Binding var proteinEnergyPercent: Int
    @Binding var carbohydrateEnergyPercent: Int
    @Binding var fatEnergyPercent: Int
    @Binding var includeEnergyExpenditureInGoal: Bool
    @Binding var goalRangeMinimumPercent: Int
    @Binding var goalRangeMaximumPercent: Int
    @Binding var macroGoalRangeMinimumPercent: Int
    @Binding var macroGoalRangeMaximumPercent: Int
    let date: Date
    @State private var isDailyEnergyGoalEditing = false

    private var copy: AppCopy { AppCopy(language: language) }
    private var macroTotal: Int { proteinEnergyPercent + carbohydrateEnergyPercent + fatEnergyPercent }

    var body: some View {
        NavigationStack {
            Form {
                SettingsLanguageSection(language: $language, copy: copy)
                SettingsEnergyGoalSection(
                    dailyEnergyGoal: $dailyEnergyGoal,
                    includeEnergyExpenditureInGoal: $includeEnergyExpenditureInGoal,
                    isEditing: $isDailyEnergyGoalEditing,
                    copy: copy
                )
                SettingsGoalRangeSection(
                    minimumPercent: $goalRangeMinimumPercent,
                    maximumPercent: $goalRangeMaximumPercent,
                    copy: copy
                )
                SettingsMacroGoalSection(
                    proteinEnergyPercent: $proteinEnergyPercent,
                    carbohydrateEnergyPercent: $carbohydrateEnergyPercent,
                    fatEnergyPercent: $fatEnergyPercent,
                    total: macroTotal,
                    copy: copy
                )
                SettingsGoalRangeSection(
                    minimumPercent: $macroGoalRangeMinimumPercent,
                    maximumPercent: $macroGoalRangeMaximumPercent,
                    copy: copy,
                    titleKey: "macroGoalRange",
                    helpKey: "macroGoalRangeHelp"
                )
                SettingsHealthSection(model: model, date: date, copy: copy)
                LivsmedelsverketSyncSection(model: model, copy: copy)
                SettingsAboutSection(copy: copy)
            }
            .navigationTitle(copy.text("settings"))
            .scrollDismissesKeyboard(.interactively)
            .background(SettingsKeyboardDismissArea())
            .overlay(alignment: .bottomTrailing) {
                if isDailyEnergyGoalEditing {
                    Button {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .padding(10)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(copy.text("done"))
                    .padding(.trailing, 26)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

private struct SettingsAboutSection: View {
    let copy: AppCopy

    var body: some View {
        Section {
            NavigationLink {
                AboutView(copy: copy)
            } label: {
                Label(copy.text("about"), systemImage: "info.circle")
            }
        }
    }
}

private struct AboutView: View {
    let copy: AppCopy

    var body: some View {
        List {
            AboutAppSection(copy: copy)
            AboutDataSourcesSection(copy: copy)
            AboutPrivacySection(copy: copy)
            TipDeveloperSection(copy: copy)
        }
        .navigationTitle(copy.text("about"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutAppSection: View {
    let copy: AppCopy

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Simple Foods")
                    .font(.title2.bold())
                Text(copy.text("aboutDescription"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(copy.text("aiToolingAcknowledgment"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("\(copy.text("version")) \(version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            if let repositoryURL = AppConfiguration.repositoryURL {
                Link(destination: repositoryURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
    }
}

private struct AboutDataSourcesSection: View {
    let copy: AppCopy

    var body: some View {
        Section(copy.text("dataSources")) {
            if let openFoodFactsURL = URL(string: "https://world.openfoodfacts.org") {
                Link(destination: openFoodFactsURL) {
                    Label(copy.text("openFoodFacts"), systemImage: "globe")
                }
            }
            if let livsmedelsverketURL = URL(string: "https://www.livsmedelsverket.se") {
                Link(destination: livsmedelsverketURL) {
                    Label(copy.text("livsmedelsverket"), systemImage: "building.columns")
                }
            }
            Text(copy.text("aboutDataSources"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(copy.text("openFoodFactsDatasetNotice"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let odblURL = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/") {
                Link(copy.text("openDatabaseLicense"), destination: odblURL)
            }
            Text(copy.text("openFoodFactsDisclaimer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(copy.text("livsmedelsverketDatasetNotice"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let ccByURL = URL(string: "https://creativecommons.org/licenses/by/4.0/") {
                Link("CC BY 4.0", destination: ccByURL)
            }
        }
    }
}

private struct AboutPrivacySection: View {
    let copy: AppCopy

    var body: some View {
        Section(copy.text("privacy")) {
            Text(copy.text("aboutPrivacy"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct TipDeveloperSection: View {
    let copy: AppCopy
    @Environment(\.purchase) private var purchase
    @State private var product: Product?
    @State private var isLoading = true
    @State private var isPurchasing = false
    @State private var message: String?

    var body: some View {
        Section(copy.text("supportDevelopment")) {
            Text(copy.text("tipExplanation"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let product {
                Button {
                    Task { await buy(product) }
                } label: {
                    HStack {
                        Label(copy.text("tipDeveloper"), systemImage: "heart.fill")
                        Spacer()
                        if isPurchasing {
                            ProgressView()
                        } else {
                            Text(product.displayPrice)
                        }
                    }
                }
                .disabled(isPurchasing)
            } else if isLoading {
                HStack {
                    Text(copy.text("loadingTip"))
                    Spacer()
                    ProgressView()
                }
            } else {
                Text(copy.text("tipUnavailable"))
                    .foregroundStyle(.secondary)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadProduct()
            await finishUnfinishedTips()
        }
    }

    private func loadProduct() async {
        isLoading = true
        defer { isLoading = false }
        guard let productID = AppConfiguration.tipProductID else {
            product = nil
            return
        }
        do {
            product = try await Product.products(for: [productID]).first
        } catch {
            product = nil
        }
    }

    private func buy(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await purchase(product) {
            case let .success(.verified(transaction)):
                await transaction.finish()
                message = copy.text("tipThankYou")
            case .success(.unverified):
                message = copy.text("tipVerificationFailed")
            case .pending:
                message = copy.text("tipPending")
            case .userCancelled:
                break
            @unknown default:
                message = copy.text("tipFailed")
            }
        } catch {
            message = copy.text("tipFailed")
        }
    }

    private func finishUnfinishedTips() async {
        guard let productID = AppConfiguration.tipProductID else { return }
        for await result in Transaction.unfinished {
            guard case let .verified(transaction) = result,
                  transaction.productID == productID else { continue }
            await transaction.finish()
        }
    }
}

private struct SettingsLanguageSection: View {
    @Binding var language: AppLanguage
    let copy: AppCopy

    var body: some View {
        Picker(copy.text("language"), selection: $language) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.name).tag(language)
            }
        }
    }
}

private struct SettingsEnergyGoalSection: View {
    @Binding var dailyEnergyGoal: Double
    @Binding var includeEnergyExpenditureInGoal: Bool
    @Binding var isEditing: Bool
    let copy: AppCopy

    var body: some View {
        Section(copy.text("energyGoal")) {
            LabeledContent(copy.text("dailyEnergyGoal")) {
                CalorieGoalTextField(value: $dailyEnergyGoal, isEditing: $isEditing)
                    .frame(minWidth: 80, minHeight: 24)
                    .accessibilityIdentifier("settings.dailyEnergyGoal")
            }
            Toggle(copy.text("includeEnergyExpenditureInGoal"), isOn: $includeEnergyExpenditureInGoal)
                .accessibilityIdentifier("settings.includeEnergyExpenditureInGoal")
            Text(copy.text("energyGoalHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CalorieGoalTextField: UIViewRepresentable {
    @Binding var value: Double
    @Binding var isEditing: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, isEditing: $isEditing)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.textAlignment = .right
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .editingChanged)
        context.coordinator.textField = textField
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.value = $value
        context.coordinator.isEditing = $isEditing
        guard !textField.isFirstResponder else { return }
        let formatted = value.formatted(.number.precision(.fractionLength(0)))
        if textField.text != formatted {
            textField.text = formatted
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var value: Binding<Double>
        var isEditing: Binding<Bool>
        weak var textField: UITextField?

        init(value: Binding<Double>, isEditing: Binding<Bool>) {
            self.value = value
            self.isEditing = isEditing
        }

        @objc func valueChanged() {
            guard let text = textField?.text, let number = Double(text) else { return }
            value.wrappedValue = number
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            textField.text = Self.editingText(value.wrappedValue)
            isEditing.wrappedValue = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            valueChanged()
            textField.text = value.wrappedValue.formatted(.number.precision(.fractionLength(0)))
            isEditing.wrappedValue = false
        }

        private static func editingText(_ value: Double) -> String {
            String(Int(value.rounded()))
        }
    }
}

private struct SettingsKeyboardDismissArea: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.isUserInteractionEnabled = false
        view.windowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.install(in: window)
        }
        return view
    }

    func updateUIView(_ view: WindowTrackingView, context: Context) {}

    static func dismantleUIView(_ view: WindowTrackingView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class WindowTrackingView: UIView {
        var windowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard self.window !== window else { return }
            uninstall()
            guard let window else { return }
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            self.window = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer {
                window?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var touchedView = touch.view
            while let view = touchedView {
                if view is UITextField { return false }
                touchedView = view.superview
            }
            return true
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }
    }
}

private struct SettingsGoalRangeSection: View {
    @Binding var minimumPercent: Int
    @Binding var maximumPercent: Int
    let copy: AppCopy
    var titleKey = "goalRange"
    var helpKey = "goalRangeHelp"

    var body: some View {
        Section(copy.text(titleKey)) {
            EditablePercentStepper(
                title: copy.text("goalRangeMinimum"),
                value: $minimumPercent,
                range: 0...maximumPercent
            )
            EditablePercentStepper(
                title: copy.text("goalRangeMaximum"),
                value: $maximumPercent,
                range: minimumPercent...300
            )
            Text(copy.text(helpKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsMacroGoalSection: View {
    @Binding var proteinEnergyPercent: Int
    @Binding var carbohydrateEnergyPercent: Int
    @Binding var fatEnergyPercent: Int
    let total: Int
    let copy: AppCopy

    var body: some View {
        Section(copy.text("macroGoals")) {
            EditablePercentStepper(
                title: copy.text("protein"),
                value: $proteinEnergyPercent,
                range: 0...100
            )
            EditablePercentStepper(
                title: copy.text("carbohydrate.euAvailable"),
                value: $carbohydrateEnergyPercent,
                range: 0...100
            )
            EditablePercentStepper(
                title: copy.text("fat.total"),
                value: $fatEnergyPercent,
                range: 0...100
            )
            Text("\(copy.text("total")): \(total)%")
                .foregroundStyle(total == 100 ? Color.secondary : Color.red)
        }
        .temporaryErrorBanner(total == 100 ? nil : copy.text("macroGoalTotalHelp"))
    }
}

private struct EditablePercentStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>) {
        self.title = title
        _value = value
        self.range = range
        _text = State(initialValue: String(value.wrappedValue))
    }

    var body: some View {
        Stepper(value: clampedValue, in: range) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 2) {
                    TextField("", text: $text)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isFocused)
                        .frame(width: 46)
                        .accessibilityLabel(title)
                    Text("%")
                }
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: text) { _, newText in
            guard let enteredValue = Int(newText), !newText.isEmpty else { return }
            value = min(max(enteredValue, range.lowerBound), range.upperBound)
        }
        .onChange(of: value) { _, newValue in
            guard !isFocused else { return }
            text = String(newValue)
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                text = String(value)
            } else {
                value = min(max(value, range.lowerBound), range.upperBound)
                text = String(value)
            }
        }
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
                if !isFocused { text = String(value) }
            }
        )
    }
}

private struct SettingsHealthSection: View {
    @ObservedObject var model: MealModel
    let date: Date
    let copy: AppCopy

    var body: some View {
        Section {
            Text(copy.text(model.healthConnected ? "healthConnected" : "health"))
            Text(copy.text("healthReadExplanation"))
                .foregroundStyle(.secondary)
            Button(copy.text("connectHealth")) {
                Task { await model.connectHealth(day: date) }
            }
            .disabled(model.healthBusy || model.energy.availability == .unavailable)
            if model.healthBusy { ProgressView() }
        }
    }
}

private struct FoodLibraryTab: View {
    private struct Result: Identifiable {
        let food: CatalogueFood?
        let product: OFFProduct?
        let nameEntry: OFFNameEntry?
        let origin: FoodOriginFilter?
        var id: String { nameEntry?.barcode ?? String(describing: food!.id) }
    }

    @ObservedObject var model: MealModel
    @Binding var language: AppLanguage
    @State private var query = ""
    @State private var market = ""
    @State private var foodOrigin = FoodOriginFilter.all
    @State private var favoritesOnly = false
    @State private var creatingFood = false
    @State private var resultLimit = 20
    @State private var results: [Result] = []
    @State private var correctedQuery: String?
    @State private var loadingOperationCount = 0
    @State private var hasLoadedInitialContent = false

    private var copy: AppCopy { AppCopy(language: language) }
    private var isLoading: Bool { loadingOperationCount > 0 }

    var body: some View {
        NavigationStack {
            List {
                if let correctedQuery {
                    Text(copy.text("searchCorrection") + " “" + correctedQuery + "”")
                        .font(.caption).foregroundStyle(.secondary)
                }
                FoodFilterTags(market: $market, origin: $foodOrigin, favoritesOnly: $favoritesOnly, copy: copy)
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
                if !isLoading, results.isEmpty, hasActiveSearch {
                    ContentUnavailableView(copy.text("noSearchResults"), systemImage: "magnifyingglass")
                }
                ForEach(results.prefix(resultLimit)) { result in
                    NavigationLink {
                        if let food = result.food {
                            FoodDetail(food: food, product: result.product, model: model, copy: copy)
                                .onAppear { model.recordFoodSelection(food, query: query, language: language) }
                        } else if let entry = result.nameEntry {
                            OFFNameEntryDetail(entry: entry, model: model, copy: copy, searchQuery: query)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            if let food = result.food {
                                FoodLibraryFoodLabel(
                                    food: food,
                                    product: result.product,
                                    model: model,
                                    copy: copy
                                )
                            } else if let entry = result.nameEntry {
                                OFFNameEntryLabel(entry: entry, copy: copy)
                                Text(entry.markets.map { $0 == "SE" ? "🇸🇪 SE" : $0 == "DE" ? "🇩🇪 DE" : $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                UnsyncedBadge(copy: copy)
                            }
                            if let origin = result.origin {
                                FoodOriginBadge(origin: origin, copy: copy)
                            }
                        }
                    }
                }
                if results.count > resultLimit {
                    Button(copy.text("showMore")) {
                        resultLimit += 20
                    }
                }
                FoodLibraryCounts(model: model, copy: copy)
            }
            .toolbar {
                Button(copy.text("createFood")) { creatingFood = true }
            }
            .sheet(isPresented: $creatingFood, onDismiss: { Task { await model.loadOFF() } }) {
                FoodEditor(model: model, copy: copy, base: nil)
            }
            .task {
                await model.loadOFF()
                hasLoadedInitialContent = true
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: copy.text("search")
            )
            .task(id: "\(hasLoadedInitialContent)|\(query)|\(market)|\(foodOrigin.rawValue)|\(favoritesOnly)|\(language.rawValue)|\(model.favoriteRevision)|\(resultLimit)") {
                guard hasLoadedInitialContent else { return }
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await search()
            }
            .onChange(of: query) { _, _ in resultLimit = 20 }
            .onChange(of: market) { _, _ in resultLimit = 20 }
            .onChange(of: favoritesOnly) { _, _ in resultLimit = 20 }
            .onChange(of: model.favoriteRevision) { _, _ in resultLimit = 20 }
            .onChange(of: foodOrigin) { _, _ in resultLimit = 20 }
            .onChange(of: language) { _, _ in resultLimit = 20 }
            .navigationTitle(copy.text("foods"))
        }
    }

    private func search(showLoading: Bool = true) async {
        if showLoading { loadingOperationCount += 1 }
        defer { if showLoading { loadingOperationCount -= 1 } }
        do {
            let result = try await model.searchFoods(query: query, language: language, market: market, origin: foodOrigin, favoritesOnly: favoritesOnly, limit: resultLimit + 1)
            try Task.checkCancellation()
            let offByID = Dictionary(uniqueKeysWithValues: model.offProducts.compactMap { product in product.food.map { ($0.id, product) } })
            results = result.hits.map { hit in
                let origin: FoodOriginFilter?
                switch hit.id {
                case .personal: origin = .personal
                case let .catalogue(namespace, _):
                    origin = namespace == "off" ? .openFoodFacts : namespace == "livsmedelsverket" ? .livsmedelsverket : nil
                }
                return Result(food: hit.food, product: offByID[hit.id], nameEntry: hit.nameEntry, origin: origin)
            }
            correctedQuery = result.correctedQuery
        } catch is CancellationError {
            return
        } catch { model.error = appError(error) }
    }

    private var hasActiveSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !market.isEmpty || foodOrigin != .all || favoritesOnly
    }

    private func resultName(_ result: Result) -> String {
        if let food = result.food { return model.name(food, language: language.rawValue) }
        return result.nameEntry?.displayName(language: language.rawValue) ?? ""
    }
}

private struct FoodFilterTags: View {
    @Binding var market: String
    @Binding var origin: FoodOriginFilter
    @Binding var favoritesOnly: Bool
    let copy: AppCopy
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @AppStorage("foodSearch.tagsExpanded") private var expanded = true

    private let markets = ["SE", "DE"]
    private let sources: [FoodOriginFilter] = [.openFoodFacts, .personal, .livsmedelsverket]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private func color(for source: FoodOriginFilter) -> Color {
        switch source {
        case .all: .secondary
        case .openFoodFacts: .teal
        case .personal: .pink
        case .livsmedelsverket: .green
        }
    }

    var body: some View {
        DisclosureGroup(copy.text("tags"), isExpanded: $expanded) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                FoodFilterChip(title: copy.text("favoritesFilter"), color: .orange, selected: favoritesOnly) {
                    favoritesOnly.toggle()
                }
                ForEach(markets, id: \.self) { code in
                    FoodFilterChip(title: copy.text(code == "SE" ? "marketSweden" : "marketGermany"), color: code == "SE" ? .blue : .purple, selected: market == code) {
                        market = market == code ? "" : code
                    }
                }
                ForEach(sources) { source in
                    FoodFilterChip(title: copy.text(source.localizationKey), color: color(for: source), selected: origin == source) {
                        origin = origin == source ? .all : source
                    }
                }
                if !market.isEmpty || origin != .all || favoritesOnly {
                    FoodFilterChip(title: copy.text("clearFilters"), color: .secondary, selected: false) {
                        market = ""
                        origin = .all
                        favoritesOnly = false
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FoodFilterChip: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void
    // Caption 2 is 11 pt at the default size; retain Dynamic Type scaling at 130%.
    @ScaledMetric(relativeTo: .caption2) private var fontSize = 14.3

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if selected {
                    Image(systemName: "checkmark")
                }
                Text(title)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(selected ? 0.28 : 0.12), in: Capsule())
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct OFFNameEntryDetail: View {
    let entry: OFFNameEntry
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let searchQuery: String
    @State private var product: OFFProduct?
    @State private var error: String?
    @State private var retryID = 0

    var body: some View {
        Group {
            if let product, let food = product.food {
                FoodDetail(food: food, product: product, model: model, copy: copy)
            } else if error != nil {
                Button(copy.text("retry")) { error = nil; retryID += 1 }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(copy.text("syncingOpenFoodFacts")).foregroundStyle(.secondary)
                }
                .navigationTitle(entry.displayName(language: copy.language.rawValue))
            }
        }
        .task(id: retryID) {
            do {
                // lookup is cache-first and only contacts OFF when this barcode has
                // not already been hydrated on the device.
                product = try await model.off.lookup(barcode: entry.barcode, language: copy.language.rawValue)
                if let food = product?.food {
                    model.recordFoodSelection(food, query: searchQuery, language: copy.language)
                }
                await model.loadOFF()
            } catch {
                self.error = appError(error)
            }
        }
        .temporaryErrorBanner(error)
    }
}

private struct FoodLibraryFoodLabel: View {
    let food: CatalogueFood
    let product: OFFProduct?
    @ObservedObject var model: MealModel
    let copy: AppCopy

    private var productDetails: String? {
        guard product != nil else { return nil }
        var values: [String] = []
        if let brand = product?.brands?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            values.append(brand)
        }
        if let energy = food.profile.nutrients[Nutrient.energy.rawValue]?.value?.value {
            let basisUnit = food.profile.basis.unit == .ml ? "ml" : "g"
            values.append("\(copy.kilocalories(energy)) kcal / 100 \(basisUnit)")
        }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            FoodPersonalizedName(food: food, model: model, copy: copy)
            if let productDetails {
                Text(productDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if product?.hasApproximateNutrition == true {
                ApproximateNutritionBadge(copy: copy)
            }
            Text(food.salesCountries.map { $0 == "SE" ? "🇸🇪 SE" : $0 == "DE" ? "🇩🇪 DE" : $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FoodLibraryOFFRow: View {
    let item: OFFProduct
    @ObservedObject var model: MealModel
    let copy: AppCopy

    var body: some View {
        Group {
            if let food = item.food {
                NavigationLink {
                    FoodDetail(food: food, product: item, model: model, copy: copy)
                } label: {
                    VStack(alignment: .leading) {
                        FoodLibraryFoodLabel(food: food, product: item, model: model, copy: copy)
                        FoodOriginBadge(origin: .openFoodFacts, copy: copy)
                    }
                }
            } else {
                VStack(alignment: .leading) {
                    Text(item.barcode)
                    Text(copy.text("unsupported")).font(.caption)
                    Text(item.attribution).font(.caption)
                }
            }
        }
    }
}

private struct OFFSyncSection: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    @State private var reportItemLimit = 20

    var body: some View {
        Section {
            if model.offSyncBusy { Text(copy.text("syncingOpenFoodFacts")).font(.caption) }
            Button {
                Task { await model.sync() }
            } label: {
                HStack {
                    Text(copy.text("sync"))
                    if model.offSyncBusy { ProgressView() }
                }
            }
            .disabled(model.offSyncBusy)
            .accessibilityIdentifier("off.sync")
            if let report = model.syncReport {
                Text("\(copy.text("changed")): \(report.items.filter(\.changed).count)")
                Text("\(copy.text("failures")): \(report.failedCount)")
                    .foregroundStyle(report.failedCount > 0 ? .red : .secondary)
                let failedItems = report.items.filter { $0.error != nil }
                ForEach(failedItems.prefix(reportItemLimit), id: \.barcode) { item in
                    Text(item.barcode + ": " + copy.text("offError"))
                        .font(.caption)
                }
                if failedItems.count > reportItemLimit {
                    Button(copy.text("showMore")) { reportItemLimit += 20 }
                }
            }
        }
    }
}

private struct LivsmedelsverketSyncSection: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy

    var body: some View {
        Section(copy.text("livsmedelsverket")) {
            Button(copy.text("syncLivsmedelsverket")) {
                Task { await model.syncLivsmedelsverket() }
            }
            .disabled(model.livsmedelsverketSyncBusy)
            .accessibilityIdentifier("livsmedelsverket.sync")
            if model.livsmedelsverketSyncBusy { ProgressView() }
            if let report = model.livsmedelsverketSyncReport {
                Text("\(copy.text("available")): \(report.available)")
                Text("\(copy.text("changed")): \(report.changed)")
                Text("\(copy.text("failures")): \(report.failed)")
                    .foregroundStyle(report.failed == 0 ? Color.secondary : Color.red)
            }
        }
    }
}

private struct FoodLibraryCounts: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    @State private var isLivsmedelsverketExpanded = false
    @State private var isOpenFoodFactsExpanded = false

    private var offSweden: Int { model.offProducts.filter { $0.food?.salesCountries.contains("SE") == true }.count }
    private var offGermany: Int { model.offProducts.filter { $0.food?.salesCountries.contains("DE") == true }.count }

    var body: some View {
        Section(copy.text("foodCounts")) {
            DisclosureGroup(isExpanded: $isLivsmedelsverketExpanded) {
                LabeledContent("🇸🇪 SE", value: String(model.livsmedelsverketFoods.count))
            } label: {
                LabeledContent(copy.text("livsmedelsverket"), value: String(model.livsmedelsverketFoods.count))
            }
            DisclosureGroup(isExpanded: $isOpenFoodFactsExpanded) {
                LabeledContent("🇸🇪 SE", value: String(offSweden))
                LabeledContent("🇩🇪 DE", value: String(offGermany))
            } label: {
                LabeledContent(
                    copy.text("openFoodFacts"),
                    value: "\(model.offProducts.count) \(copy.text("synced"))"
                )
            }
            LabeledContent(copy.text("yourFoods"), value: String(model.personalFoods.count))
        }
    }
}

private struct TodayMealSection: View {
    let event: MealEvent
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let edit: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var isExpanded = false

    private var totalKilocalories: Decimal {
        event.totals[Nutrient.energy.rawValue]?.knownSubtotal.value ?? .zero
    }

    var body: some View {
        Section {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                TodayMealHeader(
                    title: copy.text(event.category.rawValue),
                    kilocalories: copy.kilocalories(totalKilocalories),
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(event.components) { component in
                    TodayMealComponentRow(component: component, copy: copy)
                }
                Button(action: edit) {
                    MealActionLabel(title: copy.text("edit"))
                }
                .buttonStyle(.borderless)
                Button(action: duplicate) {
                    MealActionLabel(title: copy.text("duplicate"))
                }
                .buttonStyle(.borderless)
                if let shareDocument = MealShareDocument(
                    MealSharePayload.meal(event),
                    filename: "\(copy.text(event.category.rawValue)) \(event.eatenAt.formatted(.dateTime.year().month().day().locale(copy.language.locale)))"
                ) {
                    ShareLink(
                        item: shareDocument,
                        subject: Text(copy.text("shareMeal")),
                        preview: SharePreview(copy.text("shareMeal"))
                    ) {
                        MealActionLabel(
                            title: copy.text("shareMeal"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .buttonStyle(.borderless)
                }
                Button(role: .destructive, action: delete) {
                    MealActionLabel(title: copy.text("delete"))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

private struct TodayMealHeader: View {
    let title: String
    let kilocalories: String
    let isExpanded: Bool

    var body: some View {
        HStack {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(kilocalories) kcal")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct MealActionLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct TodayMealComponentRow: View {
    let component: MealComponent
    let copy: AppCopy

    private var kilocalories: Decimal? {
        guard let consumed = try? component.quantity.consumed(),
              let totals = try? NutritionCalculator.calculate(profile: component.food.profile, quantity: consumed) else {
            return nil
        }
        return totals[.energy].knownSubtotal
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(component.displayName)
            HStack(spacing: 4) {
                Text("\(copy.number(component.quantity.amount.value)) \(component.quantity.unit == .millilitres ? "ml" : "g")")
                if let kilocalories {
                    Text("· \(copy.kilocalories(kilocalories)) kcal")
                }
            }
                .foregroundStyle(.secondary)
        }
    }
}

struct DailyNutritionCharts: View {
    let events: [MealEvent]
    let dailyEnergyGoal: Double
    let goalRangeMinimumPercent: Int
    let goalRangeMaximumPercent: Int
    let proteinEnergyPercent: Int
    let carbohydrateEnergyPercent: Int
    let fatEnergyPercent: Int
    let activeEnergyKcal: Double?
    let copy: AppCopy
    @Binding var selectedMacroValue: Double?
    @Binding var selectedMacroComparisonNutrient: Nutrient?
    @Binding var selectedEnergyComponent: String?

    private struct Macro: Identifiable {
        let nutrient: Nutrient
        let amount: Double

        var id: String { nutrient.rawValue }
    }

    private struct MacroComparison: Identifiable {
        let nutrient: Nutrient
        let amount: Double
        let seriesKey: String

        var id: String { nutrient.rawValue + seriesKey }
    }

    private struct MealEnergySegment: Identifiable {
        let id: UUID
        let name: String
        let amount: Double
    }

    private var macros: [Macro] {
        MacronutrientColors.order.compactMap { nutrient in
            let amount = total(for: nutrient)
            return amount > 0 ? Macro(nutrient: nutrient, amount: amount) : nil
        }
    }

    private var energy: Double { total(for: .energy) }
    private var baseGoal: Double { max(dailyEnergyGoal, 0) }
    private var movementEnergy: Double { max(activeEnergyKcal ?? 0, 0) }
    private var adjustedGoal: Double { baseGoal + movementEnergy }
    private var remainingEnergyLabel: String {
        "\(copy.text("untilGoal")) \(copy.kilocalories(decimal(adjustedGoal - energy))) kcal"
    }
    private var remainingEnergyColor: Color {
        let minimum = adjustedGoal * Double(goalRangeMinimumPercent) / 100
        let maximum = adjustedGoal * Double(goalRangeMaximumPercent) / 100
        if energy > maximum { return .red }
        if energy >= minimum { return .green }
        return .orange
    }
    private var mealEnergySegments: [MealEnergySegment] {
        events
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            .compactMap { event in
                let amount = event.totals[Nutrient.energy.rawValue]?.knownSubtotal.value ?? .zero
                let kilocalories = NSDecimalNumber(decimal: amount).doubleValue
                guard kilocalories > 0 else { return nil }
                return MealEnergySegment(
                    id: event.id,
                    name: copy.text(event.category.rawValue),
                    amount: kilocalories
                )
            }
    }
    private var selectedEnergyMeal: MealEnergySegment? {
        guard let selectedEnergyComponent,
              let id = UUID(uuidString: selectedEnergyComponent) else { return nil }
        return mealEnergySegments.first { $0.id == id }
    }
    private var energyProgress: Double {
        guard adjustedGoal > 0 else { return 0 }
        return min(max(energy / adjustedGoal, 0), 1)
    }
    private var macroTotal: Double { macros.reduce(0) { $0 + $1.amount } }
    private var macroComparisons: [MacroComparison] {
        MacronutrientColors.order.flatMap { (nutrient: Nutrient) -> [MacroComparison] in
            let percent: Int
            let kilocaloriesPerGram: Double
            switch nutrient {
            case .protein:
                percent = proteinEnergyPercent
                kilocaloriesPerGram = 4
            case .carbohydrateAvailable:
                percent = carbohydrateEnergyPercent
                kilocaloriesPerGram = 4
            case .totalFat:
                percent = fatEnergyPercent
                kilocaloriesPerGram = 9
            default:
                return []
            }
            return [
                MacroComparison(nutrient: nutrient, amount: total(for: nutrient), seriesKey: "consumed"),
                MacroComparison(
                    nutrient: nutrient,
                    amount: adjustedGoal * Double(percent) / 100 / kilocaloriesPerGram,
                    seriesKey: "goal"
                )
            ]
        }
    }

    private var selectedMacro: Macro? {
        guard let selectedMacroValue else { return nil }
        var upperBound = 0.0
        for macro in macros {
            upperBound += macro.amount
            if selectedMacroValue <= upperBound { return macro }
        }
        return macros.last
    }

    var body: some View {
        Section {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.gray.opacity(0.18))
                    ZStack(alignment: .leading) {
                        LinearGradient(
                            colors: [.gray.opacity(0.65), .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width)
                        .frame(width: geometry.size.width * energyProgress, alignment: .leading)
                        .clipped()

                        ForEach(Array(mealEnergySegments.enumerated()), id: \.element.id) { index, segment in
                            let bounds = energySegmentBounds(at: index)
                            if let selectedEnergyMeal, selectedEnergyMeal.id != segment.id {
                                Rectangle()
                                    .fill(.background.opacity(0.65))
                                    .frame(width: geometry.size.width * (bounds.upper - bounds.lower))
                                    .offset(x: geometry.size.width * bounds.lower)
                            }
                            if index < mealEnergySegments.count - 1 {
                                Rectangle()
                                    .fill(.background)
                                    .frame(width: 2)
                                    .offset(x: geometry.size.width * bounds.upper - 1)
                            }
                        }
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                    .clipShape(Capsule())

                    if let selectedEnergyMeal,
                       let selectedIndex = mealEnergySegments.firstIndex(where: { $0.id == selectedEnergyMeal.id }) {
                        let selectedBounds = energySegmentBounds(at: selectedIndex)
                        VStack(spacing: 1) {
                            Text(selectedEnergyMeal.name).fontWeight(.semibold)
                            Text("\(copy.kilocalories(decimal(selectedEnergyMeal.amount))) kcal")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .position(
                            x: geometry.size.width * (selectedBounds.lower + selectedBounds.upper) / 2,
                            y: geometry.size.height / 2
                        )
                        .allowsHitTesting(false)
                    } else {
                        Text("\(copy.kilocalories(decimal(energy))) / \(copy.kilocalories(decimal(adjustedGoal))) kcal")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { tap in
                        selectEnergyMeal(at: tap.location.x, width: geometry.size.width)
                    }
                )
            }
            .frame(height: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.text("energyProgress"))
            .accessibilityValue("\(copy.kilocalories(decimal(energy))) / \(copy.kilocalories(decimal(adjustedGoal))) kcal")
            .listRowBackground(Color.secondary.opacity(0.10))
        } header: {
            Text(remainingEnergyLabel)
                .foregroundStyle(remainingEnergyColor)
                .textCase(nil)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }

        Section(copy.text("macroComposition")) {
            if macros.isEmpty {
                Text(copy.text("noMacroData"))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Chart(macros) { macro in
                        SectorMark(
                            angle: .value(copy.text("amount"), macro.amount),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(by: .value(copy.text("nutrition"), copy.text(macro.nutrient.rawValue)))
                        .opacity(selectedMacro == nil || selectedMacro?.id == macro.id ? 1 : 0.45)
                    }
                    .onChange(of: selectedMacroValue) { _, selection in
                        if selection != nil { selectedEnergyComponent = nil }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture().onEnded { tap in
                                        guard let plotFrame = proxy.plotFrame else {
                                            clearSelections()
                                            return
                                        }
                                        let frame = geometry[plotFrame]
                                        guard frame.contains(tap.location) else {
                                            clearSelections()
                                            return
                                        }
                                        let plotLocation = CGPoint(
                                            x: tap.location.x - frame.minX,
                                            y: tap.location.y - frame.minY
                                        )
                                        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
                                        let distance = hypot(plotLocation.x - center.x, plotLocation.y - center.y)
                                        let outerRadius = min(frame.width, frame.height) / 2
                                        guard distance >= outerRadius * 0.55,
                                              distance <= outerRadius,
                                              let selectedValue = proxy.value(
                                                atAngle: proxy.angle(at: plotLocation),
                                                as: Double.self
                                              ) else {
                                            clearSelections()
                                            return
                                        }
                                        clearSelections()
                                        selectedMacroValue = selectedValue
                                    }
                                )

                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                if let selectedMacro {
                                    VStack(spacing: 2) {
                                        Text(copy.text(selectedMacro.nutrient.rawValue))
                                            .fontWeight(.semibold)
                                        Text("\(copy.macronutrient(decimal(selectedMacro.amount))) g · \(copy.number(decimal(selectedMacro.amount / macroTotal * 100)))%")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .position(x: frame.midX, y: frame.midY)
                                    .accessibilityElement(children: .combine)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .center)
                    .chartForegroundStyleScale(
                        domain: MacronutrientColors.order.map { copy.text($0.rawValue) },
                        range: MacronutrientColors.order.map(MacronutrientColors.color(for:))
                    )
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(copy.text("macroComposition"))

                    Chart(macroComparisons) { value in
                        BarMark(
                            x: .value(copy.text("nutrition"), macroSymbol(for: value.nutrient)),
                            y: .value(copy.text("amount"), value.amount)
                        )
                        .foregroundStyle(MacronutrientColors.color(for: value.nutrient))
                        .opacity(value.seriesKey == "goal" ? 0.35 : 1)
                        .position(by: .value(copy.text("nutrition"), copy.text(value.seriesKey)))
                        .cornerRadius(2)
                    }
                    .chartXScale(domain: MacronutrientColors.order.map(macroSymbol(for:)))
                    .chartYAxisLabel("g")
                    .chartLegend(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture().onEnded { tap in
                                        guard let plotFrame = proxy.plotFrame else {
                                            clearSelections()
                                            return
                                        }
                                        let frame = geometry[plotFrame]
                                        guard frame.contains(tap.location) else {
                                            clearSelections()
                                            return
                                        }
                                        let plotLocation = CGPoint(
                                            x: tap.location.x - frame.minX,
                                            y: tap.location.y - frame.minY
                                        )
                                        guard let symbol = proxy.value(atX: plotLocation.x, as: String.self),
                                              let nutrient = MacronutrientColors.order.first(where: {
                                                macroSymbol(for: $0) == symbol
                                              }),
                                              let values = comparisonValues(for: nutrient),
                                              let categoryCenter = proxy.position(forX: symbol),
                                              let zeroY = proxy.position(forY: 0),
                                              let spacing = macroCategorySpacing(proxy: proxy) else {
                                            clearSelections()
                                            return
                                        }
                                        let groupHalfWidth = spacing * 0.4
                                        guard abs(plotLocation.x - categoryCenter) <= groupHalfWidth else {
                                            clearSelections()
                                            return
                                        }
                                        let selectedAmount = plotLocation.x < categoryCenter ? values.eaten : values.goal
                                        guard selectedAmount > 0,
                                              let valueY = proxy.position(forY: selectedAmount),
                                              plotLocation.y >= min(zeroY, valueY),
                                              plotLocation.y <= max(zeroY, valueY) else {
                                            clearSelections()
                                            return
                                        }
                                        clearSelections()
                                        selectedMacroComparisonNutrient = nutrient
                                    }
                                )

                            if let plotFrame = proxy.plotFrame {
                                let frame = geometry[plotFrame]
                                if let nutrient = selectedMacroComparisonNutrient,
                                   let values = comparisonValues(for: nutrient) {
                                    VStack(spacing: 2) {
                                        Text(copy.text(nutrient.rawValue))
                                            .fontWeight(.semibold)
                                        Text("\(copy.text("consumed")): \(copy.macronutrient(decimal(values.eaten))) g")
                                        Text("\(copy.text("goal")): \(copy.macronutrient(decimal(values.goal))) g")
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                    .position(x: frame.midX, y: frame.midY)
                                    .accessibilityElement(children: .combine)
                                    .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(copy.text("macroGoals"))
                }
                .frame(height: 154)
            }
        }
    }

    private func clearSelections() {
        selectedEnergyComponent = nil
        selectedMacroValue = nil
        selectedMacroComparisonNutrient = nil
    }

    private func energySegmentBounds(at index: Int) -> (lower: Double, upper: Double) {
        let denominator = adjustedGoal > 0 ? adjustedGoal : max(energy, 1)
        let rawLowerBound = mealEnergySegments.prefix(index).reduce(0) { $0 + $1.amount } / denominator
        let rawUpperBound = rawLowerBound + mealEnergySegments[index].amount / denominator
        let lowerBound = min(max(rawLowerBound, 0), 1)
        let upperBound = min(max(rawUpperBound, lowerBound), 1)
        return (lowerBound, upperBound)
    }

    private func selectEnergyMeal(at x: CGFloat, width: CGFloat) {
        guard width > 0 else {
            clearSelections()
            return
        }
        let denominator = adjustedGoal > 0 ? adjustedGoal : max(energy, 1)
        let tappedEnergy = max(0, min(Double(x / width), 1)) * denominator
        var upperBound = 0.0
        guard let segment = mealEnergySegments.first(where: { segment in
            upperBound += segment.amount
            return tappedEnergy <= upperBound
        }), Double(x / width) <= energyProgress else {
            clearSelections()
            return
        }
        if selectedEnergyComponent == segment.id.uuidString {
            clearSelections()
            return
        }
        clearSelections()
        selectedEnergyComponent = segment.id.uuidString
    }

    private func macroCategorySpacing(proxy: ChartProxy) -> CGFloat? {
        let positions = MacronutrientColors.order.compactMap { proxy.position(forX: macroSymbol(for: $0)) }
        guard positions.count > 1 else { return nil }
        return zip(positions.dropFirst(), positions).map { abs($0 - $1) }.min()
    }

    private func total(for nutrient: Nutrient) -> Double {
        let decimal = events
            .compactMap { $0.totals[nutrient.rawValue]?.knownSubtotal.value }
            .reduce(Decimal.zero, +)
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    private func decimal(_ value: Double) -> Decimal {
        Decimal(value)
    }

    private func macroSymbol(for nutrient: Nutrient) -> String {
        String(copy.text(nutrient.rawValue).prefix(1))
    }

    private func comparisonValues(for nutrient: Nutrient) -> (eaten: Double, goal: Double)? {
        let values = macroComparisons.filter { $0.nutrient == nutrient }
        guard let eaten = values.first(where: { $0.seriesKey == "consumed" })?.amount,
              let goal = values.first(where: { $0.seriesKey == "goal" })?.amount else {
            return nil
        }
        return (eaten, goal)
    }

}

private struct ComposerWorkingState: Codable {
    var selectedFood: CatalogueFood?
    var offBarcode: String?
    var quantity: String
    var unit: QuantityUnit
    var categoryManual: Bool
    var componentInputs: [UUID: String]
    var selectedProvenance: [String: Provenance]?
    var inputLanguage: AppLanguage?
}

private struct BarcodeFoodSearchResult {
    let foods: [CatalogueFood]
    let product: OFFProduct?
}

private struct BarcodeFoodSearchSection: View {
    private enum SearchStatus {
        case cached
        case openFoodFacts
        case notFound

        var isSearching: Bool {
            self != .notFound
        }

        var localizationKey: String {
            switch self {
            case .cached: "searchingCachedBarcodes"
            case .openFoodFacts: "searchingOpenFoodFactsBarcodes"
            case .notFound: "barcodeNotFound"
            }
        }
    }

    @ObservedObject var model: MealModel
    let copy: AppCopy
    let completion: (BarcodeFoodSearchResult) -> Void

    @AppStorage("foodSearch.barcodeExpanded") private var expanded = true
    @State private var barcode = ""
    @State private var scanning = false
    @State private var searchStatus: SearchStatus?
    @State private var error: String?

    var body: some View {
        Section {
            DisclosureGroup(copy.text("barcode"), isExpanded: $expanded) {
                HStack {
                    TextField(copy.text("barcode"), text: $barcode)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("barcode.input")
                    Button {
                        scanning = true
                    } label: {
                        Image(systemName: "camera")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(copy.text("scan"))
                    .accessibilityIdentifier("barcode.scan")
                }
                .fullScreenCover(isPresented: $scanning) {
                    NavigationStack {
                        BarcodeScanner(copy: copy) { code in
                            barcode = code
                            scanning = false
                            Task { await lookup() }
                        }
                        .toolbar {
                            Button(copy.text("cancel")) { scanning = false }
                        }
                    }
                }
                Button(copy.text("lookup")) {
                    Task { await lookup() }
                }
                .disabled(searchStatus?.isSearching == true)
                if let searchStatus {
                    HStack(spacing: 8) {
                        if searchStatus.isSearching {
                            ProgressView()
                        }
                        Text(copy.text(searchStatus.localizationKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

            }
        }
        .temporaryErrorBanner(error)
    }

    private func lookup() async {
        error = nil
        guard let code = BarcodeInput.normalized(barcode) else {
            error = copy.text("barcodeError")
            return
        }
        searchStatus = .cached
        defer {
            if searchStatus?.isSearching == true {
                searchStatus = nil
            }
        }
        error = nil

        do {
            var foods = try model.catalogue.barcodeMatches(code)
            var product = try await model.off.cached(barcode: code)
            if let cachedFood = product?.food,
               !foods.contains(where: { $0.id == cachedFood.id }) {
                foods.append(cachedFood)
            }

            if foods.isEmpty {
                searchStatus = .openFoodFacts
                product = try await model.off.lookup(barcode: code, language: copy.language.rawValue)
                if let fetchedFood = product?.food {
                    foods = [fetchedFood]
                }
                await model.loadOFF()
            }

            guard !foods.isEmpty else {
                searchStatus = nil
                error = copy.text("barcodeNotFound")
                return
            }
            completion(BarcodeFoodSearchResult(foods: foods, product: product))
        } catch let lookupError as OFFError where lookupError == .notFound {
            searchStatus = nil
            error = copy.text("barcodeNotFound")
        } catch {
            self.error = appError(error, copy: copy)
        }
    }
}

struct MealComposer: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let selectedDate: Date
    var editing: MealEvent? = nil
    var duplicate: MealEvent? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var eatenAt = Date()
    @State private var zoneID = TimeZone.current.identifier
    @State private var category = MealCategory.snack
    @State private var categoryManual = false
    @State private var query = ""
    @State private var market = ""
    @State private var foodOrigin = FoodOriginFilter.all
    @State private var favoritesOnly = false
    @State private var searchResults: [FoodSearchHit] = []
    @State private var correctedQuery: String?
    private var matches: [CatalogueFood] {
        get { searchResults.compactMap(\.food) }
        nonmutating set { searchResults = newValue.map(FoodSearchHit.init(food:)) }
    }
    private var offNameMatches: [OFFNameEntry] {
        get { searchResults.compactMap(\.nameEntry) }
        nonmutating set {
            let kept = Set(newValue.map(\.barcode))
            searchResults.removeAll { $0.nameEntry.map { !kept.contains($0.barcode) } ?? false }
            let existing = Set(searchResults.compactMap { $0.nameEntry?.barcode })
            searchResults += newValue.filter { !existing.contains($0.barcode) }.map(FoodSearchHit.init(nameEntry:))
        }
    }
    @State private var isSearching = false
    @State private var searchID = UUID()
    @State private var resultLimit = 20
    @State private var selected: CatalogueFood?
    @State private var product: OFFProduct?
    @State private var grams = "100"
    @State private var quantityUnit = QuantityUnit.grams
    @State private var presentingFoodAmount = false
    @State private var components: [MealComponent] = []
    @State private var componentInputs: [UUID: String] = [:]
    @State private var invalidComponents: Set<UUID> = []
    @State private var showingBarcodeResults = false
    @State private var savingReusableMeal = false
    @State private var busy = false
    @State private var error: String?
    @State private var showingUnsupportedProduct = false
    @State private var unsupportedProductBarcode: String?
    @State private var didInitialize = false
    @State private var draftID = UUID()
    @State private var confirmFuture = false
    @State private var operationID = UUID()
    @State private var expectedRevision: Int64?
    @State private var editingBaseline: MealEvent?
    @State private var pendingOFFBarcode: String?
    @State private var selectedProvenance: [String: Provenance]?
    @State private var gingerbreadComponentID: UUID?

    init(model: MealModel, copy: AppCopy, selectedDate: Date, editing: MealEvent? = nil, duplicate: MealEvent? = nil) {
        self.model = model
        self.copy = copy
        self.selectedDate = selectedDate
        self.editing = editing
        self.duplicate = duplicate
        _eatenAt = State(initialValue: editing?.eatenAt ?? selectedDate)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                    Form {
                        DatePicker(copy.text("date"), selection: $eatenAt, displayedComponents: .date)
                            .environment(\.timeZone, TimeZone(identifier: zoneID) ?? .current)
                            .onChange(of: eatenAt) { _, value in if !categoryManual { category = suggestion(value) }; persist() }
                        Picker(copy.text("category"), selection: Binding(get: { category }, set: { category = $0; categoryManual = true; persist() })) { ForEach(MealCategory.allCases, id: \.rawValue) { Text(copy.text($0.rawValue)).tag($0) } }
                            .onChange(of: category) { _, _ in persist() }
                        if !components.isEmpty {
                            Section(copy.text("mealFoods")) {
                                ForEach(components) { component in
                                    MealComponentRow(
                                        component: component,
                                        amount: componentQuantity(component),
                                        copy: copy,
                                        celebrateLebkuchen: gingerbreadComponentID == component.id,
                                        remove: {
                                            invalidComponents.remove(component.id)
                                            componentInputs.removeValue(forKey: component.id)
                                            components.removeAll { $0.id == component.id }
                                            persist()
                                        }
                                    )
                                }
                                LabeledContent(copy.text("mealTotalEnergy")) {
                                    Text("\(copy.kilocalories(accumulatedKilocalories)) kcal")
                                        .fontWeight(.semibold)
                                }
                                Button(copy.text("saveAsMeal")) { savingReusableMeal = true }
                            }
                        }
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            BarcodeFoodSearchSection(model: model, copy: copy) { result in
                                showingBarcodeResults = true
                                searchID = UUID()
                                isSearching = false
                                offNameMatches = []
                                resultLimit = 20
                                selected = nil
                                product = result.product
                                selectedProvenance = result.product?.provenance
                                pendingOFFBarcode = result.product?.barcode
                                matches = result.foods
                            }
                        }
                        Section {
                            if let correctedQuery {
                                Text(copy.text("searchCorrection") + " “" + correctedQuery + "”")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            FoodFilterTags(market: $market, origin: $foodOrigin, favoritesOnly: $favoritesOnly, copy: copy)
                            if isSearching {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(copy.text("search"))
                            }
                            ForEach(searchResults.prefix(resultLimit)) { result in
                                Group {
                                    if let food = result.food {
                                        Button { select(food) } label: {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading) {
                                                    FoodPersonalizedName(food: food, model: model, copy: copy)
                                                    Text(sourceLabel(food)).font(.caption)
                                                    Text(food.salesCountries.map { $0 == "SE" ? "🇸🇪 SE" : $0 == "DE" ? "🇩🇪 DE" : $0 }.joined(separator: " · ")).font(.caption)
                                                    if model.offProducts.first(where: { $0.food?.id == food.id })?.hasApproximateNutrition == true {
                                                        ApproximateNutritionBadge(copy: copy)
                                                    }
                                                }
                                                Spacer()
                                                if selected?.id == food.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.teal)
                                                        .accessibilityLabel(copy.text("selected"))
                                                }
                                            }
                                        }
                                        .accessibilityAddTraits(selected?.id == food.id ? .isSelected : [])
                                    } else if let entry = result.nameEntry {
                                        Button { Task { await selectOFF(entry) } } label: {
                                            VStack(alignment: .leading) {
                                                OFFNameEntryLabel(entry: entry, copy: copy)
                                                HStack {
                                                    FoodOriginBadge(origin: .openFoodFacts, copy: copy)
                                                    UnsyncedBadge(copy: copy)
                                                }
                                            }
                                        }
                                    }
                                }
                                .id(result.id)
                            }
                            if matches.count + offNameMatches.count > resultLimit {
                                Button(copy.text("showMore")) {
                                    resultLimit += 20
                                }
                            }
                            if !busy,
                               !isSearching,
                               matches.isEmpty,
                               offNameMatches.isEmpty,
                               (showingBarcodeResults || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !market.isEmpty || foodOrigin != .all || favoritesOnly) {
                                Text(copy.text("noSearchResults"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if selected == nil, let product {
                            Section {
                                Text(copy.text("unsupported"))
                                Text(product.attribution).font(.caption)
                            }
                        }

                        Color.clear
                            .frame(height: searchResults.isEmpty ? 64 : max(64, geometry.size.height - 100))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityHidden(true)
                    }
                    .navigationTitle(copy.text("add"))
                    .searchable(text: $query, prompt: copy.text("search"))
                    .searchPresentationToolbarBehavior(.avoidHidingContent)
                    .onChange(of: selected) { _, _ in updateQuantityUnitForSelectedFood(); persist() }
                    .onChange(of: product?.barcode) { _, _ in persist() }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(copy.text("cancel")) {
                                dismissSearch()
                                cancel()
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(copy.text("save")) {
                                dismissSearch()
                                save()
                            }
                            .disabled(components.isEmpty || !invalidComponents.isEmpty)
                            .accessibilityIdentifier("meal.save")
                        }
                    }
                    .onAppear { recover() }
                    .task(id: "\(foodOrigin.rawValue)|\(market)|\(favoritesOnly)|\(model.favoriteRevision)|\(query)|\(resultLimit)") {
                        await search()
                    }
                    .onChange(of: showingUnsupportedProduct) { _, showing in
                        guard showing else { return }
                        error = copy.text("unsupported")
                        purgeUnsupportedProduct()
                        showingUnsupportedProduct = false
                    }
                    .sheet(isPresented: $savingReusableMeal) {
                        SavedMealMetadataSheet(model: model, copy: copy, ingredients: components)
                    }
                    .sheet(isPresented: $presentingFoodAmount) {
                        if let selected {
                            MealFoodAmountSheet(
                                food: selected,
                                foodName: model.name(selected, language: copy.language.rawValue),
                                amount: $grams,
                                unit: $quantityUnit,
                                availableUnits: availableQuantityUnits(for: selected),
                                copy: copy,
                                error: $error,
                                add: {
                                    if await add(selected) {
                                        presentingFoodAmount = false
                                    }
                                }
                            )
                        }
                    }
                    .confirmationDialog(copy.text("futureConfirm"), isPresented: $confirmFuture, titleVisibility: .visible) { Button(copy.text("save")) { save(allowFuture: true) }; Button(copy.text("cancel"), role: .cancel) {} }
                    .onChange(of: searchResults.map(\.id)) { _, _ in
                        guard !searchResults.isEmpty else { return }
                        Task { @MainActor in
                            await Task.yield()
                            if let first = searchResults.first {
                                scroll.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: presentingFoodAmount) { _, presented in
                        guard !presented, !searchResults.isEmpty else { return }
                        Task { @MainActor in
                            await Task.yield()
                            if let first = searchResults.first {
                                scroll.scrollTo(first.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .temporaryErrorBanner(error)
    }
    func sourceLabel(_ food: CatalogueFood) -> String {
        switch food.id {
        case .personal: copy.text("userEntered")
        case let .catalogue(namespace, _): copy.text(namespace == "off" ? "community" : namespace == "livsmedelsverket" ? "livsmedelsverket" : "source")
        }
    }
    private var accumulatedKilocalories: Decimal {
        components.reduce(into: Decimal.zero) { total, component in
            guard let consumed = try? component.quantity.consumed(),
                  let nutrients = try? NutritionCalculator.calculate(
                    profile: component.food.profile,
                    quantity: consumed
                  ) else { return }
            total += nutrients[.energy].knownSubtotal
        }
    }
    func suggestion(_ date: Date) -> MealCategory { (try? DiaryTime.category(date, zoneID: zoneID)) ?? .snack }
    func search() async {
        showingBarcodeResults = false
        let currentSearchID = UUID()
        searchID = currentSearchID
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedMarket = market
        let selectedFavoritesOnly = favoritesOnly
        let selectedOrigin = foodOrigin
        guard !searchQuery.isEmpty || !selectedMarket.isEmpty || selectedOrigin != .all || selectedFavoritesOnly else {
            matches = []
            offNameMatches = []
            correctedQuery = nil
            isSearching = false
            return
        }

        isSearching = true
        defer {
            if searchID == currentSearchID {
                isSearching = false
            }
        }
        error = nil

        do {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            let result = try await model.searchFoods(
                query: searchQuery,
                language: copy.language,
                market: selectedMarket,
                origin: selectedOrigin,
                favoritesOnly: selectedFavoritesOnly,
                limit: resultLimit + 1
            )
            guard searchID == currentSearchID, !showingBarcodeResults else { return }
            searchResults = result.hits
            correctedQuery = result.correctedQuery
        } catch is CancellationError {
            return
        } catch {
            guard searchID == currentSearchID else { return }
            self.error = appError(error)
        }
    }
    func selectOFF(_ entry: OFFNameEntry) async {
        busy = true; defer { busy = false }
        do {
            let fetched = try await model.off.lookup(barcode: entry.barcode, language: copy.language.rawValue)
            await model.loadOFF()
            guard let food = fetched.food else {
                unsupportedProductBarcode = fetched.barcode
                showingUnsupportedProduct = true
                return
            }
            product = fetched; selectedProvenance = fetched.provenance; pendingOFFBarcode = fetched.barcode
            select(food)
        } catch { self.error = appError(error) }
    }
    func select(_ food: CatalogueFood) {
        grams = "100"
        quantityUnit = .grams
        model.recordFoodSelection(food, query: query, language: copy.language)
        selected = food
        product = model.offProducts.first(where: { $0.food?.id == food.id })
        pendingOFFBarcode = product?.barcode
        selectedProvenance = product?.provenance
        updateQuantityUnitForSelectedFood()
        presentingFoodAmount = true
        persist()
    }
    private func purgeUnsupportedProduct() {
        guard let barcode = unsupportedProductBarcode else { return }
        unsupportedProductBarcode = nil
        offNameMatches.removeAll { $0.barcode == barcode }
        Task {
            do {
                try await model.off.purgeCachedProduct(barcode: barcode)
                await model.loadOFF()
            } catch {
                self.error = appError(error)
            }
        }
    }
    func availableQuantityUnits(for food: CatalogueFood) -> [QuantityUnit] {
        [QuantityUnit.grams, .millilitres].filter { unit in
            guard let amount = try? DecimalAmount("1") else { return false }
            let quantity = LoggedQuantity(amount: amount, unit: unit)
            return (try? NutritionCalculator.calculate(profile: food.profile, quantity: quantity.consumed())) != nil
        }
    }
    func updateQuantityUnitForSelectedFood() {
        guard let selected else { return }
        let units = availableQuantityUnits(for: selected)
        if !units.contains(quantityUnit) {
            quantityUnit = units.first ?? .grams
        }
    }
    @discardableResult
    func add(_ food: CatalogueFood) async -> Bool {
        guard availableQuantityUnits(for: food).contains(quantityUnit) else { error = copy.text("conversionError"); return false }
        guard let canonical = copy.canonicalQuantity(grams) else { error = copy.text("quantityError"); return false }
        do {
            error = nil
            product = try await model.productForLogging(food, language: copy.language)
            let food = product?.food ?? food
            selectedProvenance = product?.provenance
            let resolution = try model.personal.resolve(base: food)
            let isOFF: Bool = { if case let .catalogue(namespace, _) = food.id { return namespace == "off" }; return false }()
            let isSLV: Bool = { if case let .catalogue(namespace, _) = food.id { return namespace == "livsmedelsverket" }; return false }()
            if isOFF && selectedProvenance == nil && product == nil { error = copy.text("offMetadataMissing"); return false }
            let quantity = LoggedQuantity(amount: try DecimalAmount(canonical), unit: quantityUnit)
            let provenance = isOFF ? (selectedProvenance ?? product?.provenance ?? [:]) : isSLV ? livsmedelsverketProvenance(for: food) : model.catalogue.provenance
            let component = try MealComponent(food: resolution.food, generationID: model.catalogue.generationID, displayName: model.catalogue.displayName(resolution.food, language: copy.language.rawValue), language: copy.language.rawValue, quantity: quantity, fixtureOnly: !isOFF && !isSLV && product == nil && model.catalogue.fixtureOnly && { if case .personal = food.id { return false }; return true }(), provenance: provenance, evidence: isOFF || isSLV ? [:] : model.catalogue.evidence, overlayRevision: resolution.overlayRevision)
            components.append(component)
            if FoodEasterEgg.isLebkuchen(component.displayName) {
                gingerbreadComponentID = component.id
            }
            selected = nil; product = nil; pendingOFFBarcode = nil; selectedProvenance = nil; error = nil; persist()
            return true
        } catch { self.error = appError(error); return false }
    }
    func draft() throws -> MealDraft {
        let state = ComposerWorkingState(selectedFood: selected, offBarcode: product?.barcode ?? pendingOFFBarcode, quantity: grams, unit: quantityUnit, categoryManual: categoryManual, componentInputs: componentInputs, selectedProvenance: selectedProvenance, inputLanguage: copy.language)
        return MealDraft(id: draftID, eatenAt: eatenAt, zoneID: zoneID, category: categoryManual ? category : nil, components: components, workingState: try JSONEncoder().encode(state), expectedEventRevision: expectedRevision)
    }
    func persist() {
        do { try model.diary.saveDraft(draft()) } catch { self.error = appError(error) }
    }
    func recover() {
        guard !didInitialize else { return }
        didInitialize = true
        do {
            if let duplicate {
                eatenAt = selectedDate; category = duplicate.category; categoryManual = true
                components = try duplicate.components.map { old in try MealComponent(food: old.food, generationID: old.generationID, displayName: old.displayName, language: old.language, quantity: old.quantity, fixtureOnly: old.fixtureOnly, provenance: old.provenance, evidence: old.evidence, overlayRevision: old.overlayRevision) }; return
            }
            if let editing { draftID = editing.id; expectedRevision = editing.revision; editingBaseline = editing; zoneID = editing.zoneID; eatenAt = editing.eatenAt; category = editing.category; categoryManual = editing.categoryMode == "manual"; components = editing.components; return }
            eatenAt = selectedDate
            category = suggestion(selectedDate)
        } catch { self.error = appError(error) }
    }
    func cancel() {
        do { try model.diary.deleteDraft(id: draftID) }
        catch { self.error = appError(error); return }
        dismiss()
    }
    func componentQuantity(_ component: MealComponent) -> Binding<String> {
        Binding(get: { componentInputs[component.id] ?? component.quantity.amount.canonicalString.replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",") }, set: { raw in
            componentInputs[component.id] = raw
            guard let canonical = copy.canonicalQuantity(raw), let amount = try? DecimalAmount(canonical) else { invalidComponents.insert(component.id); error = copy.text("quantityError"); persist(); return }
            guard let index = components.firstIndex(where: { $0.id == component.id }) else { return }
            invalidComponents.remove(component.id); components[index].quantity.amount = amount; error = nil; persist()
        })
    }
    func save(allowFuture: Bool = false, retryingRevisionOnly: Bool = false) {
        persist()
        if eatenAt > Date(), !allowFuture { confirmFuture = true; return }
        do {
            let originalDraftID = draftID
            let saveDraft = try draftForSave()
            let event = try model.diary.save(
                saveDraft,
                operationID: operationID,
                expectedRevision: saveDraft.expectedEventRevision,
                confirmFuture: allowFuture
            )
            if saveDraft.id != originalDraftID { try model.diary.deleteDraft(id: originalDraftID) }
            Task { await model.syncMealToHealth(event) }
            dismiss()
        } catch let error as DiaryError where error == .staleRevision && !retryingRevisionOnly {
            retryRevisionOnlySave(allowFuture: allowFuture)
        } catch { self.error = appError(error) }
    }

    /// New additions join the existing meal category for that day. Editing and
    /// explicit duplication continue to address their own meal event.
    private func draftForSave() throws -> MealDraft {
        let composerDraft = try draft()
        guard editing == nil, duplicate == nil,
              let existing = try model.diary.events(localDate: MealModel.day(eatenAt)).last(where: { $0.category == category }) else { return composerDraft }
        return MealDraft(
            id: existing.id,
            eatenAt: existing.eatenAt,
            zoneID: existing.zoneID,
            category: existing.categoryMode == "manual" ? existing.category : nil,
            components: existing.components + components,
            expectedEventRevision: existing.revision
        )
    }

    /// A revision can advance for an internal no-content refresh. Retry only in
    /// that narrow case; any externally changed meal content remains a conflict.
    private func retryRevisionOnlySave(allowFuture: Bool) {
        guard let baseline = editingBaseline,
              let current = try? model.diary.event(id: baseline.id),
              current.deletedAt == nil,
              sameMealContent(current, baseline) else {
            error = copy.text("conflictError")
            return
        }
        expectedRevision = current.revision
        operationID = UUID()
        save(allowFuture: allowFuture, retryingRevisionOnly: true)
    }

    private func sameMealContent(_ lhs: MealEvent, _ rhs: MealEvent) -> Bool {
        lhs.id == rhs.id &&
        lhs.eatenAt == rhs.eatenAt &&
        lhs.zoneID == rhs.zoneID &&
        lhs.category == rhs.category &&
        lhs.categoryMode == rhs.categoryMode &&
        lhs.components == rhs.components &&
        lhs.totals == rhs.totals &&
        lhs.deletedAt == rhs.deletedAt
    }
}

/// Adds a one-off nutrition entry directly to a meal without creating a reusable food.
private struct CustomNutritionAdd: View {
    @ObservedObject var model: MealModel
    let copy: AppCopy
    let selectedDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var category = MealCategory.snack
    @State private var name = ""
    @State private var energy = ""
    @State private var protein = ""
    @State private var carbohydrate = ""
    @State private var fat = ""
    @State private var estimatedMacros: Set<Nutrient> = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(copy.text("category"), selection: $category) {
                        ForEach(MealCategory.allCases, id: \.rawValue) { category in
                            Text(copy.text(category.rawValue)).tag(category)
                        }
                    }
                    TextField(copy.text("name"), text: $name)
                }

                Section(copy.text("nutrition")) {
                    nutrientField(copy.text(Nutrient.energy.rawValue), unit: "kcal", text: $energy)
                    nutrientField(copy.text(Nutrient.protein.rawValue), unit: "g", text: macroBinding($protein, nutrient: .protein))
                    nutrientField(copy.text(Nutrient.carbohydrateAvailable.rawValue), unit: "g", text: macroBinding($carbohydrate, nutrient: .carbohydrateAvailable))
                    nutrientField(copy.text(Nutrient.totalFat.rawValue), unit: "g", text: macroBinding($fat, nutrient: .totalFat))
                }

                Text(copy.text("customNutritionExplanation"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            }
            .navigationTitle(copy.text("addCustomNutrition"))
            .onChange(of: energy) { _, _ in
                fillEstimatedMacros()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.text("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text("add")) { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear {
                category = (try? DiaryTime.category(selectedDate, zoneID: TimeZone.current.identifier)) ?? .snack
            }
        }
        .temporaryErrorBanner(error)
    }

    private func macroBinding(_ value: Binding<String>, nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { value.wrappedValue },
            set: {
                value.wrappedValue = $0
                estimatedMacros.remove(nutrient)
            }
        )
    }

    private func fillEstimatedMacros() {
        guard let canonical = copy.canonicalQuantity(energy, allowZero: true),
              let calories = try? DecimalAmount(canonical) else { return }

        // Each macro receives one third of the energy: 4 kcal/g for protein
        // and carbohydrates, and 9 kcal/g for fat. Only untouched estimates
        // keep updating as the user types the remaining calorie digits.
        for (nutrient, field, divisor) in [
            (Nutrient.protein, $protein, "12"),
            (.carbohydrateAvailable, $carbohydrate, "12"),
            (.totalFat, $fat, "27")
        ] {
            guard field.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || estimatedMacros.contains(nutrient),
                  let denominator = try? DecimalAmount(divisor),
                  let grams = try? calories.divided(by: denominator) else { continue }
            var value = grams.value
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 2, .bankers)
            field.wrappedValue = NSDecimalNumber(decimal: rounded).stringValue
                .replacingOccurrences(of: ".", with: copy.language == .en ? "." : ",")
            estimatedMacros.insert(nutrient)
        }
    }

    private func nutrientField(_ title: String, unit: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary)
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [energy, protein, carbohydrate, fat].allSatisfy {
            copy.canonicalQuantity($0, allowZero: true) != nil
        }
    }

    private func save() {
        do {
            guard isValid else { throw DiaryError.invalidInput }
            let foodID = UUID()
            var nutrients: [String: NutrientValue] = [:]
            for nutrient in Nutrient.allCases {
                nutrients[nutrient.rawValue] = try NutrientValue(
                    status: .unknown,
                    unit: nutrient.unit,
                    reason: "notUserEntered"
                )
            }
            for (nutrient, input) in [
                (Nutrient.energy, energy),
                (.protein, protein),
                (.carbohydrateAvailable, carbohydrate),
                (.totalFat, fat)
            ] {
                guard let canonical = copy.canonicalQuantity(input, allowZero: true) else {
                    throw DiaryError.invalidInput
                }
                let amount = try DecimalAmount(canonical)
                nutrients[nutrient.rawValue] = try NutrientValue(
                    status: amount.value == 0 ? .knownZero : .known,
                    value: amount,
                    unit: nutrient.unit
                )
            }
            let profile = try NutritionProfile(
                profileRevision: UUID().uuidString,
                basis: NutritionBasis(quantity: try DecimalAmount("100"), unit: .g),
                preparation: "asEntered",
                density: nil,
                nutrients: nutrients,
                portions: [],
                provenanceRef: "personal.quickNutrition"
            )
            let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let food = CatalogueFood(
                id: .personal(foodID),
                revision: "1",
                kind: "product",
                lifecycle: "active",
                names: [copy.language.rawValue: cleanedName],
                salesCountries: [],
                manufacturingCountries: [],
                ingredientOrigins: [],
                barcodes: [],
                profile: profile,
                provenanceRef: "personal.quickNutrition"
            )
            let component = try MealComponent(
                food: food,
                generationID: model.catalogue.generationID,
                displayName: cleanedName,
                language: copy.language.rawValue,
                quantity: LoggedQuantity(amount: try DecimalAmount("100"), unit: .grams),
                fixtureOnly: false
            )
            let matchingEvent = model.events.last {
                $0.category == category && $0.localDate == MealModel.day(selectedDate)
            }
            let draft: MealDraft
            if let matchingEvent {
                draft = MealDraft(
                    id: matchingEvent.id,
                    eatenAt: matchingEvent.eatenAt,
                    zoneID: matchingEvent.zoneID,
                    category: matchingEvent.categoryMode == "manual" ? matchingEvent.category : nil,
                    components: matchingEvent.components + [component],
                    expectedEventRevision: matchingEvent.revision
                )
            } else {
                draft = MealDraft(
                    eatenAt: selectedDate,
                    zoneID: TimeZone.current.identifier,
                    category: category,
                    components: [component]
                )
            }
            let event = try model.diary.save(
                draft,
                operationID: UUID(),
                expectedRevision: matchingEvent?.revision
            )
            Task { await model.syncMealToHealth(event) }
            model.reload(selectedDate)
            dismiss()
        } catch {
            self.error = appError(error, copy: copy)
        }
    }
}

/// Adds one food to the selected meal category without opening the full meal editor.
private struct QuickFoodAdd: View {
    private struct AmountSelection: Identifiable {
        let food: CatalogueFood
        var id: FoodID { food.id }
    }

    @ObservedObject var model: MealModel
    let copy: AppCopy
    let selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var category = MealCategory.snack
    @State private var query = ""
    @State private var market = ""
    @State private var foodOrigin = FoodOriginFilter.all
    @State private var favoritesOnly = false
    @State private var searchResults: [FoodSearchHit] = []
    @State private var correctedQuery: String?
    private var matches: [CatalogueFood] {
        get { searchResults.compactMap(\.food) }
        nonmutating set { searchResults = newValue.map(FoodSearchHit.init(food:)) }
    }
    private var offNameMatches: [OFFNameEntry] {
        get { searchResults.compactMap(\.nameEntry) }
        nonmutating set {
            let kept = Set(newValue.map(\.barcode))
            searchResults.removeAll { $0.nameEntry.map { !kept.contains($0.barcode) } ?? false }
            let existing = Set(searchResults.compactMap { $0.nameEntry?.barcode })
            searchResults += newValue.filter { !existing.contains($0.barcode) }.map(FoodSearchHit.init(nameEntry:))
        }
    }
    @State private var resultLimit = 20
    @State private var isSearching = false
    @State private var activeSearchID = UUID()
    @State private var product: OFFProduct?
    @State private var amount = "100"
    @State private var unit = QuantityUnit.grams
    @State private var amountSelection: AmountSelection?
    @State private var error: String?
    @State private var showingUnsupportedProduct = false
    @State private var unsupportedProductBarcode: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(copy.text("category"), selection: $category) {
                        ForEach(MealCategory.allCases, id: \.rawValue) { category in
                            Text(copy.text(category.rawValue)).tag(category)
                        }
                    }
                }

                Section {
                    TextField(copy.text("search"), text: $query)
                        .onChange(of: query) { _, _ in resultLimit = 20 }
                    if let correctedQuery {
                        Text(copy.text("searchCorrection") + " “" + correctedQuery + "”")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    FoodFilterTags(market: $market, origin: $foodOrigin, favoritesOnly: $favoritesOnly, copy: copy)
                        .onChange(of: foodOrigin) { _, _ in resultLimit = 20 }
                        .onChange(of: market) { _, _ in resultLimit = 20 }
                        .onChange(of: favoritesOnly) { _, _ in resultLimit = 20 }
                        .onChange(of: model.favoriteRevision) { _, _ in resultLimit = 20 }
                    ForEach(searchResults.prefix(resultLimit)) { result in
                        if let food = result.food {
                            Button {
                                product = model.offProducts.first(where: { $0.food?.id == food.id })
                                updateUnit(for: food)
                                model.recordFoodSelection(food, query: query, language: copy.language)
                                amountSelection = AmountSelection(food: food)
                            } label: {
                                VStack(alignment: .leading) {
                                    FoodPersonalizedName(food: food, model: model, copy: copy)
                                    Text(sourceLabel(food))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if model.offProducts.first(where: { $0.food?.id == food.id })?.hasApproximateNutrition == true {
                                        ApproximateNutritionBadge(copy: copy)
                                    }
                                }
                            }
                        } else if let entry = result.nameEntry {
                            Button { Task { await selectOFF(entry) } } label: {
                                VStack(alignment: .leading) {
                                    OFFNameEntryLabel(entry: entry, copy: copy)
                                    HStack {
                                        FoodOriginBadge(origin: .openFoodFacts, copy: copy)
                                        UnsyncedBadge(copy: copy)
                                    }
                                }
                            }
                        }
                    }
                    if isSearching { ProgressView() }
                    if !isSearching && searchResults.isEmpty && (favoritesOnly || !query.isEmpty || !market.isEmpty || foodOrigin != .all) {
                        ContentUnavailableView(copy.text("noSearchResults"), systemImage: "star")
                    }
                    if matches.count + offNameMatches.count > resultLimit {
                        Button(copy.text("showMore")) { resultLimit += 20 }
                    }
                }

            }
            .navigationTitle(copy.text("quickAdd"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.text("cancel")) { dismiss() }
                }
            }
            .onChange(of: showingUnsupportedProduct) { _, showing in
                guard showing else { return }
                error = copy.text("unsupported")
                purgeUnsupportedProduct()
                showingUnsupportedProduct = false
            }
            .onAppear {
                category = (try? DiaryTime.category(selectedDate, zoneID: TimeZone.current.identifier)) ?? .snack
            }
            .task(id: "\(query)|\(market)|\(foodOrigin.rawValue)|\(favoritesOnly)|\(model.favoriteRevision)|\(resultLimit)") {
                await search()
            }
            .sheet(item: $amountSelection) { selection in
                MealFoodAmountSheet(
                    food: selection.food,
                    foodName: model.name(selection.food, language: copy.language.rawValue),
                    amount: $amount,
                    unit: $unit,
                    availableUnits: availableQuantityUnits(for: selection.food),
                    copy: copy,
                    error: $error,
                    add: {
                        if await add(selection.food) {
                            amountSelection = nil
                            dismiss()
                        }
                    }
                )
            }
        }
        .temporaryErrorBanner(error)
    }

    private func search() async {
        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        defer { if activeSearchID == searchID { isSearching = false } }
        do {
            try await Task.sleep(for: .milliseconds(150))
            let result = try await model.searchFoods(query: query, language: copy.language, market: market, origin: foodOrigin, favoritesOnly: favoritesOnly, limit: resultLimit + 1)
            try Task.checkCancellation()
            guard activeSearchID == searchID else { return }
            searchResults = result.hits
            correctedQuery = result.correctedQuery
        } catch is CancellationError {
            return
        } catch { self.error = appError(error) }
    }

    private func selectOFF(_ entry: OFFNameEntry) async {
        do {
            let fetched = try await model.off.lookup(barcode: entry.barcode, language: copy.language.rawValue)
            await model.loadOFF()
            guard let food = fetched.food else {
                unsupportedProductBarcode = fetched.barcode
                showingUnsupportedProduct = true
                return
            }
            product = fetched
            updateUnit(for: food)
            model.recordFoodSelection(food, query: query, language: copy.language)
            amountSelection = AmountSelection(food: food)
        } catch { self.error = appError(error) }
    }

    private func sourceLabel(_ food: CatalogueFood) -> String {
        switch food.id {
        case .personal:
            copy.text("userEntered")
        case let .catalogue(namespace, _):
            copy.text(namespace == "off" ? "community" : namespace == "livsmedelsverket" ? "livsmedelsverket" : "source")
        }
    }

    private func purgeUnsupportedProduct() {
        guard let barcode = unsupportedProductBarcode else { return }
        unsupportedProductBarcode = nil
        offNameMatches.removeAll { $0.barcode == barcode }
        Task {
            do {
                try await model.off.purgeCachedProduct(barcode: barcode)
                await model.loadOFF()
            } catch {
                self.error = appError(error)
            }
        }
    }

    private func availableQuantityUnits(for food: CatalogueFood) -> [QuantityUnit] {
        [QuantityUnit.grams, .millilitres].filter { unit in
            guard let amount = try? DecimalAmount("1") else { return false }
            let quantity = LoggedQuantity(amount: amount, unit: unit)
            return (try? NutritionCalculator.calculate(profile: food.profile, quantity: quantity.consumed())) != nil
        }
    }

    private func updateUnit(for food: CatalogueFood) {
        amount = "100"
        unit = .grams
        let units = availableQuantityUnits(for: food)
        if !units.contains(unit) {
            unit = units.first ?? .grams
        }
    }

    @discardableResult
    private func add(_ food: CatalogueFood) async -> Bool {
        guard availableQuantityUnits(for: food).contains(unit) else {
            error = copy.text("conversionError")
            return false
        }
        guard let canonical = copy.canonicalQuantity(amount),
              let decimalAmount = try? DecimalAmount(canonical) else {
            error = copy.text("quantityError")
            return false
        }

        do {
            error = nil
            product = try await model.productForLogging(food, language: copy.language)
            let food = product?.food ?? food
            let resolution = try model.personal.resolve(base: food)
            let isOFF: Bool = {
                if case let .catalogue(namespace, _) = food.id { return namespace == "off" }
                return false
            }()
            let isSLV: Bool = {
                if case let .catalogue(namespace, _) = food.id { return namespace == "livsmedelsverket" }
                return false
            }()
            guard !isOFF || product != nil else {
                error = copy.text("offMetadataMissing")
                return false
            }
            let component = try MealComponent(
                food: resolution.food,
                generationID: model.catalogue.generationID,
                displayName: model.catalogue.displayName(resolution.food, language: copy.language.rawValue),
                language: copy.language.rawValue,
                quantity: LoggedQuantity(amount: decimalAmount, unit: unit),
                fixtureOnly: !isOFF && !isSLV && product == nil && model.catalogue.fixtureOnly && { if case .personal = food.id { return false }; return true }(),
                provenance: isOFF ? (product?.provenance ?? [:]) : isSLV ? livsmedelsverketProvenance(for: food) : model.catalogue.provenance,
                evidence: isOFF || isSLV ? [:] : model.catalogue.evidence,
                overlayRevision: resolution.overlayRevision
            )
            let matchingEvent = model.events.last(where: {
                $0.category == category && $0.localDate == MealModel.day(selectedDate)
            })
            let draft: MealDraft
            let expectedRevision: Int64?
            if let event = matchingEvent {
                draft = MealDraft(
                    id: event.id,
                    eatenAt: event.eatenAt,
                    zoneID: event.zoneID,
                    category: event.categoryMode == "manual" ? event.category : nil,
                    components: event.components + [component],
                    expectedEventRevision: event.revision
                )
                expectedRevision = event.revision
            } else {
                draft = MealDraft(
                    eatenAt: selectedDate,
                    zoneID: TimeZone.current.identifier,
                    category: category,
                    components: [component]
                )
                expectedRevision = nil
            }
            let event = try model.diary.save(draft, operationID: UUID(), expectedRevision: expectedRevision)
            Task { await model.syncMealToHealth(event) }
            model.reload(selectedDate)
            return true
        } catch {
            self.error = appError(error)
            return false
        }
    }
}

private struct MealComponentRow: View {
    let component: MealComponent
    @Binding var amount: String
    let copy: AppCopy
    var celebrateLebkuchen = false
    let remove: () -> Void

    var body: some View {
        HStack {
            GingerbreadFoodLabel(text: component.displayName, celebrate: celebrateLebkuchen)
            Spacer()
            HStack(spacing: 4) {
                TextField(copy.text("amount"), text: $amount)
                    .keyboardType(.decimalPad)
                    .modifier(AmountKeyboardDone(title: copy.text("done")))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .accessibilityIdentifier("meal.component.grams")
                Text(component.quantity.unit == .millilitres ? "ml" : "g")
            }
            .fixedSize(horizontal: true, vertical: false)
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .accessibilityLabel(copy.text("delete"))
        }
    }
}

private struct MealFoodAmountSheet: View {
    let food: CatalogueFood
    let foodName: String
    @Binding var amount: String
    @Binding var unit: QuantityUnit
    let availableUnits: [QuantityUnit]
    let copy: AppCopy
    @Binding var error: String?
    let add: () async -> Void
    @State private var isAdding = false
    @Environment(\.dismiss) private var dismiss

    private var preview: NutritionTotals? {
        guard availableUnits.contains(unit),
              let canonical = copy.canonicalQuantity(amount),
              let decimalAmount = try? DecimalAmount(canonical) else {
            return nil
        }
        let quantity = LoggedQuantity(amount: decimalAmount, unit: unit)
        guard let consumed = try? quantity.consumed() else { return nil }
        return try? NutritionCalculator.calculate(profile: food.profile, quantity: consumed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(foodName)
                        .font(.headline)
                    Picker(copy.text("unit"), selection: $unit) {
                        ForEach(availableUnits, id: \.rawValue) { unit in
                            Text(unit == .grams ? "g" : "ml").tag(unit)
                        }
                    }
                    TextField(copy.text("amount"), text: $amount)
                        .keyboardType(.decimalPad)
                        .modifier(AmountKeyboardDone(title: copy.text("done")))
                        .accessibilityIdentifier("meal.grams")
                }

                Section(copy.text("calculatedNutrition")) {
                    if let preview {
                        MealNutritionPreview(totals: preview, copy: copy)
                    }
                }
            }
            .disabled(isAdding)
            .navigationTitle(copy.text("add"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.text("cancel")) { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !isAdding else { return }
                        isAdding = true
                        error = nil
                        Task {
                            await add()
                            isAdding = false
                        }
                    } label: {
                        if isAdding {
                            ProgressView()
                                .accessibilityLabel(copy.text("add"))
                        } else {
                            Text(copy.text("add"))
                        }
                    }
                    .disabled(preview == nil || isAdding)
                }
            }
        }
        .temporaryErrorBanner(error ?? (preview == nil ? copy.text("quantityError") : nil))
        .interactiveDismissDisabled(isAdding)
    }
}

private struct MealNutritionPreview: View {
    let totals: NutritionTotals
    let copy: AppCopy

    private let displayedNutrients: [Nutrient] = [.energy, .protein, .carbohydrateAvailable, .totalFat]

    var body: some View {
        ForEach(displayedNutrients, id: \.rawValue) { nutrient in
            let total = totals[nutrient]
            LabeledContent(copy.text(nutrient.rawValue)) {
                Text("\(copy.nutrientNumber(total.knownSubtotal, nutrient: nutrient)) \(total.unit.rawValue)")
            }
        }
    }
}

private enum GoalCalendarMetric: String, CaseIterable, Identifiable {
    case energy
    case protein
    case carbohydrate
    case fat

    var id: String { rawValue }
}

private enum GoalViewMode: String, CaseIterable, Identifiable {
    case calendar
    case graph

    var id: String { rawValue }
}

private struct GoalFoodStatistic: Identifiable {
    let id: String
    let name: String
    let value: Double
    let unit: String
}

private struct GoalFoodAccumulator {
    let name: String
    var amount = 0.0
    var energy = 0.0
    var protein = 0.0
    var carbohydrate = 0.0
    var fat = 0.0
}

private struct GoalDaySummary {
    let date: Date
    let hasMeals: Bool
    let energy: Double
    let protein: Double
    let carbohydrate: Double
    let fat: Double
}

private struct GoalProgressIndicator: View {
    let progress: Double?
    let hasData: Bool
    let isWithinGoal: Bool

    private let ringSize = 19.0
    private let lineWidth = 3.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)

            if hasData, let progress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(
                        indicatorColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringSize, height: ringSize)

                if progress > 1 {
                    GoalOverflowSpiral(progress: progress - 1)
                        .stroke(
                            indicatorColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }

                if isWithinGoal {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(indicatorColor)
                }
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var indicatorColor: Color {
        isWithinGoal ? .green : .orange
    }
}

private struct GoalOverflowSpiral: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let turns = min(max(progress, 0), 1)
        let endAngle = turns * 2 * Double.pi
        let innerRadius = min(rect.width, rect.height) * 0.39
        let availableGrowth = min(rect.width, rect.height) * 0.045
        let steps = max(Int(endAngle / (Double.pi / 40)), 1)

        for step in 0...steps {
            let angle = endAngle * Double(step) / Double(steps)
            let radius = innerRadius + availableGrowth * angle / (2 * Double.pi)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle - Double.pi / 2) * radius),
                y: center.y + CGFloat(sin(angle - Double.pi / 2) * radius)
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct GoalCalendarView: View {
    let diary: DiaryStore
    let copy: AppCopy
    let energyGoal: Double
    let proteinPercent: Int
    let carbohydratePercent: Int
    let fatPercent: Int
    let goalRangeMinimumPercent: Int
    let goalRangeMaximumPercent: Int
    let macroGoalRangeMinimumPercent: Int
    let macroGoalRangeMaximumPercent: Int
    let activeEnergyByDay: [String: MealTrackerHealth.EnergyValue]
    let refreshID: Int
    let showGraphs: Bool
    let widgetNavigationID: Int
    let refreshActivity: ([Date]) async -> Void
    let viewInToday: (Date) -> Void

    @State private var displayedMonth = Date()
    @State private var viewMode = GoalViewMode.calendar
    @State private var metric = GoalCalendarMetric.energy
    @State private var summaries: [String: GoalDaySummary] = [:]
    @State private var monthEvents: [MealEvent] = []
    @State private var selectedDayKey: String?
    @State private var error: String?

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker(copy.text("goalView"), selection: $viewMode) {
                    ForEach(GoalViewMode.allCases) { mode in
                        Text(copy.text(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { moveMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(copy.language.locale)))
                        .font(.headline)
                    Spacer()
                    Button { moveMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                }

                if viewMode == .calendar {
                    Picker(copy.text("goalMetric"), selection: $metric) {
                        ForEach(GoalCalendarMetric.allCases) { metric in
                            Text(copy.text(metric.rawValue == "energy" ? "energy.declared" : metric.rawValue)).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol).font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(monthCells, id: \.self) { date in
                            if let date {
                                dayCell(date)
                            } else {
                                Color.clear.frame(height: 62)
                            }
                        }
                    }
                    Text(
                        "\(copy.text("goalCalendarRange")): " +
                        "\(selectedGoalRangeMinimumPercent)%–\(selectedGoalRangeMaximumPercent)%"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    GoalFoodGraphs(events: monthEvents, month: displayedMonth, copy: copy)
                }

            }
            .padding()
        }
        .navigationTitle(copy.text("goals"))
        .onChange(of: widgetNavigationID, initial: true) { _, _ in
            guard widgetNavigationID > 0 else { return }
            displayedMonth = Date()
            viewMode = showGraphs ? .graph : .calendar
        }
        .task(id: "\(MealModel.day(displayedMonth))-\(refreshID)") {
            loadMonth()
            let loggedDates = summaries.values
                .filter(\.hasMeals)
                .map(\.date)
            await refreshActivity(loggedDates)
        }
        .temporaryErrorBanner(error)
    }

    private var weekdaySymbols: [String] {
        var values = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        values = Array(values[offset...] + values[..<offset])
        return values
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let days = calendar.range(of: .day, in: .month, for: interval.start) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + days.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }.map(Optional.some)
    }

    private var selectedGoalRangeMinimumPercent: Int {
        metric == .energy ? goalRangeMinimumPercent : macroGoalRangeMinimumPercent
    }

    private var selectedGoalRangeMaximumPercent: Int {
        metric == .energy ? goalRangeMaximumPercent : macroGoalRangeMaximumPercent
    }

    private func dayCell(_ date: Date) -> some View {
        let key = MealModel.day(date)
        let summary = summaries[key]
        let progress = summary.map(progress(for:))
        let goalRange = Double(selectedGoalRangeMinimumPercent) / 100...Double(selectedGoalRangeMaximumPercent) / 100
        let met = progress.map { goalRange.contains($0) } ?? false
        return Button {
            selectedDayKey = key
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day().locale(copy.language.locale)))
                    .font(.caption)
                GoalProgressIndicator(
                    progress: progress,
                    hasData: summary?.hasMeals == true,
                    isWithinGoal: met
                )
                if let summary, summary.hasMeals {
                    Text(displayValue(summary))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(calendar.isDateInToday(date) ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .popover(
            isPresented: Binding(
                get: { selectedDayKey == key },
                set: { if !$0, selectedDayKey == key { selectedDayKey = nil } }
            ),
            arrowEdge: .bottom
        ) {
            GoalDayPopover(
                summary: summary ?? GoalDaySummary(date: date, hasMeals: false, energy: 0, protein: 0, carbohydrate: 0, fat: 0),
                copy: copy,
                viewInToday: {
                    selectedDayKey = nil
                    viewInToday(date)
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private func progress(for summary: GoalDaySummary) -> Double {
        let adjustedEnergyGoal = max(energyGoal + movementEnergy(on: summary.date), 1)
        return switch metric {
        case .energy: summary.energy / adjustedEnergyGoal
        case .protein: summary.protein / max(macroTarget(percent: proteinPercent, kcalPerGram: 4, energyGoal: adjustedEnergyGoal), 1)
        case .carbohydrate: summary.carbohydrate / max(macroTarget(percent: carbohydratePercent, kcalPerGram: 4, energyGoal: adjustedEnergyGoal), 1)
        case .fat: summary.fat / max(macroTarget(percent: fatPercent, kcalPerGram: 9, energyGoal: adjustedEnergyGoal), 1)
        }
    }

    private func displayValue(_ summary: GoalDaySummary) -> String {
        let value: Double
        let unit: String
        let formattedValue: String
        switch metric {
        case .energy:
            value = summary.energy; unit = "kcal"; formattedValue = copy.kilocalories(Decimal(value))
        case .protein:
            value = summary.protein; unit = "g"; formattedValue = copy.macronutrient(Decimal(value))
        case .carbohydrate:
            value = summary.carbohydrate; unit = "g"; formattedValue = copy.macronutrient(Decimal(value))
        case .fat:
            value = summary.fat; unit = "g"; formattedValue = copy.macronutrient(Decimal(value))
        }
        return "\(formattedValue) \(unit)"
    }

    private func macroTarget(percent: Int, kcalPerGram: Double, energyGoal: Double) -> Double {
        max(energyGoal, 0) * Double(percent) / 100 / kcalPerGram
    }

    private func movementEnergy(on date: Date) -> Double {
        guard let activeEnergy = activeEnergyByDay[MealModel.day(date)] else { return 0 }
        var healthCalendar = Calendar(identifier: .gregorian)
        healthCalendar.timeZone = TimeZone(identifier: activeEnergy.window.timeZoneID) ?? .current
        return healthCalendar.isDate(date, inSameDayAs: activeEnergy.window.start) ? activeEnergy.kcal : 0
    }

    private func moveMonth(by value: Int) {
        if let date = calendar.date(byAdding: .month, value: value, to: displayedMonth) { displayedMonth = date }
    }

    private func loadMonth() {
        var result: [String: GoalDaySummary] = [:]
        var loadedEvents: [MealEvent] = []
        do {
            for case let date? in monthCells {
                let key = MealModel.day(date)
                let events = try diary.events(localDate: key)
                loadedEvents.append(contentsOf: events)
                func total(_ nutrient: Nutrient) -> Double {
                    let amount = events.compactMap { $0.totals[nutrient.rawValue]?.knownSubtotal.value }.reduce(Decimal.zero, +)
                    return NSDecimalNumber(decimal: amount).doubleValue
                }
                result[key] = GoalDaySummary(
                    date: date,
                    hasMeals: !events.isEmpty,
                    energy: total(.energy),
                    protein: total(.protein),
                    carbohydrate: total(.carbohydrateAvailable),
                    fat: total(.totalFat)
                )
            }
            summaries = result
            monthEvents = loadedEvents
            error = nil
        } catch {
            self.error = appError(error)
        }
    }
}

private struct GoalFoodGraphs: View {
    let events: [MealEvent]
    let month: Date
    let copy: AppCopy

    private let chartLimit = 7

    var body: some View {
        let statistics = makeStatistics()
        VStack(alignment: .leading, spacing: 24) {
            GoalFoodBarChart(
                title: copy.text("energyByMealType"),
                items: mealEnergyStatistics,
                copy: copy,
                categoryLabel: copy.text("mealType")
            )
            if statistics.amount.isEmpty {
                ContentUnavailableView(copy.text("noGoalGraphData"), systemImage: "chart.bar")
            } else {
                GoalFoodBarChart(
                    title: copy.text("mostEatenByAmount"),
                    items: Array(statistics.amount.prefix(chartLimit)),
                    copy: copy
                )
                GoalFoodBarChart(
                    title: copy.text("mostEatenByEnergy"),
                    items: Array(statistics.energy.prefix(chartLimit)),
                    copy: copy
                )

                VStack(alignment: .leading, spacing: 16) {
                    Text(copy.text("topFoodsByMacronutrient"))
                        .font(.title3.bold())
                    GoalMacroRanking(
                        title: copy.text("protein"),
                        items: Array(statistics.protein.prefix(3)),
                        color: MacronutrientColors.protein,
                        copy: copy
                    )
                    GoalMacroRanking(
                        title: copy.text("carbohydrate.euAvailable"),
                        items: Array(statistics.carbohydrate.prefix(3)),
                        color: MacronutrientColors.carbohydrate,
                        copy: copy
                    )
                    GoalMacroRanking(
                        title: copy.text("fat.total"),
                        items: Array(statistics.fat.prefix(3)),
                        color: MacronutrientColors.fat,
                        copy: copy
                    )
                }
            }
            GoalDailyMacroChart(events: events, month: month, copy: copy)
        }
    }

    private var mealEnergyStatistics: [GoalFoodStatistic] {
        var totals: [MealCategory: Decimal] = [:]
        for event in events where event.deletedAt == nil {
            totals[event.category, default: .zero] += event.totals[Nutrient.energy.rawValue]?.knownSubtotal.value ?? .zero
        }
        return MealCategory.allCases.map { category in
            GoalFoodStatistic(
                id: category.rawValue,
                name: copy.text(category.rawValue),
                value: double(totals[category] ?? .zero),
                unit: "kcal"
            )
        }
    }

    private func makeStatistics() -> (
        amount: [GoalFoodStatistic],
        energy: [GoalFoodStatistic],
        protein: [GoalFoodStatistic],
        carbohydrate: [GoalFoodStatistic],
        fat: [GoalFoodStatistic]
    ) {
        var amounts: [String: GoalFoodAccumulator] = [:]
        var nutrients: [String: GoalFoodAccumulator] = [:]

        for component in events.flatMap(\.components) {
            let foodID = String(describing: component.food.id)
            let amountID = "\(foodID)|\(component.quantity.unit.rawValue)"
            let quantity = NSDecimalNumber(decimal: component.quantity.amount.value).doubleValue
            var amount = amounts[amountID] ?? GoalFoodAccumulator(name: component.displayName)
            amount.amount += quantity
            amounts[amountID] = amount

            guard let totals = try? NutritionCalculator.calculate(
                profile: component.food.profile,
                quantity: component.quantity.consumed()
            ) else { continue }
            var nutrient = nutrients[foodID] ?? GoalFoodAccumulator(name: component.displayName)
            nutrient.energy += double(totals[.energy].knownSubtotal)
            nutrient.protein += double(totals[.protein].knownSubtotal)
            nutrient.carbohydrate += double(totals[.carbohydrateAvailable].knownSubtotal)
            nutrient.fat += double(totals[.totalFat].knownSubtotal)
            nutrients[foodID] = nutrient
        }

        let amountItems = amounts.map { key, value in
            let unit = key.components(separatedBy: "|").last.flatMap(QuantityUnit.init(rawValue:)).map(unitLabel) ?? ""
            return GoalFoodStatistic(id: key, name: value.name, value: value.amount, unit: unit)
        }
        let nutrientItems: (KeyPath<GoalFoodAccumulator, Double>, String) -> [GoalFoodStatistic] = { keyPath, unit in
            nutrients.map { key, value in
                GoalFoodStatistic(id: key, name: value.name, value: value[keyPath: keyPath], unit: unit)
            }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
        }
        return (
            amountItems.filter { $0.value > 0 }.sorted { $0.value > $1.value },
            nutrientItems(\.energy, "kcal"),
            nutrientItems(\.protein, "g"),
            nutrientItems(\.carbohydrate, "g"),
            nutrientItems(\.fat, "g")
        )
    }

    private func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }

    private func unitLabel(_ unit: QuantityUnit) -> String {
        switch unit {
        case .grams: "g"
        case .millilitres: "ml"
        case .portions: copy.text("portions")
        }
    }
}

private struct GoalDailyMacroChart: View {
    let events: [MealEvent]
    let month: Date
    let copy: AppCopy
    @State private var selectedDay: String?

    private struct DayTotal: Identifiable {
        let id: String
        let label: String
        let totals: [Nutrient: Decimal]
    }

    private var days: [DayTotal] {
        let calendar = Calendar.autoupdatingCurrent
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        var totals: [String: [Nutrient: Decimal]] = [:]
        for event in events where event.deletedAt == nil {
            for nutrient in MacronutrientColors.order {
                totals[event.localDate, default: [:]][nutrient, default: .zero] +=
                    event.totals[nutrient.rawValue]?.knownSubtotal.value ?? .zero
            }
        }
        return range.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return nil }
            let key = MealModel.day(date)
            return DayTotal(id: key, label: day.formatted(.number.locale(copy.language.locale)), totals: totals[key] ?? [:])
        }
    }

    var body: some View {
        let days = days
        let nutrients = MacronutrientColors.order
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.text("dailyMacronutrients"))
                .font(.title3.bold())
            Chart {
                ForEach(days) { day in
                    ForEach(nutrients, id: \.rawValue) { nutrient in
                        BarMark(
                            x: .value("g", NSDecimalNumber(decimal: day.totals[nutrient] ?? .zero).doubleValue),
                            y: .value(copy.text("dayOfMonth"), day.label)
                        )
                        .foregroundStyle(by: .value(copy.text("dailyMacronutrients"), copy.text(nutrient.rawValue)))
                        .accessibilityLabel("\(copy.text("dayOfMonth")) \(day.label), \(copy.text(nutrient.rawValue))")
                        .accessibilityValue("\(copy.number(day.totals[nutrient] ?? .zero)) g")
                    }
                }
                if let selected = days.first(where: { $0.label == selectedDay }) {
                    RuleMark(y: .value(copy.text("dayOfMonth"), selected.label))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .annotation(
                            position: .top,
                            spacing: 8,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(copy.text("dayOfMonth")) \(selected.label)")
                                    .font(.headline)
                                ForEach(nutrients, id: \.rawValue) { nutrient in
                                    Text("\(copy.text(nutrient.rawValue)): \(copy.number(selected.totals[nutrient] ?? .zero)) g")
                                        .font(.callout)
                                }
                            }
                            .padding(12)
                            .foregroundStyle(.black)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                            .allowsHitTesting(false)
                        }
                }
            }
            .chartYScale(domain: days.map(\.label))
            .chartForegroundStyleScale(
                domain: nutrients.map { copy.text($0.rawValue) },
                range: [MacronutrientColors.protein, MacronutrientColors.carbohydrate, MacronutrientColors.fat]
            )
            .chartXAxis {
                AxisMarks {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel().foregroundStyle(Color.primary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel().foregroundStyle(Color.primary)
                }
            }
            .chartXAxisLabel { Text("g").foregroundStyle(Color.primary) }
            .chartLegend(position: .bottom, alignment: .leading)
            .chartYSelection(value: $selectedDay)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let frame = geometry[plotFrame]
                            guard frame.contains(tap.location),
                                  let day: String = proxy.value(atY: tap.location.y - frame.minY) else {
                                selectedDay = nil
                                return
                            }
                            selectedDay = selectedDay == day ? nil : day
                        })
                }
            }
            .onChange(of: month) { _, _ in selectedDay = nil }
            .frame(height: CGFloat(days.count) * 28 + 70)

            Text(copy.text("tapBarForDetails"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct GoalFoodBarChart: View {
    let title: String
    let items: [GoalFoodStatistic]
    let copy: AppCopy
    var categoryLabel: String? = nil
    @State private var selectedName: String?

    private let colors: [Color] = [.pink, .purple, .indigo, .blue, .teal, .green, .orange]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            Chart(items) { item in
                BarMark(
                    x: .value(title, item.value),
                    y: .value(categoryLabel ?? copy.text("foods"), item.name)
                )
                .foregroundStyle(color(for: item))
                .cornerRadius(5)
                .opacity(selectedName == nil || selectedName == item.name ? 1 : 0.4)
            }
            .chartYSelection(value: $selectedName)
            .chartXAxis {
                AxisMarks(position: .bottom) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel().foregroundStyle(Color.primary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisValueLabel().foregroundStyle(Color.primary)
                }
            }
            .frame(height: max(190, CGFloat(items.count) * 40))
            .accessibilityLabel(title)

            if let selected = items.first(where: { $0.name == selectedName }) {
                Label {
                    Text("\(selected.name): \(formatted(selected.value, unit: selected.unit))")
                } icon: {
                    Circle().fill(color(for: selected)).frame(width: 10, height: 10)
                }
                .font(.callout.weight(.semibold))
                .transition(.opacity)
            } else {
                Text(copy.text("tapBarForDetails"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: selectedName)
    }

    private func color(for item: GoalFoodStatistic) -> Color {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return .teal }
        return colors[index % colors.count]
    }

    private func formatted(_ value: Double, unit: String) -> String {
        let decimal = Decimal(value)
        let number = unit == "kcal" ? copy.kilocalories(decimal) : copy.number(decimal)
        return "\(number) \(unit)"
    }
}

private struct GoalMacroRanking: View {
    let title: String
    let items: [GoalFoodStatistic]
    let color: Color
    let copy: AppCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(color)
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name).foregroundStyle(Color.primary).lineLimit(1)
                        Spacer()
                        Text("\(copy.macronutrient(Decimal(item.value))) g")
                            .foregroundStyle(Color.primary)
                    }
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: proxy.size.width * relativeWidth(for: item))
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding()
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func relativeWidth(for item: GoalFoodStatistic) -> Double {
        guard let maximum = items.first?.value, maximum > 0 else { return 0 }
        return min(max(item.value / maximum, 0), 1)
    }
}

private struct GoalDayPopover: View {
    let summary: GoalDaySummary
    let copy: AppCopy
    let viewInToday: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(copy.language.locale)))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                nutritionRow(copy.text("energy.declared"), value: copy.kilocalories(Decimal(summary.energy)), unit: "kcal")
                nutritionRow(copy.text("protein"), value: copy.macronutrient(Decimal(summary.protein)), unit: "g")
                nutritionRow(copy.text("carbohydrate.euAvailable"), value: copy.macronutrient(Decimal(summary.carbohydrate)), unit: "g")
                nutritionRow(copy.text("fat.total"), value: copy.macronutrient(Decimal(summary.fat)), unit: "g")
            }
            Divider()
            Button(copy.text("viewInToday"), action: viewInToday)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 260)
    }

    private func nutritionRow(_ label: String, value: String, unit: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text("\(value) \(unit)")
                .gridColumnAlignment(.trailing)
        }
    }
}

struct FoodDetail: View {
    let food: CatalogueFood
    @State var product: OFFProduct?
    @ObservedObject var model: MealModel
    let copy: AppCopy
    @State private var busy = false
    @State private var error: String?
    @State private var productChanged: Bool?
    @State private var customizing = false
    @State private var resolved: PersonalResolution?
    var currentFood: CatalogueFood { resolved?.food ?? product?.food ?? food }
    var body: some View {
        List {
            Text(model.catalogue.displayName(currentFood, language: copy.language.rawValue)).font(.title2)
            FoodPersonalizationTags(food: currentFood, model: model, copy: copy)
            FoodFavoriteButton(food: currentFood, model: model, copy: copy)
            if resolved?.sourceChanged == true { Text(copy.text("sourceChanged")).font(.footnote) }
            if resolved?.needsReview == true { Text(copy.text("needsReview")).foregroundStyle(.orange) }
            if let product {
                Text(copy.text("community")); Text(product.attribution)
                Link("Open Food Facts", destination: URL(string: "https://world.openfoodfacts.org/product/\(product.barcode)")!)
                Link("ODbL", destination: product.licenceURL)
                Text(copy.text("checked") + ": " + product.lastSuccessfulCheck.formatted(.dateTime.locale(copy.language.locale)))
                Text(copy.text("upstreamChanged") + ": " + product.upstreamModifiedAt.formatted(.dateTime.locale(copy.language.locale)))
            } else if case .personal = food.id { Text(copy.text("userEntered")) }
            Text("\(copy.number(currentFood.profile.basis.quantity.value)) \(currentFood.profile.basis.unit.rawValue)")
            ForEach(Nutrient.allCases, id: \.rawValue) { nutrient in
                let value = currentFood.profile.nutrients[nutrient.rawValue]
                VStack(alignment: .leading) {
                    Text(copy.text(nutrient.rawValue) + ": " + (value?.value.map { copy.nutrientNumber($0.value, nutrient: nutrient) + " " + nutrient.unit.rawValue } ?? "—"))
                    if value?.status == .trace { Text(copy.text("trace")).font(.caption) }
                    if value == nil || value?.status == .unknown { Text(copy.text("incomplete")).font(.caption) }
                }
            }

        }.navigationTitle(copy.text("nutrition"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    let foodName = model.name(currentFood, language: copy.language.rawValue)
                    if let shareDocument = MealShareDocument(
                        MealSharePayload.food(
                            currentFood,
                            displayName: foodName,
                            language: copy.language.rawValue
                        ),
                        filename: foodName
                    ) {
                        ShareLink(
                            item: shareDocument,
                            subject: Text(copy.text("shareFood")),
                            preview: SharePreview(copy.text("shareFood"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(copy.text("shareFood"))
                    }
                    Button(copy.text("customize")) { customizing = true }
                }
            }
            .sheet(isPresented: $customizing, onDismiss: resolve) { FoodEditor(model: model, copy: copy, base: product?.food ?? food) }
        .temporaryErrorBanner(error)
            .onAppear(perform: resolve)
    }
    func resolve() { do { model.foodPreferencesForDisplay(); var base = product?.food ?? food; if case let .personal(id) = base.id { base = try model.personal.personalFood(id: id).food }; resolved = try model.personal.resolve(base: base); model.effectiveNames[base.id] = resolved?.food.names; Task { await model.loadOFF() } } catch { self.error = appError(error) }
    }
}

struct MealHistory: View {
    @ObservedObject var model: MealModel
    let id: UUID
    let copy: AppCopy
    @State private var revisions: [MealEvent] = []
    @State private var error: String?
    @State private var productChanged: Bool?
    @State private var customizing = false
    @State private var resolved: PersonalResolution?
    var body: some View {
        List {
            ForEach(revisions, id: \.revision) { event in
                Section("\(copy.text("revision")) \(event.revision)") {
                    Text(event.updatedAt.formatted(.dateTime.locale(copy.language.locale)))
                    Text(event.localDate).font(.caption)
                    Text(copy.text(event.category.rawValue))
                    if event.deletedAt != nil { Text(copy.text("deleted")) }
                    ForEach(event.components) { component in Text(component.displayName + " · " + copy.number(component.quantity.amount.value) + " " + (component.quantity.unit == .millilitres ? "ml" : "g")) }
                }
            }

        }.navigationTitle(copy.text("history"))
            .onAppear { do { revisions = try model.diary.history(id: id) } catch { self.error = appError(error) } }
        .temporaryErrorBanner(error)
    }
}
