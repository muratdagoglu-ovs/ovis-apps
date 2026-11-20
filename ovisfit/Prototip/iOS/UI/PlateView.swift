import SwiftUI
import PhotosUI
import ImageIO
import UIKit
import AVFoundation

// MARK: - Ağ

struct PlateClient {
    let endpoint: URL

    func analyze(_ jpeg: Data) async throws -> PlateResponse {
        var request = URLRequest(url: endpoint, timeoutInterval: 65)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: jpeg)
            guard let http = response as? HTTPURLResponse else { throw PlateServiceError.badResponse }
            if let error = PlateServiceError.from(status: http.statusCode) { throw error }
            guard let result = try? JSONDecoder().decode(PlateResponse.self, from: data) else {
                throw PlateServiceError.badResponse
            }
            return result
        } catch let error as PlateServiceError {
            throw error
        } catch let error as URLError {
            throw PlateServiceError.from(urlErrorCode: error.code.rawValue)
        } catch is CancellationError {
            throw PlateServiceError.cancelled
        } catch {
            throw PlateServiceError.unreachable
        }
    }
}

// MARK: - Akış modeli

@MainActor
final class PlateFlowModel: ObservableObject {
    enum Phase: Equatable {
        case idle, preparing, ready, uploading, unrecognized, noEndpoint, photoError
        case failed(PlateServiceError)
    }

    @Published var pickerItem: PhotosPickerItem? {
        didSet { if pickerItem != nil && pickerItem != oldValue { loadPicked() } }
    }
    @Published private(set) var image: UIImage?
    @Published private(set) var jpeg: Data?
    @Published private(set) var phase: Phase = .idle
    @Published var draft: PlateDraft?
    @Published var slot: MealSlot = .lunch
    @Published private(set) var isSample = false
    @Published private(set) var saving = false
    /// Her yeni sonuçta değişir; fotoğraf ekranı analiz ekranına geçer.
    @Published private(set) var resultToken: UUID?
    /// Aynı analiz bir kez kaydedilir: kimlik sabit, depo ikinci kaydı reddeder.
    private(set) var mealID = UUID()
    private var task: Task<Void, Never>?
    private var loadToken = UUID()

    static func defaultSlot(for date: Date = Date()) -> MealSlot {
        switch Calendar.current.component(.hour, from: date) {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        pickerItem = nil
        image = nil; jpeg = nil; draft = nil
        isSample = false; saving = false
        phase = .idle; resultToken = nil
        mealID = UUID()
    }

    private func startNewPhoto() {
        task?.cancel()
        draft = nil; resultToken = nil; isSample = false; saving = false
        mealID = UUID()
    }

    private func loadPicked() {
        guard let item = pickerItem else { return }
        startNewPhoto()
        let token = UUID()
        loadToken = token
        phase = .preparing
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            guard token == loadToken else { return }
            if let data, let prepared = Self.prepare(data) {
                image = prepared.0; jpeg = prepared.1; phase = .idle
            } else {
                image = nil; jpeg = nil; phase = .photoError
            }
        }
    }

    func setCamera(_ captured: UIImage) {
        startNewPhoto()
        pickerItem = nil
        if let data = captured.jpegData(compressionQuality: 0.9), let prepared = Self.prepare(data) {
            image = prepared.0; jpeg = prepared.1; phase = .idle
        } else {
            phase = .photoError
        }
    }

    /// Paketteki örnek fotoğraf: ağ kullanılmaz, sonuç "Örnek analiz" etiketlidir ve günlüğe kaydedilmez.
    func useSample() {
        startNewPhoto()
        pickerItem = nil
        image = UIImage(named: "tabak")
        jpeg = nil
        isSample = true
        phase = .idle
    }

