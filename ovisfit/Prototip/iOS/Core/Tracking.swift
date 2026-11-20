import Foundation

// MARK: - Sıvı

public struct HydrationSummary: Equatable, Sendable {
    public let water: Int
    public let other: Int
    public var total: Int { water + other }
    /// Hekim kısıtlaması varsa nil: otomatik hedef, kalan ve teşvik gösterilmez.
    public let target: Int?
    public var remaining: Int? { target.map { max(0, $0 - total) } }
    public var progress: Double? { target.map { $0 > 0 ? min(1, Double(total) / Double($0)) : 0 } }
}

public enum Hydration {
    /// Genel yetişkin başlangıç aralığı: tüm içeceklerden günde yaklaşık 1,5–2 litre.
    public static let range = 1500...2000
    public static let defaultTarget = 1750
    public static let step = 50
    public static let quickAmounts = [150, 250, 500]

    public static func clampTarget(_ value: Int) -> Int {
        let v = min(max(value, range.lowerBound), range.upperBound)
        return (v / step) * step
    }

    public static func summary(_ drinks: [Drink], on day: Date, target: Int, restricted: Bool,
                               calendar: Calendar = .current) -> HydrationSummary {
        let today = drinks.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let water = today.filter { $0.kind == DrinkKind.water }.reduce(0) { $0 + $1.amount }
        let other = today.filter { $0.kind != DrinkKind.water }.reduce(0) { $0 + $1.amount }
        return HydrationSummary(water: water, other: other, target: restricted ? nil : clampTarget(target))
    }

    /// Bugünün son kaydını geri alır (önceki günlere dokunmaz).
    public static func undoLast(_ drinks: [Drink], on day: Date, calendar: Calendar = .current) -> [Drink] {
        guard let last = drinks.filter({ calendar.isDate($0.date, inSameDayAs: day) })
            .max(by: { $0.date < $1.date }) else { return drinks }
        return drinks.filter { $0.id != last.id }
    }
}

// MARK: - Öğün özeti

public struct DaySummary: Equatable, Sendable {
    public let meals: [Meal]
    public var low: Int { meals.reduce(0) { $0 + $1.low } }
    public var high: Int { meals.reduce(0) { $0 + $1.high } }
    /// Aralıkların orta noktası: tahmindir.
    public var estimate: Int { Int((Double(low + high) / 2).rounded()) }

    public func percent(of target: Int) -> Int {
        target > 0 ? Int((Double(estimate) * 100 / Double(target)).rounded()) : 0
    }
    public func remaining(to target: Int) -> Int { max(0, target - estimate) }

    public static func of(_ meals: [Meal], on day: Date, calendar: Calendar = .current) -> DaySummary {
        DaySummary(meals: meals.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date })
    }
}

public enum NextMeal {
    /// Saati henüz geçmemiş ve kaydedilmemiş ilk planlı öğün; yoksa kaydedilmemiş son öğün.
    public static func find(in plan: DayPlan, loggedSlots: Set<MealSlot>, now: Date,
                            calendar: Calendar = .current) -> PlannedMeal? {
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let open = plan.meals.filter { !loggedSlots.contains($0.slot) }
        // Saati en fazla 60 dk geçmiş öğün hâlâ "sıradaki" sayılır.
        return open.first { $0.minutes + 60 >= minute }
    }
}

// MARK: - Hareket

public struct MovementStep: Equatable, Sendable {
    public let title: String
    public let minutes: Int
    public let detail: String
}

public struct MovementOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let place: String
    public let minutes: Int
    public let steps: [MovementStep]
    public let isRest: Bool
    public let symbol: String
}

public enum MovementPlanner {
    public static let durations = [10, 20, 30]

    struct Template {
        let id, title, place, symbol: String
        let needs: Set<Equipment>
        let avoid: Set<MovementLimit>
        let phases: [(String, Double, String)]
        let isRest: Bool
    }

