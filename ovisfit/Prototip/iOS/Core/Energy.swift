import Foundation

// MARK: - Giriş ayrıştırma

public enum NumberInput {
    /// "75,5", "75.5", "75,5 kg", "175 cm", "1,75 m" gibi girdileri sayıya çevirir.
    /// Binlik ayırıcı veya birden fazla ondalık işareti olan girdiler reddedilir.
    public static func parse(_ text: String) -> (value: Double, unit: String)? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return nil }
        var unit = ""
        while let last = s.last, last.isLetter {
            unit = String(last) + unit
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: ",", with: ".")
        guard !s.isEmpty,
              s.filter({ $0 == "." }).count <= 1,
              s.allSatisfy({ $0.isNumber || $0 == "." }),
              s.first != ".", s.last != ".",
              let value = Double(s), value.isFinite else { return nil }
        return (value, unit)
    }
}

extension NumberInput {
    /// Tam sayı girişi: "2100", "2.100", "2 100" (binlik ayırıcı), isteğe bağlı birim ("2.100 kcal").
    public static func parseInteger(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = s.last, last.isLetter { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        let compact = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        let groups = compact.split(separator: ".", omittingEmptySubsequences: false)
        if groups.count > 1 {
            // Yalnızca geçerli binlik gruplama kabul edilir: 2.100, 12.500
            guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        return Int(digits)
    }
}

public enum ProfileField: String, CaseIterable, Sendable {
    case name, age, height, weight
}

public struct ProfileDraft: Equatable, Sendable {
    public var name = ""
    public var age = ""
    public var height = ""
    public var weight = ""
    public var sex: Sex = .unspecified
    public var activity: ActivityLevel = .moderate
    public init() {}

    public init(profile: Profile) {
        name = profile.name
        age = String(profile.age)
        height = TRFormat.decimal(profile.heightCm, digits: profile.heightCm.rounded() == profile.heightCm ? 0 : 1)
        weight = TRFormat.decimal(profile.weightKg, digits: 1)
        sex = profile.sex
        activity = profile.activity
    }

    public struct Valid: Equatable, Sendable {
        public let name: String
        public let age: Int
        public let heightCm: Double
        public let weightKg: Double
    }

    public static let ageRange = 18...105
    public static let heightRange = 100.0...240.0
    public static let weightRange = 30.0...350.0

    public func validate() -> Result<Valid, ValidationErrors> {
        var errors: [ProfileField: String] = [:]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { errors[.name] = "Sana nasıl hitap edelim?" }
        else if trimmed.count > 40 { errors[.name] = "İsim en fazla 40 karakter olabilir." }

        var ageValue = 0
        if let p = NumberInput.parse(age), ["", "yıl", "yas", "yaş"].contains(p.unit),
           p.value.rounded() == p.value, Self.ageRange.contains(Int(p.value)) {
            ageValue = Int(p.value)
        } else if let p = NumberInput.parse(age), p.value < 18 {
            errors[.age] = "Bu plan yetişkinler (18 yaş ve üzeri) için hazırlandı."
        } else {
            errors[.age] = "Yaşını 18 ile 105 arasında tam sayı olarak gir."
        }

        var heightValue = 0.0
        if let p = NumberInput.parse(height) {
            var cm: Double?
            switch p.unit {
            case "", "cm": cm = p.value < 3 ? p.value * 100 : p.value   // 1,75 → 175 cm
            case "m": cm = p.value * 100
            default: cm = nil
            }
            if let cm, Self.heightRange.contains(cm) { heightValue = (cm * 10).rounded() / 10 }
            else { errors[.height] = "Boyunu 100–240 cm arasında gir (ör. 175 veya 1,75 m)." }
        } else { errors[.height] = "Boyunu santimetre olarak gir (ör. 175)." }

        var weightValue = 0.0
        if let p = NumberInput.parse(weight), ["", "kg"].contains(p.unit), Self.weightRange.contains(p.value) {
            weightValue = (p.value * 10).rounded() / 10
        } else {
            errors[.weight] = "Kilonu 30–350 kg arasında gir (ör. 72,5)."
        }

        if errors.isEmpty {
            return .success(Valid(name: trimmed, age: ageValue, heightCm: heightValue, weightKg: weightValue))
        }
        return .failure(ValidationErrors(fields: errors))
    }
}

public struct ValidationErrors: Error, Equatable, Sendable {
    public let fields: [ProfileField: String]
}

// MARK: - Enerji tahmini

public struct EnergyEstimate: Equatable, Sendable {
    public let restingKcal: Int
    public let maintenanceKcal: Int
    public let adjustment: Int
    public let floorKcal: Int
    public let floorApplied: Bool
    public let target: Int
    public let isManual: Bool
}

public enum EnergyCalculator {
    public static let method = "Mifflin-St Jeor (1990)"
    public static let manualRange = 1000...5000

    /// Mifflin MD, St Jeor ST ve ark. Am J Clin Nutr 1990;51:241-7.
    /// "Belirtmek istemiyorum" seçildiğinde kadın ve erkek sabitlerinin ortalaması (-78) kullanılır.
    public static func resting(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    public static func roundTo50(_ value: Double) -> Int { Int((value / 50).rounded()) * 50 }

    public static func estimate(_ p: Profile) -> EnergyEstimate {
        let rest = resting(weightKg: p.weightKg, heightCm: p.heightCm, age: p.age, sex: p.sex)
        let maintenance = rest * p.activity.factor
        // Güvenlik alt sınırı: dinlenme enerjisinin ve 1200 kcal'in büyüğü.
        let floor = max(roundTo50(rest), 1200)
        let raw = roundTo50(maintenance + Double(p.goal.adjustment))
        let applied = p.goal == .lose && raw < floor
        let computed = applied ? floor : raw
        if let manual = p.manualTarget, manualRange.contains(manual) {
            return EnergyEstimate(restingKcal: Int(rest.rounded()), maintenanceKcal: roundTo50(maintenance),
                                  adjustment: p.goal.adjustment, floorKcal: floor, floorApplied: false,
                                  target: manual, isManual: true)
        }
        return EnergyEstimate(restingKcal: Int(rest.rounded()), maintenanceKcal: roundTo50(maintenance),
                              adjustment: p.goal.adjustment, floorKcal: floor, floorApplied: applied,
                              target: computed, isManual: false)
    }

    public static let assumptions: [String] = [
        "Dinlenme enerjisi Mifflin-St Jeor denklemiyle yaş, boy, kilo ve cinsiyetten hesaplanır. Cinsiyet belirtilmezse iki sabitin ortalaması kullanılır.",
        "Günlük ihtiyaç, dinlenme enerjisi × aktivite katsayısıdır: Düşük 1,2 · Orta 1,55 · Yüksek 1,725.",
        "Kilo verme hedefinde günde 500 kcal eksik (haftada yaklaşık 0,5 kg), kilo alma hedefinde 300 kcal fazla planlanır.",
        "Hedef, dinlenme enerjisinin ve 1.200 kcal'in altına indirilmez. Sonuç 50 kcal'e yuvarlanır.",
        "Bu bir başlangıç tahminidir; bireysel fark ±%10 veya daha fazla olabilir. Gebelik, emzirme, 18 yaş altı, yeme bozukluğu, böbrek hastalığı veya diyabet gibi durumlarda hekim/diyetisyen planı esas alınmalıdır."
    ]
}
