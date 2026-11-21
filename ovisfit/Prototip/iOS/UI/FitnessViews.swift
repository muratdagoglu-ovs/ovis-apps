import SwiftUI
import AVFoundation
import UIKit

private struct ExercisePoster: View {
    let id: String
    var body: some View {
        Image("ovi-" + id)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// Each layer owns one silent loop. Removing it stops decoding immediately.
private final class ExerciseMovieSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?

    func show(_ url: URL, playing: Bool) {
        if loadedURL == url {
            if playing {
                if queue?.rate == 0 { queue?.play() }
            } else {
                queue?.pause()
            }
            return
        }
        stop()
        let player = AVQueuePlayer()
        player.isMuted = true
        let item = AVPlayerItem(url: url)
        queue = player
        looper = AVPlayerLooper(player: player, templateItem: item)
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = player
        loadedURL = url
        if playing { player.play() }
    }

    func stop() {
        queue?.pause()
        looper?.disableLooping()
        videoLayer.player = nil
        queue?.removeAllItems()
        looper = nil
        queue = nil
        loadedURL = nil
    }
}

private struct ExerciseMovie: UIViewRepresentable {
    let url: URL
    let playing: Bool
    func makeUIView(context: Context) -> ExerciseMovieSurface { ExerciseMovieSurface() }
    func updateUIView(_ view: ExerciseMovieSurface, context: Context) { view.show(url, playing: playing) }
    static func dismantleUIView(_ view: ExerciseMovieSurface, coordinator: ()) { view.stop() }
}

private struct ExerciseDemo: View {
    let exercise: Exercise
    let resting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var userWantsPlayback: Bool?
    @State private var didPlay = false

    var body: some View {
        let url = Bundle.main.url(forResource: exercise.id, withExtension: "mp4",
                                  subdirectory: "WorkoutMedia")
        let playing = (userWantsPlayback ?? !reduceMotion) && !resting && scenePhase == .active
        ZStack(alignment: .bottomTrailing) {
            Color(hex: 0xE4EDE3)
            ExercisePoster(id: exercise.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let url, (playing || didPlay) && !resting && scenePhase == .active {
                ExerciseMovie(url: url, playing: playing)
                    .onAppear { didPlay = true }
                    .accessibilityHidden(true)
            }
            if url != nil && !resting {
                Button {
                    userWantsPlayback = !playing
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.ofDeep.opacity(0.92), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playing ? "Gösterimi duraklat" : "Ovi ile hareketi izle")
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onChange(of: reduceMotion) { _, _ in
            didPlay = false
            userWantsPlayback = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ovi ile " + exercise.name)
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

            VStack(alignment: .leading, spacing: 9) {
                Kicker(place == .gym ? "Salon · tüm vücut" : "Ev · ekipmansız",
                       color: Color.white.opacity(0.87))
                Text("\(ExerciseLibrary.estimatedMinutes(program)) dk")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("\(program.count) hareket · \(program.reduce(0) { $0 + $1.sets }) set")
                    .font(.subheadline.weight(.semibold))
                if let done {
                    Label("Bugün tamamlandı · \(done.minutes) dk", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(20)
            .foregroundStyle(.white)
            .background {
                GeometryReader { geometry in
                    Image("ovi-training-studio").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                        .clipped()
                }
                LinearGradient(colors: [Color.ofDeep.opacity(0.94), Color.ofDeep.opacity(0.77), .clear],
                               startPoint: .leading, endPoint: .trailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

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
            ExercisePoster(id: exercise.id)
                .frame(width: 88, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                ExerciseDemo(exercise: ex, resting: false)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .id(ex.id)
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
                ExerciseDemo(exercise: ex, resting: session.phase != .set)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .frame(maxHeight: 300)
                    .id(ex.id)
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
