import Foundation

// MARK: - 7 · Makro hedefleri (protein, lif, şeker)

public struct MacroTargets: Equatable, Sendable {
    public let protein: Int
    public let fiber: Int
    /// Toplam şeker için referans üst sınır.
    public let sugarLimit: Int
}

public struct MacroTotals: Equatable, Sendable {
    public var protein = 0.0
    public var carbs = 0.0
    public var fat = 0.0
    public var fiber = 0.0
    public var sugar = 0.0
    /// Makrosu bilinmeyen (ör. fotoğraf tahmini, eski kayıt) porsiyon sayısı.
    public var unknownPortions = 0
    public var knownPortions = 0
}

public enum Macros {
    /// - Protein: kilo başına g (kilo verme/almada kas kütlesini korumak için daha yüksek), enerjinin %35'ini geçmez.
    /// - Lif: 1.000 kcal başına 14 g (ABD Beslenme Rehberi 2020–2025), en az 25 g.
    /// - Şeker: toplam şeker için 2.000 kcal'de 90 g referans alımı (UK/AB Reference Intake), hedefe oranlanır.
    public static func targets(for p: Profile) -> MacroTargets {
        let energy = Double(EnergyCalculator.estimate(p).target)
        let perKg: Double
        switch p.goal {
        case .lose: perKg = 1.4
        case .maintain: perKg = 1.0
        case .gain: perKg = 1.3
        }
        let protein = min(p.weightKg * perKg, energy * 0.35 / 4)
        let fiber = max(25, energy / 1000 * 14)
        let sugar = 90 * energy / 2000
        return MacroTargets(protein: Int(protein.rounded()), fiber: Int(fiber.rounded()), sugarLimit: Int(sugar.rounded()))
    }

    public static func totals(_ meals: [Meal]) -> MacroTotals {
        var t = MacroTotals()
        for p in meals.flatMap(\.portions) where p.grams > 0 {
            guard p.food.hasMacros, let pr = p.protein, let fi = p.fiber, let su = p.sugar else {
                t.unknownPortions += 1; continue
            }
            t.knownPortions += 1
            t.protein += pr; t.fiber += fi; t.sugar += su
            t.carbs += p.carbs ?? 0; t.fat += p.fat ?? 0
        }
        return t
    }

    public static let explanation = [
        "Protein: kilo verme hedefinde 1,4 g/kg, korumada 1,0 g/kg, almada 1,3 g/kg; günlük enerjinin %35'ini geçmez.",
        "Lif: her 1.000 kcal için 14 g, en az 25 g (ABD Beslenme Rehberi 2020–2025).",
        "Şeker: toplam şeker için 2.000 kcal'de 90 g referans alım (UK/AB Reference Intake) üst sınır olarak kullanılır; ekli şekeri olabildiğince az tut.",
        "Fotoğraf tahminlerinde makrolar servis yanıtında varsa sayılır; yoksa o öğe makro toplamına katılmaz ve ekranda belirtilir."
    ]
}

// MARK: - 5 · Favori ve tekrar öğünler

public struct FavoriteMeal: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var portions: [Portion]
    public var slot: MealSlot?
    public init(id: UUID = UUID(), title: String, portions: [Portion], slot: MealSlot?) {
        self.id = id; self.title = title; self.portions = portions; self.slot = slot
    }
    public var low: Int { portions.reduce(0) { $0 + $1.low } }
    public var high: Int { portions.reduce(0) { $0 + $1.high } }
}

public enum Repeats {
    /// Önceki öğünü veya favoriyi bugüne yeni kimliklerle kopyalar.
    public static func copy(portions: [Portion], title: String?, slot: MealSlot?, date: Date = Date()) -> Meal {
        Meal(date: date, portions: portions.map { Portion(food: $0.food, grams: $0.grams) },
             slot: slot, source: .repeatMeal, title: title)
    }

    public static func favorite(from meal: Meal) -> FavoriteMeal {
        FavoriteMeal(title: meal.displayTitle, portions: meal.portions, slot: meal.slot)
    }