    /// Görüntüyü en fazla 1280 px'e küçültüp yeniden JPEG olarak kodlar (konum vb. meta veriler atılır).
    static func prepare(_ data: Data) -> (UIImage, Data)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280
              ] as CFDictionary) else { return nil }
        let ui = UIImage(cgImage: cg)
        guard let jpeg = ui.jpegData(compressionQuality: 0.74) else { return nil }
        return (ui, jpeg)
    }

    var canAnalyze: Bool { (jpeg != nil || isSample) && phase != .uploading && phase != .preparing }

    /// Yalnızca kullanıcının açık eylemiyle çağrılır.
    func analyze(endpoint: URL?) {
        guard canAnalyze else { return }
        slot = Self.defaultSlot()
        if isSample {
            finish(PlateAdvisor.sampleResponse())
            return
        }
        guard let jpeg else { return }
        guard let endpoint else { phase = .noEndpoint; return }
        phase = .uploading
        task = Task { [weak self] in
            do {
                let response = try await PlateClient(endpoint: endpoint).analyze(jpeg)
                guard let self, !Task.isCancelled else { return }
                self.finish(response)
            } catch let error as PlateServiceError {
                guard let self, self.phase == .uploading else { return }
                self.phase = .failed(error)
            } catch {
                guard let self, self.phase == .uploading else { return }
                self.phase = .failed(.badResponse)
            }
        }
    }

    private func finish(_ response: PlateResponse) {
        let d = PlateDraft(response: response)
        if d.portions.isEmpty {
            phase = .unrecognized
            return
        }
        draft = d
        mealID = UUID()
        phase = .ready
        resultToken = UUID()
    }

    func cancel() {
        guard phase == .uploading else { return }
        task?.cancel()
        task = nil
        phase = .failed(.cancelled)
    }

    func save(to store: AppStore) -> Bool {
        guard !saving, let d = draft, !d.isEmpty, !d.isSample else { return false }
        saving = true
        let ok = store.addMeal(Meal(id: mealID, date: Date(), portions: d.finalPortions, slot: slot,
                                    source: d.isDemo ? .demo : .photo))
        if !ok { saving = false }
        return ok
    }
}

// MARK: - 06 Fotoğraf

