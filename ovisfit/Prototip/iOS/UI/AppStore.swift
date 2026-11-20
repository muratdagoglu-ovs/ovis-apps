import SwiftUI
import WidgetKit

enum Route: Hashable {
    case reminders
    case barcode
    case shopping
    case profile
    case photo
    case analysis
    case movement
    case swap(MealSlot)
    case swelling
}

@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case today, plan, water, growth }
    @Published var tab: Tab = .today
    @Published var today: [Route] = []
    @Published var plan: [Route] = []
    @Published var water: [Route] = []
    @Published var growth: [Route] = []

    func popToRoot() {
        switch tab {
        case .today: today = []
        case .plan: plan = []
        case .water: water = []
        case .growth: growth = []
        }
    }
    func pop() {
        switch tab {
        case .today: if !today.isEmpty { today.removeLast() }
        case .plan: if !plan.isEmpty { plan.removeLast() }
        case .water: if !water.isEmpty { water.removeLast() }
        case .growth: if !growth.isEmpty { growth.removeLast() }
        }
    }
    func push(_ route: Route) {
        switch tab {
        case .today: today.append(route)
        case .plan: plan.append(route)
        case .water: water.append(route)
        case .growth: growth.append(route)
        }
    }
}

/// Uygulama durumu. Kalıcı veri `Repository` üzerinden UserDefaults'ta tutulur
/// (of.meals.v1 / of.drinks.v1 anahtarları korunur).
@MainActor
final class AppStore: ObservableObject {
    let repo: Repository
    let db: FoodDatabase
    let isScreenshotMode: Bool

    @Published private(set) var profile: Profile?
    @Published private(set) var meals: [Meal] = []
    @Published private(set) var drinks: [Drink] = []
    @Published private(set) var weights: [WeightEntry] = []
    @Published private(set) var activities: [ActivityRecord] = []
    @Published private(set) var swaps: PlanSwaps = [:]
    @Published private(set) var fluidTarget: Int
    @Published private(set) var fluidRestricted: Bool
    @Published private(set) var serverOverride: String
    @Published private(set) var steps: [DailyValue] = []
    @Published private(set) var activeEnergy: [DailyValue] = []
    @Published private(set) var healthRequested: Bool
    let health = HealthSync()
    @Published var now = Date()
    /// Hareket ekranında seçilen süre (kullanıcının bugünkü zamanı).
    @Published var movementMinutes = 20
    @Published private(set) var favorites: [FavoriteMeal] = []
    @Published private(set) var reminders = ReminderSettings()
    @Published private(set) var remindersConfigured = false
    @Published private(set) var healthWrite = false
    @Published private(set) var shoppingChecked: [String: [String]] = [:]

