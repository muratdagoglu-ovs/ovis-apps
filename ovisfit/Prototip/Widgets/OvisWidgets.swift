import WidgetKit
import SwiftUI

// Ana ekran ve kilit ekranı widget'ları: kalan kalori, su ve adım.
// Veri, uygulamanın App Group'a yazdığı WidgetSnapshot'tan okunur (iOS/Core/WidgetSnapshot.swift).

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
    static let wBackground = Color(hex: 0xF8F8F1)
    static let wInk = Color(hex: 0x192F28)
    static let wDeep = Color(hex: 0x163E35)
    static let wLime = Color(hex: 0xD7ED88)
    static let wWater = Color(hex: 0x427E8B)
    static let wMuted = Color(hex: 0x56655F)
}

struct OvisEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct OvisProvider: TimelineProvider {
    private var defaults: UserDefaults? {
        (Bundle.main.object(forInfoDictionaryKey: "OvisAppGroup") as? String).flatMap { UserDefaults(suiteName: $0) }
    }

    func placeholder(in context: Context) -> OvisEntry { OvisEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (OvisEntry) -> Void) {
        let s = WidgetSnapshot.load(from: defaults) ?? (context.isPreview ? WidgetSnapshot.placeholder : nil)
        completion(OvisEntry(date: Date(), snapshot: s?.normalized(for: Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OvisEntry>) -> Void) {
        let now = Date()
        let stored = WidgetSnapshot.load(from: defaults)
        var entries = [OvisEntry(date: now, snapshot: stored?.normalized(for: now))]
        // Gece yarısı günlük sayaçlar sıfırlanmış hâle geçer.
        if let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0),
                                                    matchingPolicy: .nextTime) {
            entries.append(OvisEntry(date: midnight, snapshot: stored?.normalized(for: midnight)))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

private func fmt(_ v: Int) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "tr_TR")
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

struct OvisWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OvisEntry

    var body: some View {
        if let s = entry.snapshot {
            content(s)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ovis Fit").font(.headline)
                Text("Profilini oluşturmak için uygulamayı aç.").font(.caption).foregroundStyle(Color.wMuted)
            }
        }
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        let kcalFraction = s.targetKcal > 0 ? min(1, Double(s.intakeKcal) / Double(s.targetKcal)) : 0
        let stepFraction = s.stepGoal > 0 ? min(1, Double(s.steps) / Double(s.stepGoal)) : 0
        switch family {
        case .accessoryInline:
            Text("\(fmt(s.remainingKcal)) kcal kaldı · \(fmt(s.steps)) adım")
        case .accessoryCircular:
            Gauge(value: kcalFraction) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(s.remainingKcal >= 1000 ? "\(s.remainingKcal / 100 / 10),\(s.remainingKcal / 100 % 10)b" : "\(s.remainingKcal)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("Kalan \(s.remainingKcal) kilokalori")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(fmt(s.remainingKcal)) kcal kaldı").font(.headline)
                Text("Su \(fmt(s.waterMl)) ml").font(.caption)
                Text("\(fmt(s.steps)) / \(fmt(s.stepGoal)) adım").font(.caption)
            }
        case .systemMedium:
            HStack(spacing: 14) {
                ring(kcalFraction, title: "Kalan", value: fmt(s.remainingKcal), unit: "kcal", color: .wDeep)
                VStack(alignment: .leading, spacing: 10) {
                    metric("drop.fill", "Su", "\(fmt(s.waterMl)) ml" + (s.waterTargetMl.map { " / \(fmt($0))" } ?? ""), .wWater)
                    metric("shoeprints.fill", "Adım", "\(fmt(s.steps)) / \(fmt(s.stepGoal))", .wDeep)
                    ProgressView(value: stepFraction).tint(.wDeep)
                    if s.loggingStreak > 0 {
                        Label("\(s.loggingStreak) gün seri", systemImage: "flame.fill").font(.caption2.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(Color.wInk)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("KALAN").font(.caption2.weight(.semibold)).foregroundStyle(Color.wMuted)
                Text(fmt(s.remainingKcal)).font(.title.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6)
                Text("kcal · hedef \(fmt(s.targetKcal))").font(.caption2).foregroundStyle(Color.wMuted)
                ProgressView(value: kcalFraction).tint(.wDeep)
                Spacer(minLength: 0)
                HStack {
                    Label(fmt(s.waterMl), systemImage: "drop.fill").foregroundStyle(Color.wWater)
                    Spacer()
                    Label(fmt(s.steps), systemImage: "shoeprints.fill")
                }
                .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.wInk)
        }
    }

    private func ring(_ f: Double, title: String, value: String, unit: String, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: 9)
            Circle().trim(from: 0, to: f).stroke(Color.wLime, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(title).font(.caption2).foregroundStyle(Color.wMuted)
                Text(value).font(.headline.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6)
                Text(unit).font(.caption2).foregroundStyle(Color.wMuted)
            }
        }
        .frame(width: 104, height: 104)
    }

    private func metric(_ symbol: String, _ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: symbol).font(.caption2.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
    }
}

struct OvisDailyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OvisDaily", provider: OvisProvider()) { entry in
            OvisWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.wBackground }
        }
        .configurationDisplayName("Ovis Fit · Bugün")
        .description("Kalan kalori, su ve adım.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct OvisWidgets: WidgetBundle {
    var body: some Widget {
        OvisDailyWidget()
    }
}
