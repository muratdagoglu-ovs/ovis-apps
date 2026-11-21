import SwiftUI
import AVFoundation

// MARK: - Animasyonlu hareket figürü

/// Yandan görünüm, eklem açılarıyla tanımlanan basit insan figürü.
/// Açılar derece: 0 = yukarı, 90 = sağa, 180 = aşağı, 270 = sola.
struct Pose {
    var torso: Double      // kalça → omuz
    var thigh: Double      // kalça → diz
    var shin: Double       // diz → ayak bileği
    var upperArm: Double   // omuz → dirsek
    var forearm: Double    // dirsek → el

    static func mix(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func m(_ x: Double, _ y: Double) -> Double {
            var d = (y - x).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 } else if d < -180 { d += 360 }
            return x + d * t
        }
        return Pose(torso: m(a.torso, b.torso), thigh: m(a.thigh, b.thigh), shin: m(a.shin, b.shin),
                    upperArm: m(a.upperArm, b.upperArm), forearm: m(a.forearm, b.forearm))
    }
}

enum FigureRoot {
    case ankle(CGPoint)   // ayakta / plank: ayak yere sabit
    case hip(CGPoint)     // oturarak / sırtüstü: kalça sabit
}

enum Equipment2D { case barbell, cable, dumbbellBench, mat, none }

struct FigureJoints {
    var hip, knee, ankle, toe, shoulder, elbow, hand, head: CGPoint
}

struct ExerciseMotion {
    let rootA: FigureRoot
    let rootB: FigureRoot
    let a: Pose
    let b: Pose
    let equipment: Equipment2D
    let period: Double

    static func of(_ id: String) -> ExerciseMotion {
        switch id {
        case "squat":
            return ExerciseMotion(rootA: .ankle(CGPoint(x: 0.44, y: 0.90)), rootB: .ankle(CGPoint(x: 0.44, y: 0.90)),
                                  a: Pose(torso: 5, thigh: 182, shin: 178, upperArm: 215, forearm: 35),
                                  b: Pose(torso: 38, thigh: 98, shin: 205, upperArm: 248, forearm: 68),
                                  equipment: .barbell, period: 3.2)
        case "latpulldown":
            return ExerciseMotion(rootA: .hip(CGPoint(x: 0.40, y: 0.62)), rootB: .hip(CGPoint(x: 0.40, y: 0.62)),
                                  a: Pose(torso: 350, thigh: 90, shin: 180, upperArm: 12, forearm: 8),
                                  b: Pose(torso: 345, thigh: 90, shin: 180, upperArm: 195, forearm: 25),
                                  equipment: .cable, period: 3.0)
        case "dbbench":
            return ExerciseMotion(rootA: .hip(CGPoint(x: 0.66, y: 0.60)), rootB: .hip(CGPoint(x: 0.66, y: 0.60)),
                                  a: Pose(torso: 270, thigh: 55, shin: 175, upperArm: 172, forearm: 8),
                                  b: Pose(torso: 270, thigh: 55, shin: 175, upperArm: 2, forearm: 0),
                                  equipment: .dumbbellBench, period: 3.0)
        case "pushup":
            return ExerciseMotion(rootA: .ankle(CGPoint(x: 0.14, y: 0.86)), rootB: .ankle(CGPoint(x: 0.14, y: 0.86)),
                                  a: Pose(torso: 66, thigh: 246, shin: 246, upperArm: 180, forearm: 180),
                                  b: Pose(torso: 80, thigh: 260, shin: 260, upperArm: 235, forearm: 165),
                                  equipment: .mat, period: 2.8)
        case "glutebridge":
            return ExerciseMotion(rootA: .ankle(CGPoint(x: 0.66, y: 0.86)), rootB: .ankle(CGPoint(x: 0.66, y: 0.86)),
                                  a: Pose(torso: 272, thigh: 62, shin: 168, upperArm: 95, forearm: 92),
                                  b: Pose(torso: 252, thigh: 100, shin: 178, upperArm: 80, forearm: 92),
                                  equipment: .mat, period: 2.6)
        default:
            let p = Pose(torso: 0, thigh: 180, shin: 180, upperArm: 180, forearm: 180)
            return ExerciseMotion(rootA: .ankle(CGPoint(x: 0.5, y: 0.9)), rootB: .ankle(CGPoint(x: 0.5, y: 0.9)),
                                  a: p, b: p, equipment: .none, period: 3)
        }
    }
}

