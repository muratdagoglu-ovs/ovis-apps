import SwiftUI
import VisionKit
import Vision

// MARK: - 5 · Hızlı ekle: dünkü öğün ve favoriler

struct QuickAddSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var justAdded: String?
    @State private var busy = false

    var body: some View {
        let slot = store.currentSlot
        let yesterday = store.yesterdayMeal(for: slot)
        if yesterday != nil || !store.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Hızlı ekle")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let y = yesterday {
                            chip(id: "y-\(y.id)", symbol: "arrow.counterclockwise",
                                 title: "Dünkü \(slot.title.lowercased(with: TRDate.locale))",
                                 detail: "\(y.displayTitle) · \(TRFormat.int(y.midpoint)) kcal") {
                                store.repeatMeal(portions: y.portions, title: y.title ?? y.displayTitle, slot: slot)
                            }
                        }
                        ForEach(store.favorites) { f in
                            chip(id: f.id.uuidString, symbol: "star.fill", title: f.title,
                                 detail: "\(TRFormat.range(f.low, f.high)) kcal") {
                                store.repeatMeal(portions: f.portions, title: f.title, slot: slot)
                            }
                            .contextMenu {
                                Button(role: .destructive) { store.removeFavorite(f.id) } label: {
                                    Label("Favorilerden çıkar", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                }
                Text(justAdded.map { "\($0) günlüğe eklendi." } ?? "Tek dokunuşla \(slot.title.lowercased(with: TRDate.locale)) olarak günlüğe eklenir. Favoriler için öğün kaydına basılı tut.")
                    .font(.footnote).foregroundStyle(Color.ofMuted)
            }
        }
    }

    private func chip(id: String, symbol: String, title: String, detail: String, action: @escaping () -> Bool) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            if action() { justAdded = title }
            // Art arda dokunuşla mükerrer kaydı önlemek için kısa kilit.
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                busy = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(Color.ofMuted).lineLimit(1)
            }
            .foregroundStyle(Color.ofInk)
            .padding(12)
            .frame(width: 200, alignment: .leading)
            .frame(minHeight: 56)
            .background(Color.ofSage, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityHint("Günlüğe ekler")
    }
}

// MARK: - 7 · Makro kartı

struct MacroCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var showInfo = false
    var body: some View {
        if let t = store.macroTargets {
            let m = store.todayMacros
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Makro dengesi").font(.headline)
                    Spacer()
                    Button { showInfo = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Makro hedefleri nasıl belirlenir")
                }
                macroRow("Protein", m.protein, target: t.protein, isLimit: false)
                macroRow("Lif", m.fiber, target: t.fiber, isLimit: false)
                macroRow("Şeker (toplam)", m.sugar, target: t.sugarLimit, isLimit: true)
                if m.unknownPortions > 0 {
                    Text("\(m.unknownPortions) öğenin makro bilgisi yok; toplamlara katılmadı.")
                        .font(.caption).foregroundStyle(Color.ofMuted)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .sheet(isPresented: $showInfo) {
                InfoListSheet(kicker: "Makro hedefleri", plain: "Sadece kalori ", accent: "değil.", lines: Macros.explanation)
            }
        }
    }

    private func macroRow(_ title: String, _ value: Double, target: Int, isLimit: Bool) -> some View {
        let fraction = target > 0 ? value / Double(target) : 0
        let over = isLimit && fraction > 1
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value.rounded())) / \(target) g\(isLimit ? " üst sınır" : "")")
                    .font(.subheadline).monospacedDigit().foregroundStyle(over ? Color.ofWarn : Color.ofMuted)
            }
            ProgressView(value: min(1, max(0, fraction))).tint(over ? Color.ofWarn : Color.ofDeep)
        }
        .accessibilityElement(children: .combine)
    }
}

