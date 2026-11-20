import SwiftUI
import Combine
import LumaCore
import LumaKit

// MARK: - Launch options

/// Development launch arguments (`-lumaScreen today.sleep -lumaScroll 400`), used by the screenshot
/// harness to open a screen directly. Absent in normal use.
public struct LumaLaunch {
    public var screen: String?
    /// Shifts scrolling content up by this many points so a screenshot can show below the fold.
    public static var scrollOffset: CGFloat = 0
    /// The step a multi-step screen opens on.
    public static var page = 0
    /// The field that takes the keyboard as its screen opens, by the name it is asked under ("coach",
    /// or a field's title), so a picture can show a screen being typed in.
    public static var focus: String?
    /// What is already typed in the coach's box when it opens.
    public static var draft: String?

    public init(screen: String? = nil) { self.screen = screen }

    public static func fromArguments() -> LumaLaunch {
        let d = UserDefaults.standard
        scrollOffset = CGFloat(d.double(forKey: "lumaScroll"))
        focus = d.string(forKey: "lumaFocus").flatMap { $0.isEmpty ? nil : $0 }
        draft = d.string(forKey: "lumaDraft").flatMap { $0.isEmpty ? nil : $0 }
        return LumaLaunch(screen: d.string(forKey: "lumaScreen").flatMap { $0.isEmpty ? nil : $0 })
    }
}

// MARK: - Strap and system interfaces

/// The strap's live state, as the interface needs it.
public struct LumaStrap: Equatable {
    public var connected = false
    /// Paired with encryption: history sync, strap haptics and double-tap work.
    public var secure = false
    public var heartRate: Int?
    public var heartRateAt: Date?
    public var battery: Double?
    public var charging = false
    public var worn = true
    public var syncing = false
    public var syncedChunks = 0
    public var lastSync: Date?
    /// The strap holds records newer than anything the phone has read from it.
    public var historyPending = false
    /// The strap has handed over none of its stored history in several attempts. What it streams live is
    /// then the only record there is.
    public var historyEmpty = false
    /// The strap has to be restarted before it will hand over more of its history.
    public var needsRestart = false
    /// Why the last sync ended early, when it did.
    public var syncError: String?
    /// The strap is being asked to stream heart rate at all times, not only while a screen wants it.
    public var continuous = false
    public var name: String?
    public var model: String?
    public var firmware: String?
    /// A plain-language hint when pairing needs the athlete to do something.
    public var hint: String?

    public init() {}

    /// A reading older than this is shown as "last reading", not as live.
    public static let freshFor: TimeInterval = 75

    public func liveHeartRate(now: Date = Date()) -> Int? {
        guard connected, let hr = heartRate, let at = heartRateAt, now.timeIntervalSince(at) <= LumaStrap.freshFor else { return nil }
        return hr
    }

    public var statusText: String {
        if !connected { return "Not connected" }
        if syncing { return "Syncing history" }
        return secure ? "Connected" : "Connected, not paired"
    }

    /// The strap's stored record is still arriving: being read now, or known to hold more than the phone
    /// has. Not so for a strap that has handed over nothing in repeated reads: its reads go on being
    /// tried, and saying "reading last night" each time would promise what does not come.
    public var reading: Bool { connected && !historyEmpty && (syncing || historyPending) }
}

public struct LumaFoundStrap: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var rssi: Int
    public init(id: String, name: String, rssi: Int) { self.id = id; self.name = name; self.rssi = rssi }
}

public struct LumaPairedStrap: Identifiable, Equatable {
    public var id: String
    public var name: String
    public var detail: String
    public var isActive: Bool
    public init(id: String, name: String, detail: String, isActive: Bool) { self.id = id; self.name = name; self.detail = detail; self.isActive = isActive }
}

public enum LumaHealthAccess: Equatable { case unavailable, off, on, denied }

/// The two strap families, which pair differently and so are searched for separately.
public enum LumaStrapGeneration: String, CaseIterable, Sendable {
    case four, fiveOrMG

    var title: String { self == .four ? "WHOOP 4.0" : "WHOOP 5.0 / MG" }
}

/// What Luma can ask the strap and the system to do. Implemented by the app over the strap layer.
@MainActor
public protocol LumaDeviceControl: AnyObject {
    func reconnect()
    func syncNow()
    func startScan(_ generation: LumaStrapGeneration)
    func stopScan()
    func pair(_ strap: LumaFoundStrap, generation: LumaStrapGeneration)
    func makeActive(_ id: String)
    func forget(_ id: String)
    /// A deliberate buzz the athlete asked for (finding the strap, testing it).
    func buzz()
    /// A short buzz that marks a moment inside a session: an interval change, the next race segment.
    func cue()
    /// Ask the strap for its fast heart-rate stream while a live screen is open.
    func setLiveHeartRate(_ on: Bool)
    /// Luma came on screen or left it. While it is on screen the strap is asked to stream heart rate,
    /// whatever the recording setting, so every screen shows a live figure.
    func setOnScreen(_ on: Bool)
    func connectHealth() async
    /// Notifications when the strap's battery runs low.
    func setBatteryAlerts(_ on: Bool)
}

public struct LumaRoutePoint: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    /// Seconds since the session started.
    public var t: Double
    public init(lat: Double, lon: Double, t: Double) { self.lat = lat; self.lon = lon; self.t = t }
}

/// A strap + GPS session in progress. The app implements this over the strap layer's recorder, so
/// heart rate, strain and the route are captured the same way for every kind of session.
@MainActor
public protocol LumaRecorder: AnyObject {
    var isRunning: Bool { get }
    var isPaused: Bool { get }
    /// Seconds of moving time (pauses excluded).
    var elapsed: TimeInterval { get }
    var distanceM: Double { get }
    func start(sport: String, gps: Bool) -> Bool
    func setPaused(_ paused: Bool)
    func route() -> [LumaRoutePoint]
    /// Ends the session and returns what was stored, or nil if it was too short to keep.
    func finish() async -> LWorkout?
    func discard()
    /// Called when the athlete double-taps the strap during a session.
    var onStrapDoubleTap: (() -> Void)? { get set }
}

public protocol LumaSecrets: AnyObject {
    func coachKey() -> String?
    func setCoachKey(_ key: String?)
}

final class MemorySecrets: LumaSecrets {
    private var key: String?
    init(key: String? = nil) { self.key = key }
    func coachKey() -> String? { key }
    func setCoachKey(_ key: String?) { self.key = key }
}

/// Live strap state. Kept apart from `LumaEnv` so a heart-rate tick redraws only the views showing it.
@MainActor
public final class LumaLive: ObservableObject {
    @Published public var strap = LumaStrap()
    @Published public var found: [LumaFoundStrap] = []
    @Published public var paired: [LumaPairedStrap] = []
    @Published public var health: LumaHealthAccess = .off
    @Published public var batteryAlerts = false
    /// What an earlier version of the app had been left doing on its own and this one switched off,
    /// each named for the athlete ("the wake alarm"). Today shows it once.
    @Published public var switchedOff: [String] = []
    public init() {}
}

// MARK: - Navigation

public enum LumaTab: String, CaseIterable, Hashable {
    case today, train, fuel, coach

    var title: String {
        switch self {
        case .today: return "Today"
        case .train: return "Train"
        case .fuel: return "Fuel"
        case .coach: return "Coach"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max.fill"
        case .train: return "calendar"
        case .fuel: return "fork.knife"
        case .coach: return "sparkles"
        }
    }
}