enum FigureGeometry {
    // Uzunluklar tuval yüksekliğine oranla.
    static let torso = 0.28, thigh = 0.22, shin = 0.22, upperArm = 0.15, forearm = 0.14
    static let neck = 0.035, head = 0.055, foot = 0.07

    static func dir(_ deg: Double) -> CGVector {
        let r = deg * .pi / 180
        return CGVector(dx: sin(r), dy: -cos(r))
    }
    static func add(_ p: CGPoint, _ v: CGVector, _ len: Double) -> CGPoint {
        CGPoint(x: p.x + v.dx * len, y: p.y + v.dy * len)
    }

    static func joints(_ pose: Pose, root: FigureRoot) -> FigureJoints {
        var hip: CGPoint, knee: CGPoint, ankle: CGPoint
        switch root {
        case .ankle(let a):
            ankle = a
            knee = add(a, dir(pose.shin), -shin)
            hip = add(knee, dir(pose.thigh), -thigh)
        case .hip(let h):
            hip = h
            knee = add(h, dir(pose.thigh), thigh)
            ankle = add(knee, dir(pose.shin), shin)
        }
        let shoulder = add(hip, dir(pose.torso), torso)
        let head = add(shoulder, dir(pose.torso), neck + head)
        let elbow = add(shoulder, dir(pose.upperArm), upperArm)
        let hand = add(elbow, dir(pose.forearm), forearm)
        // Ayak: sırtüstü/plank durumunda da ayak tabanı yere basacak şekilde öne doğru
        let toe = CGPoint(x: ankle.x + foot, y: ankle.y)
        return FigureJoints(hip: hip, knee: knee, ankle: ankle, toe: toe, shoulder: shoulder, elbow: elbow, hand: hand, head: head)
    }
}

