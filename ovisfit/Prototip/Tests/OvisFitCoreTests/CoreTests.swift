import XCTest
@testable import OvisFitCore

func loadDB() throws -> FoodDatabase {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("iOS/Resources/foods.json")
    return try FoodDatabase.load(from: Data(contentsOf: url))
}

func sampleProfile(goal: Goal = .maintain) -> Profile {
    Profile(name: "Deniz", age: 35, heightCm: 175, weightKg: 75, sex: .female, activity: .moderate, goal: goal)
}

var istanbul: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return c
}()

func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.calendar = istanbul; f.timeZone = istanbul.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

final class ProfileTests: XCTestCase {
    func testDecimalCommaAndUnits() {
        XCTAssertEqual(NumberInput.parse("75,5")?.value, 75.5)
        XCTAssertEqual(NumberInput.parse(" 75.5 kg ")?.unit, "kg")
        XCTAssertNil(NumberInput.parse("7,5,5"))
        XCTAssertNil(NumberInput.parse("abc"))
        XCTAssertNil(NumberInput.parse(""))
        XCTAssertNil(NumberInput.parse(",5"))
    }

    func testValidProfile() throws {
        var d = ProfileDraft()
        d.name = "  Deniz "; d.age = "35"; d.height = "1,75 m"; d.weight = "72,5 kg"
        let v = try d.validate().get()
        XCTAssertEqual(v, .init(name: "Deniz", age: 35, heightCm: 175, weightKg: 72.5))
        d.height = "1,75"
        XCTAssertEqual(try d.validate().get().heightCm, 175)
    }

    func testInvalidProfileFields() {
        var d = ProfileDraft()
        d.name = ""; d.age = "16"; d.height = "175 in"; d.weight = "500"
        guard case .failure(let e) = d.validate() else { return XCTFail() }
        XCTAssertEqual(Set(e.fields.keys), [.name, .age, .height, .weight])
        XCTAssertTrue(e.fields[.age]!.contains("yetişkin"))
        d = ProfileDraft(); d.name = "A"; d.age = "35,5"; d.height = "170"; d.weight = "70"
        guard case .failure(let e2) = d.validate() else { return XCTFail() }
        XCTAssertEqual(Set(e2.fields.keys), [.age])
    }

    func testDraftRoundTripsProfile() throws {
        var p = sampleProfile(); p.weightKg = 72.5
        let v = try ProfileDraft(profile: p).validate().get()
        XCTAssertEqual(v.weightKg, 72.5); XCTAssertEqual(v.heightCm, 175)
    }
}

final class EnergyTests: XCTestCase {
    func testMifflinStJeor() {
        // 10*75 + 6.25*175 - 5*35 = 1668.75
        XCTAssertEqual(EnergyCalculator.resting(weightKg: 75, heightCm: 175, age: 35, sex: .male), 1673.75, accuracy: 0.01)
        XCTAssertEqual(EnergyCalculator.resting(weightKg: 75, heightCm: 175, age: 35, sex: .female), 1507.75, accuracy: 0.01)
        XCTAssertEqual(EnergyCalculator.resting(weightKg: 75, heightCm: 175, age: 35, sex: .unspecified), 1590.75, accuracy: 0.01)
    }

    func testThreeGoalsDiffer() {
        let lose = EnergyCalculator.estimate(sampleProfile(goal: .lose))
        let keep = EnergyCalculator.estimate(sampleProfile(goal: .maintain))
        let gain = EnergyCalculator.estimate(sampleProfile(goal: .gain))
        // 1507.75 * 1.55 = 2337 → 2350
        XCTAssertEqual(keep.target, 2350)
        XCTAssertEqual(lose.target, 1850)
        XCTAssertEqual(gain.target, 2650)
        XCTAssertTrue(lose.target % 50 == 0 && gain.target % 50 == 0)
    }

    func testLoseFloor() {
        var p = Profile(name: "A", age: 70, heightCm: 150, weightKg: 45, sex: .female, activity: .low, goal: .lose)
        let e = EnergyCalculator.estimate(p)
        XCTAssertTrue(e.floorApplied)
        XCTAssertEqual(e.target, 1200)
        p.manualTarget = 1600
        XCTAssertEqual(EnergyCalculator.estimate(p).target, 1600)
        XCTAssertTrue(EnergyCalculator.estimate(p).isManual)
        p.manualTarget = 200   // aralık dışı: yok sayılır
        XCTAssertFalse(EnergyCalculator.estimate(p).isManual)
    }
}

final class PlanTests: XCTestCase {
    func testDatabaseIntegrityAndMacroConsistency() throws {
        let db = try loadDB()
        for f in db.foods {
            let fromMacros = f.protein * 4 + f.carbs * 4 + f.fat * 9
            XCTAssertLessThanOrEqual(abs(fromMacros - f.kcal), max(10, f.kcal * 0.15), f.id)
        }
        for slot in MealSlot.allCases { XCTAssertFalse(Planner.candidates(for: slot, profile: sampleProfile(), db: db).isEmpty) }
    }

