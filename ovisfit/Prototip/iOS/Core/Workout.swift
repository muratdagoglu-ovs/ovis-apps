import Foundation

/// Salon antrenmanı: hareket kütüphanesi, günün programı ve set akışı (UI'dan bağımsız, test edilir).
public enum WorkoutPlace: String, CaseIterable, Identifiable, Codable, Sendable {
    case gym, home
    public var id: String { rawValue }
    public var title: String { self == .gym ? "Salon" : "Ev" }
}

public struct Exercise: Identifiable, Equatable, Sendable {
    public let id: String
    public let place: WorkoutPlace
    public let name: String
    public let muscles: String
    public let equipment: String
    public let sets: Int
    public let reps: String
    public let restSeconds: Int
    /// Bir setin ortalama süresi (sn), toplam süre tahmini için.
    public let setSeconds: Int
    public let steps: [String]
    public let mistakes: [String]
    /// Bu kısıtlardan biri varsa program önermez (alternatif gösterilir).
    public let avoidFor: Set<MovementLimit>
    public let alternative: String?
}

public enum ExerciseLibrary {
    public static let all: [Exercise] = [
        Exercise(id: "squat", place: .gym, name: "Barbell squat", muscles: "Ön bacak, kalça, core",
                 equipment: "Barbell, squat rack", sets: 3, reps: "8–10", restSeconds: 90, setSeconds: 40,
                 steps: ["Barı omuzlarının arkasına, trapez kasının üstüne yerleştir.",
                         "Ayaklar omuz genişliğinde, parmak uçları hafif dışa dönük.",
                         "Kalçanı geriye iterek, dizlerin ayak uçlarıyla aynı yönde inerken nefes al.",
                         "Uyluklar yere paralel olana kadar in, topuklardan iterek kalkarken nefes ver."],
                 mistakes: ["Dizlerin içe çökmesi", "Topukların yerden kalkması", "Belin yuvarlanması"],
                 avoidFor: [.knee, .back, .balance, .standing], alternative: "Leg press (oturarak, daha az yük)"),
        Exercise(id: "latpulldown", place: .gym, name: "Lat pulldown", muscles: "Sırt (latissimus), arka omuz, biceps",
                 equipment: "Lat pulldown makinesi", sets: 3, reps: "10–12", restSeconds: 75, setSeconds: 40,
                 steps: ["Dizlerini pedin altına sabitle, barı omuz genişliğinden biraz geniş tut.",
                         "Göğsünü hafifçe öne çıkar, gövdeyi az geriye yasla.",
                         "Dirsekleri aşağı ve geriye çekerek barı üst göğsüne indir, nefes ver.",
                         "Kontrollü şekilde kollarını yukarı uzatırken nefes al."],
                 mistakes: ["Barı ensenin arkasına çekmek", "Gövdeyle sallanarak çekmek", "Omuzları kulağa kaldırmak"],
                 avoidFor: [], alternative: nil),
        Exercise(id: "dbbench", place: .gym, name: "Dambıl bench press", muscles: "Göğüs, ön omuz, triceps",
                 equipment: "Düz bench, dambıl", sets: 3, reps: "8–12", restSeconds: 90, setSeconds: 40,
                 steps: ["Benche sırtüstü uzan, ayakların yerde sabit olsun.",
                         "Dambılları göğüs hizasında tut, dirsekler gövdeye yaklaşık 45°.",
                         "Dambılları yukarı iterken nefes ver, kollar tam kilitlenmesin.",
                         "Kontrollü şekilde göğüs hizasına indirirken nefes al."],
                 mistakes: ["Dirsekleri 90° yana açmak", "Kalçayı benchten kaldırmak", "Ağırlığı göğse çarptırmak"],
                 avoidFor: [.back], alternative: "Makinede chest press"),
        Exercise(id: "pushup", place: .home, name: "Şınav", muscles: "Göğüs, ön omuz, triceps, core",
                 equipment: "Ekipmansız", sets: 3, reps: "8–12", restSeconds: 60, setSeconds: 35,
                 steps: ["Ellerini omuz genişliğinden biraz geniş, yere koy.",
                         "Baştan topuklara vücudun düz bir çizgi olsun, karnını sık.",
                         "Dirsekleri gövdeye yaklaşık 45° açıyla bükerek göğsünü yere yaklaştır, nefes al.",
                         "Avuçlardan iterek başlangıca dön, nefes ver."],
                 mistakes: ["Kalçanın düşmesi veya havaya kalkması", "Başın öne sarkması", "Yarım hareket"],
                 avoidFor: [], alternative: "Dizler yerde şınav veya duvarda şınav"),
        Exercise(id: "glutebridge", place: .home, name: "Kalça köprüsü", muscles: "Kalça, arka bacak, core",
                 equipment: "Ekipmansız (mat önerilir)", sets: 3, reps: "12–15", restSeconds: 45, setSeconds: 35,
                 steps: ["Sırtüstü uzan, dizlerini bük, ayakların kalça genişliğinde yerde olsun.",
                         "Kollar yanlarda, avuçlar yere dönük.",
                         "Topuklardan iterek kalçanı omuz–diz hizasına kadar kaldır, kalçanı sık, nefes ver.",
                         "Kontrollü şekilde indir, nefes al."],
                 mistakes: ["Beli aşırı kavislendirmek", "Dizlerin içe kapanması", "Hızlı ve kontrolsüz inmek"],
                 avoidFor: [], alternative: nil)
    ]