struct ExerciseFigure: View {
    let exerciseID: String
    var animated = true
    var lineScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = ExerciseMotion.of(exerciseID)
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    figure(motion, t: phase(ctx.date, period: motion.period))
                }
            } else {
                figure(motion, t: 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func phase(_ date: Date, period: Double) -> Double {
        let x = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        // 0→1→0, uçlarda kısa bekleme (hareketin tepe ve dip noktası)
        let tri = x < 0.5 ? x * 2 : (1 - x) * 2
        let held = min(1, max(0, (tri - 0.12) / 0.76))
        return held * held * (3 - 2 * held)
    }

    private func figure(_ m: ExerciseMotion, t: Double) -> some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let ox = (size.width - s) / 2, oy = (size.height - s) / 2
            func P(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
            let pose = Pose.mix(m.a, m.b, t)
            let root: FigureRoot
            switch (m.rootA, m.rootB) {
            case let (.hip(a), .hip(b)): root = .hip(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            case let (.ankle(a), .ankle(b)): root = .ankle(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            default: root = m.rootA
            }
            let j = FigureGeometry.joints(pose, root: root)
            let w = s * 0.05 * lineScale
            let ink = Color.ofDeep
            let far = Color.ofDeep.opacity(0.32)
            let gear = Color(hex: 0x8A9A92)
            let floorY = max(j.ankle.y, j.toe.y) + 0.02

            func line(_ pts: [CGPoint], _ color: Color, _ width: CGFloat, offset: CGFloat = 0) {
                var path = Path()
                path.addLines(pts.map { CGPoint(x: P($0).x + offset, y: P($0).y) })
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func rect(_ x: Double, _ y: Double, _ w2: Double, _ h: Double, _ c: Color, r: CGFloat = 4) {
                let rr = CGRect(x: ox + x * s, y: oy + y * s, width: w2 * s, height: h * s)
                ctx.fill(Path(roundedRect: rr, cornerRadius: r), with: .color(c))
            }

            // Zemin
            line([CGPoint(x: 0.04, y: floorY), CGPoint(x: 0.96, y: floorY)], Color.ofDivider, 2)

            // Ekipman (arka plan)
            switch m.equipment {
            case .cable:
                line([CGPoint(x: 0.80, y: 0.06), CGPoint(x: 0.80, y: floorY)], gear, w * 0.8)
                line([CGPoint(x: 0.80, y: 0.06), CGPoint(x: 0.50, y: 0.06)], gear, w * 0.8)
                line([CGPoint(x: 0.50, y: 0.06), j.hand], gear.opacity(0.8), 1.5)
                rect(j.hip.x - 0.10, j.hip.y + 0.03, 0.20, 0.035, gear)                  // oturak
                line([CGPoint(x: j.hip.x, y: j.hip.y + 0.065), CGPoint(x: j.hip.x, y: floorY)], gear, w * 0.6)
                rect(j.knee.x - 0.05, j.knee.y - 0.075, 0.10, 0.035, gear)               // diz pedi
            case .dumbbellBench:
                let left = min(j.shoulder.x, j.hip.x) - 0.06, right = max(j.shoulder.x, j.hip.x) + 0.03
                rect(left, j.hip.y + 0.03, right - left, 0.04, gear)
                line([CGPoint(x: left + 0.04, y: j.hip.y + 0.07), CGPoint(x: left + 0.04, y: floorY)], gear, w * 0.6)
                line([CGPoint(x: right - 0.04, y: j.hip.y + 0.07), CGPoint(x: right - 0.04, y: floorY)], gear, w * 0.6)
            case .mat:
                rect(0.06, floorY - 0.012, 0.88, 0.014, Color.ofLime, r: 3)
            default: break
            }

            // Arka bacak ve kol (derinlik için soluk, hafif kaydırılmış)
            line([j.hip, j.knee, j.ankle, j.toe], far, w, offset: -s * 0.018)
            line([j.shoulder, j.elbow, j.hand], far, w * 0.85, offset: -s * 0.018)

            // Gövde, baş, ön bacak ve kol
            line([j.hip, j.shoulder], ink, w * 1.35)
            let hc = P(j.head), hr = FigureGeometry.head * s
            ctx.fill(Path(ellipseIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2)), with: .color(ink))
            line([j.hip, j.knee, j.ankle, j.toe], ink, w)
            line([j.shoulder, j.elbow, j.hand], ink, w * 0.85)

            // Ekipman (ön plan, elde)
            let h = P(j.hand)
            switch m.equipment {
            case .barbell:
                line([CGPoint(x: j.hand.x - 0.14, y: j.hand.y), CGPoint(x: j.hand.x + 0.14, y: j.hand.y)], gear, w * 0.45)
                let pr = s * 0.085
                ctx.fill(Path(ellipseIn: CGRect(x: h.x - pr, y: h.y - pr, width: pr * 2, height: pr * 2)), with: .color(gear.opacity(0.85)))
                ctx.fill(Path(ellipseIn: CGRect(x: h.x - pr * 0.3, y: h.y - pr * 0.3, width: pr * 0.6, height: pr * 0.6)), with: .color(Color.ofBackground))
            case .cable:
                line([CGPoint(x: j.hand.x - 0.09, y: j.hand.y), CGPoint(x: j.hand.x + 0.09, y: j.hand.y)], ink.opacity(0.75), w * 0.5)
            case .dumbbellBench:
                line([CGPoint(x: j.hand.x - 0.045, y: j.hand.y), CGPoint(x: j.hand.x + 0.045, y: j.hand.y)], gear, w * 0.45)
                for dx in [-0.05, 0.05] {
                    rect(j.hand.x + dx - 0.015, j.hand.y - 0.035, 0.03, 0.07, gear, r: 3)
                }
            default: break
            }
        }
    }
}

// MARK: - Antrenman sekmesi

struct WorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("of.workoutPlace") private var placeRaw = WorkoutPlace.gym.rawValue
    @State private var showPlayer = false

    private var place: WorkoutPlace { WorkoutPlace(rawValue: placeRaw) ?? .gym }

    var body: some View {
        let limits = store.profile?.limits ?? []
        let program = ExerciseLibrary.todaysWorkout(place: place, limits: limits)
        let skipped = ExerciseLibrary.all.filter { $0.place == place && !$0.avoidFor.isDisjoint(with: limits) }
        let done = store.todayWorkout

        ScreenScroll {
            BrandBar()
            ScreenHeading(kicker: "Antrenman", plain: "Bugünün ", accent: "programı.")
            HStack(spacing: 8) {
                ForEach(WorkoutPlace.allCases) { p in
                    Button { placeRaw = p.rawValue } label: {
                        Label(p.title, systemImage: p == .gym ? "dumbbell" : "house")
                    }
                    .buttonStyle(PillButtonStyle(selected: place == p))
                    .accessibilityAddTraits(place == p ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(place == .gym ? "Salon · tüm vücut" : "Ev · ekipmansız", color: Color.white.opacity(0.75))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(ExerciseLibrary.estimatedMinutes(program))").font(.system(.largeTitle).weight(.bold)).monospacedDigit()
                            Text("dk").font(.title3)
                        }
                        Text("\(program.count) hareket · \(program.reduce(0) { $0 + $1.sets }) set")
                            .font(.subheadline).foregroundStyle(Color.white.opacity(0.85))
                    }
                    Spacer()
                    if let first = program.first {
                        ExerciseFigure(exerciseID: first.id).frame(width: 110, height: 110)
                            .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                if let done {
                    Label("Bugün tamamlandı · \(done.minutes) dk", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ofRing)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(Color.ofDeep, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Button { showPlayer = true } label: {
                Label(done == nil ? "Antrenmanı başlat" : "Tekrar başlat", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(program.isEmpty)

            SectionHeader("Hareketler")
            VStack(spacing: 10) {
                ForEach(program) { ex in
                    NavigationLink(value: Route.exercise(ex.id)) { ExerciseRow(exercise: ex) }
                        .buttonStyle(.plain)
                }
            }
            if !skipped.isEmpty {
                InfoCard(title: "Kısıtların nedeniyle çıkarıldı",
                         text: skipped.map { "\($0.name)\($0.alternative.map { " → yerine: " + $0 } ?? "")" }.joined(separator: "\n"),
                         tint: .ofSage)
            }
            InfoCard(title: "Güvenlik",
                     text: "Her antrenmandan önce 5 dk ısın. Ağrı, baş dönmesi veya göğüs ağrısı olursa dur. Yeni başlıyorsan hafif ağırlıkla tekniği öğren; kronik bir hastalığın varsa önce hekimine danış.")
        }
        .rootScreen()
        .fullScreenCover(isPresented: $showPlayer) {
            WorkoutPlayerView(exercises: program, place: place).environmentObject(store)
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-OvisScreen"), i + 1 < args.count, args[i + 1] == "player" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showPlayer = true }
            }
            #endif
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        HStack(spacing: 14) {
            ExerciseFigure(exerciseID: exercise.id)
                .frame(width: 72, height: 72)
                .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.headline).foregroundStyle(Color.ofInk)
                Text("\(exercise.sets) set × \(exercise.reps) tekrar").font(.subheadline.weight(.semibold)).foregroundStyle(Color.ofDeep)
                Text(exercise.muscles).font(.footnote).foregroundStyle(Color.ofMuted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").foregroundStyle(Color.ofMuted)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseDetailView: View {
    let exerciseID: String

    var body: some View {
        if let ex = ExerciseLibrary.exercise(exerciseID) {
            ScreenScroll {
                ExerciseFigure(exerciseID: ex.id, lineScale: 1.1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                ScreenHeading(kicker: ex.muscles, plain: ex.name, accent: "")
                HStack(spacing: 10) {
                    stat("\(ex.sets)", "set")
                    stat(ex.reps, "tekrar")
                    stat("\(ex.restSeconds) sn", "dinlenme")
                }
                Label(ex.equipment, systemImage: "dumbbell").font(.subheadline).foregroundStyle(Color.ofMuted)

                SectionHeader("Doğru yapılış")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(ex.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(Color.ofDeep, in: Circle())
                            Text(step).font(.body).foregroundStyle(Color.ofInk).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                SectionHeader("Sık yapılan hatalar")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ex.mistakes, id: \.self) { m in
                        Label { Text(m).fixedSize(horizontal: false, vertical: true) } icon: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ofWarn)
                        }
                    }
                }
                if let alt = ex.alternative {
                    InfoCard(title: "Daha kolay alternatif", text: alt)
                }
            }
            .secondaryScreen()
        }
    }

    private func stat(_ value: String, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.caption).foregroundStyle(Color.ofMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Antrenman oynatıcı

final class Coach {
    private let synth = AVSpeechSynthesizer()
    var enabled = true
    func say(_ text: String) {
        guard enabled else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        u.rate = 0.5
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}

struct WorkoutPlayerView: View {
    let exercises: [Exercise]
    let place: WorkoutPlace
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var session: WorkoutSession
    @State private var started = Date()
    @State private var coach = Coach()
    @AppStorage("of.workoutVoice") private var voice = true
    @State private var saved = false
    @State private var confirmClose = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(exercises: [Exercise], place: WorkoutPlace) {
        self.exercises = exercises
        self.place = place
        _session = State(initialValue: WorkoutSession(exercises: exercises))
    }

    private var minutes: Int { max(1, Int((Date().timeIntervalSince(started) / 60).rounded())) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Button { if session.phase == .finished { dismiss() } else { confirmClose = true } } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(Color.ofInk)
                        .frame(width: 44, height: 44).background(Color.ofSoftLime, in: Circle())
                }
                .accessibilityLabel("Kapat")
                ProgressView(value: session.progress).tint(Color.ofDeep)
                Button { voice.toggle(); coach.enabled = voice } label: {
                    Image(systemName: voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.headline).foregroundStyle(Color.ofInk)
                        .frame(width: 44, height: 44).background(Color.ofSoftLime, in: Circle())
                }
                .accessibilityLabel(voice ? "Sesli yönlendirmeyi kapat" : "Sesli yönlendirmeyi aç")
            }

            if session.phase == .finished {
                finished
            } else if let ex = session.current {
                ExerciseFigure(exerciseID: ex.id, lineScale: 1.1)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 320)
                    .background(Color.ofSoftLime, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(spacing: 6) {
                    Text(ex.name).font(.title.weight(.bold)).foregroundStyle(Color.ofInk)
                    Text("Set \(session.set) / \(ex.sets) · \(ex.reps) tekrar")
                        .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Color.ofDeep)
                    Text("Hareket \(session.index + 1) / \(exercises.count)").font(.subheadline).foregroundStyle(Color.ofMuted)
                }
                Spacer(minLength: 0)
                if case .rest(let r) = session.phase {
                    VStack(spacing: 8) {
                        Kicker("Dinlen")
                        Text(String(format: "%d:%02d", r / 60, r % 60))
                            .font(.system(size: 64, weight: .bold)).monospacedDigit().foregroundStyle(Color.ofInk)
                            .accessibilityLabel("\(r) saniye dinlenme kaldı")
                        Button("Dinlenmeyi atla") { session.skipRest(); announceSet() }
                            .buttonStyle(LinkButtonStyle())
                    }
                } else {
                    Button {
                        session.finishSet()
                        announceAfterSet()
                    } label: { Label("Seti bitirdim", systemImage: "checkmark") }
                        .buttonStyle(PrimaryButtonStyle())
                        .sensoryFeedback(.success, trigger: session.completedSets)
                    Button("Bu hareketi atla") { session.skipExercise(); announceSet() }
                        .buttonStyle(LinkButtonStyle())
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 12)
        .background(Color.ofBackground.ignoresSafeArea())
        .onReceive(ticker) { _ in
            guard case .rest(let r) = session.phase else { return }
            if r == 11 { coach.say("Son on saniye") }
            session.tick()
            if session.phase == .set { announceSet() }
        }
        .onAppear {
            coach.enabled = voice
            UIApplication.shared.isIdleTimerDisabled = true
            announceSet()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("Antrenman bitirilsin mi?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Kaydetmeden çık", role: .destructive) { dismiss() }
            if session.completedSets > 0 {
                Button("Yapılan kadarını kaydet") { save(); dismiss() }
            }
        }
    }

    private var finished: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "trophy.fill").font(.system(size: 64)).foregroundStyle(Color.ofDeep)
            DisplayTitle(plain: "Harika, ", accent: "bitti!")
            Text("\(session.completedSets) set · \(minutes) dk · yaklaşık \(ActivityEnergy.fromActivity(record, weightKg: store.profile?.weightKg ?? 70)) kcal")
                .font(.headline).monospacedDigit().foregroundStyle(Color.ofMuted)
            Spacer()
            Button {
                save(); dismiss()
            } label: { Label(saved ? "Kaydedildi" : "Kaydet ve kapat", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(saved)
        }
        .onAppear { coach.say("Tebrikler, antrenman bitti") }
    }

    private var record: ActivityRecord {
        ActivityRecord(date: Date(), optionID: "workout", title: "\(place.title) antrenmanı", minutes: minutes)
    }

    private func save() {
        guard !saved else { return }
        saved = true
        store.completeWorkout(record)
    }

    private func announceSet() {
        guard let ex = session.current, session.phase == .set else { return }
        coach.say("\(ex.name). Set \(session.set). \(ex.reps) tekrar.")
    }

    private func announceAfterSet() {
        if case .rest(let r) = session.phase { coach.say("Dinlen, \(r) saniye") } else { announceSet() }
    }
}
