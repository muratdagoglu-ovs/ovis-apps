import SwiftUI
import HealthKit
import Charts
import UserNotifications

// MARK: - Apple Sağlık (yalnızca okuma: adım ve aktif enerji)

final class HealthSync {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let activeType = HKQuantityType(.activeEnergyBurned)

    func requestAccess() async {
        guard Self.isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [stepType, activeType])
    }

    // MARK: Yazma (isteğe bağlı): öğün enerjisi ve makroları, su, kilo

    private var shareTypes: Set<HKSampleType> {
        [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein), HKQuantityType(.dietaryCarbohydrates),
         HKQuantityType(.dietaryFatTotal), HKQuantityType(.dietaryFiber), HKQuantityType(.dietarySugar),
         HKQuantityType(.dietaryWater), HKQuantityType(.bodyMass)]
    }

    func requestWriteAccess() async {
        guard Self.isAvailable else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: [stepType, activeType])
    }

    private func sample(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double, at date: Date,
                        external: UUID) -> HKQuantitySample? {
        let type = HKQuantityType(id)
        guard value > 0, store.authorizationStatus(for: type) == .sharingAuthorized else { return nil }
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date,
                                metadata: [HKMetadataKeyExternalUUID: external.uuidString])
    }

    private func save(_ samples: [HKQuantitySample?]) async {
        let list = samples.compactMap { $0 }
        guard !list.isEmpty else { return }
        try? await store.save(list)
    }

    func save(_ meal: Meal) async {
        let t = Macros.totals([meal])
        let g = HKUnit.gram()
        var samples = [sample(.dietaryEnergyConsumed, .kilocalorie(), Double(meal.midpoint), at: meal.date, external: meal.id)]
        if t.unknownPortions == 0 {
            samples += [sample(.dietaryProtein, g, t.protein, at: meal.date, external: meal.id),
                        sample(.dietaryCarbohydrates, g, t.carbs, at: meal.date, external: meal.id),
                        sample(.dietaryFatTotal, g, t.fat, at: meal.date, external: meal.id),
                        sample(.dietaryFiber, g, t.fiber, at: meal.date, external: meal.id),
                        sample(.dietarySugar, g, t.sugar, at: meal.date, external: meal.id)]
        }
        await save(samples)
    }

    /// Yalnızca "Su" türü Sağlık'taki Su kaydına yazılır.
    func save(_ drink: Drink) async {
        guard drink.kind == DrinkKind.water else { return }
        await save([sample(.dietaryWater, .literUnit(with: .milli), Double(drink.amount), at: drink.date, external: drink.id)])
    }

    func save(_ weight: WeightEntry) async {
        await save([sample(.bodyMass, .gramUnit(with: .kilo), weight.kg, at: weight.date, external: weight.id)])
    }

    /// Ovis Fit'in bu kayıt için yazdığı tüm örnekleri siler.
    func deleteSamples(_ external: UUID) async {
        guard Self.isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID,
                                                    allowedValues: [external.uuidString])
        for type in shareTypes where store.authorizationStatus(for: type) == .sharingAuthorized {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    /// Son `days` günün günlük toplamları. Okuma izni reddedildiyse HealthKit boş veri döner.
    func fetch(days: Int) async -> (steps: [DailyValue], active: [DailyValue])? {
        guard Self.isAvailable else { return nil }
        let steps = await daily(stepType, unit: .count(), days: days)
        let active = await daily(activeType, unit: .kilocalorie(), days: days)
        return (steps, active)
    }

    private func daily(_ type: HKQuantityType, unit: HKUnit, days: Int) async -> [DailyValue] {
        let calendar = Calendar.current
        let end = Date()
        let anchor = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [] }
        var out: [DailyValue] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let value = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
            out.append(DailyValue(date: stats.startDate, value: Int(value.rounded())))
        }
        return out
    }
}

// MARK: - Bugün: adım, yakım ve denge

struct ActivityTiles: View {
    @EnvironmentObject private var store: AppStore
    @State private var showTargets = false

