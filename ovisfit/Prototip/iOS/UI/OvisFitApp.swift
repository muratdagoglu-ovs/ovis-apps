import SwiftUI

@main
struct OvisFitApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var router = Router()
    @StateObject private var plate = PlateFlowModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(plate)
                .tint(Color.ofDeep)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.profile == nil {
                OnboardingView()
            } else {
                MainTabs()
            }
        }
        .background(Color.ofBackground.ignoresSafeArea())
        .onReceive(clock) { date in
            store.now = date
            Task { await store.refreshHealth() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.now = Date()
                Task { await store.refreshHealth() }
            }
        }
        .task { await store.refreshHealth() }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var plate: PlateFlowModel

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.today) {
                TodayView().withRoutes()
            }
            .tabItem { Label("Bugün", systemImage: "house") }
            .tag(Router.Tab.today)

            NavigationStack(path: $router.plan) {
                PlanView().withRoutes()
            }
            .tabItem { Label("Plan", systemImage: "calendar") }
            .tag(Router.Tab.plan)

            NavigationStack(path: $router.workout) {
                WorkoutView().withRoutes()
            }
            .tabItem { Label("Antrenman", systemImage: "dumbbell") }
            .tag(Router.Tab.workout)

            NavigationStack(path: $router.water) {
                WaterView().withRoutes()
            }
            .tabItem { Label("Su", systemImage: "drop") }
            .tag(Router.Tab.water)

            NavigationStack(path: $router.growth) {
                GrowthView().withRoutes()
            }
            .tabItem { Label("Gelişim", systemImage: "chart.xyaxis.line") }
            .tag(Router.Tab.growth)
        }
        .task { await openScreenshotScreen() }
    }

    /// Yalnızca `-OvisScreenshotData -OvisScreen <ekran>` ile: tasarım karşılaştırma görüntüleri için.
    private func openScreenshotScreen() async {
        let args = ProcessInfo.processInfo.arguments
        guard store.isScreenshotMode, let i = args.firstIndex(of: "-OvisScreen"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "water":
            router.tab = .water
        case "workout", "player":
            router.tab = .workout
        case "exercise":
            router.tab = .workout
            router.workout = [.exercise("squat")]
        case "analysis":
            router.tab = .today
            plate.useSample()
            router.today = [.photo]
            try? await Task.sleep(nanoseconds: 700_000_000)
            plate.analyze(endpoint: nil)
            plate.slot = .lunch
        default:
            router.tab = .today
        }
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .profile: ProfileFormView(mode: .edit)
            case .exercise(let id): ExerciseDetailView(exerciseID: id)
            case .reminders: RemindersView()
            case .barcode: BarcodeView()
            case .shopping: ShoppingView()
            case .photo: PhotoView()
            case .analysis: AnalysisView()
            case .movement: MovementView()
            case .swap(let slot): SwapView(slot: slot)
            case .swelling: SwellingView()
            }
        }
    }

    /// Ana sekme ekranları kendi marka satırını gösterir; sistem gezinme çubuğu gizlenir.
    func rootScreen() -> some View {
        toolbar(.hidden, for: .navigationBar)
    }

    /// İkincil ekranlar: sistem geri düğmesi ve kaydırarak geri dönme korunur.
    func secondaryScreen(_ title: String = "") -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ofBackground, for: .navigationBar)
    }
}
