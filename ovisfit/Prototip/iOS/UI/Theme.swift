import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
    static let ofBackground = Color(hex: 0xF8F8F1)
    static let ofInk = Color(hex: 0x192F28)
    static let ofDeep = Color(hex: 0x163E35)
    static let ofLime = Color(hex: 0xDEEFA1)
    static let ofRing = Color(hex: 0xD7ED88)
    static let ofWater = Color(hex: 0xDCEEF2)
    static let ofWaterInk = Color(hex: 0x1D4E5C)
    static let ofDivider = Color(hex: 0xDBE2D3)
    static let ofMuted = Color(hex: 0x56655F)
    static let ofSage = Color(hex: 0xE5EADA)
    static let ofSoftLime = Color(hex: 0xE8EFD9)
    static let ofMove = Color(hex: 0xE9EACF)
    static let ofWarn = Color(hex: 0x9B2C1F)
}

enum Metrics {
    static let gutter: CGFloat = 20
    static let section: CGFloat = 22
    static let cardRadius: CGFloat = 20
    static let actionHeight: CGFloat = 50
}

// MARK: - Yazı

/// "Günaydın, *Murat.*" gibi büyük başlık: sistem kalın + serif italik vurgu.
struct DisplayTitle: View {
    let plain: String
    let accent: String
    var body: some View {
        (Text(plain).font(.system(.largeTitle, design: .default).weight(.bold))
         + Text(accent).font(.system(.largeTitle, design: .serif).weight(.regular).italic()))
            .foregroundStyle(Color.ofInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct Kicker: View {
    let text: String
    var color: Color = .ofMuted
    init(_ text: String, color: Color = .ofMuted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
}

struct ScreenHeading: View {
    let kicker: String
    let plain: String
    let accent: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(kicker)
            DisplayTitle(plain: plain, accent: accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Color.ofInk)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.top, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.title = title; self.trailing = EmptyView() }
}

// MARK: - Marka

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.ofDeep, lineWidth: 6)
                Circle().trim(from: 0.62, to: 0.86)
                    .stroke(Color(hex: 0x9DB27A), style: StrokeStyle(lineWidth: 6))
            }
            .frame(width: 22, height: 22)
            (Text("Ovis").font(.system(.title, design: .default).weight(.bold))
             + Text("Fit").font(.system(.title, design: .serif).italic()))
                .foregroundStyle(Color.ofInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ovis Fit")
    }
}

struct OviAvatar: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Color.ofSoftLime)
            Image("ovi")
                .resizable()
                .scaledToFit()
                .frame(width: size * 1.55)
                .offset(y: size * 0.5)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Ana sekmelerin üst satırı: kelime imi ve profil avatarı.
struct BrandBar: View {
    var body: some View {
        HStack {
            Wordmark()
            Spacer()
            NavigationLink(value: Route.profile) {
                OviAvatar()
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Profilim")
            .accessibilityHint("Profil bilgilerini ve hedefini düzenle")
        }
    }
}

// MARK: - Düğmeler

struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = .ofDeep
    var ink: Color = .white
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: Metrics.actionHeight)
            .padding(.horizontal, 16)
            .background(fill.opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.ofDeep.opacity(configuration.isPressed ? 0.6 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct PillButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.white : Color.ofInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(selected ? Color.ofDeep : Color.ofSoftLime,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Alt kenarda sabit ana eylem.
struct BottomAction<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 8) { content }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Color.ofBackground.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Kartlar ve satırlar

struct InfoCard: View {
    let title: String
    let text: String
    var tint: Color = .ofSoftLime
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(Color.ofInk)
            Text(text).font(.subheadline).foregroundStyle(Color.ofMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct IconTile: View {
    let symbol: String
    var tint: Color = .ofSoftLime
    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(Color.ofDeep)
            .frame(width: 44, height: 44)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct LineRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.ofInk)
                Text(detail).font(.subheadline).foregroundStyle(Color.ofMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

extension LineRow where Trailing == EmptyView {
    init(symbol: String, title: String, detail: String) {
        self.symbol = symbol; self.title = title; self.detail = detail; self.trailing = EmptyView()
    }
}

struct MetricLine<Trailing: View>: View {
    let title: String
    var bold = true
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(bold ? .headline : .body).foregroundStyle(Color.ofInk)
                Spacer(minLength: 8)
                trailing
            }
            .frame(minHeight: 50)
            Divider().overlay(Color.ofDivider)
        }
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.ofInk)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.ofSoftLime, in: Capsule())
    }
}

struct EnergyRing: View {
    let fraction: Double
    let label: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color.ofRing, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 92, height: 92)
    }
}

/// Ana içerik kaydırma iskeleti: 20 pt kenar, 22 pt bölüm aralığı.
struct ScreenScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.section) { content }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ofBackground.ignoresSafeArea())
    }
}

enum TRDate {
    static let locale = Locale(identifier: "tr_TR")
    /// "20 Kasım · Cuma"
    static func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "d MMMM"
        let w = DateFormatter()
        w.locale = locale
        w.dateFormat = "EEEE"
        return f.string(from: date) + " · " + w.string(from: date)
    }
    static func short(_ date: Date, _ format: String = "d MMM") -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f.string(from: date)
    }
    static func greeting(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Günaydın, "
        case 12..<18: return "İyi günler, "
        default: return "İyi akşamlar, "
        }
    }
}

// MARK: - Giriş kutusu

/// Kutunun tamamı dokunulabilir metin alanı. SwiftUI'da TextField yalnızca yazı satırına
/// dokunulunca odaklanır; kutunun boş kısmına dokunmak da klavyeyi açmalı.
struct BoxField: View {
    let prompt: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let contentType: UITextContentType?
    let autocorrect: Bool
    let invalid: Bool
    let identifier: String
    @FocusState private var focused: Bool

    init(_ prompt: String, text: Binding<String>, keyboard: UIKeyboardType = .default,
         contentType: UITextContentType? = nil, autocorrect: Bool = false, invalid: Bool = false,
         identifier: String = "") {
        self.prompt = prompt
        self._text = text
        self.keyboard = keyboard
        self.contentType = contentType
        self.autocorrect = autocorrect
        self.invalid = invalid
        self.identifier = identifier
    }

    var body: some View {
        TextField(prompt, text: $text)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .autocorrectionDisabled(!autocorrect)
            .textInputAutocapitalization(keyboard == .default ? .words : .never)
            .focused($focused)
            .font(.body)
            .foregroundStyle(Color.ofInk)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(invalid ? Color.ofWarn : (focused ? Color.ofDeep : Color.ofDivider),
                            lineWidth: focused || invalid ? 1.5 : 1)
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { focused = true }
            .accessibilityIdentifier(identifier)
    }
}

enum Keyboard {
    /// Açık klavyeyi kapatır (sayı klavyesinde "Bitti" tuşu yoktur).
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
