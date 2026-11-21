import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @State private var mealToDelete: Meal?

    var body: some View {
        let now = store.now
        let summary = store.summary(on: now)
        let target = store.target
        let plan = store.plan(for: now)
        let next = plan.flatMap { NextMeal.find(in: $0, loggedSlots: store.loggedSlots(on: now), now: now) }

        ScreenScroll {
            BrandBar()
            VStack(alignment: .leading, spacing: 6) {
                Kicker(TRDate.dayTitle(now))
                DisplayTitle(plain: TRDate.greeting(now), accent: (store.profile?.name ?? "") + ".")
                StreakChip(days: store.streaks.logging)
            }

            energyCard(summary: summary, target: target)

            NavigationLink(value: Route.photo) {
                Label("Tabağımı analiz et", systemImage: "camera")
            }
            .buttonStyle(PrimaryButtonStyle())
            NavigationLink(value: Route.barcode) {
                Label("Paketli ürün · barkod okut", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(LinkButtonStyle())
            .frame(maxWidth: .infinity)

            SectionHeader(title: "Sıradaki öğün") {
                Button("Planım ›") { router.tab = .plan }
                    .buttonStyle(LinkButtonStyle())
                    .font(.subheadline)
            }
            if let next {
                Button { router.tab = .plan } label: { NextMealCard(meal: next) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Günlük planı aç")
            } else {
                InfoCard(title: "Bugünkü planın tamam",
                         text: plan?.meals.isEmpty == false
                            ? "Planlanan öğünlerin saati geçti veya kaydedildi."
                            : "Tercihlerine uygun tarif bulunamadı. Plan ekranından hedefini ve tercihlerini kontrol edebilirsin.",
                         tint: .ofSage)
            }

            HStack(spacing: 14) {
                Button { router.tab = .water } label: {
                    StatTile(symbol: "drop", title: "Su",
                             value: TRFormat.int(store.hydration.water), unit: "ml",
                             detail: "Bugün içilen su", tint: .ofWater)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Su takibini aç")

                NavigationLink(value: Route.movement) {
                    let done = store.todayActivity
                    StatTile(symbol: "figure.walk", title: "Hareket",
                             value: "\(done?.minutes ?? store.movementMinutes)", unit: "dk",
                             detail: done.map { "Tamamlandı · \($0.title)" } ?? (store.movementOptions.first?.place ?? "Hareket planı"),
                             tint: .ofMove)
                }
                .buttonStyle(.plain)
            }

            QuickAddSection()
            ReminderSetupCard()

            ActivityTiles()
            if let balance = store.todayBalance {
                BalanceCard(balance: balance)
            }
            MacroCard()

            if !summary.meals.isEmpty {
                SectionHeader("Bugünkü öğünlerim")
                VStack(spacing: 0) {
                    ForEach(summary.meals) { meal in
                        MealLogRow(meal: meal)
                            .contextMenu {
                                Button { store.addFavorite(from: meal) } label: {
                                    Label(store.isFavorite(meal) ? "Favorilerde" : "Favorilere ekle", systemImage: "star")
                                }
                                .disabled(store.isFavorite(meal))
                                Button { _ = store.repeatMeal(portions: meal.portions, title: meal.title ?? meal.displayTitle, slot: meal.slot) } label: {
                                    Label("Tekrar ekle", systemImage: "plus.square.on.square")
                                }
                                Button(role: .destructive) { mealToDelete = meal } label: {
                                    Label("Kaydı sil", systemImage: "trash")
                                }
                            }
                            .accessibilityAction(named: "Kaydı sil") { mealToDelete = meal }
                    }
                }
                Text("Kayıtlar tahmini aralık olarak saklanır. Favorilere eklemek, tekrar eklemek veya silmek için kayda basılı tut.")
                    .font(.footnote).foregroundStyle(Color.ofMuted)
            }
        }
        .rootScreen()
        .confirmationDialog("Bu öğün kaydı silinsin mi?", isPresented: Binding(
            get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }), titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let m = mealToDelete { store.deleteMeal(m.id) }
                mealToDelete = nil
            }
        }
    }

    private func energyCard(summary: DaySummary, target: Int) -> some View {
        let pct = summary.percent(of: target)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker("Bugünkü enerji", color: Color.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TRFormat.int(summary.estimate))
                            .font(.system(.largeTitle, design: .default).weight(.bold))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("kcal").font(.body)
                    }
                    Text("\(TRFormat.int(target)) kcal günlük hedef")
                        .font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer(minLength: 8)
                EnergyRing(fraction: target > 0 ? Double(summary.estimate) / Double(target) : 0, label: "%\(pct)")
            }
            Divider().overlay(Color.white.opacity(0.25))
            HStack {
                Text("Hedefe kalan").font(.subheadline)
                Spacer()
                Text("\(TRFormat.int(summary.remaining(to: target))) kcal").font(.subheadline.weight(.bold)).monospacedDigit()
            }
            Text(summary.meals.isEmpty
                 ? "Henüz öğün kaydetmedin. Kaydettiğin öğünler burada toplanır."
                 : "Kayıtlı aralık \(TRFormat.range(summary.low, summary.high)) kcal · gösterilen değer aralıkların orta noktası, tahminidir.")
                .font(.footnote).foregroundStyle(Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Color.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bugünkü tahmini enerji \(summary.estimate) kilokalori, hedef \(target), hedefin yüzde \(pct)'i. Hedefe kalan \(summary.remaining(to: target)) kilokalori.")
    }
}