    func testPlanScalesToTargetAndQuantitiesFollow() throws {
        let db = try loadDB()
        let p = sampleProfile()
        let small = Planner.plan(for: date("2026-11-20 09:00"), profile: p, target: 1600, db: db, calendar: istanbul)
        let large = Planner.plan(for: date("2026-11-20 09:00"), profile: p, target: 2600, db: db, calendar: istanbul)
        XCTAssertEqual(small.meals.map(\.recipe.id), large.meals.map(\.recipe.id))
        XCTAssertEqual(small.meals.count, 4)
        XCTAssertEqual(Double(small.plannedKcal), 1600, accuracy: 1600 * 0.12)
        XCTAssertEqual(Double(large.plannedKcal), 2600, accuracy: 2600 * 0.12)
        let lunchSmall = small.meals.first { $0.slot == .lunch }!
        let lunchLarge = large.meals.first { $0.slot == .lunch }!
        XCTAssertGreaterThan(lunchLarge.items[0].grams, lunchSmall.items[0].grams)
        XCTAssertEqual(Set(small.meals.map(\.recipe.id)).count, small.meals.count, "aynı tarif bir günde iki kez")
    }

    func testAllergyAndDietFilter() throws {
        let db = try loadDB()
        var p = sampleProfile()
        p.allergens = [.milk]
        let plan = Planner.plan(for: Date(), profile: p, target: 2000, db: db)
        XCTAssertTrue(plan.meals.allSatisfy { !$0.allergens.contains(.milk) })
        p.diet = .vegan; p.allergens = []
        let vegan = Planner.plan(for: Date(), profile: p, target: 2000, db: db)
        XCTAssertTrue(vegan.meals.flatMap(\.items).allSatisfy { $0.food.origin == .plant })
        p.allergens = Set(Allergen.allCases)
        let none = Planner.plan(for: Date(), profile: p, target: 2000, db: db)
        XCTAssertFalse(none.missing.isEmpty, "uygun tarif yoksa eksik öğün bildirilmeli")
    }

    func testAlternativesByContextDoNotTouchDiary() throws {
        let db = try loadDB()
        let repo = Repository(store: MemoryStore())
        let p = sampleProfile()
        for ctx in MealContext.allCases {
            let alts = Planner.alternatives(slot: .lunch, context: ctx, profile: p, target: 2100, db: db, excluding: "tavuk-bulgur")
            XCTAssertTrue((2...3).contains(alts.count), ctx.rawValue)
            XCTAssertFalse(alts.contains { $0.recipe.id == "tavuk-bulgur" })
        }
        var milk = p; milk.allergens = [.milk]
        let alts = Planner.alternatives(slot: .lunch, context: .quick, profile: milk, target: 2100, db: db, excluding: nil)
        XCTAssertTrue(alts.allSatisfy { !$0.allergens.contains(.milk) })
        XCTAssertTrue(repo.meals.isEmpty)
    }

    func testOverrideReplacesPlannedLunch() throws {
        let db = try loadDB()
        let plan = Planner.plan(for: Date(), profile: sampleProfile(), target: 2100, db: db, overrides: [.lunch: "ton-sandvic"])
        XCTAssertEqual(plan.meals.first { $0.slot == .lunch }?.recipe.id, "ton-sandvic")
    }
}

final class PlateTests: XCTestCase {
    func testSampleMatchesDesignAndPortionChangesTotals() {
        var d = PlateDraft(response: PlateAdvisor.sampleResponse())
        XCTAssertEqual(d.low, 430); XCTAssertEqual(d.high, 560)
        XCTAssertTrue(d.isSample)
        let rice = d.portions[1]
        d.setGrams(rice.id, 125)
        XCTAssertEqual(d.portions[1].low, 150); XCTAssertEqual(d.portions[1].high, 217)
        XCTAssertLessThan(d.low, 430); XCTAssertLessThan(d.high, 560)
        d.oilGrams = 5
        XCTAssertEqual(d.low, 210 + 150 + 40 + 44)
        d.remove(rice.id)
        XCTAssertEqual(d.portions.count, 2)
        d.setGrams(d.portions[0].id, 99999)
        XCTAssertEqual(d.portions[0].grams, PlateDraft.maxGrams)
    }

    func testSuggestionRespectsAllergyAndPreviewDoesNotMutate() throws {
        let db = try loadDB()
        let d = PlateDraft(response: PlateAdvisor.sampleResponse())
        let s = PlateAdvisor.suggestion(for: d, profile: sampleProfile(), db: db)
        XCTAssertEqual(s?.actionTitle, "Yoğurt ekle · 80 g")
        var milk = sampleProfile(); milk.allergens = [.milk]
        let s2 = PlateAdvisor.suggestion(for: d, profile: milk, db: db)
        XCTAssertFalse(s2?.actionTitle.contains("Yoğurt") ?? false)
        var vegan = sampleProfile(); vegan.diet = .vegan
        XCTAssertFalse(PlateAdvisor.suggestion(for: d, profile: vegan, db: db)?.actionTitle.contains("Yoğurt") ?? false)

        let preview = d.totals(applying: s!)
        XCTAssertEqual(preview.low, 430 + 49)
        XCTAssertEqual(d.low, 430, "önizleme taslağı değiştirmemeli")

        let lose = PlateAdvisor.suggestion(for: d, profile: sampleProfile(goal: .lose), db: db)!
        var applied = d; applied.apply(lose)
        XCTAssertLessThan(applied.high, d.high)
        let gain = PlateAdvisor.suggestion(for: d, profile: sampleProfile(goal: .gain), db: db)!
        applied = d; applied.apply(gain)
        XCTAssertGreaterThan(applied.high, d.high)
    }