    var body: some View {
        if let t = store.targets {
            VStack(alignment: .leading, spacing: 12) {
                if store.healthAvailable && !store.healthRequested {
                    HealthConnectCard()
                }
                HStack(spacing: 14) {
                    ProgressTile(symbol: "shoeprints.fill", title: "Adım",
                                 value: TRFormat.int(store.todaySteps), unit: "",
                                 detail: "Hedef \(TRFormat.int(t.steps))",
                                 fraction: Double(store.todaySteps) / Double(max(1, t.steps)),
                                 tint: .ofMove)
                    ProgressTile(symbol: "flame", title: "Hareketle yakılan",
                                 value: TRFormat.int(store.todayActive.kcal), unit: "kcal",
                                 detail: "Hedef \(TRFormat.int(t.activeKcal)) kcal · \(sourceText)",
                                 fraction: Double(store.todayActive.kcal) / Double(max(1, t.activeKcal)),
                                 tint: .ofSoftLime)
                }
                Button { showTargets = true } label: {
                    Label("Hedefler sistem tarafından belirlenir", systemImage: "info.circle")
                        .font(.footnote)
                }
                .buttonStyle(LinkButtonStyle())
            }
            .sheet(isPresented: $showTargets) { TargetsSheet().environmentObject(store) }
        }
    }

    private var sourceText: String {
        switch store.todayActive.source {
        case .health: return "Apple Sağlık"
        case .estimate: return "tahmini"
        case .none: return "veri yok"
        }
    }
}

struct HealthConnectCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adımlarını Apple Sağlık'tan al").font(.headline)
            Text("Adım ve aktif enerji verilerin (iPhone ve Apple Watch) yalnızca okunur, cihazında kalır ve günlük yakımını hesaplamak için kullanılır.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
            Button {
                Task { await store.connectHealth() }
            } label: { Label("Apple Sağlık'a bağlan", systemImage: "heart.text.square") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }
}

struct ProgressTile: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    let detail: String
    let fraction: Double
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.headline) }
            }
            ProgressView(value: min(1, max(0, fraction)))
                .tint(Color.ofDeep)
            Text(detail).font(.footnote).foregroundStyle(Color.ofMuted).lineLimit(2)
        }
        .foregroundStyle(Color.ofInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue("Hedefin yüzde \(Int((min(1, fraction) * 100).rounded()))'i")
    }
}

/// Bugün alınan − yakılan ve tahmini kilo değişimi.
struct BalanceCard: View {
    let balance: DayBalance
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bugünkü denge").font(.headline)
                Spacer()
                Text(balance.hasMeals ? EnergyBalance.describe(balance.kgChange) : "Öğün kaydı yok")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(balance.balance < 0 ? Color.ofDeep : Color.ofInk)
            }
            HStack(spacing: 10) {
                figure("Alınan", balance.intake)
                Text("−").font(.title3.weight(.bold)).foregroundStyle(Color.ofMuted)
                figure("Yakılan", balance.burned)
                Text("=").font(.title3.weight(.bold)).foregroundStyle(Color.ofMuted)
                figure("Fark", balance.balance, signed: true)
            }
            Text("Yakılan = dinlenme \(TRFormat.int(balance.resting)) + hareket \(TRFormat.int(balance.active)) kcal. Gün sonu varsayımıyla, 7.700 kcal ≈ 1 kg kabulüyle tahmindir; tartıdaki günlük değişim su ve tuz nedeniyle farklı olabilir.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private func figure(_ title: String, _ value: Int, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.ofMuted)
            Text((signed && value > 0 ? "+" : "") + TRFormat.int(value))
                .font(.title3.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibility: String {
        guard balance.hasMeals else { return "Bugünkü denge: öğün kaydı yok. Yakılan tahmini \(balance.burned) kilokalori." }
        return "Bugün alınan \(balance.intake), yakılan \(balance.burned) kilokalori, fark \(balance.balance). \(EnergyBalance.describe(balance.kgChange))."
    }
}

struct TargetsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeading(kicker: "Günlük hedefler", plain: "Sistem ", accent: "belirler.")
                if let t = store.targets {
                    VStack(spacing: 0) {
                        MetricLine(title: "Alınacak enerji", bold: false) { Text("\(TRFormat.int(t.intakeKcal)) kcal").bold().monospacedDigit() }
                        MetricLine(title: "Adım", bold: false) { Text(TRFormat.int(t.steps)).bold().monospacedDigit() }
                        MetricLine(title: "Hareketle yakılacak", bold: false) { Text("\(TRFormat.int(t.activeKcal)) kcal").bold().monospacedDigit() }
                        MetricLine(title: "Toplam yakım (dinlenme dahil)") { Text("\(TRFormat.int(t.totalBurnKcal)) kcal").bold().monospacedDigit() }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Targets.explanation, id: \.self) { line in
                        Label { Text(line).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.circle") }
                            .font(.subheadline)
                    }
                }
                InfoCard(title: "Yakılan enerji nasıl hesaplanır?",
                         text: "Apple Watch gibi bir kaynaktan aktif enerji varsa o kullanılır. Yoksa adım başına yaklaşık 0,0005 kcal × kilo ve tamamlanan hareketin MET değeri (Ainsworth, 2011) ile tahmin edilir. Dinlenme enerjisi Mifflin-St Jeor denkleminden gelir.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kaynaklar").font(.headline)
                    Link("Paluch ve ark., Lancet Public Health 2022 (adım sayısı)", destination: URL(string: "https://doi.org/10.1016/S2468-2667(21)00302-9")!)
                    Link("Compendium of Physical Activities", destination: URL(string: "https://pacompendium.com/")!)
                }
                .font(.subheadline)
            }
            .secondaryScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Gelişim: adım haftası ve haftalık denge

