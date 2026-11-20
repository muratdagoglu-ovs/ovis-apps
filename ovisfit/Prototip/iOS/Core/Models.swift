import Foundation

// MARK: - Profil

public enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female = "Kadın"
    case male = "Erkek"
    case unspecified = "Belirtmek istemiyorum"
    public var id: String { rawValue }
}

public enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low = "Düşük"
    case moderate = "Orta"
    case high = "Yüksek"
    public var id: String { rawValue }

    /// Mifflin-St Jeor dinlenme enerjisiyle birlikte yaygın kullanılan aktivite katsayıları.
    public var factor: Double {
        switch self {
        case .low: return 1.2
        case .moderate: return 1.55
        case .high: return 1.725
        }
    }

    public var detail: String {
        switch self {
        case .low: return "Çoğunlukla oturarak geçen gün"
        case .moderate: return "Haftada 3–5 gün orta tempolu hareket"
        case .high: return "Neredeyse her gün yoğun hareket veya fiziksel iş"
        }
    }
}

public enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose = "Kilo vermek"
    case maintain = "Kilomu korumak"
    case gain = "Kilo almak"
    public var id: String { rawValue }

    /// Günlük enerji farkı (kcal).
    public var adjustment: Int {
        switch self {
        case .lose: return -500
        case .maintain: return 0
        case .gain: return 300
        }
    }
}

public enum DietPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case omnivore = "Her şeyi yerim"
    case pescatarian = "Pesketaryen"
    case vegetarian = "Vejetaryen"
    case vegan = "Vegan"
    public var id: String { rawValue }

    public func allows(_ origin: FoodOrigin) -> Bool {
        switch self {
        case .omnivore: return true
        case .pescatarian: return origin != .meat
        case .vegetarian: return origin == .plant || origin == .dairy || origin == .egg
        case .vegan: return origin == .plant
        }
    }
}

public enum Allergen: String, Codable, CaseIterable, Identifiable, Sendable {
    case milk, egg, gluten, nuts, fish, soy
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .milk: return "Süt ve süt ürünleri"
        case .egg: return "Yumurta"
        case .gluten: return "Gluten içeren tahıllar"
        case .nuts: return "Sert kabuklu yemişler"
        case .fish: return "Balık"
        case .soy: return "Soya"
        }
    }
}

public enum MovementLimit: String, Codable, CaseIterable, Identifiable, Sendable {
    case knee = "Diz hassasiyeti"
    case back = "Bel veya sırt hassasiyeti"
    case balance = "Denge güçlüğü"
    case standing = "Uzun süre ayakta duramıyorum"
    public var id: String { rawValue }
}

public enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case chair = "Sandalye"
    case mat = "Mat"
    case band = "Direnç bandı"
    public var id: String { rawValue }
}

public enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case breakfast, lunch, snack, dinner
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .breakfast: return "Kahvaltı"
        case .lunch: return "Öğle"
        case .snack: return "Ara öğün"
        case .dinner: return "Akşam"
        }
    }
    var order: Int { MealSlot.allCases.firstIndex(of: self)! }
    public static func < (a: MealSlot, b: MealSlot) -> Bool { a.order < b.order }
}

public enum MealContext: String, Codable, CaseIterable, Identifiable, Sendable {
    case out, home, quick
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .out: return "Dışarıdayım"
        case .home: return "Evdeyim"
        case .quick: return "Vaktim az"
        }
    }
}

/// Gün içindeki dakika (ör. 13:00 → 780).
public struct MealTimes: Codable, Equatable, Sendable {
    public var breakfast = 8 * 60 + 30
    public var lunch = 13 * 60
    public var snack = 16 * 60
    public var dinner = 19 * 60 + 30
    public var includeSnack = true
    public init() {}

    public func minutes(for slot: MealSlot) -> Int {
        switch slot {
        case .breakfast: return breakfast
        case .lunch: return lunch
        case .snack: return snack
        case .dinner: return dinner
        }
    }
    public mutating func set(_ minutes: Int, for slot: MealSlot) {
        let value = min(max(minutes, 0), 24 * 60 - 1)
        switch slot {
        case .breakfast: breakfast = value
        case .lunch: lunch = value
        case .snack: snack = value
        case .dinner: dinner = value
        }
    }
    public var slots: [MealSlot] {
        MealSlot.allCases.filter { includeSnack || $0 != .snack }
    }
    public static func label(_ minutes: Int) -> String {
        String(format: "%02d.%02d", minutes / 60, minutes % 60)
    }
}

public struct Profile: Codable, Equatable, Sendable {
    public var name: String
    public var age: Int
    public var heightCm: Double
    public var weightKg: Double
    public var sex: Sex
    public var activity: ActivityLevel
    public var goal: Goal
    public var diet: DietPreference = .omnivore
    public var allergens: Set<Allergen> = []
    public var limits: Set<MovementLimit> = []
    public var equipment: Set<Equipment> = []
    public var mealTimes = MealTimes()
    /// Klinik plan veya kişisel tercih için elle girilen hedef (kcal).
    public var manualTarget: Int?
    public var confirmedAt: Date?

