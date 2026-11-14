import SwiftUI
import LumaCore

/// HYROX Lab's five-tab shell. Replaces NOOP's RootTabView when `hyrox.shellEnabled` is on; every
/// NOOP screen stays reachable from Body (Trends, Sleep, Health, Stress…) and Train (Workouts, Lift
/// Log) so nothing upstream is lost.
struct HXRootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var router: NavRouter
    @StateObject private var store = HXStore()
    @State private var tab = 0
    @State private var showDevices = false
    @State private var showOnboarding = false
    @State private var activeRun: RunSessionController? = nil
    @State private var activeRace: RaceSessionController? = nil
    @State private var resumePrompt = false

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(HX.ink)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HXTodayView(startRun: startRun, startRace: startRace).tabRouteDestinations() }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }.tag(0)
            NavigationStack { HXTrainView().tabRouteDestinations() }
                .tabItem { Label("Train", systemImage: "calendar") }.tag(1)
            NavigationStack { HXGoView(startRun: startRun, startRace: startRace).tabRouteDestinations() }
                .tabItem { Label("Go", systemImage: "play.circle.fill") }.tag(2)
            NavigationStack { HXBodyView().tabRouteDestinations() }
                .tabItem { Label("Body", systemImage: "heart.text.square.fill") }.tag(3)
            NavigationStack { HXCoachView().tabRouteDestinations() }
                .tabItem { Label("Coach", systemImage: "sparkles") }.tag(4)
        }
        .tint(HX.volt)
        .preferredColorScheme(.dark)
        .environmentObject(store)
        .task {
            store.attach(repo: repo, profile: profile)
            if !store.profile.onboarded { showOnboarding = true }
            if store.plan.isEmpty || (store.plan.last.map { $0.date < Date() } ?? false) { store.regeneratePlan() }
            HXCoachContext.install(store: store)
            if store.unfinished != nil { resumePrompt = true }
        }
        .sheet(isPresented: $showOnboarding) { HXOnboardingView().environmentObject(store).interactiveDismissDisabled() }
        .sheet(isPresented: $showDevices) { DevicesView() }
        .fullScreenCover(item: $activeRun) { run in
            HXRunLiveView(controller: run) { activeRun = nil }
                .environmentObject(store)
        }
        .fullScreenCover(item: $activeRace) { race in
            HXRaceModeView(controller: race) { activeRace = nil }
                .environmentObject(store)
        }
        .alert("Unfinished session", isPresented: $resumePrompt) {
            Button("Discard", role: .destructive) { if let s = store.unfinished { store.delete(s) } }
            Button("Keep as is") { if var s = store.unfinished { s.endedAt = Date(); store.upsert(s) } }
        } message: {
            Text("A session was still running when the app closed. Keep what was recorded, or discard it.")
        }
        .onChange(of: router.requestedDestination) { _, dest in
            guard let dest else { return }
            switch dest {
            case .devices: showDevices = true
            case .coach: tab = 4
            case .trends: tab = 3
            case .activeWorkout, .liveSession: tab = 2
            default: break
            }
            router.requestedDestination = nil
        }
    }

    private func startRun(_ kind: HXSessionKind, planned: PlannedSession?) {
        let c = RunSessionController(model: model, store: store, kind: kind, planned: planned)
        activeRun = c
    }

    private func startRace(_ kind: HXSessionKind, planned: PlannedSession?) {
        let c = RaceSessionController(model: model, store: store, kind: kind, planned: planned)
        activeRace = c
    }
}