    /// Dünkü aynı öğün (ör. "Dünkü kahvaltı"). Öğün belirtilmemiş eski kayıtlar saatine göre eşlenir.
    public static func yesterday(_ slot: MealSlot, meals: [Meal], now: Date, calendar: Calendar = .current) -> Meal? {
        guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
        return meals.filter { calendar.isDate($0.date, inSameDayAs: y) }
            .last { ($0.slot ?? inferredSlot($0.date, calendar: calendar)) == slot }
    }

    public static func inferredSlot(_ date: Date, calendar: Calendar = .current) -> MealSlot {
        switch calendar.component(.hour, from: date) {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }
}

// MARK: - 6 · Alışveriş listesi

public struct ShoppingItem: Identifiable, Equatable, Sendable {
    public var id: String { foodID }
    public let foodID: String
    public let name: String
    public let grams: Int
    public let group: String
    /// Okunabilir miktar: "1,2 kg", "350 g", "1,5 L" (süt).
    public var amountText: String {
        if foodID == "sut" { return grams >= 1000 ? TRFormat.decimal(Double(grams) / 1000) + " L" : "\(grams) ml" }
        if foodID == "yumurta" { let n = max(1, Int((Double(grams) / 50).rounded(.up))); return "\(n) adet" }
        return grams >= 1000 ? TRFormat.decimal(Double(grams) / 1000) + " kg" : "\(grams) g"
    }
}

public enum Shopping {
    /// Bugünden itibaren `days` günlük planın malzemeleri; aynı besin toplanır, 50 g'a yukarı yuvarlanır.
    public static func list(from plans: [DayPlan], db: FoodDatabase) -> [ShoppingItem] {
        var grams: [String: Int] = [:]
        for item in plans.flatMap(\.meals).flatMap(\.items) { grams[item.food.id, default: 0] += item.grams }
        let order = ["sebze", "protein", "tahil", "diger", "sos"]
        return grams.compactMap { id, g -> ShoppingItem? in
            guard let f = db.food(id) else { return nil }
            let rounded = id == "zeytinyagi" ? max(10, g) : Int((Double(g) / 50).rounded(.up)) * 50
            return ShoppingItem(foodID: id, name: f.name, grams: rounded, group: f.group)
        }.sorted {
            let a = order.firstIndex(of: $0.group) ?? 9, b = order.firstIndex(of: $1.group) ?? 9
            return a == b ? $0.name < $1.name : a < b
        }
    }

    public static func groupTitle(_ g: String) -> String {
        switch g {
        case "sebze": return "Sebze ve meyve"
        case "protein": return "Protein ve baklagil"
        case "tahil": return "Tahıl ve ekmek"
        case "sos": return "Yağ ve sos"
        default: return "Diğer"
        }
    }

    public static func shareText(_ items: [ShoppingItem], checked: Set<String>) -> String {
        "Ovis Fit alışveriş listesi\n" + items.map { (checked.contains($0.id) ? "☑︎ " : "☐ ") + "\($0.name) · \($0.amountText)" }
            .joined(separator: "\n")
    }
}

// MARK: - 8 · Seriler ve rozetler

public struct Streaks: Equatable, Sendable {
    public let logging: Int
    public let water: Int
    public let steps: Int
}

public struct Badge: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let earned: Bool
}