    public init(name: String, age: Int, heightCm: Double, weightKg: Double, sex: Sex,
                activity: ActivityLevel, goal: Goal) {
        self.name = name; self.age = age; self.heightCm = heightCm; self.weightKg = weightKg
        self.sex = sex; self.activity = activity; self.goal = goal
    }
}

// MARK: - Günlük kayıtları (of.meals.v1 / of.drinks.v1 ile uyumlu)

/// Analiz servisinin ve günlüğün ortak yiyecek biçimi. Prototipteki alanlar korunur.
public struct Food: Codable, Equatable, Sendable {
    public var name: String
    public let grams: Int
    public let low: Int
    public let high: Int
    public let group: String
    /// Bu `grams` miktarı için makrolar (g). Bilinmiyorsa nil; eski kayıtlarda yoktur.
    public var protein: Double? = nil
    public var carbs: Double? = nil
    public var fat: Double? = nil
    public var fiber: Double? = nil
    public var sugar: Double? = nil
    public var allergens: [Allergen]? = nil

    public init(name: String, grams: Int, low: Int, high: Int, group: String,
                protein: Double? = nil, carbs: Double? = nil, fat: Double? = nil,
                fiber: Double? = nil, sugar: Double? = nil, allergens: [Allergen]? = nil) {
        self.name = name; self.grams = grams; self.low = low; self.high = high; self.group = group
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.fiber = fiber; self.sugar = sugar
        self.allergens = allergens
    }

    public var hasMacros: Bool { protein != nil && fiber != nil && sugar != nil }
}

public struct Portion: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var food: Food
    public var grams: Int
    public var low: Int { scaled(food.low) }
    public var high: Int { scaled(food.high) }
    public var midpoint: Double { Double(low + high) / 2 }
    public var protein: Double? { macro(food.protein) }
    public var carbs: Double? { macro(food.carbs) }
    public var fat: Double? { macro(food.fat) }
    public var fiber: Double? { macro(food.fiber) }
    public var sugar: Double? { macro(food.sugar) }

    private func macro(_ v: Double?) -> Double? {
        guard let v, food.grams > 0 else { return nil }
        return v * Double(grams) / Double(food.grams)
    }

    public init(id: UUID = UUID(), food: Food, grams: Int) {
        self.id = id; self.food = food; self.grams = grams
    }
    private func scaled(_ value: Int) -> Int {
        guard food.grams > 0 else { return 0 }
        return Int((Double(value) * Double(grams) / Double(food.grams)).rounded())
    }
}

public enum MealSource: String, Codable, Sendable {
    /// Kullanıcının fotoğrafı, canlı analiz.
    case photo
    /// Kullanıcının fotoğrafı, sunucu demo yanıtı (gerçek analiz değil).
    case demo
    /// Plandaki tarifin "yedim" olarak kaydı.
    case plan
    /// Besin değeri bilinen öğelerle elle kayıt.
    case manual
    /// Paketli ürün barkodu (Open Food Facts).
    case barcode
    /// Favori veya önceki öğünün tekrarı.
    case repeatMeal
}

public struct Meal: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var portions: [Portion]
    // v1 sonrası eklenen isteğe bağlı alanlar: eski kayıtlar bunlar olmadan da okunur.
    public var slot: MealSlot?
    public var source: MealSource?
    public var title: String?

    public init(id: UUID = UUID(), date: Date = Date(), portions: [Portion],
                slot: MealSlot? = nil, source: MealSource? = nil, title: String? = nil) {
        self.id = id; self.date = date; self.portions = portions
        self.slot = slot; self.source = source; self.title = title
    }

    public var low: Int { portions.reduce(0) { $0 + $1.low } }
    public var high: Int { portions.reduce(0) { $0 + $1.high } }
    public var midpoint: Int { Int((Double(low + high) / 2).rounded()) }
    public var displayTitle: String {
        title ?? portions.map { $0.food.name }.joined(separator: ", ")
    }
}

public enum DrinkKind {
    public static let water = "Su"
    public static let other = "Diğer içecek"
}

public struct Drink: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var amount: Int
    public var kind: String

    public init(id: UUID = UUID(), date: Date = Date(), amount: Int, kind: String) {
        self.id = id; self.date = date; self.amount = amount; self.kind = kind
    }
}

public struct WeightEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var kg: Double
    public init(id: UUID = UUID(), date: Date, kg: Double) {
        self.id = id; self.date = date; self.kg = kg
    }
}

public struct ActivityRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date: Date
    public var optionID: String
    public var title: String
    public var minutes: Int
    public init(id: UUID = UUID(), date: Date, optionID: String, title: String, minutes: Int) {
        self.id = id; self.date = date; self.optionID = optionID; self.title = title; self.minutes = minutes
    }
}

// MARK: - Yardımcılar

public enum DayKey {
    /// Cihazın yerel takvimine göre "yyyy-MM-dd".
    public static func string(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public enum TRFormat {
    /// 1240 → "1.240"
    public static func int(_ value: Int) -> String {
        let negative = value < 0
        var digits = String(abs(value))
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        groups.insert(digits, at: 0)
        return (negative ? "-" : "") + groups.joined(separator: ".")
    }
    /// 75.0 → "75,0"
    public static func decimal(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
    public static func range(_ low: Int, _ high: Int) -> String {
        low == high ? int(low) : "\(int(low))–\(int(high))"
    }
}
