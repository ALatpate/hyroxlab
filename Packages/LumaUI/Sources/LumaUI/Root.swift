import SwiftUI
import LumaCore
import LumaKit

/// Luma's root: four tabs under a floating bar with the Go button at its centre.
public struct LumaRootView: View {
    @ObservedObject private var env: LumaEnv
    @ObservedObject private var router: LumaRouter
    private let launch: LumaLaunch

    public init(env: LumaEnv, launch: LumaLaunch = LumaLaunch()) {
        self.env = env
        self.router = env.router
        self.launch = launch
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.tab) {
                NavigationStack(path: $router.todayPath) {
                    TodayScreen().navigationDestination(for: LumaDest.self) { LumaDestinationView(dest: $0) }
                }
                .tag(LumaTab.today)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $router.trainPath) {
                    TrainScreen().navigationDestination(for: LumaDest.self) { LumaDestinationView(dest: $0) }
                }
                .tag(LumaTab.train)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $router.fuelPath) {
                    FuelScreen().navigationDestination(for: LumaDest.self) { LumaDestinationView(dest: $0) }
                }
                .tag(LumaTab.fuel)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack(path: $router.coachPath) {
                    CoachScreen().navigationDestination(for: LumaDest.self) { LumaDestinationView(dest: $0) }
                }
                .tag(LumaTab.coach)
                .toolbar(.hidden, for: .tabBar)
            }
            LumaTabBar(router: router)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Luma.night.ignoresSafeArea())
        .environmentObject(env)
        .environmentObject(env.live)
        .environmentObject(router)
        .tint(Luma.volt)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.small ... .xLarge)
        .sheet(item: $router.sheet) { sheet in
            LumaSheetView(sheet: sheet)
                .environmentObject(env)
                .environmentObject(env.live)
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $router.cover) { cover in
            LumaCoverView(cover: cover)
                .environmentObject(env)
                .environmentObject(env.live)
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
        .task {
            env.reload()
            LumaRoute.apply(launch.screen, env: env)
            if launch.screen == nil, !env.profile.isSetUp { router.cover = .onboarding }
        }
    }
}

// MARK: - Tab bar

struct LumaTabBar: View {
    @ObservedObject var router: LumaRouter

    var body: some View {
        HStack(spacing: 0) {
            tab(.today)
            tab(.train)
            Button {
                LumaHaptics.thud()
                router.sheet = .go
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Luma.ink)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Luma.volt))
                    .shadow(color: Luma.volt.opacity(0.5), radius: 14, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .accessibilityLabel("Start a session")
            tab(.fuel)
            tab(.coach)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Luma.slate.opacity(0.82))
                .background(Capsule().fill(.ultraThinMaterial))
        )
        .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        .padding(.horizontal, 18)
        .padding(.bottom, 2)
    }

    private func tab(_ t: LumaTab) -> some View {
        let isOn = router.tab == t
        return Button {
            LumaHaptics.select()
            if isOn { popToRoot(t) } else { router.tab = t }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: t.symbol).font(.system(size: 18, weight: .semibold))
                Text(t.title).font(LumaFont.label(9.5))
            }
            .foregroundStyle(isOn ? Luma.frost : Luma.smoke)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func popToRoot(_ t: LumaTab) {
        switch t {
        case .today: router.todayPath.removeAll()
        case .train: router.trainPath.removeAll()
        case .fuel: router.fuelPath.removeAll()
        case .coach: router.coachPath.removeAll()
        }
    }
}

// MARK: - Destinations

struct LumaDestinationView: View {
    let dest: LumaDest

