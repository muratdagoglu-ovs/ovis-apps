import Foundation

/// Günlük toplam değer (adım veya aktif enerji kcal). Apple Sağlık'tan okunur, yalnızca cihazda saklanır.
public struct DailyValue: Codable, Equatable, Sendable {
    public let date: Date
    public let value: Int
    public init(date: Date, value: Int) { self.date = date; self.value = max(0, value) }
}

public enum DailyValues {
    public static func value(on day: Date, in list: [DailyValue], calendar: Calendar = .current) -> Int {
        list.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.value }
    }

    /// Yeni okunan günleri öncekilerle birleştirir (aynı gün yeni değerle değişir), son `keep` günü tutar.
    public static func merge(_ old: [DailyValue], _ new: [DailyValue], keep: Int = 60, now: Date = Date(),
                             calendar: Calendar = .current) -> [DailyValue] {
        var byDay: [String: DailyValue] = [:]
        for d in old + new {
            byDay[DayKey.string(for: d.date, calendar: calendar)] = DailyValue(date: calendar.startOfDay(for: d.date), value: d.value)
        }
        let limit = calendar.date(byAdding: .day, value: -keep, to: calendar.startOfDay(for: now))!
        return byDay.values.filter { $0.date >= limit }.sorted { $0.date < $1.date }
    }
}

// MARK: - Sistem hedefleri

/// Kullanıcı girmez; profil (aktivite düzeyi ve hedef) değişince sistem yeniden belirler.
public struct DailyTargets: Equatable, Sendable {
    /// Alınacak enerji (kcal) — EnergyCalculator'dan.
    public let intakeKcal: Int
    /// Hareketle yakılacak aktif enerji (kcal, dinlenme enerjisi hariç).
    public let activeKcal: Int
    public let steps: Int
    /// Gün sonunda beklenen toplam yakım: dinlenme + aktif hedef.
    public let totalBurnKcal: Int
}

public enum Targets {
    public static func daily(for p: Profile) -> DailyTargets {
        let estimate = EnergyCalculator.estimate(p)
        var steps: Int
        var active: Int
        switch p.activity {
        case .low: steps = 6000; active = 250
        case .moderate: steps = 8000; active = 400
        case .high: steps = 10000; active = 600
        }
        switch p.goal {
        case .lose: steps += 1000; active += 100
        case .maintain: break
        case .gain: active -= 100      // fazlalık hedefini korumak için hareket hedefi biraz düşük
        }
        // Yürüme kısıtı olanlarda adım hedefi düşürülür; aktif enerji oturarak da yakılabilir.
        if p.limits.contains(.standing) || p.limits.contains(.knee) { steps = min(steps, 5000) }
        if p.age >= 65 { steps = min(steps, 7000) }
        return DailyTargets(intakeKcal: estimate.target, activeKcal: active, steps: steps,
                            totalBurnKcal: estimate.restingKcal + active)
    }

    public static let explanation: [String] = [
        "Adım hedefi aktivite düzeyine göre belirlenir: Düşük 6.000 · Orta 8.000 · Yüksek 10.000. Kilo verme hedefinde +1.000 adım.",
        "Günde 7.000–8.000 adım yetişkinlerde sağlık yararının belirgin olduğu aralıktır (Paluch ve ark., Lancet Public Health 2022).",
        "Diz hassasiyeti veya uzun süre ayakta durma güçlüğünde adım hedefi en fazla 5.000; 65 yaş ve üzerinde en fazla 7.000'dir.",
        "Hareketle yakılacak enerji hedefi: Düşük 250 · Orta 400 · Yüksek 600 kcal; kilo vermede +100, kilo almada −100 kcal.",
        "Hedefler profilindeki aktivite düzeyi ve hedef değişince kendiliğinden güncellenir."
    ]
}

// MARK: - Yakılan enerji

public enum ActivityEnergy {
    /// Adım başına yaklaşık enerji: ~0,0005 kcal × kg (75 kg için ~0,04 kcal/adım).
    public static let kcalPerStepPerKg = 0.0005

    /// Tamamlanan hareket seçeneklerinin MET değerleri (Ainsworth ve ark., Compendium of Physical Activities 2011).
    public static let mets: [String: Double] = ["walk": 3.5, "chair": 2.0, "mobility": 2.5, "band": 3.5, "rest": 1.0, "workout": 5.0]

    public static func fromSteps(_ steps: Int, weightKg: Double) -> Int {
        Int((Double(steps) * weightKg * kcalPerStepPerKg).rounded())
    }

    /// Dinlenmenin üzerindeki net enerji: (MET − 1) × kg × saat.
    public static func fromActivity(_ r: ActivityRecord, weightKg: Double) -> Int {
        let met = mets[r.optionID] ?? 2.5
        return Int((max(0, met - 1) * weightKg * Double(r.minutes) / 60).rounded())
    }

    public enum Source: Equatable, Sendable { case health, estimate, none }

