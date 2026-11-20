import Foundation

/// Uygulamanın App Group'a yazdığı, widget'ın okuduğu küçük özet.
/// Bu dosya hem uygulama hem widget hedefinde derlenir; yalnızca Foundation kullanır.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var name: String
    public var intakeKcal: Int
    public var targetKcal: Int
    public var waterMl: Int
    /// Hekim kısıtlamasında nil: hedef ve kalan gösterilmez.
    public var waterTargetMl: Int?
    public var steps: Int
    public var stepGoal: Int
    public var loggingStreak: Int

    public init(date: Date, name: String, intakeKcal: Int, targetKcal: Int, waterMl: Int, waterTargetMl: Int?,
                steps: Int, stepGoal: Int, loggingStreak: Int) {
        self.date = date; self.name = name; self.intakeKcal = intakeKcal; self.targetKcal = targetKcal
        self.waterMl = waterMl; self.waterTargetMl = waterTargetMl; self.steps = steps; self.stepGoal = stepGoal
        self.loggingStreak = loggingStreak
    }

    public var remainingKcal: Int { max(0, targetKcal - intakeKcal) }

    public static let key = "of.widget.snapshot.v1"
    public static let placeholder = WidgetSnapshot(date: Date(), name: "", intakeKcal: 1240, targetKcal: 2100,
                                                   waterMl: 1250, waterTargetMl: 1750, steps: 6240, stepGoal: 8000,
                                                   loggingStreak: 3)

    /// Gün değiştiyse günlük sayaçlar sıfırlanmış hâli (widget uygulama açılmadan da doğru günü gösterir).
    public func normalized(for now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        guard !calendar.isDate(date, inSameDayAs: now) else { return self }
        var s = self
        s.date = now; s.intakeKcal = 0; s.waterMl = 0; s.steps = 0
        return s
    }

    public static func load(from defaults: UserDefaults?) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(to defaults: UserDefaults?) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
