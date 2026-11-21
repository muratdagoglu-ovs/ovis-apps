import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedDay = Date()
    @State private var showMethod = false
    @State private var expanded: MealSlot?

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDate(selectedDay, inSameDayAs: store.now)
        let plan = store.plan(for: selectedDay)

        ScreenScroll {
            BrandBar()
            ScreenHeading(kicker: TRDate.dayTitle(selectedDay), plain: "Günlük ", accent: "planım.")
            WeekStrip(selected: $selectedDay, today: store.now)

            HStack {
                Text("Beslenme").font(.title3.weight(.bold))
                Spacer()
                Pill(text: "\(TRFormat.int(store.target)) kcal hedef")
                Button { showMethod = true } label: {
                    Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hedef yöntemi ve varsayımlar")
            }

            if let plan {
                VStack(spacing: 0) {
                    ForEach(plan.meals) { meal in
                        PlannedMealRow(meal: meal, isToday: isToday,
                                       logged: store.isPlannedMealLogged(meal.slot, on: selectedDay),
                                       expanded: expanded == meal.slot,
                                       toggle: { expanded = expanded == meal.slot ? nil : meal.slot },
                                       log: { _ = store.logPlanned(meal, on: selectedDay) })
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                Text("Planlanan toplam ≈ \(TRFormat.int(plan.plannedKcal)) kcal. Porsiyonlar hedefe göre ölçeklenir; hedef değişince miktarlar da güncellenir.")
                    .font(.footnote).foregroundStyle(Color.ofMuted)

                if !plan.missing.isEmpty {
                    InfoCard(title: "Uygun tarif bulunamadı",
                             text: "\(plan.missing.map(\.title).joined(separator: ", ")) için tercihlerine ve alerjilerine uyan bir tarif yok. Bu öğünü fotoğrafla kaydedebilir veya profilinden tercihlerini ve hedefini (klinik planın varsa elle) düzenleyebilirsin.",
                             tint: Color(hex: 0xF6E3DC))
                }
            }

            if isToday {
                NavigationLink(value: Route.swap(.lunch)) {
                    Label("Planım değişti", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(PrimaryButtonStyle(fill: .ofLime, ink: .ofInk))
            }
            NavigationLink(value: Route.shopping) {
                LineRow(symbol: "cart", title: "Alışveriş listesi", detail: "Plandaki malzemeler, porsiyonuna göre") {
                    Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
                }
            }
            .buttonStyle(.plain)

            SectionHeader("Hareket")
            NavigationLink(value: Route.movement) {
                LineRow(symbol: "figure.walk",
                        title: store.todayActivity.map { "\($0.title) · \($0.minutes) dk" } ?? "\(store.movementMinutes) dk \(store.movementOptions.first?.title.lowercased(with: TRDate.locale) ?? "hareket")",
                        detail: store.todayActivity == nil ? (store.movementOptions.first?.place ?? "") : "Bugün tamamlandı") {
                    Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
                }
            }
            .buttonStyle(.plain)
        }
        .rootScreen()
        .sheet(isPresented: $showMethod) { MethodSheet(estimate: store.estimate).environmentObject(store) }
        .onChange(of: store.now) { old, new in
            // Gün değişince bugüne dön.
            if cal.isDate(selectedDay, inSameDayAs: old) && !cal.isDate(old, inSameDayAs: new) { selectedDay = new }
        }
    }
}

struct WeekStrip: View {
    @Binding var selected: Date
    let today: Date
    var body: some View {
        let cal = Calendar.current
        let start = ProgressReport.week(containing: today, calendar: cal).0
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start)!
                let on = cal.isDate(day, inSameDayAs: selected)
                Button { selected = day } label: {
                    VStack(spacing: 4) {
                        Text(TRDate.short(day, "EEE")).font(.caption.weight(.semibold))
                        Text(TRDate.short(day, "d")).font(.headline).monospacedDigit()
                    }
                    .foregroundStyle(on ? Color.white : Color.ofInk)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(on ? Color.ofDeep : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ofDivider.opacity(on ? 0 : 0.8)))
                    .overlay(alignment: .bottom) {
                        if cal.isDate(day, inSameDayAs: today) && !on {
                            Circle().fill(Color.ofDeep).frame(width: 5, height: 5).padding(.bottom, 5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TRDate.short(day, "d MMMM EEEE"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

struct PlannedMealRow: View {
    let meal: PlannedMeal
    let isToday: Bool
    let logged: Bool
    let expanded: Bool
    let toggle: () -> Void
    let log: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 14) {
                    IconTile(symbol: logged ? "checkmark" : (meal.slot == .lunch ? "fork.knife" : "clock"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(meal.timeLabel) · \(meal.slot.title)").font(.headline).foregroundStyle(Color.ofInk)
                        Text("\(meal.recipe.name) · \(meal.recipe.subtitle)").font(.subheadline).foregroundStyle(Color.ofMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text("\(TRFormat.int(meal.kcal))\nkcal").font(.footnote.weight(.semibold)).monospacedDigit()
                        .multilineTextAlignment(.trailing).foregroundStyle(Color.ofDeep)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Ayrıntıları gizle" : "Porsiyon ve besin değerlerini göster")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(meal.items, id: \.food.id) { item in
                        HStack {
                            Text(item.food.name).font(.subheadline)
                            Spacer()
                            Text("\(item.grams) g · \(item.kcal) kcal").font(.subheadline).monospacedDigit().foregroundStyle(Color.ofMuted)
                        }
                    }
                    Text("Protein \(Int(meal.protein.rounded())) g · Karbonhidrat \(Int(meal.carbs.rounded())) g · Yağ \(Int(meal.fat.rounded())) g")
                        .font(.footnote).foregroundStyle(Color.ofMuted)
                    Text(meal.allergens.isEmpty ? "Bilinen alerjen yok" : "Alerjen: " + meal.allergens.map(\.title).sorted().joined(separator: ", "))
                        .font(.footnote).foregroundStyle(meal.allergens.isEmpty ? Color.ofMuted : Color.ofWarn)
                    Text("Besin değerleri: USDA FoodData Central · porsiyon ×\(TRFormat.decimal(meal.scale, digits: 2))")
                        .font(.caption).foregroundStyle(Color.ofMuted)
                }
                .padding(.leading, 58)
            }

            if isToday {
                HStack {
                    Spacer()
                    Button(logged ? "Günlüğe kaydedildi" : "Yedim, günlüğe ekle", action: log)
                        .buttonStyle(LinkButtonStyle())
                        .font(.subheadline)
                        .disabled(logged)
                }
            }
            Divider().overlay(Color.ofDivider)
        }
        .padding(.top, 10)
    }
}

// MARK: - Planım değişti

struct SwapView: View {
    let slot: MealSlot
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @State private var context: MealContext = .out

    var body: some View {
        let current = store.plan(for: store.now)?.meals.first { $0.slot == slot }
        let options = store.profile.map {
            Planner.alternatives(slot: slot, context: context, profile: $0, target: store.target,
                                 db: store.db, excluding: current?.recipe.id)
        } ?? []

        ScreenScroll {
            ScreenHeading(kicker: slot == .lunch ? "Öğle yemeği" : slot.title, plain: "Planım ", accent: "değişti.")
            HStack(spacing: 8) {
                ForEach(MealContext.allCases) { c in
                    Button(c.title) { context = c }
                        .buttonStyle(PillButtonStyle(selected: context == c))
                        .accessibilityAddTraits(context == c ? .isSelected : [])
                }
            }
            SectionHeader("\(slot.title) alternatifleri")
            if options.isEmpty {
                InfoCard(title: "Uygun alternatif yok", text: "Tercihlerine ve alerjilerine uygun başka bir tarif bulunamadı.")
            }
            VStack(spacing: 10) {
                ForEach(options) { option in
                    Button {
                        store.swap(slot, to: option.recipe.id, on: store.now)
                        router.pop()
                    } label: {
                        HStack(spacing: 14) {
                            IconTile(symbol: "fork.knife")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.recipe.name).font(.headline).foregroundStyle(Color.ofInk)
                                Text(option.items.map { "\($0.food.name) \($0.grams) g" }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(Color.ofMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("≈ \(TRFormat.int(option.kcal)) kcal").font(.footnote.weight(.semibold)).monospacedDigit()
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
                        }
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Planlanan \(slot.title.lowercased(with: TRDate.locale)) öğününü bununla değiştir")
                }
            }
            Text("Bir seçeneğe dokunduğunda yalnızca planlanan öğün değişir. Yediğinde Plan ekranındaki “Yedim, günlüğe ekle” ile ayrıca kaydedersin.")
                .font(.footnote).foregroundStyle(Color.ofMuted)
        }
        .secondaryScreen()
    }
}

// MARK: - Hareket

struct MovementView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @State private var selectedID: String?

    var body: some View {
        let options = store.movementOptions
        let done = store.todayActivity
        let selected = options.first { $0.id == (selectedID ?? done?.optionID) } ?? options.first

        ScreenScroll {
            ScreenHeading(kicker: "Günlük hareket",
                          plain: selected.map { $0.isRest ? "Dinlenme " : "\($0.title) " } ?? "Hareket ",
                          accent: selected?.isRest == true ? "zamanı." : "zamanı.")

            if let s = selected {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker("Bugünkü aktivite", color: Color.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(s.minutes)").font(.system(.largeTitle).weight(.bold)).monospacedDigit()
                        Text("dakika")
                    }
                    RouteSketch().frame(height: 70).accessibilityHidden(true)
                    Text(s.place).font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            SectionHeader("Ne kadar vaktin var?")
            HStack(spacing: 8) {
                ForEach(MovementPlanner.durations, id: \.self) { m in
                    Button("\(m) dk") { store.movementMinutes = m }
                        .buttonStyle(PillButtonStyle(selected: store.movementMinutes == m))
                        .disabled(done != nil)
                }
            }

            SectionHeader("Seçenekler")
            VStack(spacing: 8) {
                ForEach(options) { o in
                    Button { selectedID = o.id } label: {
                        LineRow(symbol: o.symbol, title: o.title, detail: o.place) {
                            Image(systemName: o.id == selected?.id ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(Color.ofDeep)
                        }
                        .padding(.horizontal, 10)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(done != nil)
                    .accessibilityAddTraits(o.id == selected?.id ? .isSelected : [])
                }
            }
            Text(constraintText).font(.footnote).foregroundStyle(Color.ofMuted)

            if let s = selected {
                SectionHeader("Akış")
                ForEach(Array(s.steps.enumerated()), id: \.offset) { i, step in
                    LineRow(symbol: ["clock", s.symbol, "leaf"][min(i, 2)], title: step.title,
                            detail: "\(step.minutes) dk · \(step.detail)")
                }
            }
            InfoCard(title: "Güvenlik", text: "Göğüs ağrısı, baş dönmesi veya olağandışı nefes darlığı olursa dur. Kronik bir hastalığın varsa yeni bir programdan önce hekimine danış.")
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                Button {
                    if let s = selected, store.complete(s) { router.pop() }
                } label: {
                    Label(done.map { "Bugün tamamlandı · \($0.title)" } ?? "Tamamlandı olarak işaretle", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(done != nil || selected == nil)
            }
        }
        .secondaryScreen()
    }

    private var constraintText: String {
        let p = store.profile
        let eq = (p?.equipment ?? []).map(\.rawValue).sorted()
        let lim = (p?.limits ?? []).map(\.rawValue).sorted()
        return "Ekipman: \(eq.isEmpty ? "yok" : eq.joined(separator: ", ")) · Kısıtlar: \(lim.isEmpty ? "yok" : lim.joined(separator: ", ")). Profilinden düzenleyebilirsin. Tamamlama günde bir kez işlenir."
    }
}

struct RouteSketch: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Path { p in
                p.move(to: CGPoint(x: w * 0.03, y: h * 0.84))
                p.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.58), control1: CGPoint(x: w * 0.15, y: h * 0.5), control2: CGPoint(x: w * 0.24, y: h * 0.96))
                p.addCurve(to: CGPoint(x: w * 0.69, y: h * 0.44), control1: CGPoint(x: w * 0.45, y: h * 0.3), control2: CGPoint(x: w * 0.6, y: h * 0.9))
                p.addCurve(to: CGPoint(x: w * 0.96, y: h * 0.16), control1: CGPoint(x: w * 0.78, y: h * 0.1), control2: CGPoint(x: w * 0.88, y: h * 0.5))
            }
            .stroke(Color.ofRing, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().fill(Color.ofRing).frame(width: 14, height: 14)
                .position(x: w * 0.96, y: h * 0.16)
        }
    }
}