struct PhotoView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: PlateFlowModel
    @State private var showCamera = false
    @State private var cameraDenied = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        ScreenScroll {
            ScreenHeading(kicker: "Tabak analizi", plain: "Tabağını ", accent: "göster.")
            photoArea

            let pickTitle = model.image == nil ? "Fotoğraf seç" : "Başka fotoğraf seç"
            HStack(spacing: 8) {
                PhotosPicker(selection: $model.pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label(pickTitle, systemImage: "photo")
                }
                .buttonStyle(PillButtonStyle(selected: false))
                if cameraAvailable {
                    Button { openCamera() } label: { Label("Fotoğraf çek", systemImage: "camera") }
                        .buttonStyle(PillButtonStyle(selected: false))
                }
            }
            .disabled(model.phase == .uploading)

            status

            SectionHeader("Fotoğrafını kontrol et")
            Text("Tabağın tamamı ve yanındaki soslar görünürse porsiyonu kontrol etmek kolaylaşır. İyi ışıkta, tabağa yukarıdan bakarak çek.")
                .font(.subheadline).foregroundStyle(Color.ofMuted)
            InfoCard(title: "Fotoğraf nerede işleniyor?",
                     text: "Seçtiğin fotoğraf, sen “Fotoğrafı analiz et”e dokunana kadar cihazdan çıkmaz. Dokunduğunda yalnızca bu fotoğraf küçültülüp konum bilgisi olmadan Ovis Fit sunucusu üzerinden Anthropic'in Claude görsel analiz modeline gönderilir ve sunucuda saklanmaz. Fotoğraf seçmek için galeri iznine gerek yoktur; yalnızca seçtiğin görüntüye erişilir.")
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                if model.phase == .uploading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Tabak inceleniyor…").font(.headline)
                        Spacer()
                        Button("İptal") { model.cancel() }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .frame(minHeight: Metrics.actionHeight)
                    .accessibilityElement(children: .contain)
                } else {
                    Button { model.analyze(endpoint: store.plateEndpoint) } label: {
                        Label(model.isSample ? "Örnek tabağı analiz et" : "Fotoğrafı analiz et", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canAnalyze)
                }
            }
        }
        .secondaryScreen()
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { model.setCamera($0) }.ignoresSafeArea()
        }
        .alert("Kamera izni kapalı", isPresented: $cameraDenied) {
            Button("Ayarlar'ı aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Tabağını çekmek için Ayarlar › Ovis Fit › Kamera iznini açabilir veya galeriden fotoğraf seçebilirsin.")
        }
        .onChange(of: model.resultToken) { _, token in
            if token != nil { router.push(.analysis) }
        }
        .onDisappear {
            if model.phase == .uploading { model.cancel() }
        }
    }

    @ViewBuilder private var photoArea: some View {
        if let image = model.image {
            Image(uiImage: image)
                .resizable().scaledToFill()
                .frame(maxWidth: .infinity).frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    PhotoCaption(text: model.isSample ? "Örnek fotoğraf" : "Seçtiğin fotoğraf").padding(12)
                }
                .accessibilityLabel(model.isSample ? "Örnek tabak fotoğrafı: ızgara tavuk, bulgur ve salata" : "Seçtiğin tabak fotoğrafı")
        } else {
            VStack(spacing: 10) {
                Image(systemName: model.phase == .preparing ? "hourglass" : "photo.on.rectangle.angled")
                    .font(.largeTitle).foregroundStyle(Color.ofDeep)
                Text(model.phase == .preparing ? "Fotoğraf hazırlanıyor…" : "Henüz fotoğraf seçmedin")
                    .font(.headline).foregroundStyle(Color.ofInk)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(Color.ofSage, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color.ofDivider, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
        }
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .failed(let error):
            VStack(alignment: .leading, spacing: 8) {
                InfoCard(title: title(for: error), text: error.message, tint: Color(hex: 0xF6E3DC))
                if error != .notConfigured {
                    Button("Tekrar dene") { model.analyze(endpoint: store.plateEndpoint) }
                        .buttonStyle(LinkButtonStyle())
                }
            }
        case .unrecognized:
            InfoCard(title: "Tabak tanınamadı",
                     text: "Fotoğrafta yiyecek seçilemedi. Tabağın tamamı görünecek şekilde, iyi ışıkta tekrar çekebilir veya başka bir fotoğraf seçebilirsin.",
                     tint: Color(hex: 0xF6E3DC))
        case .noEndpoint:
            InfoCard(title: "Sunucu adresi yapılandırılmadı",
                     text: "Fiziksel iPhone'da analiz için HTTPS sunucu adresi gerekir. Profil › Analiz sunucusu bölümünden ekleyebilirsin.",
                     tint: Color(hex: 0xF6E3DC))
        case .photoError:
            InfoCard(title: "Fotoğraf okunamadı", text: "Başka bir fotoğraf seçebilirsin.", tint: Color(hex: 0xF6E3DC))
        default:
            EmptyView()
        }
    }

    private func title(for error: PlateServiceError) -> String {
        switch error {
        case .offline: return "Çevrimdışısın"
        case .unreachable: return "Servise erişilemiyor"
        case .notConfigured: return "Analiz servisi kapalı"
        case .badResponse: return "Yanıt okunamadı"
        case .rateLimited: return "Biraz bekle"
        case .cancelled: return "İptal edildi"
        }
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: cameraDenied = true
        default: showCamera = true
        }
    }
}

struct PhotoCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Color.ofInk)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.white, in: Capsule())
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - 07 Analiz