public enum LumaDest: Hashable {
    case sleep, recovery, strain, heart, vitals, stress, trends, insights, load
    case workout(String)
    case raceReadiness, strength, history
    case session(UUID)
    case lift(UUID)
    case supplements, fuelHistory
    case devices, settings, profile, about
    /// Where heart rate reached the phone and what is stored, hour by hour.
    case dataCheck
    /// The copies kept of what the athlete has logged, and going back to one.
    case backups
    /// Luma Doctor: the weekly check of the athlete's numbers against their own usual range.
    case doctor
    /// The companion: why it looks the way it does, its build, and its day ahead.
    case buddy
    /// Supplement trials, and one trial.
    case trials
    case trial(UUID)
    /// How much and how late: caffeine, alcohol, the last meal and bedtime against the next morning.
    case dose
    /// What goes with a better or worse recovery, fitted together.
    case drivers
    /// The weight log, real burn and sweat rate.
    case body
    /// Weekly reviews.
    case reviews
    /// One lift over time.
    case liftHistory(String)
    case reminders
    /// Development only: the widget design sheets.
    case dev(Int)
}

enum LumaSheetDest: Identifiable {
    case go
    case you
    case checkIn(String)
    case fuelAdd(FuelAddMode)
    case plan(PlannedSession?, String)
    case routine
    case coachSetup
    case manualWorkout
    /// Add sessions to the training log from photos; the day they are filed under when no photo says.
    case workoutPhotos(String)
    case weighIn
    case sweatTest
    /// Set up a trial of one supplement.
    case trialSetup(String)
    /// Add an official race, or correct the one with this id.
    case raceEntry(UUID?)

    var id: String {
        switch self {
        case .go: return "go"
        case .you: return "you"
        case .checkIn(let d): return "checkin-\(d)"
        case .fuelAdd(let m): return "fuel-\(m.rawValue)"
        case .plan(let p, let d): return "plan-\(p?.id.uuidString ?? d)"
        case .routine: return "routine"
        case .coachSetup: return "coach-setup"
        case .manualWorkout: return "manual-workout"
        case .workoutPhotos(let d): return "workout-photos-\(d)"
        case .weighIn: return "weigh-in"
        case .sweatTest: return "sweat-test"
        case .trialSetup(let name): return "trial-setup-\(name)"
        case .raceEntry(let id): return "race-entry-\(id?.uuidString ?? "new")"
        }
    }
}

enum FuelAddMode: String { case meal, photo, supplement, water }

/// The two faces of the Train tab: the calendar of what is planned and done, and what it has added up to.
enum TrainView: String { case calendar, progress }

enum LumaCoverDest: Identifiable {
    case run(RunPlan)
    case race(HXSessionKind)
    case lift
    case onboarding

    var id: String {
        switch self {
        case .run: return "run"
        case .race: return "race"
        case .lift: return "lift"
        case .onboarding: return "onboarding"
        }
    }
}

/// What a run is meant to be, chosen before it starts.
struct RunPlan: Equatable {
    /// `session` is any timed, non-GPS workout (a class, a ride on a stationary bike…).
    enum Mode: String, CaseIterable { case free, intervals, treadmill, session }
    var mode: Mode = .free
    var title: String = "Run"
    /// The sport name the session is stored under.
    var sport: String = "Running"
    var targetPaceSPerKm: Double?
    var intervalCount: Int = 6
    var intervalMeters: Double = 1000
    var restSeconds: Double = 90
}

@MainActor
public final class LumaRouter: ObservableObject {
    @Published var tab: LumaTab = .today
    @Published var todayPath: [LumaDest] = []
    @Published var trainPath: [LumaDest] = []
    @Published var fuelPath: [LumaDest] = []
    @Published var coachPath: [LumaDest] = []
    @Published var sheet: LumaSheetDest?
    @Published var cover: LumaCoverDest?
    @Published var trainView: TrainView = .calendar
    /// A question handed to the coach from elsewhere in the app.
    @Published var coachPrompt: String?

    public init() {}

    /// `source` names the tile that was tapped, so the screen can open out of it (`lumaZoomSource`).
    func push(_ dest: LumaDest, from source: String? = nil) {
        LumaZoom.pending = source
        switch tab {
        case .today: todayPath.append(dest)
        case .train: trainPath.append(dest)
        case .fuel: fuelPath.append(dest)
        case .coach: coachPath.append(dest)
        }
    }

    func open(_ tab: LumaTab, _ dest: LumaDest? = nil) {
        self.tab = tab
        if let dest { push(dest) }
    }

    public func askCoach(_ prompt: String) {
        sheet = nil
        coachPrompt = prompt
        tab = .coach
    }

    /// Opens what a widget, the Lock Screen card or a shortcut points at.
    public func open(link: String) {
        sheet = nil
        switch link {
        case "fuel": tab = .fuel
        case "train": tab = .train
        case "coach": tab = .coach
        case "heart": show(.heart)
        case "stress": show(.stress)
        case "strap": show(.devices)
        case "buddy": show(.buddy)
        case "body": show(.body)
        case "reviews": show(.reviews)
        case "go":
            tab = .today
            sheet = .go
        case "checkin":
            tab = .today
            sheet = .checkIn(LumaAnalysis.todayKey())
        default: tab = .today
        }
    }

    private func show(_ dest: LumaDest) {
        LumaZoom.pending = nil
        tab = .today
        if todayPath.last != dest { todayPath = [dest] }
    }
}

// MARK: - Disk

/// The athlete's own records: small JSON files under Application Support, kept by a `LumaVault`, which
/// tells a file it could not read from one that is not there, keeps daily copies, and will not save
/// over a store it has not read. A vault with no directory keeps nothing (the gallery).
struct LumaDisk {
    let vault: LumaVault
    var directory: URL? { vault.directory }

    static func standard() -> LumaDisk {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let vault = LumaVault(directory: base?.appendingPathComponent("HYROXLab", isDirectory: true))
        #if canImport(UIKit)
        // Asked on the main thread, where every store is read.
        vault.sealed = {
            guard Thread.isMainThread else { return false }
            return MainActor.assumeIsolated { !UIApplication.shared.isProtectedDataAvailable }
        }
        #endif
        return LumaDisk(vault: vault)
    }

    static func memory() -> LumaDisk { LumaDisk(vault: LumaVault(directory: nil)) }

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? { vault.load(type, name) }
    func save<T: Encodable>(_ value: T, _ name: String) { vault.save(value, name) }
    func remove(_ name: String) { vault.remove(name) }
    func list(prefix: String) -> [String] { vault.list(prefix: prefix) }
    func url(_ name: String) -> URL? { vault.url(name) }
}

// MARK: - Environment

/// The app's state: strap data and what Luma derives from it, plus everything the athlete enters.
@MainActor
public final class LumaEnv: ObservableObject {
    public let source: LumaDataSource
    public let live: LumaLive
    public let router = LumaRouter()
    public weak var device: LumaDeviceControl?
    public var recorder: LumaRecorder?
    public let secrets: LumaSecrets
    let disk: LumaDisk
    public let isDemo: Bool

