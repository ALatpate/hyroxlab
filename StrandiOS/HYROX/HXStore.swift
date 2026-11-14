import Foundation
import SwiftUI
import Combine
import HYROXCore
import WhoopStore

// MARK: - Profile

/// Everything HYROX Lab needs to know about the athlete that NOOP's ProfileStore doesn't hold.
struct HXProfile: Codable, Equatable {
    var onboarded = false
    var format: RaceFormat = .openSingles
    var fiveKSeconds: Double = 25 * 60
    var lthr: Int? = nil
    var classWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var runsPerWeek = 3
    var raceDate: Date? = nil
    var raceName: String = ""
    var weakestStations: [Station] = []
    var voiceCues = true
    var cueEveryKm = true
    var autoPause = true
    var sleepNeedHours: Double = 7.5
}

// MARK: - Food

struct HXFoodEntry: Codable, Equatable, Identifiable {
    enum Provenance: String, Codable { case measured, reviewed, estimated }
    var id = UUID()
    var at: Date
    var title: String
    var kcal: Double?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var provenance: Provenance
    var note: String?
}

// MARK: - Store

/// On-device store for HYROX Lab's own records (sessions, benchmarks, plan, food, profile), kept as
/// small JSON files under Application Support/HYROXLab so a session in progress is written after
/// every segment. NOOP's database stays NOOP's; every finished session is mirrored into it as a
/// WorkoutRow so Effort, Trends and Health write-back keep working.
@MainActor
final class HXStore: ObservableObject {
    @Published var profile: HXProfile { didSet { save(profile, "profile.json") } }
    @Published private(set) var sessions: [HXSession] = []
    @Published private(set) var benchmarks = Benchmarks()
    @Published var plan: [PlannedSession] = [] { didSet { save(plan, "plan.json") } }
    @Published var food: [HXFoodEntry] = [] { didSet { save(food, "food.json") } }
    @Published private(set) var readiness: HXReadiness?
    @Published private(set) var readinessInputs: ReadinessInputs?
    @Published private(set) var raceReadiness: [FormatReadiness] = []
    @Published private(set) var dailyLoads: [(day: String, load: Double)] = []
    @Published private(set) var runPBs: [PersonalBest] = []

    private var repo: Repository?
    private var noopProfile: ProfileStore?
    private var cancellables = Set<AnyCancellable>()
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("HYROXLab", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        profile = Self.load(HXProfile.self, from: dir.appendingPathComponent("profile.json")) ?? HXProfile()
        plan = Self.load([PlannedSession].self, from: dir.appendingPathComponent("plan.json")) ?? []
        food = Self.load([HXFoodEntry].self, from: dir.appendingPathComponent("food.json")) ?? []
        benchmarks = Self.load(Benchmarks.self, from: dir.appendingPathComponent("benchmarks.json")) ?? Benchmarks()
        sessions = loadSessions()
        runPBs = Self.load([PersonalBest].self, from: dir.appendingPathComponent("runpbs.json")) ?? []
        recomputeRaceReadiness()
    }

    /// Call once from the root view so readiness can follow NOOP's daily metrics.
    func attach(repo: Repository, profile noop: ProfileStore) {
        guard self.repo == nil else { return }
        self.repo = repo
        self.noopProfile = noop
        repo.$days
            .receive(on: RunLoop.main)
            .sink { [weak self] days in self?.recomputeReadiness(days: days) }
            .store(in: &cancellables)
        recomputeReadiness(days: repo.days)
    }

    var sex: Sex { (noopProfile?.sex ?? "male") == "female" ? .female : .male }
    var hrMax: Double { Double(noopProfile?.hrMax ?? 190) }
    var zones: HXZones { profile.lthr.map { HXZones.fromLTHR(Double($0)) } ?? HXZones.fromMaxHR(hrMax) }
    var paces: TrainingPaces { TrainingPaces(fiveKSeconds: profile.fiveKSeconds) }

    // MARK: Sessions

