import SwiftUI
import LumaCore
import LumaKit

/// Luma's root: four tabs under a floating bar with the Go button at its centre.
public struct LumaRootView: View {
    @ObservedObject private var env: LumaEnv
    @ObservedObject private var router: LumaRouter
    @ObservedObject private var keyboard = LumaKeyboard.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Namespace private var zoom
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
            // The bar floats over the pages. Left to itself it rises with the keyboard and sits on top
            // of the box being typed in, which is what hid the coach's box and any field on a tab's
            // page. It is held at the foot of the screen, behind the keyboard, and is out of sight and
            // out of reach while one is up.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LumaTabBar(router: router)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .opacity(keyboard.isUp ? 0 : 1)
            .allowsHitTesting(!keyboard.isUp)
        }
        .overlay(alignment: .top) { celebration }
        // While the athlete's records cannot be opened, nothing behind this can be reached.
        .overlay { if !env.storesReady { LumaHoldingScreen() } }
        .background(Luma.night.ignoresSafeArea())
        // Text sized from the system setting is measured again when that setting changes.
        .id(textSize)
        .onChange(of: textSize) { _, _ in LumaType.textSizeChanged() }
        .environment(\.lumaZoom, zoom)
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
            env.isInFront = scenePhase != .background
            env.retryStores()
            env.reload()
            LumaRoute.apply(launch.screen, env: env)
            offerSetup()
            await signalReady()
        }
        .onChange(of: env.storesReady) { _, ready in if ready { offerSetup() } }
        // Coming back on screen reloads, so anything held back while the app was out of sight (the
        // search for unrecorded sessions) runs for the person now looking.
        .onChange(of: scenePhase) { _, phase in
            // A phone that was locked when Luma was started is unlocked by now.
            if phase == .active { env.retryStores() }
            let front = phase != .background
            guard front != env.isInFront else { return }
            env.isInFront = front
            if front { env.reload() }
        }
    }

    /// The first-run screens are for someone whose details are not there, never for someone whose
    /// details could not be read: asking for them again then ends with the real ones saved over.
    private func offerSetup() {
        guard launch.screen == nil, env.storesReady, !env.profile.isSetUp, router.cover == nil else { return }
        router.cover = .onboarding
    }
}

/// Shown in place of the app while the athlete's records cannot be opened, which is what happens
/// when the strap starts Luma while the phone is locked. It clears by itself the moment they can be.
struct LumaHoldingScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var tries = 0
    @State private var asking = false

    /// Still unread after several tries with the phone unlocked: not the lock, so say what and offer the way on.
    private var stuck: Bool {
        if env.isDemo { return env.demoScenario == "stuck" }
        return tries >= 3 && !env.storesSealed
    }

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .neutral, strength: 0.7)
            VStack(spacing: 14) {
                Image(systemName: stuck ? "exclamationmark.triangle" : "lock.open")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(stuck ? Luma.amber : Luma.mist)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                Text(stuck ? "Some of your records will not open" : "Opening your records")
                    .font(LumaFont.title(24)).foregroundStyle(Luma.frost).multilineTextAlignment(.center)
                Text(stuck
                     ? "Luma could not read these, though the phone is unlocked. Nothing has been changed or deleted."
                     : "Luma was started while your phone was locked and could not read what you have logged. Nothing is lost. This clears by itself in a moment.")
                    .font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if stuck {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(env.unreadStores, id: \.self) { name in
                            Text(name).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LumaPanel(radius: 18))
                    Button("Try again") {
                        LumaHaptics.tap()
                        env.retryStores()
                    }
                    .buttonStyle(LumaPrimaryButtonStyle())
                    Button("Start without them") { asking = true }
                        .buttonStyle(LumaSecondaryButtonStyle())
                    Text("Starting without them moves those files aside on this phone and uses the last copy Luma kept of each. The files are not deleted.")
                        .font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().tint(Luma.mist).padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
        }
        // Nothing underneath can be touched through this.
        .contentShape(Rectangle())
        .task {
            // Tried again every second and a half while this is up.
            while !Task.isCancelled, !env.storesReady {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                env.retryStores()
                tries += 1
            }
        }
        .confirmationDialog("Start without these records?", isPresented: $asking, titleVisibility: .visible) {
            Button("Start without them", role: .destructive) { env.startWithoutUnreadStores() }
            Button("Keep trying", role: .cancel) {}
        } message: {
            Text("The files are moved aside, not deleted, and the last copy Luma kept of each is used.")
        }
    }
}

extension LumaRootView {
    /// Development only: when the app was launched straight onto a named screen, says when that screen
    /// is ready to photograph, by writing an empty file the screenshot harness waits for. Ready means
    /// the strap data has been read once and the screen has had time to draw and settle.
    fileprivate func signalReady() async {
        guard launch.screen != nil else { return }
        for _ in 0..<600 where !env.loaded { try? await Task.sleep(nanoseconds: 100_000_000) }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        try? Data().write(to: FileManager.default.temporaryDirectory.appendingPathComponent("luma-ready"))
    }