public enum Gamification {
    /// Bugün veya dün biten ardışık gün sayısı (bugün henüz kayıt yoksa seri bozulmaz).
    public static func streak(days: Set<String>, now: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if !days.contains(DayKey.string(for: day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(DayKey.string(for: day, calendar: calendar)) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    public static func streaks(meals: [Meal], drinks: [Drink], fluidTarget: Int?, steps: [DailyValue], stepGoal: Int,
                               now: Date, calendar: Calendar = .current) -> Streaks {
        let mealDays = Set(meals.map { DayKey.string(for: $0.date, calendar: calendar) })
        var waterByDay: [String: Int] = [:]
        for d in drinks { waterByDay[DayKey.string(for: d.date, calendar: calendar), default: 0] += d.amount }
        let waterDays = fluidTarget.map { t in Set(waterByDay.filter { $0.value >= t }.keys) } ?? []
        let stepDays = Set(steps.filter { $0.value >= stepGoal }.map { DayKey.string(for: $0.date, calendar: calendar) })
        return Streaks(logging: streak(days: mealDays, now: now, calendar: calendar),
                       water: streak(days: waterDays, now: now, calendar: calendar),
                       steps: streak(days: stepDays, now: now, calendar: calendar))
    }

    public static func badges(meals: [Meal], drinks: [Drink], weights: [WeightEntry], steps: [DailyValue],
                              activities: [ActivityRecord], streaks: Streaks, calendar: Calendar = .current) -> [Badge] {
        let weighWeeks = Set(weights.map { calendar.component(.weekOfYear, from: $0.date) * 10000 + calendar.component(.yearForWeekOfYear, from: $0.date) })
        return [
            Badge(id: "first-meal", title: "İlk tabak", detail: "İlk öğününü kaydet", symbol: "fork.knife", earned: !meals.isEmpty),
            Badge(id: "log-7", title: "7 gün seri", detail: "7 gün üst üste öğün kaydet", symbol: "flame", earned: streaks.logging >= 7),
            Badge(id: "log-30", title: "30 gün seri", detail: "30 gün üst üste öğün kaydet", symbol: "flame.fill", earned: streaks.logging >= 30),
            Badge(id: "water-5", title: "Su ustası", detail: "5 gün üst üste sıvı hedefine ulaş", symbol: "drop.fill", earned: streaks.water >= 5),
            Badge(id: "steps-10k", title: "10.000 adım", detail: "Bir günde 10.000 adım at", symbol: "shoeprints.fill", earned: steps.contains { $0.value >= 10000 }),
            Badge(id: "move-5", title: "Hareketli hafta", detail: "5 hareket tamamla", symbol: "figure.walk", earned: activities.filter { $0.minutes > 0 }.count >= 5),
            Badge(id: "barcode", title: "Etiket okuru", detail: "Bir ürünü barkodla ekle", symbol: "barcode.viewfinder", earned: meals.contains { $0.source == .barcode }),
            Badge(id: "weigh-4", title: "Düzenli tartı", detail: "4 farklı haftada tartıl", symbol: "scalemass", earned: weighWeeks.count >= 4)
        ]
    }
}

// MARK: - 1 · Hatırlatmalar

public struct ReminderSettings: Codable, Equatable, Sendable {
    public var meals = true
    public var water = true
    public var weigh = true
    /// Gün içindeki dakika.
    public var weighMinutes = 21 * 60
    public var waterStart = 10 * 60
    public var waterEnd = 20 * 60
    public var waterEveryMinutes = 120
    public init() {}
}

public struct ReminderItem: Equatable, Sendable {
    public let id: String
    public let minutes: Int
    public let title: String
    public let body: String
}

public enum Reminders {
    /// Günlük tekrarlayan yerel bildirim listesi. Hekim sıvı kısıtlaması varsa su teşviki gönderilmez.
    public static func plan(_ s: ReminderSettings, profile: Profile?, fluidRestricted: Bool) -> [ReminderItem] {
        var items: [ReminderItem] = []
        if s.meals, let p = profile {
            for slot in p.mealTimes.slots {
                items.append(ReminderItem(id: "meal.\(slot.rawValue)", minutes: p.mealTimes.minutes(for: slot),
                                          title: "\(slot.title) zamanı",
                                          body: "Tabağını kaydetmeyi unutma. Fotoğraf, barkod veya favorilerinden tek dokunuşla ekleyebilirsin."))
            }
        }
        if s.water && !fluidRestricted && s.waterEveryMinutes >= 30 {
            var m = s.waterStart
            while m <= s.waterEnd {
                items.append(ReminderItem(id: "water.\(m)", minutes: m, title: "Su molası",
                                          body: "Bir bardak su içip kaydetmeye ne dersin?"))
                m += s.waterEveryMinutes
            }
        }
        if s.weigh {
            items.append(ReminderItem(id: "weigh", minutes: s.weighMinutes, title: "Tartı zamanı",
                                      body: "Bugünkü kilonu kaydet; haftalık eğrin güncellensin. Her gün aynı saatte tartılmak karşılaştırmayı kolaylaştırır."))
        }
        return items
    }
}

// MARK: - 2 · Barkod (Open Food Facts)

public struct BarcodeProduct: Equatable, Sendable {
    public let code: String
    public let name: String
    public let brand: String?
    /// 100 g veya 100 ml için
    public let kcal: Double
    public let protein: Double?
    public let carbs: Double?
    public let fat: Double?
    public let fiber: Double?
    public let sugar: Double?
    public let servingGrams: Int?
    public let allergens: [Allergen]
    /// Etikette alerjen bilgisi hiç yoksa false: "alerjen yok" anlamına gelmez.
    public let allergenInfoKnown: Bool

    public func food(grams: Int) -> Food {
        let f = Double(grams) / 100
        func r(_ v: Double?) -> Double? { v.map { ($0 * f * 10).rounded() / 10 } }
        let k = Int((kcal * f).rounded())
        return Food(name: brand.map { "\(name) (\($0))" } ?? name, grams: grams, low: k, high: k, group: "diger",
                    protein: r(protein), carbs: r(carbs), fat: r(fat), fiber: r(fiber), sugar: r(sugar),
                    allergens: allergens)
    }

    public func conflicts(with profile: Profile?) -> [Allergen] {
        guard let profile else { return [] }
        return allergens.filter { profile.allergens.contains($0) }
    }
}

public enum OpenFoodFacts {
    public static func isValidBarcode(_ code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        return digits.count == code.count && [8, 12, 13, 14].contains(digits.count)
    }

    public static func url(for code: String) -> URL? {
        guard isValidBarcode(code) else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=code,product_name,product_name_tr,brands,nutriments,allergens_tags,serving_quantity")
    }

    static let allergenMap: [String: Allergen] = [
        "en:milk": .milk, "en:eggs": .egg, "en:gluten": .gluten, "en:nuts": .nuts,
        "en:fish": .fish, "en:soybeans": .soy
    ]

    public enum ParseError: Error, Equatable { case notFound, noEnergy, invalid }

    public static func parse(_ data: Data, code: String) throws -> BarcodeProduct {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.invalid }
        guard (root["status"] as? Int) == 1, let p = root["product"] as? [String: Any] else { throw ParseError.notFound }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        var kcal = num("energy-kcal_100g")
        if kcal == nil, let kj = num("energy_100g") { kcal = kj / 4.184 }
        guard let energy = kcal, energy >= 0, energy < 1000 else { throw ParseError.noEnergy }
        let nameTR = (p["product_name_tr"] as? String)?.trimmingCharacters(in: .whitespaces)
        let name = (nameTR?.isEmpty == false ? nameTR : (p["product_name"] as? String)?.trimmingCharacters(in: .whitespaces))
        let brand = (p["brands"] as? String)?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let tags = p["allergens_tags"] as? [String]
        let serving: Int? = {
            if let d = p["serving_quantity"] as? Double { return Int(d.rounded()) }
            if let i = p["serving_quantity"] as? Int { return i }
            if let s = p["serving_quantity"] as? String, let d = Double(s) { return Int(d.rounded()) }
            return nil
        }()
        return BarcodeProduct(code: code, name: (name?.isEmpty == false ? name! : "Ürün \(code)"),
                              brand: brand?.isEmpty == false ? brand : nil,
                              kcal: (energy * 10).rounded() / 10,
                              protein: num("proteins_100g"), carbs: num("carbohydrates_100g"), fat: num("fat_100g"),
                              fiber: num("fiber_100g"), sugar: num("sugars_100g"),
                              servingGrams: serving.flatMap { (1...2000).contains($0) ? $0 : nil },
                              allergens: Array(Set((tags ?? []).compactMap { allergenMap[$0] })).sorted { $0.rawValue < $1.rawValue },
                              allergenInfoKnown: tags != nil)
    }
}
