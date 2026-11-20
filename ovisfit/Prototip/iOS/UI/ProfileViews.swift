import SwiftUI

/// Profil akışının ortak taslağı (1/2 bilgiler, 2/2 hedef ve tercihler).
@MainActor
final class ProfileEditor: ObservableObject {
    @Published var draft = ProfileDraft()
    @Published var goal: Goal = .maintain
    @Published var diet: DietPreference = .omnivore
    @Published var allergens: Set<Allergen> = []
    @Published var limits: Set<MovementLimit> = []
    @Published var equipment: Set<Equipment> = []
    @Published var mealTimes = MealTimes()
    @Published var useManualTarget = false
    @Published var manualTargetText = ""
    @Published var errors: [ProfileField: String] = [:]
    private var original: Profile?

    func load(_ profile: Profile?, legacyGoal: Goal?) {
        original = profile
        guard let p = profile else {
            goal = legacyGoal ?? .maintain
            return
        }
        draft = ProfileDraft(profile: p)
        goal = p.goal; diet = p.diet; allergens = p.allergens; limits = p.limits
        equipment = p.equipment; mealTimes = p.mealTimes
        useManualTarget = p.manualTarget != nil
        manualTargetText = p.manualTarget.map(String.init) ?? ""
    }

    func validateStepOne() -> Bool {
        switch draft.validate() {
        case .success: errors = [:]; return true
        case .failure(let e): errors = e.fields; return false
        }
    }

    var manualTarget: Int? {
        guard useManualTarget, let v = NumberInput.parse(manualTargetText)?.value,
              EnergyCalculator.manualRange.contains(Int(v)) else { return nil }
        return Int(v)
    }
    var manualTargetInvalid: Bool { useManualTarget && manualTarget == nil }

    /// Onaya sunulacak profil (doğrulanmamışsa nil).
    func build() -> Profile? {
        guard case .success(let v) = draft.validate(), !manualTargetInvalid else { return nil }
        var p = Profile(name: v.name, age: v.age, heightCm: v.heightCm, weightKg: v.weightKg,
                        sex: draft.sex, activity: draft.activity, goal: goal)
        p.diet = diet; p.allergens = allergens; p.limits = limits; p.equipment = equipment
        p.mealTimes = mealTimes; p.manualTarget = manualTarget
        p.confirmedAt = original?.confirmedAt
        return p
    }
}

enum ProfileMode { case onboarding, edit }

// MARK: - 1 / 2

struct ProfileFormView: View {
    let mode: ProfileMode
    @EnvironmentObject private var store: AppStore
    @StateObject private var editor = ProfileEditor()
    @State private var loaded = false
    @State private var showGoal = false
    @FocusState private var focus: ProfileField?