    func testDemoLabelAndErrors() throws {
        let json = #"{"foods":[{"name":"Pilav","grams":150,"low":180,"high":260,"group":"tahil"}],"mode":"demo"}"#
        let r = try JSONDecoder().decode(PlateResponse.self, from: Data(json.utf8))
        XCTAssertTrue(r.isDemo)
        let live = try JSONDecoder().decode(PlateResponse.self, from: Data(#"{"foods":[]}"#.utf8))
        XCTAssertFalse(live.isDemo)
        XCTAssertTrue(PlateDraft(response: live).isEmpty)
        XCTAssertEqual(PlateServiceError.from(status: 503), .notConfigured)
        XCTAssertEqual(PlateServiceError.from(status: 429), .rateLimited)
        XCTAssertNil(PlateServiceError.from(status: 200))
        XCTAssertEqual(PlateServiceError.from(urlErrorCode: -1009), .offline)
        XCTAssertEqual(PlateServiceError.from(urlErrorCode: -1004), .unreachable)
        XCTAssertEqual(PlateServiceError.from(urlErrorCode: -999), .cancelled)
    }

    func testServerAddress() {
        XCTAssertNotNil(ServerAddress.validate("https://api.example.com", allowInsecureLocal: false))
        XCTAssertNil(ServerAddress.validate("http://api.example.com", allowInsecureLocal: true))
        XCTAssertNotNil(ServerAddress.validate("http://127.0.0.1:8787", allowInsecureLocal: true))
        XCTAssertNil(ServerAddress.validate("http://127.0.0.1:8787", allowInsecureLocal: false))
        XCTAssertNotNil(ServerAddress.validate("http://Murats-MacBook.local:8787", allowInsecureLocal: true))
        XCTAssertNotNil(ServerAddress.validate("http://192.168.1.20:8787", allowInsecureLocal: true))
        XCTAssertNotNil(ServerAddress.validate("http://172.20.0.5:8787", allowInsecureLocal: true))
        XCTAssertNil(ServerAddress.validate("http://172.40.0.5:8787", allowInsecureLocal: true))
        XCTAssertNil(ServerAddress.validate("http://8.8.8.8:8787", allowInsecureLocal: true))
        XCTAssertNil(ServerAddress.validate("http://192.168.1.20:8787", allowInsecureLocal: false))
        XCTAssertEqual(ServerAddress.plateEndpoint(base: URL(string: "https://a.b/api")!).absoluteString, "https://a.b/api/plate")
    }
}

final class StorageTests: XCTestCase {
    /// Prototipin of.meals.v1 biçimi (Date: referans tarihinden saniye).
    let legacyMeals = """
    [{"id":"0E0B1F9C-6E43-4C4C-9E1E-1A2B3C4D5E6F","date":785000000,"portions":[
      {"id":"6D9C4E1A-1111-4C4C-9E1E-1A2B3C4D5E6F","food":{"name":"Pilav","grams":150,"low":180,"high":260,"group":"tahil"},"grams":150},
      {"id":"6D9C4E1A-2222-4C4C-9E1E-1A2B3C4D5E6F","food":{"name":"Yanlış","grams":80,"low":10,"high":20,"group":"diger"},"grams":0}]},
     {"id":"0E0B1F9C-6E43-4C4C-9E1E-1A2B3C4D5E6F","date":785000000,"portions":[]},
     {"bozuk":true},
     {"id":"1E0B1F9C-6E43-4C4C-9E1E-1A2B3C4D5E6F","date":785000100,"portions":[
      {"id":"6D9C4E1A-3333-4C4C-9E1E-1A2B3C4D5E6F","food":{"name":"Salata","grams":80,"low":40,"high":50,"group":"sebze"},"grams":0}]}]
    """
    let legacyDrinks = """
    [{"id":"2E0B1F9C-6E43-4C4C-9E1E-1A2B3C4D5E6F","date":785000000,"amount":250,"kind":"Su"},
     {"id":"3E0B1F9C-6E43-4C4C-9E1E-1A2B3C4D5E6F","date":785000010,"amount":150,"kind":"Diğer içecek"}]
    """

    func testMigrationIsSafeAndIdempotent() {
        let store = MemoryStore()
        store.set(Data(legacyMeals.utf8), forKey: StoreKey.meals)
        store.set(Data(legacyDrinks.utf8), forKey: StoreKey.drinks)
        store.set(5000, forKey: StoreKey.fluidTarget)
        store.set("Kilo vermek", forKey: StoreKey.legacyGoal)
        let repo = Repository(store: store)
        repo.migrate()
        XCTAssertEqual(repo.meals.count, 1)
        XCTAssertEqual(repo.meals[0].portions.count, 1)
        XCTAssertNil(repo.meals[0].slot)
        XCTAssertEqual(repo.drinks.count, 2)
        XCTAssertEqual(repo.fluidTarget, 2000)
        XCTAssertEqual(repo.legacyGoal, .lose)
        XCTAssertEqual(store.data(forKey: StoreKey.mealsBackup), Data(legacyMeals.utf8))
        let first = store.data(forKey: StoreKey.meals)
        repo.migrate()
        XCTAssertEqual(store.data(forKey: StoreKey.meals), first)
        XCTAssertEqual(store.data(forKey: StoreKey.mealsBackup), Data(legacyMeals.utf8))
        XCTAssertEqual(store.object(forKey: StoreKey.schema) as? Int, 2)
    }

    func testEmptyFirstRunWritesNoSampleData() {
        let store = MemoryStore()
        let repo = Repository(store: store)
        repo.migrate()
        XCTAssertNil(store.data(forKey: StoreKey.meals))
        XCTAssertNil(store.data(forKey: StoreKey.drinks))
        XCTAssertTrue(repo.meals.isEmpty)
        XCTAssertNil(repo.profile)
    }

    func testDuplicateMealSaveIsRejectedAndProfilePersists() {
        let store = MemoryStore()
        let repo = Repository(store: store)
        let meal = Meal(portions: [Portion(food: Food(name: "Pilav", grams: 150, low: 180, high: 260, group: "tahil"), grams: 150)],
                        slot: .lunch, source: .photo)
        XCTAssertTrue(repo.addMeal(meal))
        XCTAssertFalse(repo.addMeal(meal))
        XCTAssertFalse(repo.addMeal(Meal(portions: [])))
        XCTAssertEqual(repo.meals.count, 1)
        repo.saveProfile(sampleProfile(goal: .gain))
        // "yeniden açılış": aynı depodan yeni bir Repository
        let reopened = Repository(store: store)
        XCTAssertEqual(reopened.profile?.goal, .gain)
        XCTAssertEqual(reopened.meals.first?.source, .photo)
    }

    func testOldAppCanStillReadNewMeals() throws {
        // Yeni alanlar eklenmiş kayıt, prototipteki şemayla da çözümlenebilmeli.
        struct OldMeal: Decodable { let id: UUID; let date: Date; let portions: [Portion] }
        let data = try JSONEncoder().encode([Meal(portions: [Portion(food: Food(name: "A", grams: 10, low: 1, high: 2, group: "diger"), grams: 10)], slot: .dinner, source: .plan, title: "x")])
        XCTAssertEqual(try JSONDecoder().decode([OldMeal].self, from: data).count, 1)
    }
}

final class TrackingTests: XCTestCase {
    func testDailySummaryUsesMidpoint() {
        let day = date("2026-11-20 12:00")
        let m1 = Meal(date: date("2026-11-20 08:30"), portions: [Portion(food: Food(name: "A", grams: 100, low: 400, high: 500, group: "tahil"), grams: 100)])
        let m2 = Meal(date: date("2026-11-19 20:00"), portions: [Portion(food: Food(name: "B", grams: 100, low: 900, high: 900, group: "tahil"), grams: 100)])
        let s = DaySummary.of([m1, m2], on: day, calendar: istanbul)
        XCTAssertEqual(s.meals.count, 1)
        XCTAssertEqual(s.estimate, 450)
        XCTAssertEqual(s.percent(of: 2100), 21)
        XCTAssertEqual(s.remaining(to: 2100), 1650)
        XCTAssertEqual(DaySummary.of([], on: day).estimate, 0)
    }

    func testHydration() {
        let day = date("2026-11-20 12:00")
        var drinks = [Drink(date: date("2026-11-19 10:00"), amount: 500, kind: DrinkKind.water)]
        drinks.append(Drink(date: date("2026-11-20 09:00"), amount: 1000, kind: DrinkKind.water))
        drinks.append(Drink(date: date("2026-11-20 10:00"), amount: 250, kind: DrinkKind.other))
        let s = Hydration.summary(drinks, on: day, target: 1750, restricted: false, calendar: istanbul)
        XCTAssertEqual(s.water, 1000); XCTAssertEqual(s.other, 250); XCTAssertEqual(s.total, 1250)
        XCTAssertEqual(s.remaining, 500)
        let r = Hydration.summary(drinks, on: day, target: 1750, restricted: true, calendar: istanbul)
        XCTAssertNil(r.target); XCTAssertNil(r.remaining); XCTAssertEqual(r.total, 1250)
        let undone = Hydration.undoLast(drinks, on: day, calendar: istanbul)
        XCTAssertEqual(Hydration.summary(undone, on: day, target: 1750, restricted: false, calendar: istanbul).total, 1000)
        XCTAssertEqual(undone.count, 2)
        XCTAssertEqual(Hydration.clampTarget(1234), 1500)
        XCTAssertEqual(Hydration.clampTarget(1777), 1750)
    }

    func testMovementOptionsAndSingleCompletion() {
        let free = MovementPlanner.options(minutes: 20, equipment: [], limits: [])
        XCTAssertEqual(free.map(\.id), ["walk", "rest"])
        XCTAssertTrue(free.allSatisfy { $0.steps.reduce(0) { $0 + $1.minutes } == 20 })
        let limited = MovementPlanner.options(minutes: 10, equipment: [.chair, .mat, .band], limits: [.standing, .back, .balance])
        XCTAssertEqual(limited.map(\.id), ["chair", "rest"])
        let day = date("2026-11-20 18:00")
        let once = MovementPlanner.record(free[0], on: day, existing: [], calendar: istanbul)!
        XCTAssertNil(MovementPlanner.record(free[0], on: date("2026-11-20 19:00"), existing: once, calendar: istanbul))
        XCTAssertEqual(MovementPlanner.record(free[0], on: date("2026-11-21 08:00"), existing: once, calendar: istanbul)?.count, 2)
    }

    func testWeeklyReportStates() {
        let day = date("2026-11-20 12:00")
        XCTAssertEqual(ProgressReport.report(for: day, weights: [], meals: [], activities: [], calendar: istanbul).state, .empty)
        var w = ProgressReport.addWeight(75.04, on: date("2026-11-17 08:00"), to: [], calendar: istanbul)
        let single = ProgressReport.report(for: day, weights: w, meals: [], activities: [], calendar: istanbul)
        XCTAssertEqual(single.state, .single); XCTAssertNil(single.change); XCTAssertEqual(single.latest?.kg, 75.0)
        w = ProgressReport.addWeight(74.6, on: date("2026-11-20 08:00"), to: w, calendar: istanbul)
        w = ProgressReport.addWeight(74.5, on: date("2026-11-20 21:00"), to: w, calendar: istanbul) // aynı gün: yerine geçer
        w = ProgressReport.addWeight(80, on: date("2026-11-10 08:00"), to: w, calendar: istanbul)   // önceki hafta
        let meals = [Meal(date: date("2026-11-18 13:00"), portions: [Portion(food: Food(name: "A", grams: 1, low: 1, high: 1, group: "diger"), grams: 1)]),
                     Meal(date: date("2026-11-18 19:00"), portions: [Portion(food: Food(name: "A", grams: 1, low: 1, high: 1, group: "diger"), grams: 1)])]
        let acts = [ActivityRecord(date: date("2026-11-19 18:00"), optionID: "walk", title: "Yürüyüş", minutes: 20),
                    ActivityRecord(date: date("2026-11-20 18:00"), optionID: "rest", title: "Dinlenme", minutes: 0)]
        let r = ProgressReport.report(for: day, weights: w, meals: meals, activities: acts, calendar: istanbul)
        XCTAssertEqual(r.state, .trend)
        XCTAssertEqual(r.weights.count, 2)
        XCTAssertEqual(r.change, -0.5)
        XCTAssertEqual(r.mealCount, 2); XCTAssertEqual(r.mealDays, 1)
        XCTAssertEqual(r.activityCount, 1); XCTAssertEqual(r.activityMinutes, 20)
        XCTAssertEqual(DayKey.string(for: r.start, calendar: istanbul), "2026-11-16")
    }

    func testFormatting() {
        XCTAssertEqual(TRFormat.int(1240), "1.240")
        XCTAssertEqual(TRFormat.int(860), "860")
        XCTAssertEqual(TRFormat.int(1234567), "1.234.567")
        XCTAssertEqual(TRFormat.decimal(75), "75,0")
        XCTAssertEqual(TRFormat.range(430, 560), "430–560")
    }

    func testNextMeal() throws {
        let db = try loadDB()
        let plan = Planner.plan(for: date("2026-11-20 09:00"), profile: sampleProfile(), target: 2100, db: db, calendar: istanbul)
        XCTAssertEqual(NextMeal.find(in: plan, loggedSlots: [], now: date("2026-11-20 10:00"), calendar: istanbul)?.slot, .lunch)
        XCTAssertEqual(NextMeal.find(in: plan, loggedSlots: [.lunch], now: date("2026-11-20 12:00"), calendar: istanbul)?.slot, .snack)
        XCTAssertNil(NextMeal.find(in: plan, loggedSlots: [], now: date("2026-11-20 23:00"), calendar: istanbul))
    }
}

final class SuggestionRepeatTests: XCTestCase {
    func testAppliedAddIsNotSuggestedAgain() throws {
        let db = try loadDB()
        var d = PlateDraft(response: PlateAdvisor.sampleResponse())
        let s = PlateAdvisor.suggestion(for: d, profile: sampleProfile(), db: db)!
        d.apply(s)
        XCTAssertEqual(d.portions.count, 4)
        let next = PlateAdvisor.suggestion(for: d, profile: sampleProfile(), db: db)
        XCTAssertNotEqual(next?.actionTitle, s.actionTitle)
    }
}

final class ActivityBalanceTests: XCTestCase {
    func testSystemTargets() {
        let keep = Targets.daily(for: sampleProfile())
        XCTAssertEqual(keep.steps, 8000); XCTAssertEqual(keep.activeKcal, 400)
        XCTAssertEqual(keep.intakeKcal, 2350)
        XCTAssertEqual(keep.totalBurnKcal, 1508 + 400)
        let lose = Targets.daily(for: sampleProfile(goal: .lose))
        XCTAssertEqual(lose.steps, 9000); XCTAssertEqual(lose.activeKcal, 500)
        var knee = sampleProfile(); knee.limits = [.knee]
        XCTAssertEqual(Targets.daily(for: knee).steps, 5000)
        var old = sampleProfile(); old.age = 70; old.activity = .high
        XCTAssertEqual(Targets.daily(for: old).steps, 7000)
    }

    func testActiveEnergySources() {
        let day = date("2026-11-20 18:00")
        let steps = [DailyValue(date: date("2026-11-20 00:00"), value: 8000)]
        let walk = ActivityRecord(date: day, optionID: "walk", title: "Yürüyüş", minutes: 20)
        let band = ActivityRecord(date: day, optionID: "band", title: "Bant", minutes: 20)
        // 8000 × 75 × 0.0005 = 300; yürüyüş adımlarda sayılı; bant: 2.5 × 75 × 1/3 = 62.5 → 63
        let est = ActivityEnergy.active(on: day, steps: steps, healthActive: [], activities: [walk, band], weightKg: 75, calendar: istanbul)
        XCTAssertEqual(est.kcal, 363); XCTAssertEqual(est.source, .estimate)
        // Adım yoksa yürüyüş MET'ten: 2.5 × 75 × 1/3 = 63
        XCTAssertEqual(ActivityEnergy.active(on: day, steps: [], healthActive: [], activities: [walk], weightKg: 75, calendar: istanbul).kcal, 63)
        let measured = ActivityEnergy.active(on: day, steps: steps, healthActive: [DailyValue(date: day, value: 520)], activities: [walk], weightKg: 75, calendar: istanbul)
        XCTAssertEqual(measured.kcal, 520); XCTAssertEqual(measured.source, .health)
        XCTAssertEqual(ActivityEnergy.active(on: day, steps: [], healthActive: [], activities: [], weightKg: 75, calendar: istanbul).source, .none)
    }

    func testDailyBalanceAndKg() {
        let p = sampleProfile()   // dinlenme 1508
        let meal = Meal(date: date("2026-11-20 13:00"), portions: [Portion(food: Food(name: "A", grams: 100, low: 1500, high: 1700, group: "diger"), grams: 100)])
        let steps = [DailyValue(date: date("2026-11-20 00:00"), value: 8000)]
        let b = EnergyBalance.day(date("2026-11-20 20:00"), profile: p, meals: [meal], steps: steps, healthActive: [], activities: [], calendar: istanbul)
        XCTAssertEqual(b.intake, 1600); XCTAssertEqual(b.resting, 1508); XCTAssertEqual(b.active, 300)
        XCTAssertEqual(b.burned, 1808); XCTAssertEqual(b.balance, -208)
        XCTAssertEqual(b.kgChange, -0.027, accuracy: 0.0005)
        XCTAssertEqual(EnergyBalance.describe(b.kgChange), "≈ 27 g verme yönünde")
        XCTAssertEqual(EnergyBalance.describe(0.004), "≈ değişim yok")
        XCTAssertEqual(EnergyBalance.describe(1.2), "≈ 1,20 kg alma yönünde")
    }

    func testWeekCountsOnlyDaysWithMeals() {
        let p = sampleProfile()
        let meal = Meal(date: date("2026-11-18 13:00"), portions: [Portion(food: Food(name: "A", grams: 100, low: 2000, high: 2000, group: "diger"), grams: 100)])
        let w = EnergyBalance.week(containing: date("2026-11-20 12:00"), profile: p, meals: [meal], steps: [], healthActive: [], activities: [], calendar: istanbul)
        XCTAssertEqual(w.days.count, 5)            // Pzt–Cum
        XCTAssertEqual(w.counted.count, 1)
        XCTAssertEqual(w.balance, 2000 - 1508)
    }

    func testStepWeekAndMerge() {
        let now = date("2026-11-20 12:00")
        let old = [DailyValue(date: date("2026-11-17 00:00"), value: 5000), DailyValue(date: date("2026-11-20 00:00"), value: 1000)]
        let new = [DailyValue(date: date("2026-11-20 00:00"), value: 9000), DailyValue(date: date("2026-08-01 00:00"), value: 1)]
        let merged = DailyValues.merge(old, new, now: now, calendar: istanbul)
        XCTAssertEqual(merged.map(\.value), [5000, 9000])
        let w = StepWeek.of(now, steps: merged, goal: 8000, calendar: istanbul)
        XCTAssertEqual(w.days.count, 7); XCTAssertEqual(w.elapsedDays, 5)
        XCTAssertEqual(w.total, 14000); XCTAssertEqual(w.average, 2800); XCTAssertEqual(w.goalDays, 1)
    }
}

final class FeatureTests: XCTestCase {
    func testMacroTargetsAndTotals() throws {
        let t = Macros.targets(for: sampleProfile(goal: .lose))   // 1850 kcal, 75 kg
        XCTAssertEqual(t.protein, 105)                              // 75 × 1.4
        XCTAssertEqual(t.fiber, 26)                                 // 1850/1000×14 = 25.9
        XCTAssertEqual(t.sugarLimit, 83)                            // 90 × 1850/2000
        let db = try loadDB()
        let plan = Planner.plan(for: Date(), profile: sampleProfile(), target: 2100, db: db)
        let lunch = plan.meals.first { $0.slot == .lunch }!
        let photo = Meal(portions: [Portion(food: Food(name: "Pilav", grams: 150, low: 180, high: 260, group: "tahil"), grams: 150)])
        let planned = Meal(portions: lunch.portions)
        let totals = Macros.totals([planned, photo])
        XCTAssertEqual(totals.unknownPortions, 1)
        XCTAssertEqual(totals.knownPortions, lunch.items.count)
        XCTAssertEqual(totals.protein, lunch.protein, accuracy: 0.5)
        XCTAssertEqual(totals.fiber, lunch.fiber, accuracy: 0.5)
        // Porsiyon yarıya inince makrolar da yarıya iner
        var half = lunch.portions[0]; let full = half.protein!
        half.grams = half.grams / 2
        XCTAssertEqual(half.protein!, full / 2, accuracy: 0.6)
    }

    func testFavoritesAndYesterday() {
        let now = date("2026-11-20 08:00")
        let breakfast = Meal(date: date("2026-11-19 08:15"), portions: [Portion(food: Food(name: "Omlet", grams: 100, low: 150, high: 160, group: "protein"), grams: 120)], slot: nil, source: .photo)
        let lunch = Meal(date: date("2026-11-19 13:00"), portions: [Portion(food: Food(name: "Pilav", grams: 100, low: 130, high: 130, group: "tahil"), grams: 100)], slot: .lunch)
        XCTAssertEqual(Repeats.yesterday(.breakfast, meals: [breakfast, lunch], now: now, calendar: istanbul)?.id, breakfast.id)
        XCTAssertNil(Repeats.yesterday(.dinner, meals: [breakfast, lunch], now: now, calendar: istanbul))
        let copy = Repeats.copy(portions: breakfast.portions, title: "Dünkü kahvaltı", slot: .breakfast, date: now)
        XCTAssertNotEqual(copy.id, breakfast.id)
        XCTAssertNotEqual(copy.portions[0].id, breakfast.portions[0].id)
        XCTAssertEqual(copy.low, breakfast.low); XCTAssertEqual(copy.source, .repeatMeal)
        let fav = Repeats.favorite(from: breakfast)
        let repo = Repository(store: MemoryStore())
        repo.saveFavorites([fav])
        XCTAssertEqual(repo.favorites.first?.title, "Omlet")
    }

    func testShoppingListAggregates() throws {
        let db = try loadDB()
        let p = sampleProfile()
        let plans = (0..<3).map { Planner.plan(for: istanbul.date(byAdding: .day, value: $0, to: date("2026-11-20 09:00"))!, profile: p, target: 2100, db: db, calendar: istanbul) }
        let list = Shopping.list(from: plans, db: db)
        XCTAssertEqual(Set(list.map(\.foodID)).count, list.count)
        let sum = plans.flatMap(\.meals).flatMap(\.items).filter { $0.food.id == "domates" }.reduce(0) { $0 + $1.grams }
        if let tomato = list.first(where: { $0.foodID == "domates" }) {
            XCTAssertGreaterThanOrEqual(tomato.grams, sum); XCTAssertEqual(tomato.grams % 50, 0)
        }
        XCTAssertEqual(list.first?.group, "sebze")
        XCTAssertEqual(ShoppingItem(foodID: "pirinc", name: "Pirinç", grams: 1250, group: "tahil").amountText, "1,2 kg")
        XCTAssertEqual(ShoppingItem(foodID: "yumurta", name: "Yumurta", grams: 260, group: "protein").amountText, "6 adet")
        XCTAssertTrue(Shopping.shareText(list, checked: [list[0].id]).contains("☑︎"))
    }

    func testStreaksAndBadges() {
        let now = date("2026-11-20 09:00")
        func meal(_ s: String) -> Meal { Meal(date: date(s), portions: [Portion(food: Food(name: "A", grams: 1, low: 1, high: 1, group: "diger"), grams: 1)]) }
        // Bugün kayıt yok ama dün ve önceki 2 gün var → seri 3
        let meals = [meal("2026-11-19 13:00"), meal("2026-11-18 13:00"), meal("2026-11-17 13:00"), meal("2026-11-15 13:00")]
        let drinks = [Drink(date: date("2026-11-20 08:00"), amount: 2000, kind: DrinkKind.water)]
        let steps = [DailyValue(date: date("2026-11-19 00:00"), value: 10500)]
        let s = Gamification.streaks(meals: meals, drinks: drinks, fluidTarget: 1750, steps: steps, stepGoal: 8000, now: now, calendar: istanbul)
        XCTAssertEqual(s, Streaks(logging: 3, water: 1, steps: 1))
        XCTAssertEqual(Gamification.streaks(meals: meals, drinks: drinks, fluidTarget: nil, steps: [], stepGoal: 8000, now: now, calendar: istanbul).water, 0)
        let b = Gamification.badges(meals: meals, drinks: drinks, weights: [], steps: steps, activities: [], streaks: s, calendar: istanbul)
        XCTAssertTrue(b.first { $0.id == "first-meal" }!.earned)
        XCTAssertTrue(b.first { $0.id == "steps-10k" }!.earned)
        XCTAssertFalse(b.first { $0.id == "log-7" }!.earned)
    }

    func testReminderPlan() {
        var settings = ReminderSettings()
        let items = Reminders.plan(settings, profile: sampleProfile(), fluidRestricted: false)
        XCTAssertEqual(items.filter { $0.id.hasPrefix("meal.") }.count, 4)
        XCTAssertEqual(items.filter { $0.id.hasPrefix("water.") }.map(\.minutes), [600, 720, 840, 960, 1080, 1200])
        XCTAssertEqual(items.first { $0.id == "weigh" }?.minutes, 21 * 60)
        XCTAssertTrue(Reminders.plan(settings, profile: sampleProfile(), fluidRestricted: true).allSatisfy { !$0.id.hasPrefix("water.") })
        settings.meals = false; settings.weigh = false; settings.water = false
        XCTAssertTrue(Reminders.plan(settings, profile: sampleProfile(), fluidRestricted: false).isEmpty)
    }

    func testOpenFoodFactsParsing() throws {
        let json = #"{"status":1,"product":{"product_name":"Süzme Yoğurt","brands":"Örnek Süt, Başka","serving_quantity":"150","allergens_tags":["en:milk"],"nutriments":{"energy-kcal_100g":97,"proteins_100g":9,"carbohydrates_100g":4,"fat_100g":5,"fiber_100g":0,"sugars_100g":4}}}"#
        let p = try OpenFoodFacts.parse(Data(json.utf8), code: "8690000000001")
        XCTAssertEqual(p.name, "Süzme Yoğurt"); XCTAssertEqual(p.brand, "Örnek Süt")
        XCTAssertEqual(p.servingGrams, 150); XCTAssertEqual(p.allergens, [.milk]); XCTAssertTrue(p.allergenInfoKnown)
        let f = p.food(grams: 150)
        XCTAssertEqual(f.low, 146); XCTAssertEqual(f.protein, 13.5); XCTAssertEqual(f.allergens, [.milk])
        var milkAllergic = sampleProfile(); milkAllergic.allergens = [.milk]
        XCTAssertEqual(p.conflicts(with: milkAllergic), [.milk])
        XCTAssertTrue(p.conflicts(with: sampleProfile()).isEmpty)

        let kj = #"{"status":1,"product":{"product_name":"Bisküvi","nutriments":{"energy_100g":2092}}}"#
        let k = try OpenFoodFacts.parse(Data(kj.utf8), code: "12345678")
        XCTAssertEqual(k.kcal, 500, accuracy: 0.1); XCTAssertFalse(k.allergenInfoKnown)
        XCTAssertThrowsError(try OpenFoodFacts.parse(Data(#"{"status":0}"#.utf8), code: "12345678"))
        XCTAssertThrowsError(try OpenFoodFacts.parse(Data(#"{"status":1,"product":{"nutriments":{}}}"#.utf8), code: "12345678"))
        XCTAssertTrue(OpenFoodFacts.isValidBarcode("8690000000001"))
        XCTAssertFalse(OpenFoodFacts.isValidBarcode("86900abc"))
        XCTAssertNil(OpenFoodFacts.url(for: "123"))
    }

    func testWidgetSnapshotRollsOverDay() {
        let s = WidgetSnapshot(date: date("2026-11-19 21:00"), name: "D", intakeKcal: 1800, targetKcal: 2100, waterMl: 1500, waterTargetMl: 1750, steps: 9000, stepGoal: 8000, loggingStreak: 4)
        let n = s.normalized(for: date("2026-11-20 07:00"), calendar: istanbul)
        XCTAssertEqual(n.intakeKcal, 0); XCTAssertEqual(n.steps, 0); XCTAssertEqual(n.remainingKcal, 2100)
        XCTAssertEqual(s.normalized(for: date("2026-11-19 23:00"), calendar: istanbul), s)
    }

    func testOldFoodWithoutMacrosStillDecodes() throws {
        let old = #"{"name":"Pilav","grams":150,"low":180,"high":260,"group":"tahil"}"#
        let f = try JSONDecoder().decode(Food.self, from: Data(old.utf8))
        XCTAssertNil(f.protein); XCTAssertFalse(f.hasMacros)
    }
}

final class InputTests: XCTestCase {
    func testIntegerWithTurkishThousands() {
        XCTAssertEqual(NumberInput.parseInteger("2100"), 2100)
        XCTAssertEqual(NumberInput.parseInteger("2.100"), 2100)
        XCTAssertEqual(NumberInput.parseInteger(" 2 100 kcal"), 2100)
        XCTAssertEqual(NumberInput.parseInteger("12.500"), 12500)
        XCTAssertNil(NumberInput.parseInteger("2.1"))
        XCTAssertNil(NumberInput.parseInteger("21.00"))
        XCTAssertNil(NumberInput.parseInteger("abc"))
        XCTAssertNil(NumberInput.parseInteger(""))
    }
}

final class WorkoutTests: XCTestCase {
    func testProgramByPlaceAndLimits() {
        XCTAssertEqual(ExerciseLibrary.todaysWorkout(place: .gym, limits: []).map(\.id), ["squat", "latpulldown", "dbbench"])
        XCTAssertEqual(ExerciseLibrary.todaysWorkout(place: .home, limits: []).map(\.id), ["pushup", "glutebridge"])
        XCTAssertEqual(ExerciseLibrary.todaysWorkout(place: .gym, limits: [.knee]).map(\.id), ["latpulldown", "dbbench"])
        let minutes = ExerciseLibrary.estimatedMinutes(ExerciseLibrary.todaysWorkout(place: .gym, limits: []))
        XCTAssertTrue((15...40).contains(minutes), "\(minutes)")
    }

    func testSessionFlow() {
        let ex = ExerciseLibrary.todaysWorkout(place: .home, limits: [])
        var s = WorkoutSession(exercises: ex)
        XCTAssertEqual(s.totalSets, 6)
        s.finishSet()
        XCTAssertEqual(s.phase, .rest(remaining: 60))
        s.tick(59); XCTAssertEqual(s.phase, .rest(remaining: 1))
        s.tick(); XCTAssertEqual(s.phase, .set); XCTAssertEqual(s.set, 2)
        s.finishSet(); s.skipRest(); s.finishSet()
        XCTAssertEqual(s.current?.id, "glutebridge"); XCTAssertEqual(s.set, 1)
        s.skipExercise()
        XCTAssertEqual(s.phase, .finished)
        XCTAssertEqual(s.completedSets, 3)
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.001)
        s.finishSet()   // bittiğinde etkisiz
        XCTAssertEqual(s.completedSets, 3)
    }

    func testWorkoutEnergy() {
        let r = ActivityRecord(date: Date(), optionID: "workout", title: "Ev antrenmanı", minutes: 30)
        XCTAssertEqual(ActivityEnergy.fromActivity(r, weightKg: 70), 140)   // (5-1) × 70 × 0,5
    }
}