    public static func exercise(_ id: String) -> Exercise? { all.first { $0.id == id } }

    /// Seçilen yere ve profildeki kısıtlara uygun günün programı.
    public static func todaysWorkout(place: WorkoutPlace, limits: Set<MovementLimit>) -> [Exercise] {
        all.filter { $0.place == place && $0.avoidFor.isDisjoint(with: limits) }
    }

    /// Isınma (5 dk) + setler + dinlenmeler, dakika olarak.
    public static func estimatedMinutes(_ list: [Exercise]) -> Int {
        let seconds = list.reduce(300) { $0 + $1.sets * $1.setSeconds + max(0, $1.sets - 1) * $1.restSeconds + 60 }
        return Int((Double(seconds) / 60).rounded())
    }
}

/// Antrenman ekranının durumu: hangi hareket, hangi set, set mi dinlenme mi.
public struct WorkoutSession: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case set, rest(remaining: Int), finished }

    public let exercises: [Exercise]
    public private(set) var index = 0
    public private(set) var set = 1
    public private(set) var phase: Phase = .set
    public private(set) var completedSets = 0

    public init(exercises: [Exercise]) {
        self.exercises = exercises
        if exercises.isEmpty { phase = .finished }
    }

    public var current: Exercise? { index < exercises.count ? exercises[index] : nil }
    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    public var progress: Double { totalSets > 0 ? Double(completedSets) / Double(totalSets) : 1 }

    /// "Seti bitirdim": son setse sonraki harekete, değilse dinlenmeye geçer.
    public mutating func finishSet() {
        guard phase == .set, let ex = current else { return }
        completedSets += 1
        if set < ex.sets {
            phase = .rest(remaining: ex.restSeconds)
        } else {
            advanceExercise()
        }
    }

    /// Dinlenmede saniye ilerletir; süre bitince sonraki set.
    public mutating func tick(_ seconds: Int = 1) {
        guard case .rest(let r) = phase else { return }
        let left = r - seconds
        if left <= 0 { set += 1; phase = .set } else { phase = .rest(remaining: left) }
    }

    public mutating func skipRest() {
        guard case .rest = phase else { return }
        set += 1
        phase = .set
    }

    /// Hareketi atlar (kalan setler sayılmaz).
    public mutating func skipExercise() {
        guard current != nil, phase != .finished else { return }
        advanceExercise()
    }

    private mutating func advanceExercise() {
        index += 1
        set = 1
        phase = index < exercises.count ? .set : .finished
    }
}