struct NextMealCard: View {
    let meal: PlannedMeal
    var body: some View {
        HStack(spacing: 14) {
            RecipeThumb(recipeID: meal.recipe.id)
                .frame(width: 104)
                .frame(maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Kicker("\(meal.slot.title) · \(meal.timeLabel)")
                Text(meal.recipe.name).font(.headline).foregroundStyle(Color.ofInk)
                Text(meal.recipe.subtitle).font(.subheadline).foregroundStyle(Color.ofMuted)
                Text("≈ \(TRFormat.int(meal.kcal)) kcal").font(.footnote.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Color.ofDeep)
            }
            .padding(.vertical, 14)
            Spacer(minLength: 8)
        }
        .frame(minHeight: 104)
        .background(Color.ofSage, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Örnek fotoğraf yalnızca ait olduğu tarifte (ızgara tavuk tabağı) kullanılır.
struct RecipeThumb: View {
    let recipeID: String
    var body: some View {
        if recipeID == "tavuk-bulgur" {
            Image("tabak").resizable().scaledToFill()
                .accessibilityHidden(true)
        } else {
            ZStack {
                Color.ofSoftLime
                Image(systemName: "fork.knife").font(.title2).foregroundStyle(Color.ofDeep)
            }
            .accessibilityHidden(true)
        }
    }
}

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    let unit: String
    let detail: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text(unit).font(.title3.weight(.bold))
            }
            Text(detail).font(.footnote).foregroundStyle(Color.ofMuted).lineLimit(2)
        }
        .foregroundStyle(Color.ofInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MealLogRow: View {
    let meal: Meal
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.displayTitle).font(.headline).foregroundStyle(Color.ofInk)
                    Text(subtitle).font(.footnote).foregroundStyle(Color.ofMuted)
                }
                Spacer(minLength: 8)
                Text("\(TRFormat.range(meal.low, meal.high)) kcal").font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(.vertical, 12)
            Divider().overlay(Color.ofDivider)
        }
        .accessibilityElement(children: .combine)
    }
    private var subtitle: String {
        var parts = [TRDate.short(meal.date, "HH.mm")]
        if let s = meal.slot { parts.append(s.title) }
        switch meal.source {
        case .demo?: parts.append("Demo tahmini · gerçek analiz değil")
        case .photo?: parts.append("Fotoğraf tahmini · onaylı")
        case .plan?: parts.append("Plandan")
        case .manual?: parts.append("Elle eklendi")
        case .barcode?: parts.append("Barkod · Open Food Facts")
        case .repeatMeal?: parts.append("Tekrar")
        case nil: parts.append("Tahmin")
        }
        return parts.joined(separator: " · ")
    }
}
