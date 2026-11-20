import Foundation

/// Analiz servisinin yanıtı. `mode` alanı yoksa canlı analiz kabul edilir.
public struct PlateResponse: Decodable, Equatable, Sendable {
    public let foods: [Food]
    public let mode: String?
    public var isDemo: Bool { mode == "demo" }
    /// Uygulama içindeki örnek tabak (fotoğraf da sonuç da örnek).
    public var isSample: Bool { mode == "sample" }

    public init(foods: [Food], mode: String?) {
        self.foods = foods; self.mode = mode
    }
}

public enum PlateServiceError: Error, Equatable, Sendable {
    case offline
    case unreachable
    case notConfigured
    case badResponse
    case rateLimited
    case cancelled

    public var message: String {
        switch self {
        case .offline: return "İnternet bağlantısı yok. Bağlandığında fotoğrafı tekrar gönderebilirsin."
        case .unreachable: return "Analiz servisine ulaşılamadı. Sunucu adresini ve sunucunun çalıştığını kontrol edip tekrar dene."
        case .notConfigured: return "Analiz servisi şu an kullanılamıyor. Öğünü barkodla, favorilerinden veya plandan ekleyebilirsin."
        case .badResponse: return "Analiz yanıtı okunamadı. Tekrar deneyebilirsin."
        case .rateLimited: return "Kısa sürede çok fazla analiz yapıldı. Bir süre sonra tekrar deneyebilirsin."
        case .cancelled: return "Analiz iptal edildi. Fotoğraf gönderilmedi veya yanıt kullanılmadı."
        }
    }

    /// URLError kodları (NSURLErrorDomain) ve HTTP durumları için eşleme.
    public static func from(urlErrorCode code: Int) -> PlateServiceError {
        switch code {
        case -999: return .cancelled                       // cancelled
        case -1009, -1020, -1018: return .offline          // notConnectedToInternet, dataNotAllowed, internationalRoamingOff
        default: return .unreachable                       // timedOut, cannotConnectToHost, cannotFindHost, ...
        }
    }

    public static func from(status: Int) -> PlateServiceError? {
        switch status {
        case 200: return nil
        case 503: return .notConfigured
        case 429: return .rateLimited
        case 400, 413, 415: return .badResponse
        default: return .unreachable
        }
    }
}

public struct PlateSuggestion: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case add(Food)
        case setGrams(portionID: UUID, grams: Int)
    }
    public let text: String
    public let actionTitle: String
    public let change: Change
}

/// Analiz ekranının düzenlenebilir durumu. UI'dan bağımsızdır, test edilir.
public struct PlateDraft: Equatable, Sendable {
    public static let oilFoodID = "zeytinyagi"
    public static let maxGrams = 2000

    public var portions: [Portion]
    public var oilGrams = 0
    public var oilKcalPer100: Double = 884
    public var mode: String?
    public var isDemo: Bool { mode == "demo" }
    public var isSample: Bool { mode == "sample" }
    /// Önizlenen ama henüz uygulanmamış öneri.
    public var preview: PlateSuggestion?

    public init(response: PlateResponse) {
        portions = response.foods.filter { $0.grams > 0 }.map { Portion(food: $0, grams: $0.grams) }
        mode = response.mode
    }

    public var isEmpty: Bool { finalPortions.isEmpty }

    public mutating func setGrams(_ id: UUID, _ grams: Int) {
        guard let i = portions.firstIndex(where: { $0.id == id }) else { return }
        portions[i].grams = min(max(grams, 0), Self.maxGrams)
    }

    public mutating func remove(_ id: UUID) {
        portions.removeAll { $0.id == id }
        if case .setGrams(let pid, _)? = preview?.change, pid == id { preview = nil }
    }

    public mutating func add(_ food: Food) {
        portions.append(Portion(food: food, grams: food.grams))
    }

    public mutating func apply(_ s: PlateSuggestion) {
        switch s.change {
        case .add(let food): add(food)
        case .setGrams(let id, let g): setGrams(id, g)
        }
        preview = nil
    }

    public var finalPortions: [Portion] {
        var list = portions.filter { $0.grams > 0 }
        if oilGrams > 0 {
            let k = Int((oilKcalPer100 * Double(oilGrams) / 100).rounded())
            list.append(Portion(food: Food(name: "İlave yağ", grams: oilGrams, low: k, high: k, group: "sos",
                                           protein: 0, carbs: 0, fat: Double(oilGrams), fiber: 0, sugar: 0),
                                grams: oilGrams))
        }
        return list
    }

    public var low: Int { finalPortions.reduce(0) { $0 + $1.low } }
    public var high: Int { finalPortions.reduce(0) { $0 + $1.high } }