    // Strap data
    @Published public private(set) var days: [LDay] = []
    @Published public private(set) var sleeps: [LSleep] = []
    @Published public private(set) var workouts: [LWorkout] = []
    @Published public private(set) var analysis: LumaAnalysis = .empty
    @Published public private(set) var loaded = false
    /// False while any of the athlete's own records could not be read from disk, which is what
    /// happens when the app is started while the phone is locked. What is in memory is then not
    /// theirs: it is not shown, not saved, and not sent to the widgets, and the stores are read again
    /// as soon as they can be (`retryStores`).
    @Published public private(set) var storesReady = true
    /// True while stores are being put in place from disk.
    private var adopting = false
    /// Sessions the strap saw and nobody recorded, waiting to be kept or dismissed. Newest first.
    @Published public private(set) var suggestions: [LSuggestedSession] = []
    /// Everything the last search of the strap record found, before Luma's own rules are applied.
    private var detectedStretches: [LSuggestedSession] = []
    private var stretchesSearchedAt: Date?
    private var dismissedStretches: Set<String>
    /// Where the heart-rate record of the last day and a half has readings. A night is only as complete
    /// as this record behind it (`RecordCheck`).
    @Published public private(set) var record: [RecordStretch] = []
    /// When `record` was read. A night is judged as of this moment, not the wall clock: a record read a
    /// while ago says nothing about the time since.
    private var recordAsOf: Double?
    /// How far the recovery baseline has got; nil once it is learned.
    public private(set) var calibration: LCalibration?
    /// Nights found only partly recorded, kept so they go on being left out of debt, averages and
    /// baselines after the record that showed it is no longer looked at.
    public private(set) var nightMarks: [NightMark]
    private var bag: Set<AnyCancellable> = []
    /// A made-up situation for the gallery ("partial": a night whose record stops early).
    var demoScenario: String?
    /// Whether the app is on screen. The root view keeps this current; it is false until a scene
    /// appears, so nothing that is only worth doing for someone looking runs during a background wake.
    var isInFront = false {
        didSet { if isInFront != oldValue { device?.setOnScreen(isInFront) } }
    }

    // Athlete's own records
    // Each saves itself when it changes, except while the stores are being put in place from disk
    // (`adopting`): what was just read is not written back, and nothing is rebuilt until all are in.
    @Published public var profile: LProfile { didSet { if !adopting, profile != oldValue { profileChanged() } } }
    @Published var routine: [RoutineSlot] { didSet { if !adopting { disk.save(routine, "routine.json") } } }
    @Published var planned: [PlannedSession] { didSet { if !adopting { disk.save(planned, "planned.json") } } }
    @Published var fuel: [FuelEntry] { didSet { if !adopting { disk.save(fuel, "fuel.json"); refreshProgress() } } }
    @Published var supplements: [SupplementPlan] { didSet { if !adopting { disk.save(supplements, "supplements.json"); refreshProgress() } } }
    @Published var checkIns: [CheckIn] { didSet { if !adopting { disk.save(checkIns, "checkins.json") } } }
    @Published var lifts: [LiftSession] { didSet { if !adopting { disk.save(lifts, "lifts.json"); refreshProgress() } } }
    /// What the training, food and supplement logs add up to: lifts, muscles, strong and weak points.
    /// Rebuilt whenever a log it reads changes, so every screen that shows a figure from it shows the same one.
    @Published private(set) var progress: TrainingProgress = .empty
    @Published private(set) var sessions: [HXSession] = []
    @Published private(set) var benchmarks = Benchmarks()
    @Published var runPBs: [PersonalBest] { didSet { if !adopting { disk.save(runPBs, "runpbs.json") } } }

    // The newer records: supplement trials, weigh-ins, sweat tests, weekly reviews, and small settings.
    @Published var trials: [SupplementTrial] { didSet { if !adopting { disk.save(trials, "trials.json"); refreshNext() } } }
    @Published var weights: [WeightEntry] { didSet { if !adopting { disk.save(weights, "weights.json"); weightsChanged() } } }
    @Published var sweatTests: [SweatTest] { didSet { if !adopting { disk.save(sweatTests, "sweat-tests.json"); refreshNext() } } }
    @Published var reviews: [WeeklyReview] { didSet { if !adopting { disk.save(reviews, "reviews.json") } } }
    @Published var extras: LumaExtras { didSet { if !adopting, extras != oldValue { disk.save(extras, "extras.json"); refreshNext(); onGlanceChange?() } } }
    /// Luma Doctor's log: the weekly checks and any asked for by hand, newest first.
    @Published var doctorReports: [DoctorReport] { didSet { if !adopting, doctorReports != oldValue { disk.save(doctorReports, "doctor.json") } } }
    /// What Glimm keeps: the taste it has learnt, what it was asked to remember, what it has on today.
    @Published var glimm: GlimmState {
        didSet {
            guard glimm != oldValue else { return }
            // Only a change to what it wears reaches the widgets: a line it said changes no clothes.
            let dressed = !glimm.dressesAs(oldValue)
            if dressed { glimmStage.outfits = [:] }
            if !adopting {
                disk.save(glimm, "glimm.json")
                if dressed { onGlanceChange?() }
            }
        }
    }
    /// What Glimm is saying and doing just now. Nothing in it is kept.
    let glimmStage = GlimmStage()
    /// The written read of a check is being fetched.
    @Published private(set) var doctorWriting = false
    private var doctorReadTriedAt: Date?
    /// What those records and the logs add up to. Rebuilt with `progress`, so every screen that shows a
    /// figure from it shows the same one.
    @Published var next = LumaNext()
    /// A new best to show once, over whatever screen is up.
    @Published var celebration: LumaBest?
    /// The weekly review being written, or why it could not be.
    @Published var reviewWriting = false
    @Published var reviewError: String?

    /// Called when the profile changes so the app can mirror age, mass and max HR to the strap layer.
    public var onProfileChange: ((LProfile) -> Void)?
    /// Called after anything the widgets show has changed.
    public var onGlanceChange: (() -> Void)?
    /// Asks iOS for leave to show notifications; true when it is given. Set by the app.
    public var requestNotifications: (() async -> Bool)?
    /// Shows a notification now: an id, a title and a line. Set by the app.
    public var postNotice: ((String, String, String) -> Void)?

    private var reloadTask: Task<Void, Never>?
    private var profileWork: Task<Void, Never>?
    private var madeCoach: CoachEngine?
    /// Made when first asked for, so a start in the background does not build it.
    var coach: CoachEngine {
        if let made = madeCoach { return made }
        let made = CoachEngine(env: self)
        madeCoach = made
        return made
    }