    /// A new best, shown once over whatever screen is up, then put away.
    @ViewBuilder
    fileprivate var celebration: some View {
        ZStack(alignment: .top) {
            if let best = env.celebration {
                NewBestBanner(best: best)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(LumaMotion.snap) { env.celebration = nil } }
                    .task(id: best.id) {
                        // The gallery leaves it up, so it can be photographed.
                        guard !env.isDemo else { return }
                        try? await Task.sleep(nanoseconds: 4_200_000_000)
                        if env.celebration?.id == best.id { withAnimation(LumaMotion.snap) { env.celebration = nil } }
                    }
            }
        }
        .animation(LumaMotion.snap, value: env.celebration)
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
        // Opens out of the tile that was tapped, when it named itself.
        screen.modifier(LumaZoomTarget())
    }

    @ViewBuilder
    private var screen: some View {
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
        case .dataCheck: DataCheckScreen()
        case .backups: BackupsScreen()
        case .doctor: DoctorScreen()
        case .buddy: BuddyScreen()
        case .trials: TrialsScreen()
        case .trial(let id): TrialScreen(id: id)
        case .dose: DoseScreen()
        case .drivers: DriversScreen()
        case .body: BodyScreen()
        case .reviews: ReviewsScreen()
        case .liftHistory(let name): LiftHistoryScreen(name: name)
        case .reminders: RemindersScreen()
        case .dev(let page): DevWidgetsScreen(page: page)
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
        case .raceEntry(let id): RaceEntrySheet(editing: id)
        case .workoutPhotos(let day): WorkoutPhotoSheet(day: day)
        case .weighIn: WeighInSheet()
        case .sweatTest: SweatTestSheet()
        case .trialSetup(let name): TrialSetupSheet(supplement: name)
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
        case "train.session":
            if let first = env.sessions.first { r.open(.train, .session(first.id)) } else { r.tab = .train }
        case "train.lift":
            if let first = env.lifts.sorted(by: { $0.start > $1.start }).first { r.open(.train, .lift(first.id)) } else { r.tab = .train }
        case "train.strength": r.open(.train, .strength)
        case "train.progress": r.tab = .train; r.trainView = .progress
        case "train.progress.trend": r.tab = .train; LumaLaunch.page = 1; r.trainView = .progress
        case "train.progress.work": r.tab = .train; LumaLaunch.page = 2; r.trainView = .progress
        case "train.progress.muscle": r.tab = .train; LumaLaunch.page = 3; r.trainView = .progress
        case "sheet.workouts": r.tab = .train; r.sheet = .workoutPhotos(today)
        case "sheet.workouts.review": r.tab = .train; LumaLaunch.page = 1; r.sheet = .workoutPhotos(today)
        case "sheet.workouts.hand": r.tab = .train; LumaLaunch.page = 2; r.sheet = .workoutPhotos(today)
        case "sheet.workouts.reading": r.tab = .train; LumaLaunch.page = 3; r.sheet = .workoutPhotos(today)
        case "train.history": r.open(.train, .history)
        case "fuel": r.tab = .fuel
        case "fuel.supplements": r.open(.fuel, .supplements)
        case "fuel.history": r.open(.fuel, .fuelHistory)
        case "coach": r.tab = .coach
        case "you.devices": r.open(.today, .devices)
        case "you.settings": r.open(.today, .settings)
        case "you.profile": r.open(.today, .profile)
        case "you.about": r.open(.today, .about)
        case "you.datacheck": r.open(.today, .dataCheck)
        case "you.backups": r.open(.today, .backups)
        case "today.doctor": r.open(.today, .doctor)
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
        case "cover.onboarding", "cover.onboarding.1", "cover.onboarding.2", "cover.onboarding.3", "cover.onboarding.4":
            LumaLaunch.page = Int(String(name.last ?? "0")) ?? 0
            r.cover = .onboarding
        case "sheet.manual": r.tab = .train; r.sheet = .manualWorkout
        case "sheet.race": r.tab = .train; r.sheet = .raceEntry(nil)
        case "sheet.race.filled": r.tab = .train; LumaLaunch.page = 1; r.sheet = .raceEntry(nil)
        case "sheet.race.check": r.tab = .train; LumaLaunch.page = 2; r.sheet = .raceEntry(nil)
        case "dev.lock": r.open(.today, .dev(0))
        case "dev.home": r.open(.today, .dev(1))
        case "dev.home2": r.open(.today, .dev(2))
        case "dev.buddy": r.open(.today, .dev(3))
        case "dev.glimm": r.open(.today, .dev(4))
        case "dev.glimm.wear": r.open(.today, .dev(5))
        case "dev.glimm.motion": r.open(.today, .dev(6))
        case "dev.share": r.open(.today, .dev(7))
        case "today.buddy": r.open(.today, .buddy)
        case "today.drivers": r.open(.today, .drivers)
        case "today.dose": r.open(.today, .dose)
        case "today.reviews": r.open(.today, .reviews)
        case "you.reminders": r.open(.today, .reminders)
        case "fuel.body": r.open(.fuel, .body)
        case "fuel.trials": r.open(.fuel, .trials)
        case "fuel.trial":
            if let first = env.trials.first { r.open(.fuel, .trial(first.id)) } else { r.open(.fuel, .trials) }
        case "train.lifthistory": r.open(.train, .liftHistory("Back squat"))
        case "sheet.weighin": r.tab = .fuel; r.sheet = .weighIn
        case "sheet.sweat": r.tab = .fuel; r.sheet = .sweatTest
        case "sheet.trial": r.tab = .fuel; r.sheet = .trialSetup("Creatine monohydrate")
        case "today.best":
            env.celebration = LumaBest(lift: "Back squat", kg: 133, previous: 130)
        case "sheet.water": r.sheet = .fuelAdd(.water)
        default: break
        }
    }
}
