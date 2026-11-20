import Foundation

public enum FoodOrigin: String, Codable, Sendable {
    case plant, dairy, egg, fish, meat
}

public struct FoodItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// 100 g için
    public let kcal: Double
    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let fiber: Double
    public let sugars: Double
    public let group: String
    public let origin: FoodOrigin
    public let allergens: [Allergen]
    public let source: String
    public let sourceName: String

    public func kcal(grams: Int) -> Int { Int((kcal * Double(grams) / 100).rounded()) }

    /// Besin değeri bilinen öğeyi analiz/günlük biçimine çevirir (alt = üst).
    public func asFood(grams: Int) -> Food {
        let k = kcal(grams: grams)
        let f = Double(grams) / 100
        func r(_ v: Double) -> Double { (v * f * 10).rounded() / 10 }
        return Food(name: name, grams: grams, low: k, high: k, group: group,
                    protein: r(protein), carbs: r(carbs), fat: r(fat), fiber: r(fiber), sugar: r(sugars),
                    allergens: allergens)
    }
}

public struct Ingredient: Codable, Equatable, Sendable {
    public let food: String
    public let grams: Int
}

public struct Recipe: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let slots: [MealSlot]
    public let contexts: [MealContext]
    public let ingredients: [Ingredient]
}

public struct DataSource: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let url: String
}

public struct FoodDatabase: Codable, Sendable {
    public let version: Int
    public let note: String
    public let sources: [DataSource]
    public let foods: [FoodItem]
    public let recipes: [Recipe]

    public static func load(from data: Data) throws -> FoodDatabase {
        let db = try JSONDecoder().decode(FoodDatabase.self, from: data)
        try db.check()
        return db
    }

    public static let empty = FoodDatabase(version: 0, note: "", sources: [], foods: [], recipes: [])

    public func food(_ id: String) -> FoodItem? { foods.first { $0.id == id } }
    public func recipe(_ id: String) -> Recipe? { recipes.first { $0.id == id } }

    public struct IntegrityError: Error, CustomStringConvertible {
        public let description: String
    }

    /// Tarif malzemelerinin veritabanında olduğunu ve kimliklerin tekil olduğunu doğrular.
    public func check() throws {
        let ids = Set(foods.map(\.id))
        guard ids.count == foods.count else { throw IntegrityError(description: "Yinelenen besin kimliği") }
        guard Set(recipes.map(\.id)).count == recipes.count else { throw IntegrityError(description: "Yinelenen tarif kimliği") }
        for r in recipes {
            for i in r.ingredients where !ids.contains(i.food) || i.grams <= 0 {
                throw IntegrityError(description: "\(r.id): geçersiz malzeme \(i.food)")
            }
        }
    }

    public func allergens(of recipe: Recipe) -> Set<Allergen> {
        Set(recipe.ingredients.compactMap { food($0.food) }.flatMap(\.allergens))
    }

    public func isSuitable(_ recipe: Recipe, for profile: Profile) -> Bool {
        let items = recipe.ingredients.compactMap { food($0.food) }
        guard items.count == recipe.ingredients.count else { return false }
        return items.allSatisfy { item in
            profile.diet.allows(item.origin) && profile.allergens.isDisjoint(with: item.allergens)
        }
    }

    public func isSuitable(_ item: FoodItem, for profile: Profile) -> Bool {
        profile.diet.allows(item.origin) && profile.allergens.isDisjoint(with: item.allergens)
    }
}

// MARK: - Plan

public struct PlannedItem: Equatable, Sendable {
    public let food: FoodItem
    public let grams: Int
    public var kcal: Int { food.kcal(grams: grams) }
}

public struct PlannedMeal: Identifiable, Equatable, Sendable {
    public var id: String { slot.rawValue + ":" + recipe.id }
    public let slot: MealSlot
    public let minutes: Int
    public let recipe: Recipe
    public let scale: Double
    public let items: [PlannedItem]
    public let allergens: Set<Allergen>

    public var kcal: Int { items.reduce(0) { $0 + $1.kcal } }
    public var protein: Double { items.reduce(0) { $0 + $1.food.protein * Double($1.grams) / 100 } }
    public var carbs: Double { items.reduce(0) { $0 + $1.food.carbs * Double($1.grams) / 100 } }
    public var fat: Double { items.reduce(0) { $0 + $1.food.fat * Double($1.grams) / 100 } }
    public var fiber: Double { items.reduce(0) { $0 + $1.food.fiber * Double($1.grams) / 100 } }
    public var sugars: Double { items.reduce(0) { $0 + $1.food.sugars * Double($1.grams) / 100 } }
    public var timeLabel: String { MealTimes.label(minutes) }

