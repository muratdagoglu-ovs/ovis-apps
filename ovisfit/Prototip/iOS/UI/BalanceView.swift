import SwiftUI

// MARK: - 09 Su

struct WaterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var kind = DrinkKind.water

    var body: some View {
        let s = store.hydration
        ScreenScroll {
            BrandBar()
            ScreenHeading(kicker: "Günlük sıvı", plain: "Su ", accent: "takibim.")

            WaterCard(summary: s)

            VStack(spacing: 0) {
                MetricLine(title: "Su", bold: false) {
                    Text("\(TRFormat.int(s.water)) ml").font(.headline).monospacedDigit()
                }
                MetricLine(title: "Diğer içecekler", bold: false) {
                    Text("\(TRFormat.int(s.other)) ml").font(.headline).monospacedDigit()
                }
            }

            SectionHeader("İçecek ekle")
            HStack(spacing: 8) {
                ForEach([DrinkKind.water, DrinkKind.other], id: \.self) { k in
                    Button(k) { kind = k }
                        .buttonStyle(PillButtonStyle(selected: kind == k))
                        .accessibilityAddTraits(kind == k ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                ForEach(Hydration.quickAmounts, id: \.self) { amount in
                    Button { store.addDrink(amount, kind: kind) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "cup.and.saucer").font(.body)
                            Text("+ \(amount) ml").font(.headline).monospacedDigit()
                                .minimumScaleFactor(0.7).lineLimit(1)
                        }
                        .foregroundStyle(Color.ofInk)
                        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(Color.ofWater, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(amount) mililitre \(kind == DrinkKind.water ? "su" : "diğer içecek") ekle")
                }
            }
            if let last = store.lastDrinkToday {
                Button {
                    store.undoDrink()
                } label: {
                    Label("Son eklemeyi geri al · \(last.amount) ml \(last.kind == DrinkKind.water ? "su" : "içecek")",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(LinkButtonStyle())
            }

            Toggle("Hekim sıvı kısıtlaması önerdi", isOn: Binding(
                get: { store.fluidRestricted }, set: { store.setFluidRestricted($0) }))
                .frame(minHeight: 48)
                .tint(Color.ofDeep)

            if store.fluidRestricted {
                Text("Otomatik hedef ve kalan miktar kapalı. İçeceklerini kaydedebilir, sınırını sağlık ekibinin önerisine göre takip edebilirsin.")
                    .font(.footnote).foregroundStyle(Color.ofMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: Binding(get: { store.fluidTarget }, set: { store.setFluidTarget($0) }),
                            in: Hydration.range, step: Hydration.step) {
                        Text("Günlük hedef · \(TRFormat.int(store.fluidTarget)) ml").font(.headline).monospacedDigit()
                    }
                    .accessibilityValue("\(store.fluidTarget) mililitre")
                    Text("Yetişkinler için genel başlangıç aralığı tüm içeceklerden günde yaklaşık 1,5–2 litredir; başlangıç değeri aralığın orta noktasıdır. Sıcak hava ve uzun egzersiz ihtiyacı değiştirebilir.")
                        .font(.footnote).foregroundStyle(Color.ofMuted)
                    Link("Kaynak · King's College Hospital", destination: URL(string: "https://www.kch.nhs.uk/patients-and-visitors/patients/hydration-matters/")!)
                        .font(.footnote)
                }
            }

            NavigationLink(value: Route.swelling) {
                LineRow(symbol: "leaf", title: "Ödem rehberi", detail: "Ayak ve bacak şişliği için") {
                    Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
                }
            }
            .buttonStyle(.plain)
        }
        .rootScreen()
    }
}

struct WaterCard: View {
    let summary: HydrationSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Kicker("Bugünkü tüm içecekler", color: .ofWaterInk)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(TRFormat.int(summary.total)).font(.system(.largeTitle).weight(.bold)).monospacedDigit()
                    Text("ml").font(.system(.largeTitle).weight(.bold))
                }
                .minimumScaleFactor(0.6).lineLimit(1)
                Text(subtitle).font(.subheadline).monospacedDigit()
            }
            .foregroundStyle(Color.ofWaterInk)
            .padding(18)
            Waves(progress: summary.progress ?? 0.5)
                .frame(height: 70)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ofWater)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var subtitle: String {
        guard let target = summary.target, let remaining = summary.remaining else { return "Hekim önerine göre takip" }
        return remaining == 0
            ? "\(TRFormat.int(target)) ml hedef · hedefe ulaştın"
            : "\(TRFormat.int(target)) ml hedef · \(TRFormat.int(remaining)) ml kaldı"
    }
    private var accessibility: String {
        if let target = summary.target, let remaining = summary.remaining {
            return "Bugün tüm içecekler \(summary.total) mililitre. Hedef \(target), kalan \(remaining) mililitre."
        }
        return "Bugün tüm içecekler \(summary.total) mililitre. Hekim kısıtlaması nedeniyle otomatik hedef kapalı."
    }
}