    static let library: [Template] = [
        Template(id: "walk", title: "Yürüyüş", place: "Açık hava · rahat tempo", symbol: "figure.walk",
                 needs: [], avoid: [.standing],
                 phases: [("Başlangıç", 0.25, "Yavaş adımlarla başla"),
                          ("Ana bölüm", 0.5, "Konuşabileceğin rahat bir tempo seç"),
                          ("Bitiş", 0.25, "Temponu yavaşlat, nefesini dinlendir")], isRest: false),
        Template(id: "chair", title: "Sandalye egzersizleri", place: "Evde · oturarak", symbol: "chair",
                 needs: [.chair], avoid: [],
                 phases: [("Isınma", 0.3, "Oturarak omuz ve ayak bileği çevirme"),
                          ("Ana bölüm", 0.5, "Oturarak diz uzatma, kol kaldırma; ağrı sınırında dur"),
                          ("Bitiş", 0.2, "Derin nefes ve hafif esneme")], isRest: false),
        Template(id: "mobility", title: "Mobilite ve esneme", place: "Evde · mat üzerinde", symbol: "figure.flexibility",
                 needs: [.mat], avoid: [.balance],
                 phases: [("Isınma", 0.3, "Boyun, omuz ve kalça hareketleri"),
                          ("Ana bölüm", 0.5, "Kontrollü esneme; zorlamadan, 20–30 sn bekle"),
                          ("Bitiş", 0.2, "Sırtüstü nefes egzersizi")], isRest: false),
        Template(id: "band", title: "Bantla kuvvet", place: "Evde · direnç bandı", symbol: "figure.strengthtraining.functional",
                 needs: [.band], avoid: [.back],
                 phases: [("Isınma", 0.25, "Kol ve omuz çevirme"),
                          ("Ana bölüm", 0.55, "Bantla çekiş ve itiş, 2–3 set × 10 tekrar"),
                          ("Bitiş", 0.2, "Göğüs ve omuz esnemesi")], isRest: false),
        Template(id: "rest", title: "Dinlenme ve nefes", place: "Bugün dinlenme günü", symbol: "leaf",
                 needs: [], avoid: [],
                 phases: [("Rahat pozisyon", 0.3, "Oturarak veya uzanarak rahatla"),
                          ("Nefes", 0.5, "4 sn al, 6 sn ver"),
                          ("Bitiş", 0.2, "Omuzlarını gevşet")], isRest: true)
    ]

    /// Süreye, ekipmana ve kısıtlara uygun seçenekler; dinlenme her zaman sunulur.
    public static func options(minutes: Int, equipment: Set<Equipment>, limits: Set<MovementLimit>) -> [MovementOption] {
        let total = max(5, minutes)
        return library.filter { t in
            t.needs.isSubset(of: equipment) && t.avoid.isDisjoint(with: limits)
        }.map { t in
            var steps: [MovementStep] = []
            var used = 0
            for (i, phase) in t.phases.enumerated() {
                let m = i == t.phases.count - 1 ? total - used : max(1, Int((Double(total) * phase.1).rounded()))
                used += m
                steps.append(MovementStep(title: phase.0, minutes: m, detail: phase.2))
            }
            return MovementOption(id: t.id, title: t.title, place: t.place, minutes: total,
                                  steps: steps, isRest: t.isRest, symbol: t.symbol)
        }
    }

    /// Aynı gün için yalnızca bir tamamlanma kaydı tutulur.
    public static func record(_ option: MovementOption, on date: Date, existing: [ActivityRecord],
                              calendar: Calendar = .current) -> [ActivityRecord]? {
        guard !existing.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) else { return nil }
        return existing + [ActivityRecord(date: date, optionID: option.id, title: option.title,
                                          minutes: option.isRest ? 0 : option.minutes)]
    }
}

// MARK: - Gelişim

public struct WeeklyReport: Equatable, Sendable {
    public enum State: Equatable, Sendable { case empty, single, trend }
    public let start: Date
    public let end: Date
    public let weights: [WeightEntry]
    public let latest: WeightEntry?
    public let mealCount: Int
    public let mealDays: Int
    public let activityCount: Int
    public let activityMinutes: Int

    public var state: State {
        switch weights.count { case 0: return .empty; case 1: return .single; default: return .trend }
    }
    public var change: Double? {
        guard let first = weights.first, let last = weights.last, weights.count > 1 else { return nil }
        return ((last.kg - first.kg) * 10).rounded() / 10
    }
}

public enum ProgressReport {
    /// Pazartesi başlayan, `date`'i içeren hafta.
    public static func week(containing date: Date, calendar base: Calendar = .current) -> (Date, Date) {
        var calendar = base
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }

    public static func report(for date: Date, weights: [WeightEntry], meals: [Meal], activities: [ActivityRecord],
                              calendar: Calendar = .current) -> WeeklyReport {
        let (start, end) = week(containing: date, calendar: calendar)
        let inWeek: (Date) -> Bool = { $0 >= start && $0 < end }
        let w = weights.filter { inWeek($0.date) }.sorted { $0.date < $1.date }
        let m = meals.filter { inWeek($0.date) }
        let a = activities.filter { inWeek($0.date) && $0.minutes > 0 }
        return WeeklyReport(start: start, end: end, weights: w,
                            latest: weights.max(by: { $0.date < $1.date }),
                            mealCount: m.count,
                            mealDays: Set(m.map { DayKey.string(for: $0.date, calendar: calendar) }).count,
                            activityCount: a.count,
                            activityMinutes: a.reduce(0) { $0 + $1.minutes })
    }

    public static func addWeight(_ kg: Double, on date: Date, to entries: [WeightEntry],
                                 calendar: Calendar = .current) -> [WeightEntry] {
        // Aynı güne ikinci kayıt öncekinin yerine geçer.
        var list = entries.filter { !calendar.isDate($0.date, inSameDayAs: date) }
        list.append(WeightEntry(date: date, kg: (kg * 10).rounded() / 10))
        return list.sorted { $0.date < $1.date }
    }
}