struct StepsWeekSection: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if let t = store.targets {
            let w = StepWeek.of(store.now, steps: store.steps, goal: t.steps)
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Adımlar")
                if w.hasData {
                    Chart {
                        ForEach(w.days, id: \.date) { d in
                            BarMark(x: .value("Gün", d.date, unit: .day), y: .value("Adım", d.value))
                                .foregroundStyle(d.value >= t.steps ? Color.ofDeep : Color.ofDeep.opacity(0.45))
                                .cornerRadius(6)
                                .accessibilityLabel(Text(TRDate.short(d.date, "d MMMM EEEE")))
                                .accessibilityValue(Text("\(d.value) adım"))
                        }
                        RuleMark(y: .value("Hedef", t.steps))
                            .foregroundStyle(Color.ofWarn.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        }
                    }
                    .frame(height: 150)
                    Text("Günlük ortalama \(TRFormat.int(w.average)) adım · hedefe ulaşılan gün \(w.goalDays)/\(w.elapsedDays)")
                        .font(.footnote).foregroundStyle(Color.ofMuted)
                } else if store.healthAvailable && !store.healthRequested {
                    HealthConnectCard()
                } else {
                    Text("Bu hafta adım verisi yok. Apple Sağlık'ta Ovis Fit'in adım okuma iznini kontrol edebilirsin (Sağlık › Paylaşım › Uygulamalar).")
                        .font(.footnote).foregroundStyle(Color.ofMuted)
                }
            }
        }
    }
}

struct WeekBalanceSection: View {
    @EnvironmentObject private var store: AppStore
    let actualChange: Double?
    var body: some View {
        if let w = store.weekBalance {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Haftalık enerji dengesi")
                if w.counted.isEmpty {
                    Text("Bu hafta öğün kaydı yok; denge hesaplanamadı.").font(.footnote).foregroundStyle(Color.ofMuted)
                } else {
                    LineRow(symbol: "scalemass", title: EnergyBalance.describe(w.kgChange),
                            detail: "\(w.counted.count) günün kaydına göre · fark \(w.balance > 0 ? "+" : "")\(TRFormat.int(w.balance)) kcal")
                    if let actual = actualChange {
                        Text("Tartıdaki değişim bu hafta \(actual > 0 ? "+" : "")\(TRFormat.decimal(actual)) kg. Fark; kaydedilmeyen öğünler, su ve tahmin payından kaynaklanabilir.")
                            .font(.footnote).foregroundStyle(Color.ofMuted)
                    }
                }
                Text("Yalnızca öğün kaydı olan günler sayılır; kaydı olmayan gün 0 kcal alınmış gibi hesaplanmaz.")
                    .font(.caption).foregroundStyle(Color.ofMuted)
            }
        }
    }
}


// MARK: - Yerel bildirimler

enum ReminderScheduler {
    static let prefix = "ovis."

    /// Ovis Fit bildirimlerini yeniden kurar (günlük tekrarlayan takvim tetikleyicileri).
    static func apply(_ items: [ReminderItem], requestPermission: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard !items.isEmpty else { return }
        let settings = await center.notificationSettings()
        var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if !allowed && requestPermission && settings.authorizationStatus == .notDetermined {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        guard allowed else { return }
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: item.minutes / 60, minute: item.minutes % 60), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: prefix + item.id, content: content, trigger: trigger))
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
}