    /// Öneri uygulanırsa oluşacak toplam (önizleme).
    public func totals(applying s: PlateSuggestion) -> (low: Int, high: Int) {
        var copy = self
        copy.apply(s)
        return (copy.low, copy.high)
    }
}

public enum PlateAdvisor {
    /// Hedefe, alerjilere ve beslenme tercihine göre en fazla bir öneri döner.
    /// Örn. süt alerjisi veya vegan tercih varsa yoğurt önerilmez.
    public static func suggestion(for draft: PlateDraft, profile: Profile?, db: FoodDatabase) -> PlateSuggestion? {
        let goal = profile?.goal ?? .maintain
        let active = draft.portions.filter { $0.grams > 0 }
        let groups = Set(active.map { $0.food.group })

        func allowed(_ id: String) -> FoodItem? {
            guard let f = db.food(id) else { return nil }
            if let profile, !db.isSuitable(f, for: profile) { return nil }
            return f
        }
        func addSuggestion(_ id: String, grams: Int, why: String) -> PlateSuggestion? {
            guard let f = allowed(id),
                  !draft.portions.contains(where: { $0.food.name == f.asFood(grams: grams).name }) else { return nil }
            return PlateSuggestion(text: why, actionTitle: "\(shortName(f)) ekle · \(grams) g",
                                   change: .add(f.asFood(grams: grams)))
        }

        switch goal {
        case .lose:
            if let p = active.first(where: { $0.food.group == "sos" }) ?? active.first(where: { $0.food.group == "tahil" }) {
                let g = max(0, p.grams - 25)
                return PlateSuggestion(text: "\(p.food.name) porsiyonunu 25 g azaltarak tahmini farkı görebilirsin.",
                                       actionTitle: "\(p.food.name) · \(p.grams) g → \(g) g",
                                       change: .setGrams(portionID: p.id, grams: g))
            }
            if !groups.contains("sebze"), let s = addSuggestion("salatalik", grams: 100, why: "Tabağına az enerjili bir sebze ekleyerek doygunluğu artırabilirsin.") { return s }
        case .gain:
            if let p = active.first(where: { $0.food.group == "tahil" }) ?? active.first(where: { $0.food.group == "protein" }) {
                let g = min(PlateDraft.maxGrams, p.grams + 25)
                return PlateSuggestion(text: "\(p.food.name) porsiyonunu 25 g artırabilirsin.",
                                       actionTitle: "\(p.food.name) · \(p.grams) g → \(g) g",
                                       change: .setGrams(portionID: p.id, grams: g))
            }
            if let s = addSuggestion("ceviz", grams: 15, why: "Küçük bir avuç ceviz enerjiyi artırır.") { return s }
        case .maintain:
            break
        }
        if !groups.contains("protein") {
            for (id, g) in [("yogurt", 80), ("nohut", 80), ("yumurta", 50)] {
                if let s = addSuggestion(id, grams: g, why: "Tabağında belirgin bir protein kaynağı görünmüyor. Tercihine uygun bir protein ekleyebilirsin.") { return s }
            }
        }
        if !groups.contains("sebze"), let s = addSuggestion("domates", grams: 100, why: "Tabağına sevdiğin bir sebze veya salata ekleyebilirsin.") { return s }
        if goal == .maintain {
            for (id, g) in [("yogurt", 80), ("salatalik", 80)] {
                if let s = addSuggestion(id, grams: g, why: id == "yogurt"
                    ? "Yanına yoğurt eklemek istersen yeni tahmini görebilirsin."
                    : "Yanına salatalık eklemek istersen yeni tahmini görebilirsin.") { return s }
            }
        }
        return nil
    }

    static func shortName(_ f: FoodItem) -> String {
        switch f.id {
        case "yogurt": return "Yoğurt"
        case "nohut": return "Nohut"
        case "yumurta": return "Yumurta"
        default: return f.name
        }
    }

    /// Bundle'daki örnek fotoğraf için yerel, etiketli demo sonucu. Ağ kullanılmaz, günlüğe kaydedilmez.
    public static func sampleResponse() -> PlateResponse {
        PlateResponse(foods: [
            Food(name: "Izgara tavuk", grams: 140, low: 210, high: 250, group: "protein", protein: 43, carbs: 0, fat: 5, fiber: 0, sugar: 0),
            Food(name: "Bulgur pilavı", grams: 150, low: 180, high: 260, group: "tahil", protein: 5, carbs: 28, fat: 4, fiber: 7, sugar: 0),
            Food(name: "Mevsim salata", grams: 80, low: 40, high: 50, group: "sebze", protein: 1, carbs: 3, fat: 3, fiber: 1, sugar: 2)
        ], mode: "sample")
    }
}
