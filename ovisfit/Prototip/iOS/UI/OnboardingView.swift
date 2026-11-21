import SwiftUI

/// İlk açılış: her ekranda tek soru, çarklar ve kartlarla (klavye yalnızca isim için).
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore

    enum Step: Int, CaseIterable {
        case welcome, name, sex, age, height, weight, activity, goal, food, summary
    }

    @State private var step: Step = .welcome
    @State private var forward = true
    @State private var name = ""
    @State private var sex: Sex?
    @State private var age = 30
    @State private var height = 170
    @State private var weightKg = 70
    @State private var weightTenth = 0
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .maintain
    @State private var diet: DietPreference = .omnivore
    @State private var allergens: Set<Allergen> = []
    @FocusState private var nameFocused: Bool

    private var weight: Double { Double(weightKg) + Double(weightTenth) / 10 }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var profile: Profile {
        var p = Profile(name: trimmedName, age: age, heightCm: Double(height), weightKg: weight,
                        sex: sex ?? .unspecified, activity: activity, goal: goal)
        p.diet = diet
        p.allergens = allergens
        return p
    }

    private var canContinue: Bool {
        switch step {
        case .name: return !trimmedName.isEmpty && trimmedName.count <= 40
        case .sex: return sex != nil
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome { topBar }
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            bottomButton
        }
        .background(Color.ofBackground.ignoresSafeArea())
        .onAppear {
            if store.legacyGoal != nil { goal = store.legacyGoal! }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-OvisOnboardingStep"), i + 1 < args.count,
               let n = Int(args[i + 1]), let s = Step(rawValue: n) {
                if n > Step.name.rawValue { name = "Murat"; sex = .male }
                step = s
            }
            #endif
        }
    }

    // MARK: Üst çubuk ve alt düğme

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .foregroundStyle(Color.ofInk)
                    .frame(width: 44, height: 44)
                    .background(Color.ofSoftLime, in: Circle())
            }
            .accessibilityLabel("Geri")
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.ofDivider)
                    Capsule().fill(Color.ofDeep)
                        .frame(width: g.size.width * progress)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Adım \(step.rawValue) / \(Step.allCases.count - 1)")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
    }

    private var progress: Double {
        Double(step.rawValue) / Double(Step.allCases.count - 1)
    }

    private var bottomButton: some View {
        VStack(spacing: 10) {
            Button {
                if step == .summary { finish() } else { go(1) }
            } label: {
                Text(buttonTitle)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            if step == .food {
                Text("Daha sonra Profil'den değiştirebilirsin.").font(.footnote).foregroundStyle(Color.ofMuted)
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: return "Başlayalım"
        case .food: return allergens.isEmpty && diet == .omnivore ? "Atla" : "Devam"
        case .summary: return "Planımı oluştur"
        default: return "Devam"
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        nameFocused = false
        forward = delta > 0
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { step = next }
        if next == .name {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true }
        }
    }

    private func finish() {
        store.saveProfile(profile)
    }

    // MARK: Adımlar

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .name: nameStep
        case .sex: sexStep
        case .age: wheelStep(kicker: "Yaş", plain: "Kaç ", accent: "yaşındasın?",
                             note: "Plan yetişkinler (18+) için hazırlanır.") {
            Picker("Yaş", selection: $age) {
                ForEach(18...100, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .overlay(alignment: .trailing) { unit("yaş") }
        }
        case .height: wheelStep(kicker: "Boy", plain: "Boyun ", accent: "kaç?", note: nil) {
            Picker("Boy", selection: $height) {
                ForEach(120...220, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .overlay(alignment: .trailing) { unit("cm") }
        }
        case .weight: wheelStep(kicker: "Kilo", plain: "Kilon ", accent: "kaç?",
                                note: "Gelişim ekranından tartımlarını ekledikçe hedeflerin güncellenir.") {
            HStack(spacing: 0) {
                Picker("Kilo", selection: $weightKg) {
                    ForEach(35...250, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                Picker("Ondalık", selection: $weightTenth) {
                    ForEach(0...9, id: \.self) { Text(",\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(width: 90)
                unit("kg").padding(.trailing, 0)
            }
        }
        case .activity: activityStep
        case .goal: goalStep
        case .food: foodStep
        case .summary: summaryStep
        }
    }

    private func header(_ kicker: String, _ plain: String, _ accent: String, _ note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker(kicker)
            DisplayTitle(plain: plain, accent: accent)
            if let note {
                Text(note).font(.subheadline).foregroundStyle(Color.ofMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func unit(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold)).foregroundStyle(Color.ofMuted)
            .padding(.trailing, 28)
            .allowsHitTesting(false)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            ZStack {
                Circle().fill(Color.ofLime).frame(width: 220, height: 220)
                Image("ovi").resizable().scaledToFit().frame(height: 230).offset(y: 10)
            }
            .accessibilityHidden(true)
            VStack(spacing: 10) {
                Wordmark()
                Text("Tabağını, suyunu ve hareketini tek yerden takip et. Birkaç kısa soruyla sana özel günlük planını oluşturalım.")
                    .font(.body).foregroundStyle(Color.ofMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Bilgilerin yalnızca bu cihazda saklanır", systemImage: "lock.fill")
                .font(.footnote).foregroundStyle(Color.ofMuted)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            header("Tanışalım", "Sana nasıl ", "hitap edelim?")
            VStack(alignment: .leading, spacing: 8) {
                TextField("Adın", text: $name)
                    .font(.system(.title, design: .default).weight(.semibold))
                    .foregroundStyle(Color.ofInk)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($nameFocused)
                    .onSubmit { if canContinue { go(1) } }
                    .accessibilityIdentifier("onb.name")
                Rectangle().fill(nameFocused ? Color.ofDeep : Color.ofDivider).frame(height: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { nameFocused = true }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nameFocused = true } }
    }

    private var sexStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header("Hakkında", "Merhaba \(trimmedName)! ", "Cinsiyetin?",
                       "Dinlenme enerjini daha doğru hesaplamak için kullanılır.")
                VStack(spacing: 12) {
                    ChoiceCard(symbol: "figure.stand.dress", title: Sex.female.rawValue, detail: nil, selected: sex == .female) { sex = .female }
                    ChoiceCard(symbol: "figure.stand", title: Sex.male.rawValue, detail: nil, selected: sex == .male) { sex = .male }
                    ChoiceCard(symbol: "person.fill.questionmark", title: Sex.unspecified.rawValue,
                               detail: "Ortalama değer kullanılır", selected: sex == .unspecified) { sex = .unspecified }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 28)
        }
    }

    private func wheelStep<W: View>(kicker: String, plain: String, accent: String, note: String?,
                                    @ViewBuilder wheel: () -> W) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(kicker, plain, accent, note)
            wheel()
                .frame(height: 216)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 28)
    }

    private var activityStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header("Hareket", "Günün nasıl ", "geçiyor?")
                VStack(spacing: 12) {
                    let symbols: [ActivityLevel: String] = [.low: "sofa", .moderate: "figure.walk", .high: "figure.run"]
                    ForEach(ActivityLevel.allCases) { level in
                        ChoiceCard(symbol: symbols[level] ?? "figure.walk", title: level.rawValue, detail: level.detail,
                                   selected: activity == level) { activity = level }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 28)
        }
    }

    private var goalStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header("Hedef", "Hedefin ", "ne?", "Öğün ve porsiyon önerilerin bu seçime göre şekillenecek.")
                VStack(spacing: 12) {
                    ChoiceCard(symbol: "arrow.down.right", title: Goal.lose.rawValue, detail: "Günde yaklaşık 500 kcal açık",
                               selected: goal == .lose) { goal = .lose }
                    ChoiceCard(symbol: "arrow.right", title: Goal.maintain.rawValue, detail: "Dengeyi koru",
                               selected: goal == .maintain) { goal = .maintain }
                    ChoiceCard(symbol: "arrow.up.right", title: Goal.gain.rawValue, detail: "Günde yaklaşık 300 kcal fazla",
                               selected: goal == .gain) { goal = .gain }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 28)
        }
    }

    private var foodStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header("Beslenme", "Neleri ", "yemiyorsun?", "Seçtiklerin plan ve önerilerde gösterilmez.")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Beslenme tercihi").font(.headline)
                    FlowChips(items: DietPreference.allCases.map { ($0.id, $0.rawValue) },
                              isOn: { $0 == diet.id }, toggle: { id in diet = DietPreference(rawValue: id) ?? .omnivore })
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Alerjiler").font(.headline)
                    FlowChips(items: Allergen.allCases.map { ($0.id, $0.title) },
                              isOn: { id in allergens.contains { $0.id == id } },
                              toggle: { id in
                                  guard let a = Allergen(rawValue: id) else { return }
                                  if allergens.contains(a) { allergens.remove(a) } else { allergens.insert(a) }
                              })
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 28)
        }
    }

    private var summaryStep: some View {
        let estimate = EnergyCalculator.estimate(profile)
        let targets = Targets.daily(for: profile)
        return ScrollView {
            VStack(spacing: 22) {
                OviAvatar(size: 96)
                    .padding(.top, 20)
                VStack(spacing: 6) {
                    Kicker("Günlük enerji hedefin")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TRFormat.int(estimate.target))
                            .font(.system(size: 56, weight: .bold)).monospacedDigit()
                        Text("kcal").font(.title3.weight(.semibold)).foregroundStyle(Color.ofMuted)
                    }
                    .foregroundStyle(Color.ofInk)
                    .accessibilityElement(children: .combine)
                    Text("\(trimmedName), \(goal.rawValue.lowercased(with: TRDate.locale)) hedefin için hazırlandı.")
                        .font(.subheadline).foregroundStyle(Color.ofMuted).multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    summaryTile("shoeprints.fill", TRFormat.int(targets.steps), "adım")
                    summaryTile("flame", TRFormat.int(targets.activeKcal), "kcal hareket")
                    summaryTile("drop.fill", TRFormat.int(Hydration.defaultTarget), "ml sıvı")
                }
                Text("Hesap Mifflin-St Jeor yöntemine dayanır ve bir başlangıç tahminidir. Gebelik, kronik hastalık veya klinik bir plan varsa Profil'den hedefini elle girebilirsin.")
                    .font(.footnote).foregroundStyle(Color.ofMuted).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metrics.gutter)
        }
    }

    private func summaryTile(_ symbol: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Color.ofDeep)
            Text(value).font(.headline).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(Color.ofMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Büyük, dokunmatik seçim kartı.
struct ChoiceCard: View {
    let symbol: String
    let title: String
    let detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(selected ? Color.white : Color.ofDeep)
                    .frame(width: 52, height: 52)
                    .background(selected ? Color.ofDeep : Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.ofInk)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(Color.ofMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Color.ofDeep : Color.ofDivider)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(selected ? Color.ofDeep : Color.clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Satıra sığdığı kadar dizilen, dokunarak açılıp kapanan etiketler.
struct FlowChips: View {
    let items: [(id: String, title: String)]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.id) { item in
                let on = isOn(item.id)
                Button { toggle(item.id) } label: {
                    HStack(spacing: 6) {
                        if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(item.title).font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(on ? Color.white : Color.ofInk)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(on ? Color.ofDeep : Color.white, in: Capsule())
                    .overlay(Capsule().stroke(on ? Color.clear : Color.ofDivider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
