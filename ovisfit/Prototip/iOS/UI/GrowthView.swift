import SwiftUI
import Charts

// MARK: - 11 Gelişim

struct GrowthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false

    var body: some View {
        let r = store.weeklyReport
        let endDay = Calendar.current.date(byAdding: .day, value: -1, to: r.end) ?? r.end

        ScreenScroll {
            BrandBar()
            ScreenHeading(kicker: "\(TRDate.short(r.start, "d"))–\(TRDate.short(endDay, "d MMMM"))",
                          plain: "Haftalık ", accent: "gelişim.")

            VStack(alignment: .leading, spacing: 10) {
                Kicker("Son kilo kaydı", color: Color.white.opacity(0.75))
                if let latest = r.latest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(TRFormat.decimal(latest.kg)).font(.system(.largeTitle).weight(.bold)).monospacedDigit()
                        Text("kg")
                        Spacer()
                        if let c = r.change {
                            Text("\(c > 0 ? "+" : "")\(TRFormat.decimal(c)) kg bu hafta")
                                .font(.footnote.weight(.semibold)).monospacedDigit()
                        }
                    }
                    Text(TRDate.short(latest.date, "d MMMM")).font(.footnote).foregroundStyle(Color.white.opacity(0.75))
                } else {
                    Text("Henüz kilo kaydı yok").font(.title2.weight(.bold))
                }

                switch r.state {
                case .trend:
                    WeightChart(entries: r.weights, start: r.start, end: r.end)
                        .frame(height: 140)
                case .single:
                    Text("Bu hafta tek ölçüm var. Eğri için farklı bir günde bir tartım daha ekle.")
                        .font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
                case .empty:
                    Text(r.latest == nil
                         ? "İlk tartımını ekleyerek haftalık eğrini başlat. Her gün aynı saatte tartılmak karşılaştırmayı kolaylaştırır."
                         : "Bu hafta henüz tartım yok.")
                        .font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
                }

                Button { showAdd = true } label: { Label("Kilo kaydı ekle", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle(fill: .ofLime, ink: .ofInk))
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(Color.heroGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            SectionHeader("Haftanın kayıtları")
            LineRow(symbol: "fork.knife", title: "\(r.mealCount) öğün",
                    detail: r.mealCount == 0 ? "Bu hafta henüz öğün kaydı yok" : "\(r.mealDays) farklı günde kaydedildi")
            LineRow(symbol: "figure.walk", title: "\(r.activityMinutes) dakika hareket",
                    detail: r.activityCount == 0 ? "Bu hafta tamamlanan hareket yok" : "\(r.activityCount) hareket tamamlandı")

            StepsWeekSection()
            WeekBalanceSection(actualChange: r.change)

            InfoCard(title: "Ovi’den haftalık not", text: note(r))
            NavigationLink(value: Route.swap(.lunch)) { Text("Öğle alternatiflerini gör") }
                .buttonStyle(LinkButtonStyle())

            BadgesSection()

            if !store.weights.isEmpty {
                SectionHeader("Tartımlarım")
                VStack(spacing: 0) {
                    ForEach(Array(store.weights.reversed().prefix(8))) { w in
                        MetricLine(title: TRDate.short(w.date, "d MMMM yyyy"), bold: false) {
                            Text("\(TRFormat.decimal(w.kg)) kg").font(.headline).monospacedDigit()
                        }
                        .contextMenu {
                            Button(role: .destructive) { store.deleteWeight(w.id) } label: { Label("Sil", systemImage: "trash") }
                        }
                        .accessibilityAction(named: "Sil") { store.deleteWeight(w.id) }
                    }
                }
                Text("Silmek için kayda basılı tut.").font(.footnote).foregroundStyle(Color.ofMuted)
            }
        }
        .rootScreen()
        .sheet(isPresented: $showAdd) { AddWeightSheet().environmentObject(store) }
    }

    private func note(_ r: WeeklyReport) -> String {
        if r.mealCount == 0 && r.activityCount == 0 && r.weights.isEmpty {
            return "Bu hafta henüz kayıt yok. Bir öğünü fotoğrafla kaydetmek veya kısa bir yürüyüş iyi bir başlangıç olur."
        }
        if r.activityCount == 0 { return "Bu hafta \(r.mealCount) öğün kaydettin. Uygun bir günde 10 dakikalık hareket ekleyebilirsin." }
        if r.mealCount == 0 { return "Bu hafta \(r.activityMinutes) dakika hareket ettin. Öğünlerini kaydetmek enerji dengesini görmeni kolaylaştırır." }
        return "Bu hafta \(r.mealDays) günde öğün kaydettin ve \(r.activityMinutes) dakika hareket ettin. Böyle devam!"
    }
}

struct WeightChart: View {
    let entries: [WeightEntry]
    let start: Date
    let end: Date
    var body: some View {
        let values = entries.map(\.kg)
        let lo = (values.min() ?? 0) - 0.5, hi = (values.max() ?? 0) + 0.5
        Chart(entries) { e in
            LineMark(x: .value("Tarih", e.date), y: .value("Kilo", e.kg))
                .foregroundStyle(Color.ofRing)
                .lineStyle(StrokeStyle(lineWidth: 3))
            PointMark(x: .value("Tarih", e.date), y: .value("Kilo", e.kg))
                .foregroundStyle(Color.ofRing)
                .accessibilityLabel(Text(TRDate.short(e.date, "d MMMM")))
                .accessibilityValue(Text("\(TRFormat.decimal(e.kg)) kilogram"))
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: lo...hi)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.15))
                AxisValueLabel(format: .dateTime.day(), centered: false).foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.2))
                AxisValueLabel().foregroundStyle(Color.white.opacity(0.75))
            }
        }
    }
}

struct AddWeightSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ör. 74,6", text: $text)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Kilo, kilogram")
                    DatePicker("Tarih", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text(error ?? "Aynı güne ikinci kayıt öncekinin yerine geçer.")
                        .foregroundStyle(error == nil ? Color.ofMuted : Color.ofWarn)
                }
            }
            .navigationTitle("Kilo kaydı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        guard let p = NumberInput.parse(text), ["", "kg"].contains(p.unit),
                              ProfileDraft.weightRange.contains(p.value) else {
                            error = "30–350 kg arasında bir değer gir (ör. 74,6)."
                            return
                        }
                        store.addWeight(p.value, on: date)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