struct InfoListSheet: View {
    let kicker: String
    let plain: String
    let accent: String
    let lines: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeading(kicker: kicker, plain: plain, accent: accent)
                ForEach(lines, id: \.self) { line in
                    Label { Text(line).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.circle") }
                        .font(.subheadline)
                }
            }
            .secondaryScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 8 · Seri ve rozetler

struct StreakChip: View {
    let days: Int
    var body: some View {
        if days > 0 {
            Label("\(days) gün seri", systemImage: "flame.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ofInk)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.ofLime, in: Capsule())
                .accessibilityLabel("\(days) gün üst üste öğün kaydı")
        }
    }
}

struct BadgesSection: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let s = store.streaks
        let badges = store.badges
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Seriler ve rozetler") {
                Text("\(badges.filter(\.earned).count)/\(badges.count)").font(.subheadline).foregroundStyle(Color.ofMuted)
            }
            HStack(spacing: 10) {
                streak("Kayıt", s.logging, "fork.knife")
                streak("Su", s.water, "drop.fill")
                streak("Adım", s.steps, "shoeprints.fill")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(badges) { b in
                    HStack(spacing: 10) {
                        Image(systemName: b.symbol).font(.title3)
                            .foregroundStyle(b.earned ? Color.ofDeep : Color.ofMuted.opacity(0.5))
                            .frame(width: 40, height: 40)
                            .background(b.earned ? Color.ofLime : Color.ofSage, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.title).font(.subheadline.weight(.semibold))
                            Text(b.detail).font(.caption).foregroundStyle(Color.ofMuted).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(b.earned ? 1 : 0.75)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(b.earned ? "Kazanıldı" : "Henüz kazanılmadı")
                }
            }
        }
    }

    private func streak(_ title: String, _ days: Int, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold))
            Text("\(days) gün").font(.title3.weight(.bold)).monospacedDigit()
        }
        .foregroundStyle(Color.ofInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 1 · Hatırlatmalar

struct ReminderSetupCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        if !store.remindersConfigured && store.profile != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hatırlatmaları aç").font(.headline)
                Text("Öğün saatlerinde, gün içinde su için ve akşam tartı için kısa bildirimler. İstediğin zaman değiştirebilirsin.")
                    .font(.footnote).foregroundStyle(Color.ofMuted)
                HStack(spacing: 16) {
                    Button { store.setReminders(ReminderSettings()) } label: { Label("Aç", systemImage: "bell") }
                        .buttonStyle(PrimaryButtonStyle())
                    NavigationLink(value: Route.reminders) { Text("Ayarla") }
                        .buttonStyle(LinkButtonStyle())
                }
            }
            .padding(16)
            .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
    }
}