    var body: some View {
        switch dest {
        case .sleep: SleepScreen()
        case .recovery: RecoveryScreen()
        case .strain: StrainScreen()
        case .heart: HeartScreen()
        case .vitals: VitalsScreen()
        case .stress: StressScreen()
        case .trends: TrendsScreen()
        case .insights: InsightsScreen()
        case .load: LoadScreen()
        case .workout(let id): WorkoutScreen(id: id)
        case .raceReadiness: RaceReadinessScreen()
        case .strength: StrengthScreen()
        case .history: HistoryScreen()
        case .session(let id): SessionReportScreen(id: id)
        case .lift(let id): LiftDetailScreen(id: id)
        case .supplements: SupplementsScreen()
        case .fuelHistory: FuelHistoryScreen()
        case .devices: DevicesScreen()
        case .settings: SettingsScreen()
        case .profile: ProfileScreen()
        case .about: AboutScreen()
        }
    }
}

struct LumaSheetView: View {
    let sheet: LumaSheetDest

    var body: some View {
        switch sheet {
        case .go: GoSheet()
        case .you: YouSheet()
        case .checkIn(let day): CheckInSheet(day: day)
        case .fuelAdd(let mode): FuelAddSheet(mode: mode)
        case .plan(let session, let day): PlanEditSheet(session: session, day: day)
        case .routine: RoutineSheet()
        case .coachSetup: CoachSetupSheet()
        case .manualWorkout: ManualWorkoutSheet()
        }
    }
}

struct LumaCoverView: View {
    let cover: LumaCoverDest

    var body: some View {
        switch cover {
        case .run(let plan): RunLiveScreen(plan: plan)
        case .race(let kind): RaceLiveScreen(kind: kind)
        case .lift: LiftLiveScreen()
        case .onboarding: OnboardingScreen()
        }
    }
}

// MARK: - Launch routing (development)

/// Opens a screen by name, e.g. "today.sleep" or "sheet.go". Used by the screenshot harness.
@MainActor
enum LumaRoute {
    static func apply(_ name: String?, env: LumaEnv) {
        guard let name, !name.isEmpty else { return }
        let r = env.router
        let today = LumaAnalysis.todayKey()
        switch name {
        case "today": r.tab = .today
        case "today.sleep": r.open(.today, .sleep)
        case "today.recovery": r.open(.today, .recovery)
        case "today.strain": r.open(.today, .strain)
        case "today.heart": r.open(.today, .heart)
        case "today.vitals": r.open(.today, .vitals)
        case "today.stress": r.open(.today, .stress)
        case "today.trends": r.open(.today, .trends)
        case "today.insights": r.open(.today, .insights)
        case "today.load": r.open(.today, .load)
        case "train": r.tab = .train
        case "train.workout":
            r.tab = .train
            Task {
                let all = await env.source.loadWorkouts(days: 60)
                if let w = all.first(where: { $0.kind == .run }) ?? all.first { r.push(.workout(w.id)) }
            }
        case "train.readiness": r.open(.train, .raceReadiness)
        case "train.strength": r.open(.train, .strength)
        case "train.history": r.open(.train, .history)
        case "fuel": r.tab = .fuel
        case "fuel.supplements": r.open(.fuel, .supplements)
        case "fuel.history": r.open(.fuel, .fuelHistory)
        case "coach": r.tab = .coach
        case "you.devices": r.open(.today, .devices)
        case "you.settings": r.open(.today, .settings)
        case "you.profile": r.open(.today, .profile)
        case "you.about": r.open(.today, .about)
        case "sheet.go": r.sheet = .go
        case "sheet.you": r.sheet = .you
        case "sheet.checkin": r.sheet = .checkIn(today)
        case "sheet.fuel": r.sheet = .fuelAdd(.meal)
        case "sheet.photo": r.sheet = .fuelAdd(.photo)
        case "sheet.supplement": r.sheet = .fuelAdd(.supplement)
        case "sheet.plan": r.tab = .train; r.sheet = .plan(nil, today)
        case "sheet.routine": r.tab = .train; r.sheet = .routine
        case "sheet.coach": r.tab = .coach; r.sheet = .coachSetup
        case "cover.run": r.cover = .run(RunPlan())
        case "cover.race": r.cover = .race(.fullSimulation)
        case "cover.lift": r.cover = .lift
        case "cover.onboarding": r.cover = .onboarding
        default: break
        }
    }
}