    /// Günlüğe "yedim" olarak yazılacak porsiyonlar.
    public var portions: [Portion] {
        items.map { Portion(food: $0.food.asFood(grams: $0.grams), grams: $0.grams) }
    }
}

public struct DayPlan: Equatable, Sendable {
    public let target: Int
    public let meals: [PlannedMeal]
    /// Tercihlere uygun tarif bulunamayan öğünler.
    public let missing: [MealSlot]
    public var plannedKcal: Int { meals.reduce(0) { $0 + $1.kcal } }
}

public enum Planner {
    public static func shares(includeSnack: Bool) -> [MealSlot: Double] {
        includeSnack
            ? [.breakfast: 0.25, .lunch: 0.35, .snack: 0.10, .dinner: 0.30]
            : [.breakfast: 0.30, .lunch: 0.40, .dinner: 0.30]
    }

    public static let scaleRange = 0.5...2.0

    static func roundGrams(_ g: Double) -> Int {
        if g < 20 { return max(1, Int(g.rounded())) }
        return max(5, Int((g / 5).rounded()) * 5)
    }

    /// Tarifi öğün payına ölçekler; miktarlar ve enerji birlikte değişir.
    public static func scaled(_ recipe: Recipe, slot: MealSlot, minutes: Int, targetKcal: Double,
                              db: FoodDatabase) -> PlannedMeal {
        let base = recipe.ingredients.reduce(0.0) { sum, i in
            sum + (db.food(i.food)?.kcal ?? 0) * Double(i.grams) / 100
        }
        var scale = base > 0 ? targetKcal / base : 1
        scale = min(max(scale, scaleRange.lowerBound), scaleRange.upperBound)
        scale = (scale * 20).rounded() / 20
        let items = recipe.ingredients.compactMap { i -> PlannedItem? in
            guard let f = db.food(i.food) else { return nil }
            return PlannedItem(food: f, grams: roundGrams(Double(i.grams) * scale))
        }
        return PlannedMeal(slot: slot, minutes: minutes, recipe: recipe, scale: scale,
                           items: items, allergens: db.allergens(of: recipe))
    }

    public static func candidates(for slot: MealSlot, profile: Profile, db: FoodDatabase,
                                  context: MealContext? = nil) -> [Recipe] {
        db.recipes.filter { r in
            r.slots.contains(slot) && db.isSuitable(r, for: profile) &&
            (context == nil || r.contexts.contains(context!))
        }
    }

    static func dayIndex(_ date: Date, calendar: Calendar) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// - Parameter overrides: Kullanıcının "Planım değişti" ile seçtiği tarif kimlikleri.
    public static func plan(for date: Date, profile: Profile, target: Int, db: FoodDatabase,
                            overrides: [MealSlot: String] = [:], calendar: Calendar = .current) -> DayPlan {
        let shares = shares(includeSnack: profile.mealTimes.includeSnack)
        var used = Set<String>()
        var meals: [PlannedMeal] = []
        var missing: [MealSlot] = []
        let day = dayIndex(date, calendar: calendar)
        for slot in profile.mealTimes.slots {
            let pool = candidates(for: slot, profile: profile, db: db)
            var chosen: Recipe?
            if let id = overrides[slot], let r = db.recipe(id), db.isSuitable(r, for: profile) {
                chosen = r
            } else if !pool.isEmpty {
                let fresh = pool.filter { !used.contains($0.id) }
                let list = fresh.isEmpty ? pool : fresh
                chosen = list[(day + slot.order) % list.count]
            }
            guard let recipe = chosen else { missing.append(slot); continue }
            used.insert(recipe.id)
            meals.append(scaled(recipe, slot: slot, minutes: profile.mealTimes.minutes(for: slot),
                                targetKcal: Double(target) * (shares[slot] ?? 0), db: db))
        }
        return DayPlan(target: target, meals: meals, missing: missing)
    }

    /// "Planım değişti" için bağlama, tercihlere ve alerjilere uygun 2–3 alternatif.
    public static func alternatives(slot: MealSlot, context: MealContext, profile: Profile, target: Int,
                                    db: FoodDatabase, excluding current: String?) -> [PlannedMeal] {
        let share = shares(includeSnack: profile.mealTimes.includeSnack)[slot] ?? 0.35
        var pool = candidates(for: slot, profile: profile, db: db, context: context)
            .filter { $0.id != current }
        if pool.count < 2 {
            // Bağlama uyan yeterli tarif yoksa aynı öğüne uygun diğer tariflerle tamamla.
            let extra = candidates(for: slot, profile: profile, db: db)
                .filter { $0.id != current && !pool.map(\.id).contains($0.id) }
            pool += extra
        }
        return pool.prefix(3).map {
            scaled($0, slot: slot, minutes: profile.mealTimes.minutes(for: slot),
                   targetKcal: Double(target) * share, db: db)
        }
    }
}