struct AnalysisView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var model: PlateFlowModel
    @State private var showManual = false
    @State private var removing: Portion?

    var body: some View {
        Group {
            if let draft = model.draft {
                content(draft)
            } else {
                ScreenScroll {
                    InfoCard(title: "Analiz sonucu yok", text: "Fotoğraf ekranına dönüp bir tabak fotoğrafı seçebilirsin.")
                }
            }
        }
        .secondaryScreen()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    Picker("Öğün", selection: $model.slot) {
                        ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Pill(text: model.slot == .lunch ? "Öğle yemeği" : model.slot == .dinner ? "Akşam yemeği" : model.slot.title)
                }
                .accessibilityLabel("Öğün: \(model.slot.title). Değiştir")
            }
        }
        .sheet(isPresented: $showManual) {
            ManualAddSheet().environmentObject(store).environmentObject(model)
        }
    }

    private func content(_ d: PlateDraft) -> some View {
        let suggestion = PlateAdvisor.suggestion(for: d, profile: store.profile, db: store.db)
        return ScreenScroll {
            ScreenHeading(kicker: "Tabak analizi", plain: "Tabağımda ", accent: "ne var?")
            if let image = model.image {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        PhotoCaption(text: d.isSample ? "Örnek analiz" : d.isDemo ? "Demo yanıt" : "Senin tabağın").padding(12)
                    }
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(TRFormat.range(d.low, d.high))
                    .font(.system(.largeTitle).weight(.bold)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("kcal · tahmini").font(.subheadline).foregroundStyle(Color.ofMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tahmini enerji \(d.low) ile \(d.high) kilokalori arası")

            if d.isDemo {
                InfoCard(title: "Demo yanıt · gerçek analiz değil",
                         text: "Sunucu demo modunda çalışıyor; bu değerler fotoğrafından üretilmedi. Kaydedersen günlükte “Demo” olarak işaretlenir.",
                         tint: Color(hex: 0xF6E3DC))
            }

            VStack(spacing: 0) {
                ForEach(d.portions) { p in
                    PortionRow(portion: p,
                               change: { delta in model.draft?.setGrams(p.id, p.grams + delta) },
                               remove: { removing = p })
                }
                MetricLine(title: "İlave yağ") {
                    GramStepper(name: "İlave yağ", grams: d.oilGrams, step: 5,
                                change: { delta in model.draft?.oilGrams = min(100, max(0, d.oilGrams + delta)) })
                }
            }
            Text("Gram değiştikçe o yiyeceğin kalori aralığı orantılı güncellenir. İlave yağ, fotoğrafta görünmeyen pişirme veya sos yağı içindir. Adı tamamen yanlış olan öğeyi çıkarabilirsin.")
                .font(.footnote).foregroundStyle(Color.ofMuted)

            if let s = suggestion {
                VStack(alignment: .leading, spacing: 8) {
                    InfoCard(title: "Ovi’nin tabak önerisi", text: s.text)
                    if let preview = d.preview {
                        let totals = d.totals(applying: preview)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Önizleme: \(TRFormat.range(d.low, d.high)) → \(TRFormat.range(totals.low, totals.high)) kcal")
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                            HStack(spacing: 16) {
                                Button("Uygula") { model.draft?.apply(preview) }.buttonStyle(LinkButtonStyle())
                                Button("Vazgeç") { model.draft?.preview = nil }.buttonStyle(LinkButtonStyle())
                            }
                        }
                    } else {
                        Button { model.draft?.preview = s } label: {
                            Label(s.actionTitle, systemImage: "plus")
                        }
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityHint("Önce yeni toplamı gösterir, onaylarsan uygulanır")
                    }
                }
            }

            HStack(spacing: 18) {
                Button { showManual = true } label: { Label("Öğe ekle", systemImage: "plus.circle") }
                    .buttonStyle(LinkButtonStyle())
                Button { router.pop() } label: { Label("Yeniden seç", systemImage: "arrow.uturn.left") }
                    .buttonStyle(LinkButtonStyle())
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomAction {
                if d.isSample {
                    Text("Örnek analiz günlüğe kaydedilmez.").font(.footnote).foregroundStyle(Color.ofMuted)
                    Button {
                        model.reset()
                        router.pop()
                    } label: { Label("Kendi fotoğrafımı seç", systemImage: "photo") }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {
                        if model.save(to: store) {
                            router.popToRoot()
                            model.reset()
                        }
                    } label: { Label("Günlüğüme kaydet", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(d.isEmpty || model.saving)
                }
            }
        }
        .confirmationDialog(removing.map { "\($0.food.name) çıkarılsın mı?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Çıkar", role: .destructive) {
                if let r = removing { model.draft?.remove(r.id) }
                removing = nil
            }
        } message: {
            if let r = removing {
                let after = d.low - r.low
                let afterHigh = d.high - r.high
                Text("Yeni toplam \(TRFormat.range(after, afterHigh)) kcal olur.")
            }
        }
    }
}

struct PortionRow: View {
    let portion: Portion
    let change: (Int) -> Void
    let remove: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: remove) {
                    Image(systemName: "xmark.circle").font(.body).foregroundStyle(Color.ofMuted)
                        .frame(width: 32, height: 44)
                }
                .accessibilityLabel("\(portion.food.name) öğesini çıkar")
                VStack(alignment: .leading, spacing: 2) {
                    Text(portion.food.name).font(.headline).foregroundStyle(Color.ofInk)
                    Text("\(TRFormat.range(portion.low, portion.high)) kcal").font(.footnote).monospacedDigit().foregroundStyle(Color.ofMuted)
                }
                Spacer(minLength: 6)
                GramStepper(name: portion.food.name, grams: portion.grams, step: portion.grams <= 50 ? 5 : 25, change: change)
            }
            .frame(minHeight: 56)
            Divider().overlay(Color.ofDivider)
        }
    }
}