    /// Writes a session in progress (or finished) to its own file and refreshes derived state.
    func upsert(_ s: HXSession) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
        sessions.sort { $0.startedAt > $1.startedAt }
        save(s, "session-\(s.id.uuidString).json")
        if s.isComplete {
            benchmarks.ingest(s)
            benchmarks.updateRoxzone(from: sessions)
            save(benchmarks, "benchmarks.json")
            recomputeRaceReadiness()
        }
    }

    func delete(_ s: HXSession) {
        sessions.removeAll { $0.id == s.id }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("session-\(s.id.uuidString).json"))
        var b = Benchmarks()
        for x in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where x.isComplete { b.ingest(x) }
        b.updateRoxzone(from: sessions)
        benchmarks = b
        save(benchmarks, "benchmarks.json")
        recomputeRaceReadiness()
    }

    /// A session left open by a crash. Only one can exist.
    var unfinished: HXSession? { sessions.first { !$0.isComplete } }

    // MARK: Run samples (one file per run session)

    func saveRunSamples(_ samples: [RunSample], for id: UUID) {
        save(samples, "run-\(id.uuidString).json")
        let pbs = RunAnalytics.personalBests(samples)
        var merged = runPBs
        for p in pbs {
            if let i = merged.firstIndex(where: { $0.distanceM == p.distanceM }) {
                if p.seconds < merged[i].seconds { merged[i] = p }
            } else { merged.append(p) }
        }
        merged.sort { $0.distanceM < $1.distanceM }
        runPBs = merged
        save(merged, "runpbs.json")
    }

    func runSamples(for id: UUID) -> [RunSample] {
        Self.load([RunSample].self, from: dir.appendingPathComponent("run-\(id.uuidString).json")) ?? []
    }

    // MARK: Mirror into NOOP

    /// Creates the NOOP WorkoutRow for a finished session so it shows in Workouts, Effort and Health.
    func mirrorToNOOP(_ s: HXSession, distanceM: Double?, avgHr: Int?, maxHr: Int?, kcal: Double?) async {
        guard let repo, let end = s.endedAt else { return }
        let sport = s.kind.isRun ? "Running" : "HYROX"
        let row = WorkoutRow(startTs: Int(s.startedAt.timeIntervalSince1970), endTs: Int(end.timeIntervalSince1970),
                             sport: sport, source: "manual", durationS: s.totalS, energyKcal: kcal,
                             avgHr: avgHr, maxHr: maxHr, strain: nil, distanceM: distanceM, zonesJSON: nil,
                             notes: "HYROX Lab · \(s.kind.title)", steps: nil)
        await repo.saveManualWorkout(row)
    }

    // MARK: Readiness

    private func recomputeReadiness(days: [DailyMetric]) {
        guard !days.isEmpty else { return }
        let todayKey = Repository.localDayKey(Date())
        let sorted = days.sorted { $0.day < $1.day }
        let today = sorted.last { $0.day == todayKey }
        let history = sorted.filter { $0.day < todayKey }
        let hrvHist = history.compactMap(\.avgHrv)
        let rhrHist = history.compactMap(\.restingHr).map(Double.init)
        // Daily load: NOOP Effort (strain) per day, zero for missing days, last 28 days ending yesterday.
        var loads: [(day: String, load: Double)] = []
        let cal = Calendar.current
        for i in stride(from: 28, through: 1, by: -1) {
            let d = cal.date(byAdding: .day, value: -i, to: Date())!
            let key = Repository.localDayKey(d)
            loads.append((key, history.first { $0.day == key }?.strain ?? 0))
        }
        dailyLoads = loads
        let sleepH: Double? = (today?.totalSleepMin).map { $0 / 60 }
        let plannedHard = plan.first { cal.isDateInToday($0.date) }?.type.isHard ?? false
        let inputs = ReadinessInputs(charge: today?.recovery, hrvToday: today?.avgHrv, hrvHistory: hrvHist,
                                     rhrToday: today?.restingHr.map(Double.init), rhrHistory: rhrHist,
                                     sleepHoursLastNight: sleepH, sleepNeedHours: profile.sleepNeedHours,
                                     dailyLoads: loads.map(\.load), hasHardSessionPlannedToday: plannedHard)
        readinessInputs = inputs
        readiness = HXReadinessEngine.compute(inputs)
    }

    private func recomputeRaceReadiness() {
        let fresh = runPBs.first { $0.distanceM == 1000 }?.seconds ?? paces.hyroxRace
        raceReadiness = RaceReadiness.assess(benchmarks: benchmarks, sessions: sessions, sex: sex, fresh1kS: fresh)
    }

    // MARK: Plan

    /// Regenerates this week and next from the profile and today's readiness; keeps completed links.
    func regeneratePlan() {
        var cal = Calendar.current; cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today)!
        let p = PlanProfile(classWeekdays: profile.classWeekdays, fiveKSeconds: profile.fiveKSeconds,
                            targetFormat: profile.format, raceDate: profile.raceDate, runsPerWeek: profile.runsPerWeek,
                            weakestStations: profile.weakestStations)
        var out: [PlannedSession] = []
        for w in 0..<2 {
            let start = cal.date(byAdding: .day, value: 7 * w, to: monday)!
            out += PlanGenerator.week(starting: start, profile: p, readiness: readiness?.score, calendar: cal)
        }
        // Preserve completion marks for days already done.
        for i in out.indices {
            if let old = plan.first(where: { cal.isDate($0.date, inSameDayAs: out[i].date) && $0.type == out[i].type }) {
                out[i].completedSessionID = old.completedSessionID
                out[i].skipped = old.skipped
            }
        }
        plan = out
    }

    func todayPlanned() -> PlannedSession? {
        plan.first { Calendar.current.isDateInToday($0.date) && $0.type != .rest }
            ?? plan.first { Calendar.current.isDateInToday($0.date) }
    }

    func markPlanned(_ planned: PlannedSession, completedBy session: HXSession) {
        guard let i = plan.firstIndex(where: { $0.id == planned.id }) else { return }
        plan[i].completedSessionID = session.id
    }

    // MARK: Food

    func todayFood() -> [HXFoodEntry] { food.filter { Calendar.current.isDateInToday($0.at) } }

    func nutritionTargets() -> NutritionTargets {
        let p = noopProfile
        let day: DayLoadClass
        switch todayPlanned()?.type {
        case .some(.rest), .none: day = .rest
        case .some(.fullSimulation): day = .race
        case .some(let t) where t.isHard: day = .hard
        default: day = .moderate
        }
        return NutritionPlanner.targets(massKg: p?.weightKg ?? 80, heightCm: p?.heightCm ?? 178, age: p?.age ?? 34, sex: sex, day: day)
    }

    // MARK: Persistence

    private func save<T: Encodable>(_ value: T, _ name: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(type, from: data)
    }

    private func loadSessions() -> [HXSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix("session-") }
            .compactMap { Self.load(HXSession.self, from: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }
}