    var body: some View {
        ScreenScroll {
            HStack(alignment: .bottom, spacing: 14) {
                ScreenHeading(kicker: "Profil · 1 / 2", plain: "Seni ", accent: "tanıyalım.")
                OviAvatar(size: 64)
            }
            Text("Günlük planını oluşturmak için bilgilerini gir. Bilgiler yalnızca bu cihazda saklanır.")
                .font(.subheadline).foregroundStyle(Color.ofMuted)

            VStack(spacing: 14) {
                field(.name, "İsim", text: $editor.draft.name, prompt: "Adın", keyboard: .default)
                field(.age, "Yaş (yıl)", text: $editor.draft.age, prompt: "ör. 35", keyboard: .numberPad)
                field(.height, "Boy (cm)", text: $editor.draft.height, prompt: "ör. 175", keyboard: .decimalPad)
                field(.weight, "Kilo (kg)", text: $editor.draft.weight, prompt: "ör. 72,5", keyboard: .decimalPad)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cinsiyet").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ofInk)
                    Picker("Cinsiyet", selection: $editor.draft.sex) {
                        ForEach(Sex.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            SectionHeader("Günlük hareket düzeyin")
            HStack(spacing: 8) {
                ForEach(ActivityLevel.allCases) { level in
                    Button(level.rawValue) { editor.draft.activity = level }
                        .buttonStyle(PillButtonStyle(selected: editor.draft.activity == level))
                        .accessibilityAddTraits(editor.draft.activity == level ? .isSelected : [])
                }
            }
            Text(editor.draft.activity.detail).font(.footnote).foregroundStyle(Color.ofMuted)

            if !editor.errors.isEmpty {
                InfoCard(title: "Bilgilerini kontrol et",
                         text: ProfileField.allCases.compactMap { editor.errors[$0] }.joined(separator: "\n"),
                         tint: Color(hex: 0xF6E3DC))
            }

            if mode == .edit {
                ConnectionsSection()
                ServerSettingsSection()
                DataSection()
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    focus = nil
                    if editor.validateStepOne() { showGoal = true }
                } label: {
                    Label("Devam et", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .navigationDestination(isPresented: $showGoal) {
            GoalView(mode: mode, editor: editor)
        }
        .secondaryScreen()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Bitti") { focus = nil }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            editor.load(store.profile, legacyGoal: store.legacyGoal)
        }
    }

    private func field(_ f: ProfileField, _ title: String, text: Binding<String>, prompt: String,
                       keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ofInk)
            TextField(prompt, text: text)
                .keyboardType(keyboard)
                .textContentType(f == .name ? .givenName : nil)
                .autocorrectionDisabled(f != .name)
                .focused($focus, equals: f)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(editor.errors[f] == nil ? Color.ofDivider : Color.ofWarn, lineWidth: 1))
                .accessibilityLabel(title)
            if let error = editor.errors[f] {
                Text(error).font(.footnote).foregroundStyle(Color.ofWarn)
            }
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.title; configuration.icon }
    }
}

// MARK: - 2 / 2

struct GoalView: View {
    let mode: ProfileMode
    @ObservedObject var editor: ProfileEditor
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var showMethod = false

    private let goalSymbols: [Goal: String] = [.lose: "arrow.down.right", .maintain: "arrow.right", .gain: "arrow.up.right"]

    var body: some View {
        let preview = editor.build()
        let estimate = preview.map(EnergyCalculator.estimate)

        ScreenScroll {
            ScreenHeading(kicker: "Profil · 2 / 2", plain: "Hedefin ", accent: "ne?")
            Text("Öğün ve porsiyon önerilerin bu seçime göre şekillenecek.")
                .font(.subheadline).foregroundStyle(Color.ofMuted)

            VStack(spacing: 10) {
                ForEach(Goal.allCases) { goal in
                    Button { editor.goal = goal } label: {
                        HStack(spacing: 14) {
                            IconTile(symbol: goalSymbols[goal] ?? "arrow.right",
                                     tint: editor.goal == goal ? .ofLime : .ofSoftLime)
                            Text(goal.rawValue).font(.headline).foregroundStyle(Color.ofInk)
                            Spacer()
                            Image(systemName: editor.goal == goal ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(Color.ofDeep)
                        }
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(editor.goal == goal ? Color.ofDeep : Color.ofDivider, lineWidth: editor.goal == goal ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(editor.goal == goal ? .isSelected : [])
                }
            }

            SectionHeader("Öğün saatleri")
            VStack(spacing: 0) {
                ForEach(MealSlot.allCases) { slot in
                    if slot != .snack || editor.mealTimes.includeSnack {
                        DatePicker(slot.title, selection: timeBinding(slot), displayedComponents: .hourAndMinute)
                            .frame(minHeight: 48)
                        Divider().overlay(Color.ofDivider)
                    }
                }
                Toggle("Ara öğün planla", isOn: $editor.mealTimes.includeSnack)
                    .frame(minHeight: 48)
            }

            SectionHeader("Beslenme tercihi")
            Picker("Beslenme tercihi", selection: $editor.diet) {
                ForEach(DietPreference.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

            SectionHeader("Alerjiler")
            ToggleList(items: Allergen.allCases, title: \.title, selection: $editor.allergens)
            Text("Seçtiğin alerjenleri içeren tarifler ve öneriler gösterilmez. Paketli ürünlerde etiketi ayrıca kontrol et.")
                .font(.footnote).foregroundStyle(Color.ofMuted)

            SectionHeader("Hareket kısıtları ve ekipman")
            ToggleList(items: MovementLimit.allCases, title: \.rawValue, selection: $editor.limits)
            ToggleList(items: Equipment.allCases, title: { "Elimde var: " + $0.rawValue }, selection: $editor.equipment)

            SectionHeader("Günlük enerji hedefi")
            Toggle("Hekim/diyetisyen planım var, hedefi kendim gireceğim", isOn: $editor.useManualTarget)
            if editor.useManualTarget {
                TextField("kcal (1.000–5.000)", text: $editor.manualTargetText)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 14).frame(minHeight: 48)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("Günlük enerji hedefi, kilokalori")
                if editor.manualTargetInvalid {
                    Text("1.000 ile 5.000 kcal arasında bir değer gir.").font(.footnote).foregroundStyle(Color.ofWarn)
                }
            }
            if let estimate {
                TargetSummary(estimate: estimate) { showMethod = true }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    guard let p = editor.build() else { return }
                    store.saveProfile(p)
                    if mode == .edit { router.popToRoot() }
                } label: {
                    Label(mode == .onboarding ? "Onayla ve planımı gör" : "Değişiklikleri kaydet", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(preview == nil)
            }
        }
        .sheet(isPresented: $showMethod) { MethodSheet(estimate: estimate).environmentObject(store) }
        .secondaryScreen()
    }

    private func timeBinding(_ slot: MealSlot) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: editor.mealTimes.minutes(for: slot) / 60,
                                  minute: editor.mealTimes.minutes(for: slot) % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            editor.mealTimes.set((c.hour ?? 0) * 60 + (c.minute ?? 0), for: slot)
        }
    }
}

struct ToggleList<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Set<Item>
    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Toggle(title(item), isOn: Binding(
                    get: { selection.contains(item) },
                    set: { on in if on { selection.insert(item) } else { selection.remove(item) } }))
                .frame(minHeight: 48)
                Divider().overlay(Color.ofDivider)
            }
        }
    }
}

struct TargetSummary: View {
    let estimate: EnergyEstimate
    let showMethod: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(TRFormat.int(estimate.target)).font(.largeTitle.weight(.bold)).monospacedDigit()
                Text("kcal / gün").foregroundStyle(Color.ofMuted)
                Spacer()
                Button(action: showMethod) {
                    Image(systemName: "info.circle").font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hedef yöntemi ve varsayımlar")
            }
            Text(detail)
                .font(.footnote).foregroundStyle(Color.ofMuted)
        }
        .padding(16)
        .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var detail: String {
        if estimate.isManual { return "Elle girdiğin hedef kullanılıyor." }
        let sign = estimate.adjustment > 0 ? "+" : ""
        let diff = estimate.adjustment == 0 ? "" : ", hedef farkı \(sign)\(estimate.adjustment) kcal"
        let floor = estimate.floorApplied ? " · güvenlik alt sınırı uygulandı" : ""
        return "Tahmini ihtiyaç \(TRFormat.int(estimate.maintenanceKcal)) kcal\(diff)\(floor)."
    }
}

