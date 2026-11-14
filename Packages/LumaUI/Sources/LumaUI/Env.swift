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

    public init(screen: String? = nil) { self.screen = screen }

    public static func fromArguments() -> LumaLaunch {
        let d = UserDefaults.standard
        scrollOffset = CGFloat(d.double(forKey: "lumaScroll"))
        return LumaLaunch(screen: d.string(forKey: "lumaScreen"))
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
    func buzz()
    /// Ask the strap for its fast heart-rate stream while a live screen is open.
    func setLiveHeartRate(_ on: Bool)
    func connectHealth() async
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
        }
    }
}

enum FuelAddMode: String { case meal, photo, supplement, water }

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
    /// A question handed to the coach from elsewhere in the app.
    @Published var coachPrompt: String?

    public init() {}

    func push(_ dest: LumaDest) {
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
}

// MARK: - Disk

/// Small JSON files under Application Support. `nil` directory keeps everything in memory (demo).
struct LumaDisk {
    let directory: URL?

    static func standard() -> LumaDisk {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent("HYROXLab", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        return LumaDisk(directory: dir)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        // Files written by the first build used the default (reference-date) encoding; accept both.
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self), let date = ISO8601DateFormatter().date(from: s) { return date }
            return Date(timeIntervalSinceReferenceDate: try c.decode(Double.self))
        }
        return d
    }

    func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = directory?.appendingPathComponent(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? LumaDisk.decoder().decode(type, from: data)
    }

    func save<T: Encodable>(_ value: T, _ name: String) {
        guard let url = directory?.appendingPathComponent(name), let data = try? LumaDisk.encoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func remove(_ name: String) {
        guard let url = directory?.appendingPathComponent(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func list(prefix: String) -> [String] {
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) }
    }

    func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }
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

    // Athlete's own records
    @Published public var profile: LProfile { didSet { if profile != oldValue { disk.save(profile, "profile.json"); onProfileChange?(profile); refreshAnalysis() } } }
    @Published var routine: [RoutineSlot] { didSet { disk.save(routine, "routine.json") } }
    @Published var planned: [PlannedSession] { didSet { disk.save(planned, "planned.json") } }
    @Published var fuel: [FuelEntry] { didSet { disk.save(fuel, "fuel.json") } }
    @Published var supplements: [SupplementPlan] { didSet { disk.save(supplements, "supplements.json") } }
    @Published var checkIns: [CheckIn] { didSet { disk.save(checkIns, "checkins.json") } }
    @Published var lifts: [LiftSession] { didSet { disk.save(lifts, "lifts.json") } }
    @Published private(set) var sessions: [HXSession] = []
    @Published private(set) var benchmarks = Benchmarks()
    @Published var runPBs: [PersonalBest] { didSet { disk.save(runPBs, "runpbs.json") } }

    /// Called when the profile changes so the app can mirror age, mass and max HR to the strap layer.
    public var onProfileChange: ((LProfile) -> Void)?
    /// Called after anything the widgets show has changed.
    public var onGlanceChange: (() -> Void)?

    private var reloadTask: Task<Void, Never>?
    private(set) lazy var coach = CoachEngine(env: self)

    public init(source: LumaDataSource, live: LumaLive, secrets: LumaSecrets, persistent: Bool = true) {
        self.source = source
        self.live = live
        self.secrets = secrets
        self.isDemo = !persistent
        let disk = persistent ? LumaDisk.standard() : LumaDisk(directory: nil)
        self.disk = disk
        profile = disk.load(LProfile.self, "profile.json") ?? LProfile()
        routine = disk.load([RoutineSlot].self, "routine.json") ?? []
        planned = disk.load([PlannedSession].self, "planned.json") ?? []
        fuel = disk.load([FuelEntry].self, "fuel.json") ?? []
        supplements = disk.load([SupplementPlan].self, "supplements.json") ?? []
        checkIns = disk.load([CheckIn].self, "checkins.json") ?? []
        lifts = disk.load([LiftSession].self, "lifts.json") ?? []
        runPBs = disk.load([PersonalBest].self, "runpbs.json") ?? []
        benchmarks = disk.load(Benchmarks.self, "benchmarks.json") ?? Benchmarks()
        sessions = disk.list(prefix: "session-").compactMap { disk.load(HXSession.self, $0) }.sorted { $0.startedAt > $1.startedAt }
    }

    /// The gallery and previews: synthetic strap data and filled-in records, nothing persisted.
    public static func demo(sparse: Bool = false) -> LumaEnv {
        let source = LumaDemoSource(dayCount: sparse ? 6 : 120)
        let live = LumaLive()
        var strap = LumaStrap()
        strap.connected = true; strap.secure = true; strap.heartRate = 58; strap.heartRateAt = Date()
        strap.battery = 64; strap.lastSync = Date().addingTimeInterval(-540); strap.name = "WHOOP MG"; strap.model = "MG"
        strap.firmware = "50.40.1.0"
        live.strap = strap
        live.paired = [LumaPairedStrap(id: "demo", name: "WHOOP MG", detail: "Active", isActive: true)]
        live.health = .on
        let env = LumaEnv(source: source, live: live, secrets: MemorySecrets(key: sparse ? nil : "demo"), persistent: false)
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
        }
        return env
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
            guard !Task.isCancelled else { return }
            self.days = days
            self.sleeps = sleeps
            self.workouts = workouts
            self.loaded = true
            self.refreshPlan()
            self.refreshAnalysis()
            if self.isDemo { self.coach.seedDemo() }
        }
    }

    func refreshAnalysis() {
        let today = LumaAnalysis.todayKey()
        analysis = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: workouts, profile: profile, planned: planned,
                                       checkIns: checkIns, personalBests: runPBs, today: today)
        onGlanceChange?()
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
        Schedule.days(keys, planned: planned, workouts: workouts)
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
        return FuelPlanner.targets(profile: profile, dayClass: FuelPlanner.dayClass(planned: ps, strain21: strain), trainingMinutes: max(45, minutes))
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
        if let url = disk.url(name) { try? data.write(to: url, options: .atomic) }
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
        if let i = lifts.firstIndex(where: { $0.id == s.id }) { lifts[i] = s } else { lifts.append(s) }
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
        let strain = a.day?.strain.map { profile.strainOn21 ? LScale.strain21($0) : $0 }
        let totals = fuelTotals(on: today), targets = fuelTargets(on: today)
        let week = LumaAnalysis.series(.recovery, days: days, ending: today, count: 7).values.map { $0.map { Int($0.rounded()) } }
        let brief: String? = coach.briefDay == today ? coach.brief : nil
        return LumaGlance(day: today, recovery: scored?.recovery.map { Int($0.rounded()) }, strain: strain, strainMax: profile.strainOn21 ? 21 : 100,
                          sleepScore: scored?.sleepScore.map { Int($0.rounded()) }, sleepMinutes: scored?.sleepMin.map { Int($0.rounded()) },
                          hrv: scored?.hrv.map { Int($0.rounded()) }, restingHR: scored?.restingHR.map { Int($0.rounded()) },
                          call: a.call.title, callDetail: a.call.body, sessions: Array(sessions.prefix(4)), tomorrow: tomorrow,
                          kcal: Int(totals.kcal.rounded()), kcalTarget: Int(targets.kcal.rounded()), protein: Int(totals.proteinG.rounded()),
                          proteinTarget: Int(targets.proteinG.rounded()), waterMl: Int(totals.waterMl.rounded()),
                          waterTargetMl: Int(targets.waterMl.rounded()), brief: brief, week: week, updated: now)
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
    }

    /// Writes everything the athlete has entered to one JSON file and returns where it is.
    func exportFile() -> URL? {
        let file = ExportFile(exportedAt: Date(), profile: profile, routine: routine, planned: planned.filter { $0.status != .removed },
                              fuel: fuel, supplements: supplements, checkIns: checkIns, lifts: lifts, personalBests: runPBs, raceSessions: sessions)
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
}
