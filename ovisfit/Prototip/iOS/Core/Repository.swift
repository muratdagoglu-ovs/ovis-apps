import Foundation

public protocol KeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

public final class MemoryStore: KeyValueStore {
    public var values: [String: Any] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { values[key] as? Data }
    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
    public func removeObject(forKey key: String) { values[key] = nil }
}

public enum StoreKey {
    public static let meals = "of.meals.v1"
    public static let drinks = "of.drinks.v1"
    public static let mealsBackup = "of.meals.v1.backup"
    public static let drinksBackup = "of.drinks.v1.backup"
    public static let profile = "of.profile.v1"
    public static let weights = "of.weights.v1"
    public static let activities = "of.activities.v1"
    public static let swaps = "of.planSwaps.v1"
    public static let fluidTarget = "of.fluidTarget"
    public static let fluidRestricted = "of.clinicalFluidLimit"
    public static let legacyGoal = "of.goal"
    public static let apiBaseURL = "of.apiBaseURL"
    public static let steps = "of.steps.v1"
    public static let activeEnergy = "of.activeEnergy.v1"
    public static let healthRequested = "of.healthRequested"
    public static let healthWrite = "of.healthWrite"
    public static let favorites = "of.favorites.v1"
    public static let reminders = "of.reminders.v1"
    public static let shoppingChecked = "of.shoppingChecked.v1"
    public static let schema = "of.schemaVersion"
}

/// Dizi içinde bozuk tek bir kaydın tüm günlüğü kaybettirmemesi için.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// Gün → öğün → tarif kimliği ("Planım değişti" seçimleri).
public typealias PlanSwaps = [String: [String: String]]