struct RemindersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = ReminderSettings()
    @State private var loaded = false
    @State private var denied = false

    var body: some View {
        ScreenScroll {
            ScreenHeading(kicker: "Bildirimler", plain: "Hatırlatma", accent: "lar.")
            if denied {
                InfoCard(title: "Bildirim izni kapalı",
                         text: "Ayarlar › Ovis Fit › Bildirimler bölümünden izin verebilirsin.", tint: Color(hex: 0xF6E3DC))
                Button("Ayarlar'ı aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(LinkButtonStyle())
            }
            VStack(spacing: 0) {
                Toggle("Öğün saatleri", isOn: $settings.meals).frame(minHeight: 48)
                if let p = store.profile {
                    Text(p.mealTimes.slots.map { "\($0.title) \(MealTimes.label(p.mealTimes.minutes(for: $0)))" }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Color.ofMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider().overlay(Color.ofDivider).padding(.vertical, 6)
                Toggle("Su", isOn: $settings.water).frame(minHeight: 48)
                    .disabled(store.fluidRestricted)
                if store.fluidRestricted {
                    Text("Hekim sıvı kısıtlaması açık olduğu için su hatırlatması gönderilmez.")
                        .font(.footnote).foregroundStyle(Color.ofMuted).frame(maxWidth: .infinity, alignment: .leading)
                } else if settings.water {
                    Picker("Sıklık", selection: $settings.waterEveryMinutes) {
                        Text("1 saatte bir").tag(60); Text("2 saatte bir").tag(120); Text("3 saatte bir").tag(180)
                    }
                    .frame(minHeight: 44)
                    DatePicker("Başlangıç", selection: time($settings.waterStart), displayedComponents: .hourAndMinute)
                    DatePicker("Bitiş", selection: time($settings.waterEnd), displayedComponents: .hourAndMinute)
                }
                Divider().overlay(Color.ofDivider).padding(.vertical, 6)
                Toggle("Tartı", isOn: $settings.weigh).frame(minHeight: 48)
                if settings.weigh {
                    DatePicker("Saat", selection: time($settings.weighMinutes), displayedComponents: .hourAndMinute)
                }
            }
            Text("Bildirimler cihazda planlanır; sunucuya bilgi gönderilmez. Öğün saatleri profilinden gelir.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    store.setReminders(settings)
                    Task { denied = await ReminderScheduler.isDenied() }
                } label: { Label("Kaydet", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .secondaryScreen()
        .task {
            if !loaded { settings = store.reminders; loaded = true }
            denied = await ReminderScheduler.isDenied()
        }
    }

    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        } set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}

/// Profil ekranındaki bağlantılar: hatırlatmalar ve Apple Sağlık'a yazma.
struct ConnectionsSection: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Bağlantılar")
            NavigationLink(value: Route.reminders) {
                LineRow(symbol: "bell", title: "Hatırlatmalar",
                        detail: store.remindersConfigured ? "Öğün, su ve tartı bildirimleri" : "Kapalı") {
                    Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
                }
            }
            .buttonStyle(.plain)
            if store.healthAvailable {
                Toggle(isOn: Binding(get: { store.healthWrite }, set: { on in Task { await store.setHealthWrite(on) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Sağlık'a yaz").font(.headline)
                        Text("Öğün enerjisi ve makroları, su ve kilo kayıtların Sağlık uygulamasında da görünür. Yalnızca bundan sonraki kayıtlar yazılır.")
                            .font(.footnote).foregroundStyle(Color.ofMuted)
                    }
                }
                .frame(minHeight: 56)
            }
        }
    }
}

// MARK: - 2 · Barkod

struct BarcodeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @State private var code = ""
    @State private var product: BarcodeProduct?
    @State private var grams = 100
    @State private var slot = MealSlot.lunch
    @State private var loading = false
    @State private var error: String?
    @State private var saving = false
    @State private var mealID = UUID()
    @State private var scanning = true

    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ScreenScroll {
            ScreenHeading(kicker: "Paketli ürün", plain: "Barkodu ", accent: "okut.")
            if product == nil {
                if scannerAvailable && scanning {
                    BarcodeScanner { value in
                        scanning = false
                        code = value
                        Task { await lookup(value) }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .accessibilityLabel("Barkod tarayıcı. Ürünün barkodunu kameraya göster.")
                } else if !scannerAvailable {
                    InfoCard(title: "Tarayıcı kullanılamıyor",
                             text: "Bu cihazda veya simülatörde canlı barkod tarama yok. Barkod numarasını aşağıya yazabilirsin.")
                }
                HStack(spacing: 10) {
                    BoxField("Barkod numarası (8–14 hane)", text: $code, keyboard: .numberPad, identifier: "field.barcode")
                    Button("Ara") { Task { await lookup(code) } }
                        .buttonStyle(PillButtonStyle(selected: true))
                        .disabled(!OpenFoodFacts.isValidBarcode(code) || loading)
                }
            }
            if loading { ProgressView("Ürün aranıyor…") }
            if let error {
                InfoCard(title: "Ürün bulunamadı", text: error, tint: Color(hex: 0xF6E3DC))
                Button("Tekrar tara") { reset() }.buttonStyle(LinkButtonStyle())
            }
            if let p = product { productCard(p) }
            Text("Ürün bilgisi Open Food Facts açık veritabanından gelir (ODbL). Yalnızca barkod numarası gönderilir. Etiketteki bilgiyle karşılaştırmanı öneririz.")
                .font(.caption).foregroundStyle(Color.ofMuted)
        }
        .safeAreaInset(edge: .bottom) {
            if let p = product {
                BottomAction {
                    Button {
                        guard !saving else { return }
                        saving = true
                        let meal = Meal(id: mealID, portions: [Portion(food: p.food(grams: grams), grams: grams)],
                                        slot: slot, source: .barcode, title: p.name)
                        if store.addMeal(meal) { router.popToRoot() } else { saving = false }
                    } label: { Label("Günlüğüme ekle", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(saving || grams <= 0)
                }
            }
        }
        .secondaryScreen()
        .onAppear { slot = store.currentSlot }
    }

    @ViewBuilder private func productCard(_ p: BarcodeProduct) -> some View {
        let food = p.food(grams: grams)
        let conflicts = p.conflicts(with: store.profile)
        VStack(alignment: .leading, spacing: 12) {
            Text(p.name).font(.title2.weight(.bold))
            if let b = p.brand { Text(b).font(.subheadline).foregroundStyle(Color.ofMuted) }
            if !conflicts.isEmpty {
                InfoCard(title: "Alerjen uyarısı",
                         text: "Bu ürün profilindeki alerjenleri içeriyor: \(conflicts.map(\.title).joined(separator: ", ")).",
                         tint: Color(hex: 0xF6E3DC))
            } else if !p.allergenInfoKnown {
                InfoCard(title: "Alerjen bilgisi yok", text: "Veritabanında bu ürünün alerjen bilgisi bulunmuyor; paketteki etiketi kontrol et.")
            } else if !p.allergens.isEmpty {
                Text("Alerjenler: \(p.allergens.map(\.title).joined(separator: ", "))").font(.footnote).foregroundStyle(Color.ofMuted)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(food.low)").font(.largeTitle.weight(.bold)).monospacedDigit()
                Text("kcal · \(grams) g").foregroundStyle(Color.ofMuted)
            }
            .accessibilityElement(children: .combine)
            GramStepper(name: p.name, grams: grams, step: grams < 50 ? 5 : 10) { delta in
                grams = min(2000, max(0, grams + delta))
            }
            if let s = p.servingGrams, s != grams {
                Button("1 porsiyon · \(s) g") { grams = s }.buttonStyle(LinkButtonStyle())
            }
            VStack(spacing: 0) {
                macro("Protein", food.protein); macro("Karbonhidrat", food.carbs); macro("Yağ", food.fat)
                macro("Lif", food.fiber); macro("Şeker", food.sugar)
            }
            Picker("Öğün", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented)
            Button("Başka ürün") { reset() }.buttonStyle(LinkButtonStyle())
        }
    }

    private func macro(_ title: String, _ value: Double?) -> some View {
        MetricLine(title: title, bold: false) {
            Text(value.map { TRFormat.decimal($0) + " g" } ?? "bilinmiyor").monospacedDigit().foregroundStyle(Color.ofMuted)
        }
    }

    private func reset() {
        product = nil; error = nil; code = ""; scanning = true; saving = false; mealID = UUID()
    }

    private func lookup(_ value: String) async {
        guard let url = OpenFoodFacts.url(for: value) else { error = "Barkod 8, 12, 13 veya 14 haneli olmalı."; return }
        loading = true; error = nil
        defer { loading = false }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("OvisFit/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw OpenFoodFacts.ParseError.notFound }
            let p = try OpenFoodFacts.parse(data, code: value)
            product = p
            grams = p.servingGrams ?? 100
            mealID = UUID()
        } catch OpenFoodFacts.ParseError.notFound {
            error = "Bu barkod Open Food Facts'te kayıtlı değil. Ürünü fotoğrafla veya elle ekleyebilirsin."
        } catch OpenFoodFacts.ParseError.noEnergy {
            error = "Ürün bulundu ama enerji değeri yok. Etiketteki değerle elle eklemeni öneririz."
        } catch let e as URLError where e.code == .notConnectedToInternet {
            error = "İnternet bağlantısı yok."
        } catch {
            self.error = "Ürün bilgisi alınamadı. Tekrar deneyebilirsin."
        }
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning { try? controller.startScanning() }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var sent = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !sent else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue,
                   OpenFoodFacts.isValidBarcode(value) {
                    sent = true
                    dataScanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}

// MARK: - 6 · Alışveriş listesi

struct ShoppingView: View {
    @EnvironmentObject private var store: AppStore
    @State private var days = 7

    var body: some View {
        let items = store.shoppingList(days: days)
        let checked = store.checkedShopping
        let groups = Dictionary(grouping: items, by: \.group)
        let order = ["sebze", "protein", "tahil", "diger", "sos"].filter { groups[$0] != nil }

        ScreenScroll {
            ScreenHeading(kicker: "Plandan", plain: "Alışveriş ", accent: "listem.")
            Picker("Süre", selection: $days) {
                Text("3 gün").tag(3); Text("7 gün").tag(7)
            }
            .pickerStyle(.segmented)
            Text("Bugünden itibaren \(days) günlük planın malzemeleri; porsiyonların hedefine göre hesaplanır. Plan değişirse liste de değişir.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
            if items.isEmpty {
                InfoCard(title: "Liste boş", text: "Tercihlerine uygun planlanmış öğün bulunamadı.")
            }
            ForEach(order, id: \.self) { g in
                VStack(alignment: .leading, spacing: 0) {
                    Text(Shopping.groupTitle(g)).font(.headline).padding(.bottom, 4)
                    ForEach(groups[g] ?? []) { item in
                        Button { store.toggleShopping(item.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(Color.ofDeep)
                                Text(item.name).strikethrough(checked.contains(item.id)).foregroundStyle(Color.ofInk)
                                Spacer()
                                Text(item.amountText).monospacedDigit().foregroundStyle(Color.ofMuted)
                            }
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(checked.contains(item.id) ? "Alındı" : "Alınmadı")
                        Divider().overlay(Color.ofDivider)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: Shopping.shareText(items, checked: checked)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Listeyi paylaş")
            }
        }
        .secondaryScreen()
    }
}