    /// Bir günün aktif enerjisi. Apple Sağlık (ör. Apple Watch) değeri varsa o kullanılır;
    /// yoksa adımlardan ve tamamlanan hareketten tahmin edilir. Adım verisi varsa yürüyüş
    /// zaten adımlarda sayıldığı için ikinci kez eklenmez.
    public static func active(on day: Date, steps: [DailyValue], healthActive: [DailyValue],
                              activities: [ActivityRecord], weightKg: Double,
                              calendar: Calendar = .current) -> (kcal: Int, source: Source) {
        let measured = DailyValues.value(on: day, in: healthActive, calendar: calendar)
        if measured > 0 { return (measured, .health) }
        let s = DailyValues.value(on: day, in: steps, calendar: calendar)
        let done = activities.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let fromMoves = done.filter { !(s > 0 && $0.optionID == "walk") }
            .reduce(0) { $0 + fromActivity($1, weightKg: weightKg) }
        let total = fromSteps(s, weightKg: weightKg) + fromMoves
        return (total, total > 0 ? .estimate : .none)
    }
}

// MARK: - Enerji dengesi ve tahmini kilo değişimi

public struct DayBalance: Equatable, Sendable {
    public let date: Date
    /// Kaydedilen öğünlerin orta noktası (tahmin).
    public let intake: Int
    public let resting: Int
    public let active: Int
    public let activeSource: ActivityEnergy.Source
    public let hasMeals: Bool

    public var burned: Int { resting + active }
    /// Pozitif: fazla (kilo alma yönünde), negatif: açık.
    public var balance: Int { intake - burned }
    public var kgChange: Double { EnergyBalance.kg(fromKcal: balance) }
}

public enum EnergyBalance {
    /// Yaklaşık 7.700 kcal ≈ 1 kg vücut ağırlığı (yaygın kullanılan yaklaşık değer; gerçek değişim kişiye göre farklıdır).
    public static let kcalPerKg = 7700.0

    public static func kg(fromKcal kcal: Int) -> Double {
        (Double(kcal) / kcalPerKg * 1000).rounded() / 1000
    }

    /// Gün sonu varsayımıyla: dinlenme enerjisinin tamamı + bugüne kadar ölçülen/tahmin edilen aktif enerji.
    public static func day(_ date: Date, profile: Profile, meals: [Meal], steps: [DailyValue],
                           healthActive: [DailyValue], activities: [ActivityRecord],
                           calendar: Calendar = .current) -> DayBalance {
        let summary = DaySummary.of(meals, on: date, calendar: calendar)
        let resting = Int(EnergyCalculator.resting(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                                   age: profile.age, sex: profile.sex).rounded())
        let a = ActivityEnergy.active(on: date, steps: steps, healthActive: healthActive,
                                      activities: activities, weightKg: profile.weightKg, calendar: calendar)
        return DayBalance(date: calendar.startOfDay(for: date), intake: summary.estimate, resting: resting,
                          active: a.kcal, activeSource: a.source, hasMeals: !summary.meals.isEmpty)
    }

    public struct Week: Equatable, Sendable {
        public let days: [DayBalance]
        /// Yalnızca öğün kaydı olan günler: kaydı olmayan gün 0 kcal alınmış gibi sayılmaz.
        public var counted: [DayBalance] { days.filter(\.hasMeals) }
        public var balance: Int { counted.reduce(0) { $0 + $1.balance } }
        public var kgChange: Double { EnergyBalance.kg(fromKcal: balance) }
        public var burned: Int { days.reduce(0) { $0 + $1.burned } }
    }

    /// Haftanın bugüne kadarki günleri.
    public static func week(containing date: Date, profile: Profile, meals: [Meal], steps: [DailyValue],
                            healthActive: [DailyValue], activities: [ActivityRecord],
                            calendar: Calendar = .current) -> Week {
        let start = ProgressReport.week(containing: date, calendar: calendar).0
        let today = calendar.startOfDay(for: date)
        var days: [DayBalance] = []
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: start)!
            guard d <= today else { break }
            days.append(day(d, profile: profile, meals: meals, steps: steps, healthActive: healthActive,
                            activities: activities, calendar: calendar))
        }
        return Week(days: days)
    }

    public static func describe(_ kg: Double) -> String {
        let grams = Int((kg * 1000).rounded())
        if abs(grams) < 10 { return "≈ değişim yok" }
        let text = abs(grams) < 1000 ? "\(abs(grams)) g" : TRFormat.decimal(abs(kg), digits: 2) + " kg"
        return grams < 0 ? "≈ \(text) verme yönünde" : "≈ \(text) alma yönünde"
    }
}

// MARK: - Adım haftası

public struct StepWeek: Equatable, Sendable {
    public let days: [DailyValue]
    public let elapsedDays: Int
    public let goal: Int
    public var total: Int { days.reduce(0) { $0 + $1.value } }
    public var average: Int { elapsedDays > 0 ? Int((Double(total) / Double(elapsedDays)).rounded()) : 0 }
    public var goalDays: Int { days.prefix(elapsedDays).filter { $0.value >= goal }.count }
    public var hasData: Bool { total > 0 }

    public static func of(_ date: Date, steps: [DailyValue], goal: Int, calendar: Calendar = .current) -> StepWeek {
        let start = ProgressReport.week(containing: date, calendar: calendar).0
        let today = calendar.startOfDay(for: date)
        var list: [DailyValue] = []
        var elapsed = 0
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: start)!
            if d <= today { elapsed += 1 }
            list.append(DailyValue(date: d, value: DailyValues.value(on: d, in: steps, calendar: calendar)))
        }
        return StepWeek(days: list, elapsedDays: elapsed, goal: goal)
    }
}