    init(arguments: [String] = ProcessInfo.processInfo.arguments, bundle: Bundle = .main) {
        let screenshot = arguments.contains("-OvisScreenshotData")
        let defaults: UserDefaults
        if screenshot {
            // Önizleme/ekran görüntüsü verisi gerçek günlükten tamamen ayrı, geçici bir alanda tutulur.
            let suite = "of.screenshot"
            UserDefaults().removePersistentDomain(forName: suite)
            defaults = UserDefaults(suiteName: suite) ?? .standard
        } else {
            defaults = .standard
            if arguments.contains("-OvisResetData"), let id = bundle.bundleIdentifier {
                defaults.removePersistentDomain(forName: id)
            }
        }
        let repo = Repository(store: defaults)
        repo.migrate()
        var db = FoodDatabase.empty
        if let url = bundle.url(forResource: "foods", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let loaded = try? FoodDatabase.load(from: data) {
            db = loaded
        }
        if screenshot { ScreenshotData.seed(repo, db: db) }
        self.repo = repo
        self.db = db
        self.isScreenshotMode = screenshot
        self.fluidTarget = repo.fluidTarget
        self.fluidRestricted = repo.fluidRestricted
        self.serverOverride = repo.apiBaseURL ?? ""
        self.healthRequested = repo.healthRequested
        reload()
    }

    func reload() {
        profile = repo.profile
        meals = repo.meals
        drinks = repo.drinks
        weights = repo.weights
        activities = repo.activities
        swaps = repo.swaps
        steps = repo.steps
        activeEnergy = repo.activeEnergy
        favorites = repo.favorites
        reminders = repo.reminders
        remindersConfigured = repo.store.object(forKey: StoreKey.reminders) != nil
        healthWrite = repo.healthWrite
        shoppingChecked = repo.shoppingChecked
        publishWidget()
    }

    var calendar: Calendar { .current }

    // MARK: Profil ve hedef

    var estimate: EnergyEstimate? { profile.map(EnergyCalculator.estimate) }
    var target: Int { estimate?.target ?? 0 }

    func saveProfile(_ p: Profile) {
        var p = p
        p.confirmedAt = Date()
        repo.saveProfile(p)
        profile = p
        rescheduleReminders()
        publishWidget()
    }

    var legacyGoal: Goal? { repo.legacyGoal }

    // MARK: Plan

    func plan(for day: Date) -> DayPlan? {
        guard let profile else { return nil }
        let key = DayKey.string(for: day, calendar: calendar)
        var overrides: [MealSlot: String] = [:]
        for (slot, id) in swaps[key] ?? [:] {
            if let s = MealSlot(rawValue: slot) { overrides[s] = id }
        }
        return Planner.plan(for: day, profile: profile, target: target, db: db, overrides: overrides, calendar: calendar)
    }

    /// Seçim yalnızca planı değiştirir; günlüğe öğün yazmaz.
    func swap(_ slot: MealSlot, to recipeID: String, on day: Date) {
        let key = DayKey.string(for: day, calendar: calendar)
        var all = swaps
        var dayMap = all[key] ?? [:]
        dayMap[slot.rawValue] = recipeID
        all[key] = dayMap
        repo.saveSwaps(all)
        swaps = all
    }

    func swappedRecipe(_ slot: MealSlot, on day: Date) -> String? {
        swaps[DayKey.string(for: day, calendar: calendar)]?[slot.rawValue]
    }

    // MARK: Öğünler

    func meals(on day: Date) -> [Meal] { DaySummary.of(meals, on: day, calendar: calendar).meals }
    func summary(on day: Date) -> DaySummary { DaySummary.of(meals, on: day, calendar: calendar) }

    func loggedSlots(on day: Date) -> Set<MealSlot> {
        Set(meals(on: day).compactMap(\.slot))
    }

    func isPlannedMealLogged(_ slot: MealSlot, on day: Date) -> Bool {
        meals(on: day).contains { $0.slot == slot && $0.source == .plan }
    }

    /// Aynı kimlikle ikinci kayıt reddedilir (art arda Kaydet dokunuşları).
    @discardableResult
    func addMeal(_ meal: Meal) -> Bool {
        guard repo.addMeal(meal) else { return false }
        meals = repo.meals
        if healthWrite { Task { await health.save(meal) } }
        publishWidget()
        return true
    }

    /// Plandaki öğünü "yedim" olarak ayrı bir eylemle kaydeder; aynı gün aynı öğün bir kez.
    @discardableResult
    func logPlanned(_ meal: PlannedMeal, on day: Date) -> Bool {
        guard !isPlannedMealLogged(meal.slot, on: day) else { return false }
        let date = calendar.isDateInToday(day) ? Date() : day
        return addMeal(Meal(date: date, portions: meal.portions, slot: meal.slot, source: .plan,
                            title: meal.recipe.name))
    }

    func deleteMeal(_ id: UUID) {
        repo.deleteMeal(id)
        meals = repo.meals
        if healthWrite { Task { await health.deleteSamples(id) } }
        publishWidget()
    }

    // MARK: Sıvı

    var hydration: HydrationSummary {
        Hydration.summary(drinks, on: now, target: fluidTarget, restricted: fluidRestricted, calendar: calendar)
    }

    func addDrink(_ amount: Int, kind: String) {
        let drink = Drink(amount: amount, kind: kind)
        drinks.append(drink)
        repo.saveDrinks(drinks)
        if healthWrite { Task { await health.save(drink) } }
        publishWidget()
    }

    var lastDrinkToday: Drink? {
        drinks.filter { calendar.isDate($0.date, inSameDayAs: now) }.max { $0.date < $1.date }
    }

    func undoDrink() {
        let removed = lastDrinkToday
        drinks = Hydration.undoLast(drinks, on: now, calendar: calendar)
        repo.saveDrinks(drinks)
        if healthWrite, let removed { Task { await health.deleteSamples(removed.id) } }
        publishWidget()
    }

    func setFluidTarget(_ value: Int) {
        repo.fluidTarget = value
        fluidTarget = repo.fluidTarget
    }

    func setFluidRestricted(_ value: Bool) {
        repo.fluidRestricted = value
        fluidRestricted = value
        rescheduleReminders()
        publishWidget()
    }

    // MARK: Hareket

    var todayActivity: ActivityRecord? {
        activities.first { calendar.isDate($0.date, inSameDayAs: now) }
    }

    var movementOptions: [MovementOption] {
        let p = profile
        var list = MovementPlanner.options(minutes: movementMinutes,
                                           equipment: p?.equipment ?? [], limits: p?.limits ?? [])
        // Geç saatte dinlenme önce sunulur.
        if calendar.component(.hour, from: now) >= 21, let i = list.firstIndex(where: \.isRest) {
            list.insert(list.remove(at: i), at: 0)
        }
        return list
    }

    @discardableResult
    func complete(_ option: MovementOption) -> Bool {
        guard let updated = MovementPlanner.record(option, on: Date(), existing: activities, calendar: calendar) else { return false }
        repo.saveActivities(updated)
        activities = updated
        return true
    }

    // MARK: Kilo

    func addWeight(_ kg: Double, on date: Date) {
        let before = weights
        weights = ProgressReport.addWeight(kg, on: date, to: weights, calendar: calendar)
        repo.saveWeights(weights)
        if healthWrite {
            let replaced = before.filter { old in !weights.contains { $0.id == old.id } }
            let added = weights.filter { new in !before.contains { $0.id == new.id } }
            Task {
                for r in replaced { await health.deleteSamples(r.id) }
                for a in added { await health.save(a) }
            }
        }
    }

    func deleteWeight(_ id: UUID) {
        weights.removeAll { $0.id == id }
        repo.saveWeights(weights)
        if healthWrite { Task { await health.deleteSamples(id) } }
    }

    var weeklyReport: WeeklyReport {
        ProgressReport.report(for: now, weights: weights, meals: meals, activities: activities, calendar: calendar)
    }

    // MARK: Apple Sağlık, hedefler ve enerji dengesi

    var healthAvailable: Bool { HealthSync.isAvailable && !isScreenshotMode }

    func connectHealth() async {
        await health.requestAccess()
        repo.healthRequested = true
        healthRequested = true
        await refreshHealth()
    }

    func refreshHealth() async {
        guard healthRequested, HealthSync.isAvailable, !isScreenshotMode,
              let result = await health.fetch(days: 14) else { return }
        steps = DailyValues.merge(steps, result.steps, calendar: calendar)
        activeEnergy = DailyValues.merge(activeEnergy, result.active, calendar: calendar)
        repo.saveSteps(steps)
        repo.saveActiveEnergy(activeEnergy)
        publishWidget()
    }

    /// Sistem hedefleri: profil değişince kendiliğinden güncellenir.
    var targets: DailyTargets? { profile.map(Targets.daily(for:)) }

    var todaySteps: Int { DailyValues.value(on: now, in: steps, calendar: calendar) }

    var todayActive: (kcal: Int, source: ActivityEnergy.Source) {
        ActivityEnergy.active(on: now, steps: steps, healthActive: activeEnergy, activities: activities,
                              weightKg: profile?.weightKg ?? 70, calendar: calendar)
    }

    var todayBalance: DayBalance? {
        profile.map { EnergyBalance.day(now, profile: $0, meals: meals, steps: steps, healthActive: activeEnergy,
                                        activities: activities, calendar: calendar) }
    }

    var weekBalance: EnergyBalance.Week? {
        profile.map { EnergyBalance.week(containing: now, profile: $0, meals: meals, steps: steps,
                                         healthActive: activeEnergy, activities: activities, calendar: calendar) }
    }

    // MARK: Apple Sağlık'a yazma

    /// Açılınca öğün enerjisi/makroları, su ve kilo Sağlık uygulamasına yazılır (yalnızca bundan sonraki kayıtlar).
    func setHealthWrite(_ on: Bool) async {
        if on { await health.requestWriteAccess() }
        repo.healthWrite = on
        healthWrite = on
    }

    // MARK: Makrolar, seriler, rozetler

    var macroTargets: MacroTargets? { profile.map(Macros.targets(for:)) }
    var todayMacros: MacroTotals { Macros.totals(meals(on: now)) }

    var streaks: Streaks {
        Gamification.streaks(meals: meals, drinks: drinks, fluidTarget: fluidRestricted ? nil : fluidTarget,
                             steps: steps, stepGoal: targets?.steps ?? 8000, now: now, calendar: calendar)
    }
    var badges: [Badge] {
        Gamification.badges(meals: meals, drinks: drinks, weights: weights, steps: steps, activities: activities,
                            streaks: streaks, calendar: calendar)
    }

    // MARK: Favoriler ve tekrar

    func isFavorite(_ meal: Meal) -> Bool {
        favorites.contains { $0.title == meal.displayTitle && $0.portions.map(\.food) == meal.portions.map(\.food) }
    }

    func addFavorite(from meal: Meal) {
        guard !isFavorite(meal) else { return }
        favorites.append(Repeats.favorite(from: meal))
        repo.saveFavorites(favorites)
    }

    func removeFavorite(_ id: UUID) {
        favorites.removeAll { $0.id == id }
        repo.saveFavorites(favorites)
    }

    /// Tek dokunuşla tekrar kayıt (her dokunuş yeni bir öğün; art arda dokunuşu çağıran ekran engeller).
    @discardableResult
    func repeatMeal(portions: [Portion], title: String?, slot: MealSlot?) -> Bool {
        addMeal(Repeats.copy(portions: portions, title: title, slot: slot ?? Repeats.inferredSlot(Date(), calendar: calendar)))
    }

    var currentSlot: MealSlot { Repeats.inferredSlot(now, calendar: calendar) }
    func yesterdayMeal(for slot: MealSlot) -> Meal? { Repeats.yesterday(slot, meals: meals, now: now, calendar: calendar) }

    // MARK: Hatırlatmalar

    func setReminders(_ r: ReminderSettings) {
        repo.saveReminders(r)
        reminders = r
        remindersConfigured = true
        rescheduleReminders(requestPermission: true)
    }

    func rescheduleReminders(requestPermission: Bool = false) {
        guard remindersConfigured, !isScreenshotMode else { return }
        let items = Reminders.plan(reminders, profile: profile, fluidRestricted: fluidRestricted)
        Task { await ReminderScheduler.apply(items, requestPermission: requestPermission) }
    }

    // MARK: Alışveriş listesi

    func shoppingList(days: Int) -> [ShoppingItem] {
        let plans = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: now).flatMap { plan(for: $0) } }
        return Shopping.list(from: plans, db: db)
    }

    private var shoppingKey: String { DayKey.string(for: ProgressReport.week(containing: now, calendar: calendar).0, calendar: calendar) }
    var checkedShopping: Set<String> { Set(shoppingChecked[shoppingKey] ?? []) }

    func toggleShopping(_ id: String) {
        var set = checkedShopping
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        shoppingChecked = [shoppingKey: Array(set).sorted()]   // eski haftalar temizlenir
        repo.saveShoppingChecked(shoppingChecked)
    }

    // MARK: Widget

    static var appGroup: String? {
        (Bundle.main.object(forInfoDictionaryKey: "OvisAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func publishWidget() {
        guard let p = profile, !isScreenshotMode else { return }
        let h = hydration
        let snapshot = WidgetSnapshot(date: now, name: p.name, intakeKcal: summary(on: now).estimate, targetKcal: target,
                                      waterMl: h.total, waterTargetMl: h.target, steps: todaySteps,
                                      stepGoal: targets?.steps ?? 8000, loggingStreak: streaks.logging)
        guard let group = Self.appGroup, let defaults = UserDefaults(suiteName: group) else { return }
        if WidgetSnapshot.load(from: defaults) != snapshot {
            snapshot.save(to: defaults)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Analiz sunucusu

    /// Simülatör ve Xcode'dan kurulan Debug derlemesi Mac'teki yerel sunucuya http ile bağlanabilir.
    /// TestFlight/App Store (Release) derlemesinde yalnızca HTTPS.
    static var allowsInsecureLocal: Bool {
        #if targetEnvironment(simulator) || DEBUG
        return true
        #else
        return false
        #endif
    }

    var bundledServerAddress: String {
        (Bundle.main.object(forInfoDictionaryKey: "OvisAPIBaseURL") as? String) ?? ""
    }

    var serverAddress: String { serverOverride.isEmpty ? bundledServerAddress : serverOverride }

    var plateEndpoint: URL? {
        ServerAddress.validate(serverAddress, allowInsecureLocal: Self.allowsInsecureLocal)
            .map(ServerAddress.plateEndpoint(base:))
    }

    /// Boş metin, paketlenmiş varsayılana döner. Geçersiz adres kaydedilmez.
    @discardableResult
    func setServerOverride(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            repo.apiBaseURL = nil
            serverOverride = ""
            return true
        }
        guard ServerAddress.validate(trimmed, allowInsecureLocal: Self.allowsInsecureLocal) != nil else { return false }
        repo.apiBaseURL = trimmed
        serverOverride = trimmed
        return true
    }

    func eraseAll() {
        for key in [StoreKey.meals, StoreKey.drinks, StoreKey.profile, StoreKey.weights, StoreKey.activities,
                    StoreKey.swaps, StoreKey.fluidTarget, StoreKey.fluidRestricted, StoreKey.legacyGoal,
                    StoreKey.mealsBackup, StoreKey.drinksBackup, StoreKey.steps, StoreKey.activeEnergy,
                    StoreKey.healthRequested, StoreKey.healthWrite, StoreKey.favorites, StoreKey.reminders,
                    StoreKey.shoppingChecked] {
            repo.store.removeObject(forKey: key)
        }
        fluidTarget = repo.fluidTarget
        fluidRestricted = repo.fluidRestricted
        healthRequested = false
        Task { await ReminderScheduler.apply([], requestPermission: false) }
        if let group = Self.appGroup { UserDefaults(suiteName: group)?.removeObject(forKey: WidgetSnapshot.key) }
        WidgetCenter.shared.reloadAllTimelines()
        reload()
    }
}

/// Yalnızca `-OvisScreenshotData` argümanıyla, geçici ayrı bir UserDefaults alanına yazılır.
/// Tasarım referanslarıyla karşılaştırma görüntüleri için; gerçek günlüğe asla dokunmaz.
enum ScreenshotData {
    static func seed(_ repo: Repository, db: FoodDatabase) {
        var p = Profile(name: "Murat", age: 35, heightCm: 175, weightKg: 75, sex: .female, activity: .moderate, goal: .maintain)
        p.manualTarget = 2100
        p.confirmedAt = Date()
        repo.saveProfile(p)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func at(_ h: Int, _ m: Int = 0, dayOffset: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(day: dayOffset, hour: h, minute: m), to: today)!
        }
        if let breakfast = db.recipe("omlet-peynir") {
            let pm = Planner.scaled(breakfast, slot: .breakfast, minutes: 510, targetKcal: 1240, db: db)
            repo.addMeal(Meal(date: at(8, 30), portions: [Portion(food: Food(name: "Kahvaltı tabağı", grams: 400, low: 1140, high: 1340, group: "diger"), grams: 400)],
                              slot: .breakfast, source: .manual, title: pm.recipe.name))
        }
        repo.saveDrinks([Drink(date: at(8), amount: 500, kind: DrinkKind.water),
                         Drink(date: at(9), amount: 500, kind: DrinkKind.water),
                         Drink(date: at(9, 30), amount: 250, kind: DrinkKind.other)])
        repo.saveSteps([DailyValue(date: today, value: 6240)])
        repo.saveWeights([WeightEntry(date: at(8, dayOffset: -4), kg: 75.5),
                          WeightEntry(date: at(8, dayOffset: -3), kg: 75.2),
                          WeightEntry(date: at(8, dayOffset: -1), kg: 75.3),
                          WeightEntry(date: at(8), kg: 75.0)])
    }
}