struct MethodSheet: View {
    let estimate: EnergyEstimate?
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeading(kicker: "Hedef yöntemi", plain: "Nasıl ", accent: "hesaplıyoruz?")
                if let e = estimate {
                    VStack(spacing: 0) {
                        MetricLine(title: "Dinlenme enerjisi", bold: false) { Text("\(TRFormat.int(e.restingKcal)) kcal").bold().monospacedDigit() }
                        MetricLine(title: "Günlük ihtiyaç (aktiviteyle)", bold: false) { Text("\(TRFormat.int(e.maintenanceKcal)) kcal").bold().monospacedDigit() }
                        MetricLine(title: "Hedef farkı", bold: false) { Text("\(e.adjustment > 0 ? "+" : "")\(e.adjustment) kcal").bold().monospacedDigit() }
                        MetricLine(title: "Alt sınır", bold: false) { Text("\(TRFormat.int(e.floorKcal)) kcal").bold().monospacedDigit() }
                        MetricLine(title: e.isManual ? "Elle girilen hedef" : "Günlük hedef") { Text("\(TRFormat.int(e.target)) kcal").bold().monospacedDigit() }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(EnergyCalculator.assumptions, id: \.self) { line in
                        Label { Text(line).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.circle") }
                            .font(.subheadline)
                    }
                }
                InfoCard(title: "Plan verisi", text: store.db.note)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kaynaklar").font(.headline)
                    Link("Mifflin-St Jeor, Am J Clin Nutr 1990 (PubMed)", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/2305711/")!)
                    ForEach(store.db.sources.filter { !$0.url.isEmpty }, id: \.id) { s in
                        if let url = URL(string: s.url) { Link(s.title, destination: url) }
                    }
                }
                .font(.subheadline)
            }
            .secondaryScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Ayarlar

struct ServerSettingsSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var text = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Analiz sunucusu")
            Text("Xcode'dan kurulan geliştirme sürümü Mac'teki sunucuyu kendiliğinden kullanır (aynı Wi‑Fi). TestFlight sürümü için erişilebilir bir HTTPS adresi gerekir. API anahtarı yalnızca sunucuda tutulur.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
            TextField(store.bundledServerAddress.isEmpty ? "https://sunucu.ornek.com" : store.bundledServerAddress, text: $text)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Analiz sunucusu adresi")
            HStack {
                Button("Kaydet") {
                    message = store.setServerOverride(text)
                        ? (text.isEmpty ? "Varsayılan adres kullanılacak." : "Adres kaydedildi.")
                        : (AppStore.allowsInsecureLocal ? "Geçerli bir https:// adresi veya yerel ağdaki http://<mac-adı>.local:8787 adresini gir." : "Fiziksel cihazda https:// ile başlayan bir adres gerekir.")
                }
                .buttonStyle(LinkButtonStyle())
                Spacer()
                Text(store.plateEndpoint == nil ? "Yapılandırılmadı" : "Etkin").font(.footnote).foregroundStyle(Color.ofMuted)
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(Color.ofMuted) }
        }
        .onAppear { text = store.serverOverride }
    }
}

struct DataSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Verilerim")
            Text("Profil, öğün, içecek, kilo ve hareket kayıtların yalnızca bu cihazda saklanır.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
            Button("Tüm verilerimi sil", role: .destructive) { confirm = true }
                .frame(minHeight: 44)
        }
        .confirmationDialog("Tüm kayıtlar bu cihazdan silinsin mi?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Sil", role: .destructive) { store.eraseAll() }
        }
    }
}