    public init(source: LumaDataSource, live: LumaLive, secrets: LumaSecrets, persistent: Bool = true) {
        self.source = source
        self.live = live
        self.secrets = secrets
        self.isDemo = !persistent
        let disk = persistent ? LumaDisk.standard() : LumaDisk.memory()
        self.disk = disk
        profile = disk.load(LProfile.self, "profile.json") ?? LProfile()
        routine = disk.load([RoutineSlot].self, "routine.json") ?? []
        planned = disk.load([PlannedSession].self, "planned.json") ?? []
        fuel = disk.load([FuelEntry].self, "fuel.json") ?? []
        supplements = disk.load([SupplementPlan].self, "supplements.json") ?? []
        checkIns = disk.load([CheckIn].self, "checkins.json") ?? []
        lifts = disk.load([LiftSession].self, "lifts.json") ?? []
        runPBs = disk.load([PersonalBest].self, "runpbs.json") ?? []
        trials = disk.load([SupplementTrial].self, "trials.json") ?? []
        weights = disk.load([WeightEntry].self, "weights.json") ?? []
        sweatTests = disk.load([SweatTest].self, "sweat-tests.json") ?? []
        reviews = disk.load([WeeklyReview].self, "reviews.json") ?? []
        extras = disk.load(LumaExtras.self, "extras.json") ?? LumaExtras()
        doctorReports = disk.load([DoctorReport].self, "doctor.json") ?? []
        glimm = disk.load(GlimmState.self, "glimm.json") ?? GlimmState()
        benchmarks = disk.load(Benchmarks.self, "benchmarks.json") ?? Benchmarks()
        dismissedStretches = SessionSuggestions.prune(Set(disk.load([String].self, "stretches-dismissed.json") ?? []),
                                                      now: Date().timeIntervalSince1970)
        nightMarks = disk.load([NightMark].self, "night-marks.json") ?? []
        progress = TrainingProgress.build(lifts: lifts, workouts: [], fuel: fuel, supplements: supplements, profile: profile,
                                          today: LumaAnalysis.todayKey())
        sessions = disk.list(prefix: "session-").compactMap { disk.load(HXSession.self, $0) }.sorted { $0.startedAt > $1.startedAt }
        storesReady = disk.vault.isReady
        if storesReady {
            disk.vault.markOpened()
        } else {
            disk.vault.note("started with \(disk.vault.blocked.count) records out of reach\(disk.vault.sealed() ? " (the phone was locked)" : "")")
        }
        // Whether the strap's record is still arriving decides what Luma says about the night, so the
        // analysis is rebuilt the moment that changes, not at the next reload.
        live.$strap.map { $0.reading }.removeDuplicates().dropFirst()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.refreshAnalysis() } }
            .store(in: &bag)
    }

    /// The gallery and previews: synthetic strap data and filled-in records, nothing persisted.
    public static func demo(sparse: Bool = false, scenario: String? = nil) -> LumaEnv {
        let source = LumaDemoSource(dayCount: sparse ? 6 : 120)
        let live = LumaLive()
        var strap = LumaStrap()
        strap.connected = true; strap.secure = true; strap.heartRate = 58; strap.heartRateAt = Date()
        strap.battery = 64; strap.lastSync = Date().addingTimeInterval(-540); strap.name = "WHOOP MG"; strap.model = "MG"
        strap.firmware = "50.40.1.0"; strap.continuous = true
        live.strap = strap
        live.paired = [LumaPairedStrap(id: "demo", name: "WHOOP MG", detail: "Active", isActive: true)]
        live.health = .on
        let env = LumaEnv(source: source, live: live, secrets: MemorySecrets(key: sparse ? nil : "demo"), persistent: false)
        env.demoScenario = scenario
        // The gallery's pictures of the screen shown while the records cannot be opened.
        if scenario == "locked" || scenario == "stuck" { env.storesReady = false }
        env.profile = LumaDemoContent.profile()
        if !sparse {
            env.routine = LumaDemoContent.routine()
            env.planned = LumaDemoContent.planned(today: LumaAnalysis.todayKey())
            env.fuel = LumaDemoContent.fuel()
            env.supplements = LumaDemoContent.supplements()
            env.checkIns = source.checkIns
            env.lifts = LumaDemoContent.lifts()
            env.runPBs = [PersonalBest(distanceM: 1000, seconds: 252), PersonalBest(distanceM: 1609, seconds: 421),
                          PersonalBest(distanceM: 5000, seconds: 1480), PersonalBest(distanceM: 10000, seconds: 3105)]
            env.upsert(LumaDemoContent.simulation(daysAgo: 37, runPace: 334, stationFactor: 1.09))
            env.upsert(LumaDemoContent.simulation(daysAgo: 9, runPace: 319))
            // An official race from before both simulations, so the race book has one to show.
            env.saveRace(RaceEntrySheet.demoEntry(format: env.profile.format, sex: env.profile.sex))
            LumaDemoNext.stage(env, source: source)
        }
        return env
    }

    // MARK: The athlete's own records

    /// The athlete's details changed. They are saved at once. Telling the strap layer and working
    /// everything out again waits until the changes stop coming: a stepper held down changes them
    /// several times a second, and doing all of that on each step made the stepper miss taps.
    private func profileChanged() {
        disk.save(profile, "profile.json")
        profileWork?.cancel()
        profileWork = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.onProfileChange?(self.profile)
            self.refreshAnalysis()
        }
    }

    /// Reads every store from disk again and puts it in place: when they could not be read at launch
    /// and now can, and after a day has been restored from its copies. Nothing is saved by doing so.
    public func readStores() {
        guard !isDemo else { return }
        disk.vault.protect()
        disk.vault.forgetBlocked()
        adopting = true
        profile = disk.load(LProfile.self, "profile.json") ?? LProfile()
        routine = disk.load([RoutineSlot].self, "routine.json") ?? []
        planned = disk.load([PlannedSession].self, "planned.json") ?? []
        fuel = disk.load([FuelEntry].self, "fuel.json") ?? []
        supplements = disk.load([SupplementPlan].self, "supplements.json") ?? []
        checkIns = disk.load([CheckIn].self, "checkins.json") ?? []
        lifts = disk.load([LiftSession].self, "lifts.json") ?? []
        runPBs = disk.load([PersonalBest].self, "runpbs.json") ?? []
        trials = disk.load([SupplementTrial].self, "trials.json") ?? []
        weights = disk.load([WeightEntry].self, "weights.json") ?? []
        sweatTests = disk.load([SweatTest].self, "sweat-tests.json") ?? []
        reviews = disk.load([WeeklyReview].self, "reviews.json") ?? []
        extras = disk.load(LumaExtras.self, "extras.json") ?? LumaExtras()
        doctorReports = disk.load([DoctorReport].self, "doctor.json") ?? []
        glimm = disk.load(GlimmState.self, "glimm.json") ?? GlimmState()
        benchmarks = disk.load(Benchmarks.self, "benchmarks.json") ?? Benchmarks()
        dismissedStretches = SessionSuggestions.prune(Set(disk.load([String].self, "stretches-dismissed.json") ?? []),
                                                      now: Date().timeIntervalSince1970)
        nightMarks = disk.load([NightMark].self, "night-marks.json") ?? []
        sessions = disk.list(prefix: "session-").compactMap { disk.load(HXSession.self, $0) }.sorted { $0.startedAt > $1.startedAt }
        adopting = false
        let wasReady = storesReady
        storesReady = disk.vault.isReady
        guard storesReady else { return }
        if !wasReady { disk.vault.note("records read") }
        disk.vault.markOpened()
        madeCoach?.readStored()
        // The strap layer is only told about details the athlete has entered, never the blank ones.
        if profile.isSetUp { onProfileChange?(profile) }
        // Everything worked out from the records is worked out again, and the strap data read with them.
        refreshAnalysis()
        reload()
    }

    /// Reads the stores again if they could not be read before. Costs nothing when they could.
    public func retryStores() {
        if !storesReady { readStores() }
    }

    /// Whether the phone says its files are sealed right now: it is locked, or has not been unlocked
    /// since it was switched on.
    var storesSealed: Bool { disk.vault.sealed() }

    /// The records that could not be opened, in the app's words for them, each once.
    var unreadStores: [String] {
        if isDemo { return ["Food, water and supplements taken", "Strength sessions"] }
        var seen: Set<String> = []
        return disk.vault.blocked.map { LumaVault.title(for: $0) }.filter { seen.insert($0).inserted }
    }

    /// The way out when records will not open and the phone is not locked: those files are moved
    /// aside (not deleted), the last copy kept of each takes its place, and the stores are read again.
    func startWithoutUnreadStores() {
        guard !isDemo else { return }
        disk.vault.setAsideBlocked()
        readStores()
    }

    /// What is known about each store in this run and what the vault has logged, as readings for the
    /// data check and its report.
    var storeFacts: [LFact] {
        let section = "Your records"
        var out: [LFact] = [LFact(section, "All read", storesReady ? "yes" : "no")]
        let notes = disk.vault.notes()
        for note in notes where !note.name.hasPrefix("session-") && !note.name.hasPrefix("run-") {
            out.append(LFact(section, LumaVault.title(for: note.name), note.words))
        }
        let races = notes.filter { $0.name.hasPrefix("session-") }
        if !races.isEmpty {
            let read = races.filter { $0.read == .loaded || $0.read == nil }.count
            out.append(LFact(section, "Race sessions", read == races.count ? "\(read) read" : "\(read) read, \(races.count - read) not"))
        }
        let sets = disk.vault.backupList()
        let days = sets.filter { $0.kind == .day }
        out.append(LFact(section, "Days with a copy", days.isEmpty ? "none yet" : "\(days.count), back to \(days.last?.name ?? "")"))
        let log = "Record log"
        let events = disk.vault.events()
        if events.isEmpty { out.append(LFact(log, "Events", "none")) }
        for (i, event) in events.suffix(12).enumerated() { out.append(LFact(log, "Event \(i + 1)", event)) }
        return out
    }

    /// The copies that can be gone back to, newest first.
    var backups: [VaultBackup] {
        guard isDemo else { return disk.vault.backupList() }
        let today = LumaAnalysis.todayKey()
        let names = ["checkins.json", "extras.json", "fuel.json", "lifts.json", "planned.json", "profile.json", "routine.json", "supplements.json", "weights.json"]
        let days = (0..<6).map { VaultBackup(name: LDate.adding(-$0, to: today), files: names, bytes: 48_200 - $0 * 1_900) }
        return days + [VaultBackup(name: "before-restore-\(LDate.adding(-2, to: today))-214503", files: names, bytes: 47_100),
                       VaultBackup(name: "before-change-\(LDate.adding(-4, to: today))-073012", files: ["fuel.json"], bytes: 21_400)]
    }

    /// Puts every store back as it was in one set of copies, and reads them. What was there is kept
    /// as a set of its own first, so this can be undone.
    @discardableResult
    func restore(_ backup: VaultBackup) -> Bool {
        guard !isDemo else { return true }
        let done = disk.vault.restore(backup.name)
        readStores()
        return done
    }

    // MARK: Luma Doctor

    /// The newest check in the log.
    var doctorLatest: DoctorReport? { doctorReports.first }

    /// The check of the seven days ending `weekEnd`, from what Luma holds now. Nights only part
    /// recorded are left out, as everywhere else, and the load is the Load screen's own.
    private func doctorCheck(weekEnd: String, scheduled: Bool, now: Date) -> DoctorReport {
        let partial = Set(nightMarks.map { $0.day })
        let whole: [LDay] = partial.isEmpty ? days : days.map { partial.contains($0.day) ? $0.withoutNight : $0 }
        let loads = Dictionary(analysis.load.days.map { ($0.day, $0.load) }, uniquingKeysWith: { first, _ in first })
        return Doctor.check(days: whole, sleeps: sleeps, loads: loads, partial: partial, weekEnd: weekEnd, scheduled: scheduled, now: now)
    }

    private func keepDoctor(_ report: DoctorReport) {
        var all = doctorReports.filter { $0.id != report.id }
        all.append(report)
        all.sort { $0.ranAt > $1.ranAt }
        doctorReports = Array(all.prefix(Doctor.kept))
    }

    private func changeDoctor(_ id: String, _ change: (inout DoctorReport) -> Void) {
        guard let i = doctorReports.firstIndex(where: { $0.id == id }) else { return }
        var all = doctorReports
        change(&all[i])
        doctorReports = all
    }

    /// Runs the weekly check when one is due: from Sunday 00:00, for the week that ended the day
    /// before, at the first moment after that the strap data has been read. Not while the athlete's
    /// records are unread, and not for a week Luma holds nothing of.
    func runDoctorIfDue(now: Date = Date()) {
        guard !isDemo, storesReady, loaded else { return }
        if let week = DoctorSchedule.due(now: now, reports: doctorReports),
           days.contains(where: { $0.day <= week && $0.day >= LDate.adding(-6, to: week) }) {
            let report = doctorCheck(weekEnd: week, scheduled: true, now: now)
            keepDoctor(report)
            if extras.doctorNotify {
                let line = report.headline
                let said = line.prefix(1).lowercased() + String(line.dropFirst())
                postNotice?("luma.doctor." + report.id, "Luma Doctor", "This week's check: \(said).")
            }
            writeDoctorRead(for: report.id)
            return
        }
        // A read that could not be fetched (no network, or the key out of reach while the phone was
        // locked) is asked for again, at most every half hour.
        if let latest = doctorLatest, latest.scheduled, latest.read == nil,
           doctorReadTriedAt.map({ now.timeIntervalSince($0) > 1800 }) ?? true {
            writeDoctorRead(for: latest.id)
        }
    }

    /// A check asked for by hand: the seven days ending today.
    func runDoctorNow() {
        guard !isDemo else { return }
        let report = doctorCheck(weekEnd: today, scheduled: false, now: Date())
        keepDoctor(report)
        writeDoctorRead(for: report.id, asked: true)
    }

    /// Whether a written read can be had: a key is connected and health data may be shared with the model.
    var doctorCanWrite: Bool { coach.hasKey && profile.shareHealthWithCoach }

    /// Has the written read of one check fetched. It is written by the most capable model the key
    /// reaches, whatever the coach is set to (`CoachEngine.doctorRead`), and only with leave to share
    /// health data: the findings are health data.
    func writeDoctorRead(for id: String, asked: Bool = false) {
        guard !isDemo, !doctorWriting, doctorCanWrite, let report = doctorReports.first(where: { $0.id == id }) else { return }
        guard asked || report.read == nil else { return }
        doctorReadTriedAt = Date()
        doctorWriting = true
        let partial = Set(nightMarks.map { $0.day })
        let whole: [LDay] = partial.isEmpty ? days : days.map { partial.contains($0.day) ? $0.withoutNight : $0 }
        Task { [weak self] in
            guard let self else { return }
            defer { self.doctorWriting = false }
            do {
                let written = try await self.coach.doctorRead(report, days: whole)
                self.changeDoctor(id) { $0.read = written.text; $0.readModel = written.model; $0.readAt = Date(); $0.readNote = nil }
            } catch {
                let said = (error as? LocalizedError)?.errorDescription ?? "The written read could not be fetched."
                self.changeDoctor(id) { $0.readNote = said }
            }
        }
    }

    /// The gallery's log: the last four weeks of the demo data, checked by the same rules, each with
    /// a read worded from its own findings (the gallery has no model to ask).
    private func stageDemoDoctor() {
        guard doctorReports.isEmpty, !days.isEmpty else { return }
        let end = DoctorSchedule.weekEnd(asOf: Date())
        var staged: [DoctorReport] = []
        for back in 0..<4 {
            let week = LDate.adding(-7 * back, to: end)
            let ran = (LDate.startOfDay(LDate.adding(1, to: week)) ?? Date()).addingTimeInterval(140)
            var report = doctorCheck(weekEnd: week, scheduled: true, now: ran)
            let notable = report.outside + report.watching
            if notable.isEmpty {
                report.read = "A steady week. Everything that could be checked sat inside your own usual range. Nothing here asks for a change: keep the bedtime and the load as they are, and next week's check will say if anything moves."
            } else {
                let seen = notable.prefix(2).map { "\($0.title): \($0.line)" }.joined(separator: " ")
                report.read = "\(report.headline). \(seen) One week like this is usually training, sleep or a late night showing in the numbers. Keep the next few days easy and see whether it settles. If it carries into next week, or you feel unwell, it is sensible to see a doctor."
            }
            report.readModel = "Claude Fable 5.2"
            report.readAt = ran.addingTimeInterval(45)
            staged.append(report)
        }
        doctorReports = staged
    }

    // MARK: Strap data

    public var today: String { analysis.today }

    /// Reloads strap data and recomputes the analysis. Safe to call often; calls coalesce.
    public func reload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            let days = await self.source.loadDays()
            let sleeps = await self.source.loadSleeps(days: 400)
            let workouts = await self.source.loadWorkouts(days: 400)
            let now = Date().timeIntervalSince1970
            // One reading a minute is enough to see where the record has holes.
            let minutes = await self.source.heartRate(from: now - 36 * 3600, to: now, bucketSeconds: 60)
            let calibration = await self.source.calibration()
            let marks = await self.checkedMarks(now: now)
            guard !Task.isCancelled else { return }
            self.days = days
            self.sleeps = sleeps
            self.workouts = workouts
            self.record = RecordCheck.stretches(readingsAt: minutes.map { $0.t }, spacing: 60)
            self.recordAsOf = now
            self.calibration = calibration
            self.keep(marks)
            if self.demoScenario == "partial" { self.stagePartialNight(now: now) }
            self.loaded = true
            self.refreshPlan()
            self.refreshAnalysis()
            if self.isDemo {
                self.coach.seedDemo()
                self.stageDemoDoctor()
                self.stageDemoGlimm()
            }
            // The weekly check is due from Sunday 00:00 and runs at the first read of the strap data after it.
            self.runDoctorIfDue()
            self.glimmKeepUp()
            await self.refreshSuggestions()
        }
    }

    /// Looks for sessions the strap saw and nobody recorded. The search reads days of raw heart rate, so
    /// it runs at most once every three minutes and only while the app is in front, never during a sync
    /// in the background. In between, the last result is checked again against what is stored now, so a
    /// stretch disappears as soon as a session covers it.
    private func refreshSuggestions() async {
        let now = Date()
        if isInFront, stretchesSearchedAt.map({ now.timeIntervalSince($0) >= 180 }) ?? true {
            stretchesSearchedAt = now
            detectedStretches = await source.suggestedSessions(days: 3)
        }
        suggestions = SessionSuggestions.open(detectedStretches, workouts: workouts, dismissed: dismissedStretches,
                                              maxHR: profile.resolvedMaxHR(), now: Date().timeIntervalSince1970)
    }

    func refreshAnalysis() {
        let today = LumaAnalysis.todayKey()
        // The gallery's ordinary data is taken as it stands, so its pictures do not depend on the hour
        // they are taken at; only a staged situation is judged against a record.
        let judged: [RecordStretch] = (isDemo && demoScenario == nil) ? [] : record
        let built = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: workouts, profile: profile, planned: planned,
                                       checkIns: checkIns, personalBests: runPBs, fuel: fuel, supplements: supplements,
                                       record: judged, recordAsOf: recordAsOf,
                                       reading: live.strap.reading, calibration: calibration,
                                       marks: nightMarks, today: today)
        analysis = built
        refreshProgress()
        // Nothing is concluded about tonight's mark before the strap data has been read once.
        if loaded { mark(built.night, on: today) }
        onGlanceChange?()
    }

    func refreshProgress() {
        progress = TrainingProgress.build(lifts: lifts, workouts: workouts, fuel: fuel, supplements: supplements, profile: profile,
                                          today: LumaAnalysis.todayKey())
        refreshNext()
    }

    /// Records today's verdict: a night found cut off is marked, one found whole is unmarked.
    private func mark(_ night: NightRecord, on day: String) {
        var marks = nightMarks
        switch night {
        case .cutOff(let at, let resumes):
            marks.removeAll { $0.day == day }
            marks.append(NightMark(day: day, at: at, resumes: resumes))
        case .complete, .none:
            marks.removeAll { $0.day == day }
        case .stillGoing, .unjudged:
            // Not settled, or nothing to judge by: what was concluded before stands.
            break
        }
        keep(marks)
    }

    private func keep(_ marks: [NightMark]) {
        let sorted = marks.sorted { $0.day < $1.day }
        guard sorted != nightMarks else { return }
        nightMarks = sorted
        disk.save(sorted, "night-marks.json")
    }

    /// The marks, with last week's checked again against the record: a hole fills when the strap hands
    /// over its stored record later, and that night is then whole. Today's is settled by the analysis.
    private func checkedMarks(now: Double) async -> [NightMark] {
        let today = LumaAnalysis.todayKey()
        var kept: [NightMark] = []
        for mark in nightMarks {
            // Older than a year: no longer feeds anything.
            if now - mark.at > 400 * 86_400 { continue }
            if mark.day == today || now - mark.at > 7 * 86_400 { kept.append(mark); continue }
            let until: Double = mark.resumes ?? (mark.at + RecordCheck.holeSeconds)
            let points = await source.heartRate(from: mark.at - 600, to: until + 600, bucketSeconds: 60)
            let found = RecordCheck.stretches(readingsAt: points.map { $0.t }, spacing: 60)
            if RecordCheck.stillMissing(mark, stretches: found) { kept.append(mark) }
        }
        return kept
    }

    /// The one thing about the state of the data worth saying now. Resolved here, once, for every screen.
    var dataNotice: DataNotice? {
        let s = live.strap
        return DataNotice.resolve(connected: s.connected, secure: s.secure, syncing: s.syncing, parts: s.syncedChunks,
                                  pending: s.historyPending, historyEmpty: s.historyEmpty, continuous: s.continuous,
                                  needsRestart: s.needsRestart, syncError: s.syncError,
                                  lastSync: s.lastSync?.timeIntervalSince1970, night: analysis.night)
    }

    /// The gallery's "partial" situation, the morning it was built from: asleep at 01:00, and the phone
    /// holds the strap's readings only up to 02:00 and for the last ten minutes, on the second night of
    /// four the recovery baseline needs.
    private func stagePartialNight(now: Double) {
        let today = LumaAnalysis.todayKey()
        guard let midnight = LDate.startOfDay(today)?.timeIntervalSince1970 else { return }
        let bed = midnight + 3600, stop = midnight + 7200
        if let i = days.lastIndex(where: { $0.day == today }) {
            days[i].recovery = nil; days[i].strain = nil; days[i].sleepMin = 60; days[i].steps = nil; days[i].activeKcal = nil
            days[i].deepMin = 12; days[i].remMin = 6; days[i].lightMin = 42; days[i].restingHR = 70; days[i].hrv = 45
            days[i].sleepScore = nil; days[i].skinTempDev = nil
        }
        sleeps.removeAll { $0.day == today }
        sleeps.append(LSleep(start: bed, end: stop, day: today, restingHR: 70, hrv: 45,
                             stages: [LStage(start: bed, end: bed + 2520, kind: .light), LStage(start: bed + 2520, end: bed + 3240, kind: .deep),
                                      LStage(start: bed + 3240, end: stop, kind: .rem)]))
        sleeps.sort { $0.start < $1.start }
        record = [RecordStretch(start: midnight + 600, end: stop), RecordStretch(start: now - 600, end: now)]
        // The charts read the same record, so they show the same hole.
        (source as? LumaDemoSource)?.recorded = record
        calibration = LCalibration(have: 2, need: 4)
        // This strap hands over nothing stored, so the hole is there to stay.
        live.strap.historyEmpty = true
    }

    // MARK: Record

    /// Where the record on hand ends; nil when there is none.
    var recordEnd: Double? { record.last?.end }
    /// When the record on hand was read.
    var recordReadAt: Double? { recordAsOf }

    /// How much of a night is in the record: today's from the analysis, an earlier one from its mark.
    func nightRecord(on day: String) -> NightRecord {
        if day == analysis.today { return analysis.night }
        if let mark = nightMarks.first(where: { $0.day == day }) { return .cutOff(at: mark.at, resumes: mark.resumes) }
        return .complete
    }

    /// Keeps four weeks of routine sessions on the calendar.
    func refreshPlan() {
        let today = LumaAnalysis.todayKey()
        let pruned = Schedule.pruneRoutine(planned, routine: routine, from: today)
        let next = Schedule.materialize(routine: routine, existing: pruned, from: today, days: 28)
        if next != planned { planned = next }
    }

    public func day(_ key: String) -> LDay? { days.last { $0.day == key } }

    func series(_ metric: LMetric, count: Int) -> (keys: [String], values: [Double?]) {
        LumaAnalysis.series(metric, days: days, ending: today, count: count)
    }

    // MARK: Schedule

    func scheduleDays(_ keys: [String]) -> [ScheduleDay] {
        Schedule.days(keys, planned: planned, workouts: workouts, logs: lifts)
    }

    func upsert(_ p: PlannedSession) {
        if let i = planned.firstIndex(where: { $0.id == p.id }) { planned[i] = p } else { planned.append(p) }
        refreshAnalysis()
    }

    func remove(_ p: PlannedSession) {
        guard let i = planned.firstIndex(where: { $0.id == p.id }) else { return }
        // Routine entries leave a tombstone so they are not re-created; others are deleted.
        if planned[i].slotID != nil { planned[i].status = .removed } else { planned.remove(at: i) }
        refreshAnalysis()
    }

    func setRoutine(_ slots: [RoutineSlot]) {
        routine = slots
        refreshPlan()
        refreshAnalysis()
    }

    // MARK: Fuel

    func fuelEntries(on day: String) -> [FuelEntry] { fuel.filter { $0.day == day }.sorted { $0.at < $1.at } }
    func fuelTotals(on day: String) -> FuelTotals { FuelTotals.of(fuel.filter { $0.day == day }) }

    func fuelTargets(on day: String) -> FuelTargets {
        let ps = planned.filter { $0.day == day }
        let strain = self.day(day)?.strain.map(LScale.strain21)
        let minutes = ps.filter { $0.status != .removed && $0.kind != .rest }.reduce(0.0) { $0 + Double($1.durationMin) }
        return FuelPlanner.targets(profile: profile, dayClass: FuelPlanner.dayClass(planned: ps, strain21: strain), trainingMinutes: max(45, minutes),
                                   sweatMlPerHour: next.sweatRate ?? SweatModel.standardMlPerHour)
    }

    func log(_ entry: FuelEntry) {
        if let i = fuel.firstIndex(where: { $0.id == entry.id }) { fuel[i] = entry } else { fuel.append(entry) }
        onGlanceChange?()
    }

    func delete(_ entry: FuelEntry) {
        fuel.removeAll { $0.id == entry.id }
        for name in entry.photos { disk.remove(name) }
        onGlanceChange?()
    }

    func logWater(_ ml: Double, at: Date = Date()) {
        log(FuelEntry(at: at, kind: .water, title: "Water", waterMl: ml, source: .quick))
    }

    func logSupplement(_ dose: SupplementDose, at: Date = Date(), source: FuelSource = .quick) {
        log(FuelEntry(at: at, kind: .supplement, title: dose.name, supplement: dose, source: source))
    }

    func supplementTaken(_ plan: SupplementPlan, on day: String) -> FuelEntry? {
        fuel.first { $0.day == day && $0.kind == .supplement && $0.title == plan.dose.name }
    }

    /// Stores a photo beside the log and returns its file name.
    func savePhoto(_ data: Data) -> String {
        let name = "photo-\(UUID().uuidString).jpg"
        disk.vault.write(data, name)
        return name
    }

    func photoData(_ name: String) -> Data? { disk.url(name).flatMap { try? Data(contentsOf: $0) } }

    // MARK: Check-ins

    func checkIn(on day: String) -> CheckIn? { checkIns.first { $0.day == day } }

    func save(_ c: CheckIn) {
        if let i = checkIns.firstIndex(where: { $0.day == c.day }) { checkIns[i] = c } else { checkIns.append(c) }
    }

    // MARK: Strength

    func save(_ s: LiftSession) {
        let before = progress.lifts
        if let i = lifts.firstIndex(where: { $0.id == s.id }) { lifts[i] = s } else { lifts.append(s) }
        noteBests(since: before, in: s)
    }

    func delete(_ s: LiftSession) { lifts.removeAll { $0.id == s.id } }

    // MARK: Race sessions

    func upsert(_ s: HXSession) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
        disk.save(s, "session-\(s.id.uuidString).json")
        if s.isComplete {
            benchmarks.ingest(s)
            benchmarks.updateRoxzone(from: sessions)
            disk.save(benchmarks, "benchmarks.json")
        }
    }

    func delete(_ s: HXSession) {
        sessions.removeAll { $0.id == s.id }
        disk.remove("session-\(s.id.uuidString).json")
        // Its bests go with it: the bests are what the sessions still kept give.
        benchmarks = Benchmarks.rebuilt(from: sessions)
        disk.save(benchmarks, "benchmarks.json")
    }

    /// Keeps an official race typed in from its results page, or the correction of one: as a session
    /// like any other, so the bests, the prediction and the comparisons read it. The bests are worked
    /// out afresh, because a correction can take one away as well as set one. With `logToo` the race
    /// also goes into the training log as a HYROX session of its length, for a race the strap did not see.
    @discardableResult
    func saveRace(_ entry: RaceEntry, replacing id: UUID? = nil, logToo: Bool = false) -> HXSession? {
        guard let session = entry.session(id: id ?? UUID()) else { return nil }
        if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session } else { sessions.append(session) }
        sessions.sort { $0.startedAt > $1.startedAt }
        disk.save(session, "session-\(session.id.uuidString).json")
        benchmarks = Benchmarks.rebuilt(from: sessions)
        disk.save(benchmarks, "benchmarks.json")
        if logToo, let total = session.totalS {
            let start = session.startedAt.timeIntervalSince1970
            saveWorkout(LWorkout(start: start, end: start + total, sport: "HYROX", source: "manual", distanceM: 8000, notes: session.title))
        }
        return session
    }

    var unfinishedSession: HXSession? { sessions.first { !$0.isComplete && Date().timeIntervalSince($0.startedAt) < 6 * 3600 } }

    func saveRunSamples(_ samples: [RunSample], for id: String) {
        disk.save(samples, "run-\(id.replacingOccurrences(of: "|", with: "-")).json")
    }

    func runSamples(for id: String) -> [RunSample]? {
        disk.load([RunSample].self, "run-\(id.replacingOccurrences(of: "|", with: "-")).json")
    }

    func mergePBs(_ new: [PersonalBest]) -> [PersonalBest] {
        var improved: [PersonalBest] = []
        var all = runPBs
        for pb in new {
            if let i = all.firstIndex(where: { $0.distanceM == pb.distanceM }) {
                if pb.seconds < all[i].seconds { all[i] = pb; improved.append(pb) }
            } else {
                all.append(pb); improved.append(pb)
            }
        }
        if !improved.isEmpty { runPBs = all.sorted { $0.distanceM < $1.distanceM } }
        return improved
    }

    // MARK: Glance

    /// What the widgets and the Lock Screen should show right now.
    public func glance(now: Date = Date()) -> LumaGlance {
        let a = analysis
        let today = a.today
        let scored: LDay? = a.lastNight?.day == today ? a.lastNight : nil
        // The night's figures come from the same summary the Sleep screen shows, so the two cannot differ.
        // A widget has no room to qualify a figure, so a part-recorded night's are withheld there.
        let night: SleepNight? = a.sleep.last.flatMap { $0.day == today && !$0.partial ? $0 : nil }
        let wholeNight: Bool = !a.night.isPartial
        let schedule = scheduleDays([today, LDate.adding(1, to: today)])
        var sessions: [LumaGlance.Session] = []
        if let day = schedule.first {
            for p in day.planned where p.kind != .rest && p.status != .skipped {
                sessions.append(LumaGlance.Session(id: p.id.uuidString, title: p.title,
                                                   time: p.startMinutes.map { LFormat.timeOfDay(minutes: Double($0)) },
                                                   symbol: p.kind.sport.symbol, done: day.isDone(p)))
            }
            for w in day.unplannedWorkouts {
                sessions.append(LumaGlance.Session(id: w.id, title: w.kind == .other ? w.sport : w.kind.title, time: nil, symbol: w.kind.symbol, done: true))
            }
        }
        var tomorrow: String?
        if schedule.count > 1, let first = schedule[1].planned.first(where: { $0.kind != .rest }) {
            tomorrow = first.startMinutes.map { first.title + " · " + LFormat.timeOfDay(minutes: Double($0)) } ?? first.title
        }
        let strain = a.day?.strain.map { LScale.shown($0, on21: profile.strainOn21) }
        let totals = fuelTotals(on: today), targets = fuelTargets(on: today)
        let week = LumaAnalysis.series(.recovery, days: days, ending: today, count: 7).values.map { $0.map { LNum.int($0.rounded()) } }
        let brief: String? = coach.briefDay == today ? coach.brief : nil
        var glance = LumaGlance(day: today, recovery: scored?.recovery.map { LNum.int($0.rounded()) }, strain: strain, strainMax: profile.strainOn21 ? 21 : 100,
                          sleepScore: night?.score.map { LNum.int($0.rounded()) }, sleepMinutes: night.map { LNum.int($0.asleepMin.rounded()) },
                          hrv: wholeNight ? scored?.hrv.map { LNum.int($0.rounded()) } : nil,
                          restingHR: wholeNight ? scored?.restingHR.map { LNum.int($0.rounded()) } : nil,
                          call: a.call.title, callDetail: a.call.body, sessions: Array(sessions.prefix(4)), tomorrow: tomorrow,
                          kcal: LNum.int(totals.kcal.rounded()), kcalTarget: LNum.int(targets.kcal.rounded()), protein: LNum.int(totals.proteinG.rounded()),
                          proteinTarget: LNum.int(targets.proteinG.rounded()), waterMl: LNum.int(totals.waterMl.rounded()),
                          waterTargetMl: LNum.int(targets.waterMl.rounded()), brief: brief, week: week, updated: now)
        glance.buddy = buddyGlance(now: now)
        return glance
    }

    // MARK: Export and about

    public var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(version), build \(build)"
    }

    private struct ExportFile: Encodable {
        var exportedAt: Date
        var profile: LProfile
        var routine: [RoutineSlot]
        var planned: [PlannedSession]
        var fuel: [FuelEntry]
        var supplements: [SupplementPlan]
        var checkIns: [CheckIn]
        var lifts: [LiftSession]
        var personalBests: [PersonalBest]
        var raceSessions: [HXSession]
        var supplementTrials: [SupplementTrial]
        var weighIns: [WeightEntry]
        var sweatTests: [SweatTest]
        var weeklyReviews: [WeeklyReview]
    }

    /// Writes everything the athlete has entered to one JSON file and returns where it is.
    func exportFile() -> URL? {
        let file = ExportFile(exportedAt: Date(), profile: profile, routine: routine, planned: planned.filter { $0.status != .removed },
                              fuel: fuel, supplements: supplements, checkIns: checkIns, lifts: lifts, personalBests: runPBs, raceSessions: sessions,
                              supplementTrials: trials, weighIns: weights, sweatTests: sweatTests, weeklyReviews: reviews)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Luma records \(today).json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    // MARK: Strap data writes

    func saveWorkout(_ w: LWorkout, replacing old: LWorkout? = nil) {
        Task {
            await source.saveWorkout(w, replacing: old)
            reload()
        }
    }

    func deleteWorkout(_ w: LWorkout) {
        Task {
            await source.deleteWorkout(w)
            reload()
        }
    }

    // MARK: Suggested sessions

    /// The plan entry a suggested stretch most likely was: an entry for that day nothing has fulfilled yet.
    func likelyPlan(for stretch: LSuggestedSession) -> PlannedSession? {
        guard let day = scheduleDays([stretch.day]).first else { return nil }
        return SessionSuggestions.likelyPlan(for: stretch, among: day.planned.filter { !day.isDone($0) })
    }

    /// Keeps a suggested stretch as a session. It is stored like a hand-logged one, and the strap layer
    /// then reads its heart rate and strain from what it recorded in that window.
    func keep(_ stretch: LSuggestedSession, sport: String) {
        suggestions.removeAll { $0.id == stretch.id }
        saveWorkout(LWorkout(start: stretch.start, end: stretch.end, sport: sport, source: "manual",
                             avgHR: stretch.avgHR, maxHR: stretch.peakHR))
    }

    /// The athlete says a suggested stretch was not a session; it is not offered again.
    func dismiss(_ stretch: LSuggestedSession) {
        dismissedStretches.insert(stretch.id)
        disk.save(Array(dismissedStretches).sorted(), "stretches-dismissed.json")
        suggestions.removeAll { $0.id == stretch.id }
    }
}