struct Waves: View {
    let progress: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let lift = CGFloat(min(max(progress, 0), 1)) * h * 0.25
            ZStack {
                wave(w, h, base: 0.40 - lift / h, amp: 0.22, phase: 0).fill(Color(hex: 0x9CCBD4))
                wave(w, h, base: 0.58 - lift / h, amp: 0.18, phase: 0.5).fill(Color(hex: 0x6BA6B6))
                wave(w, h, base: 0.78 - lift / h * 0.5, amp: 0.14, phase: 0.2).fill(Color(hex: 0x427E8B))
            }
        }
    }
    private func wave(_ w: CGFloat, _ h: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: h * base))
            p.addCurve(to: CGPoint(x: w, y: h * (base - amp * 0.4)),
                       control1: CGPoint(x: w * (0.3 + phase * 0.2), y: h * (base + amp)),
                       control2: CGPoint(x: w * (0.6 - phase * 0.2), y: h * (base - amp)))
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
    }
}

// MARK: - 10 Ödem rehberi

struct SwellingView: View {
    var body: some View {
        ScreenScroll {
            ScreenHeading(kicker: "Su ve sıvı", plain: "Ödem ", accent: "rehberi.")

            VStack(alignment: .leading, spacing: 10) {
                Text("Ne zaman yardım almalıyım?").font(.headline)
                Label("Şişlikle birlikte nefes darlığı veya göğüs ağrısı varsa Türkiye’de 112’yi ara.", systemImage: "phone.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ofWarn)
                Link(destination: URL(string: "tel://112")!) {
                    Label("112’yi ara", systemImage: "phone.arrow.up.right")
                }
                .buttonStyle(PrimaryButtonStyle(fill: .ofWarn))
                Text("Nedeni belirsiz tek taraflı şişlik, aniden başlayan veya şiddetli ağrılı şişlik, kızarıklık ya da sıcaklık varsa bugün sağlık değerlendirmesi al.")
                    .font(.subheadline).foregroundStyle(Color.ofMuted)
            }
            .padding(16)
            .background(Color(hex: 0xF6E3DC), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

            SectionHeader("Hafif, iki taraflı şişlikte")
            LineRow(symbol: "figure.walk", title: "Kısa hareket molası", detail: "Uzun süre oturduysan ve yürüyebiliyorsan kısa bir yürüyüş molası ver.")
            LineRow(symbol: "chair", title: "Ayaklarını yükselt", detail: "Dinlenirken ayaklarını bir yastıkla destekleyip yükselt.")
            LineRow(symbol: "fork.knife", title: "Tuzlu eşlikçileri değiştir", detail: "Öğünde turşu veya çok tuzlu bir sos varsa taze sebzeyle değiştirmeyi deneyebilirsin.")

            Text("Şişliğin varsa sıvı hedefini kendi kendine değiştirme; uygulama da ödem bildirimine göre hedefini otomatik değiştirmez. Şişlik artarsa veya birkaç günde düzelmezse hekime başvur. Bu rehber bilgilendirme amaçlıdır, tanı koymaz.")
                .font(.footnote).foregroundStyle(Color.ofMuted)

            VStack(alignment: .leading, spacing: 8) {
                Text("Kaynaklar").font(.headline)
                Link("NHS · Ayak ve bacaklarda ödem", destination: URL(string: "https://www.nhs.uk/conditions/oedema/")!)
                Link("Türkiye · 112 Acil Çağrı", destination: URL(string: "https://www.112.gov.tr/")!)
            }
            .font(.subheadline)
        }
        .secondaryScreen()
    }
}