struct GramStepper: View {
    let name: String
    let grams: Int
    let step: Int
    let change: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button { change(-step) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                .disabled(grams <= 0)
            Text("\(grams) g").font(.headline).monospacedDigit().foregroundStyle(Color.ofMuted)
                .frame(minWidth: 56)
            Button { change(step) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .disabled(grams >= PlateDraft.maxGrams)
        }
        .foregroundStyle(Color.ofInk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) miktarı")
        .accessibilityValue("\(grams) gram")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(step)
            case .decrement: change(-step)
            @unknown default: break
            }
        }
    }
}

/// Besin değeri bilinen öğeyi elle ekleme: önce yeni toplam gösterilir, "Ekle" ile uygulanır.
struct ManualAddSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: PlateFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: FoodItem?
    @State private var grams = 100

    var body: some View {
        NavigationStack {
            List {
                if let f = selected, let d = model.draft {
                    Section("Önizleme") {
                        Stepper("\(f.name) · \(grams) g", value: $grams, in: 5...1000, step: 5)
                        LabeledContent("Bu öğe", value: "\(f.kcal(grams: grams)) kcal")
                        LabeledContent("Yeni tabak toplamı",
                                       value: "\(TRFormat.range(d.low + f.kcal(grams: grams), d.high + f.kcal(grams: grams))) kcal")
                        Button("Tabağa ekle") {
                            model.draft?.add(f.asFood(grams: grams))
                            dismiss()
                        }
                        .bold()
                    }
                }
                Section {
                    ForEach(foods) { f in
                        Button {
                            selected = f
                            grams = f.group == "sos" ? 5 : 100
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(f.name).foregroundStyle(Color.ofInk)
                                    Text("\(Int(f.kcal)) kcal / 100 g").font(.footnote).foregroundStyle(Color.ofMuted)
                                }
                                Spacer()
                                if selected?.id == f.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } footer: {
                    Text("Yalnızca beslenme tercihine ve alerjilerine uygun, besin değeri bilinen öğeler listelenir. Kaynak: USDA FoodData Central.")
                }
            }
            .searchable(text: $query, prompt: "Besin ara")
            .navigationTitle("Öğe ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
        }
    }

    private var foods: [FoodItem] {
        store.db.foods.filter { f in
            (store.profile.map { store.db.isSuitable(f, for: $0) } ?? true) &&
            (query.isEmpty || f.name.localizedCaseInsensitiveContains(query))
        }
    }
}