public final class Repository {
    public static let schemaVersion = 2
    let store: KeyValueStore
    let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]   // deterministik çıktı: taşıma tekrar çalıştırılabilir
        return e
    }()
    let decoder = JSONDecoder()

    public init(store: KeyValueStore) { self.store = store }

    // MARK: Genel

    func load<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = store.data(forKey: key), !data.isEmpty else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
    func loadList<T: Decodable>(_ key: String) -> [T] {
        guard let data = store.data(forKey: key), !data.isEmpty,
              let list = try? decoder.decode([Lossy<T>].self, from: data) else { return [] }
        return list.compactMap(\.value)
    }
    @discardableResult
    func save<T: Encodable>(_ value: T, _ key: String) -> Bool {
        guard let data = try? encoder.encode(value) else { return false }
        store.set(data, forKey: key)
        return true
    }

    // MARK: Taşıma

    /// v1 günlüklerini güvenle yeni şemaya taşır. Tekrar çalıştırılabilir (idempotent):
    /// - İlk çalışmada ham veriler `.backup` anahtarlarına bir kez kopyalanır.
    /// - Bozuk tekil kayıtlar atlanır, sıfır gramlık porsiyonlar ve boş öğünler temizlenir,
    ///   yinelenen kimlikler tekilleştirilir. Anahtarlar ve biçim (of.meals.v1 / of.drinks.v1) korunur.
    public func migrate() {
        if let raw = store.data(forKey: StoreKey.meals), store.data(forKey: StoreKey.mealsBackup) == nil {
            store.set(raw, forKey: StoreKey.mealsBackup)
        }
        if let raw = store.data(forKey: StoreKey.drinks), store.data(forKey: StoreKey.drinksBackup) == nil {
            store.set(raw, forKey: StoreKey.drinksBackup)
        }
        if store.data(forKey: StoreKey.meals) != nil {
            var seen = Set<UUID>()
            let stored: [Meal] = loadList(StoreKey.meals)
            let meals: [Meal] = stored.compactMap { (meal: Meal) -> Meal? in
                guard seen.insert(meal.id).inserted else { return nil }
                var m = meal
                m.portions = m.portions.filter { $0.grams > 0 && $0.food.grams > 0 }
                return m.portions.isEmpty ? nil : m
            }
            save(meals, StoreKey.meals)
        }
        if store.data(forKey: StoreKey.drinks) != nil {
            var seen = Set<UUID>()
            let storedDrinks: [Drink] = loadList(StoreKey.drinks)
            let drinks = storedDrinks.filter { $0.amount > 0 && seen.insert($0.id).inserted }
            save(drinks, StoreKey.drinks)
        }
        if let t = store.object(forKey: StoreKey.fluidTarget) as? Int {
            store.set(Hydration.clampTarget(t), forKey: StoreKey.fluidTarget)
        }
        store.set(Self.schemaVersion, forKey: StoreKey.schema)
    }

    // MARK: Profil

    public var profile: Profile? { load(StoreKey.profile, as: Profile.self) }
    public func saveProfile(_ p: Profile) { save(p, StoreKey.profile) }

    /// Prototipteki `of.goal` değeri, ilk profil oluşturulurken varsayılan hedef olarak kullanılır.
    public var legacyGoal: Goal? {
        (store.object(forKey: StoreKey.legacyGoal) as? String).flatMap(Goal.init(rawValue:))
    }

    // MARK: Öğünler

    public var meals: [Meal] { loadList(StoreKey.meals) }

    /// Aynı öğünün (aynı kimlik) ikinci kez yazılmasını engeller.
    @discardableResult
    public func addMeal(_ meal: Meal) -> Bool {
        var list = meals
        guard !meal.portions.isEmpty, !list.contains(where: { $0.id == meal.id }) else { return false }
        list.append(meal)
        return save(list, StoreKey.meals)
    }

    public func deleteMeal(_ id: UUID) {
        save(meals.filter { $0.id != id }, StoreKey.meals)
    }

    // MARK: İçecekler

    public var drinks: [Drink] { loadList(StoreKey.drinks) }
    public func saveDrinks(_ d: [Drink]) { save(d, StoreKey.drinks) }

    public var fluidTarget: Int {
        get { Hydration.clampTarget(store.object(forKey: StoreKey.fluidTarget) as? Int ?? Hydration.defaultTarget) }
        set { store.set(Hydration.clampTarget(newValue), forKey: StoreKey.fluidTarget) }
    }
    public var fluidRestricted: Bool {
        get { store.object(forKey: StoreKey.fluidRestricted) as? Bool ?? false }
        set { store.set(newValue, forKey: StoreKey.fluidRestricted) }
    }

    // MARK: Kilo, hareket, plan

    public var weights: [WeightEntry] { loadList(StoreKey.weights) }
    public func saveWeights(_ w: [WeightEntry]) { save(w, StoreKey.weights) }

    public var activities: [ActivityRecord] { loadList(StoreKey.activities) }
    public func saveActivities(_ a: [ActivityRecord]) { save(a, StoreKey.activities) }

    public var swaps: PlanSwaps { load(StoreKey.swaps, as: PlanSwaps.self) ?? [:] }
    public func saveSwaps(_ s: PlanSwaps) { save(s, StoreKey.swaps) }

    // MARK: Apple Sağlık önbelleği (cihazda)

    public var steps: [DailyValue] { loadList(StoreKey.steps) }
    public func saveSteps(_ v: [DailyValue]) { save(v, StoreKey.steps) }
    public var activeEnergy: [DailyValue] { loadList(StoreKey.activeEnergy) }
    public func saveActiveEnergy(_ v: [DailyValue]) { save(v, StoreKey.activeEnergy) }
    public var healthRequested: Bool {
        get { store.object(forKey: StoreKey.healthRequested) as? Bool ?? false }
        set { store.set(newValue, forKey: StoreKey.healthRequested) }
    }

    public var healthWrite: Bool {
        get { store.object(forKey: StoreKey.healthWrite) as? Bool ?? false }
        set { store.set(newValue, forKey: StoreKey.healthWrite) }
    }

    // MARK: Favoriler, hatırlatmalar, alışveriş

    public var favorites: [FavoriteMeal] { loadList(StoreKey.favorites) }
    public func saveFavorites(_ f: [FavoriteMeal]) { save(f, StoreKey.favorites) }

    public var reminders: ReminderSettings { load(StoreKey.reminders, as: ReminderSettings.self) ?? ReminderSettings() }
    public func saveReminders(_ r: ReminderSettings) { save(r, StoreKey.reminders) }

    /// Hafta anahtarı → işaretlenen besin kimlikleri.
    public var shoppingChecked: [String: [String]] { load(StoreKey.shoppingChecked, as: [String: [String]].self) ?? [:] }
    public func saveShoppingChecked(_ c: [String: [String]]) { save(c, StoreKey.shoppingChecked) }

    public var apiBaseURL: String? {
        get { (store.object(forKey: StoreKey.apiBaseURL) as? String).flatMap { $0.isEmpty ? nil : $0 } }
        set { store.set(newValue, forKey: StoreKey.apiBaseURL) }
    }
}

public enum ServerAddress {
    /// Yayın (Release) derlemesinde HTTPS zorunlu. Simülatörde ve Xcode'dan kurulan Debug
    /// derlemesinde yerel ağdaki http adresleri de kabul edilir (Mac'teki geliştirme sunucusu).
    public static func validate(_ text: String, allowInsecureLocal: Bool) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else { return nil }
        if scheme == "https" { return url }
        return scheme == "http" && allowInsecureLocal && isLocal(host) ? url : nil
    }

    /// Geri döngü, Bonjour (.local) ve özel IPv4 aralıkları (10/8, 172.16/12, 192.168/16).
    public static func isLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if ["127.0.0.1", "localhost", "::1"].contains(h) || h.hasSuffix(".local") { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, h.split(separator: ".").count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
    }

    public static func plateEndpoint(base: URL) -> URL {
        base.appendingPathComponent("plate")
    }
}
