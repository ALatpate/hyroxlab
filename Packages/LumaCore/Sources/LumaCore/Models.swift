import Foundation

// MARK: - Day keys

/// Day-key helpers. A day key is the local calendar date as "yyyy-MM-dd"; keys sort lexicographically.
/// Everything takes an explicit calendar so tests are deterministic and the app can pass the device's.
public enum LDate {
    public static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }()

    public static func key(_ date: Date, calendar: Calendar = LDate.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Local noon of the keyed day: a safe anchor for adding days across DST changes.
    public static func date(_ key: String, calendar: Calendar = LDate.calendar) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    public static func startOfDay(_ key: String, calendar: Calendar = LDate.calendar) -> Date? {
        date(key, calendar: calendar).map { calendar.startOfDay(for: $0) }
    }

    public static func adding(_ days: Int, to key: String, calendar: Calendar = LDate.calendar) -> String {
        guard let d = date(key, calendar: calendar), let n = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return self.key(n, calendar: calendar)
    }

    /// Whole days from `a` to `b` (positive when b is later).
    public static func daysBetween(_ a: String, _ b: String, calendar: Calendar = LDate.calendar) -> Int {
        guard let da = date(a, calendar: calendar), let db = date(b, calendar: calendar) else { return 0 }
        return Int(((db.timeIntervalSince(da)) / 86_400).rounded())
    }

    /// 1 = Monday … 7 = Sunday.
    public static func weekday(_ key: String, calendar: Calendar = LDate.calendar) -> Int {
        guard let d = date(key, calendar: calendar) else { return 1 }
        let w = calendar.component(.weekday, from: d)   // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    /// Monday of the week containing `key`.
    public static func weekStart(_ key: String, calendar: Calendar = LDate.calendar) -> String {
        adding(-(weekday(key, calendar: calendar) - 1), to: key, calendar: calendar)
    }

    /// Consecutive day keys ending at `end` (inclusive), oldest first.
    public static func range(ending end: String, count: Int, calendar: Calendar = LDate.calendar) -> [String] {
        guard count > 0 else { return [] }
        return (0..<count).map { adding($0 - (count - 1), to: end, calendar: calendar) }
    }
}

// MARK: - Daily metrics

/// One day of strap-derived metrics. Every field is optional: nil means "not measured", never zero.
/// Sleep and recovery fields belong to the night that ENDED on this day (the wake day).
public struct LDay: Codable, Equatable, Sendable, Identifiable {
    public var id: String { day }
    public var day: String
    public var sleepMin: Double?
    /// Sleep efficiency as a percentage (0–100).
    public var sleepEfficiency: Double?
    public var deepMin: Double?
    public var remMin: Double?
    public var lightMin: Double?
    public var disturbances: Int?
    public var restingHR: Double?
    /// Nightly HRV (RMSSD, ms).
    public var hrv: Double?
    public var sdnn: Double?
    /// Recovery score, 0–100.
    public var recovery: Double?
    /// Day strain on the 0–100 axis (see `LScale.strain21` for the familiar 0–21 scale).
    public var strain: Double?
    public var workouts: Int?
    public var spo2: Double?
    /// Skin temperature deviation from the personal baseline, °C.
    public var skinTempDev: Double?
    public var skinTemp: Double?
    public var respRate: Double?
    public var steps: Int?
    public var activeKcal: Double?
    /// Sleep performance (0–100) when the source provides one.
    public var sleepScore: Double?
    public var sleepNeedMin: Double?

    public init(day: String, sleepMin: Double? = nil, sleepEfficiency: Double? = nil, deepMin: Double? = nil,
                remMin: Double? = nil, lightMin: Double? = nil, disturbances: Int? = nil, restingHR: Double? = nil,
                hrv: Double? = nil, sdnn: Double? = nil, recovery: Double? = nil, strain: Double? = nil,
                workouts: Int? = nil, spo2: Double? = nil, skinTempDev: Double? = nil, skinTemp: Double? = nil,
                respRate: Double? = nil, steps: Int? = nil, activeKcal: Double? = nil, sleepScore: Double? = nil,
                sleepNeedMin: Double? = nil) {
        self.day = day; self.sleepMin = sleepMin; self.sleepEfficiency = sleepEfficiency; self.deepMin = deepMin
        self.remMin = remMin; self.lightMin = lightMin; self.disturbances = disturbances; self.restingHR = restingHR
        self.hrv = hrv; self.sdnn = sdnn; self.recovery = recovery; self.strain = strain; self.workouts = workouts
        self.spo2 = spo2; self.skinTempDev = skinTempDev; self.skinTemp = skinTemp; self.respRate = respRate
        self.steps = steps; self.activeKcal = activeKcal; self.sleepScore = sleepScore; self.sleepNeedMin = sleepNeedMin
    }

    /// True when the night behind this day has been scored.
    public var hasNight: Bool { sleepMin != nil || recovery != nil || hrv != nil }
}

/// A metric that can be read off an `LDay`, with display metadata. One list drives trends, the coach
/// tools and the insight engine, so a metric means the same thing everywhere.
public enum LMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case recovery, strain, sleepScore, sleepHours, hrv, restingHR, respRate, skinTempDev, spo2
    case deepMin, remMin, sleepEfficiency, steps, activeKcal

    public var id: String { rawValue }

    public func value(_ d: LDay) -> Double? {
        switch self {
        case .recovery: return d.recovery
        case .strain: return d.strain.map(LScale.strain21)
        case .sleepScore: return d.sleepScore
        case .sleepHours: return d.sleepMin.map { $0 / 60 }
        case .hrv: return d.hrv
        case .restingHR: return d.restingHR
        case .respRate: return d.respRate
        case .skinTempDev: return d.skinTempDev
        case .spo2: return d.spo2
        case .deepMin: return d.deepMin
        case .remMin: return d.remMin
        case .sleepEfficiency: return d.sleepEfficiency
        case .steps: return d.steps.map(Double.init)
        case .activeKcal: return d.activeKcal
        }
    }

    public var title: String {
        switch self {
        case .recovery: return "Recovery"
        case .strain: return "Strain"
        case .sleepScore: return "Sleep score"
        case .sleepHours: return "Sleep"
        case .hrv: return "HRV"
        case .restingHR: return "Resting heart rate"
        case .respRate: return "Respiratory rate"
        case .skinTempDev: return "Skin temperature"
        case .spo2: return "Blood oxygen"
        case .deepMin: return "Deep sleep"
        case .remMin: return "REM sleep"
        case .sleepEfficiency: return "Sleep efficiency"
        case .steps: return "Steps"
        case .activeKcal: return "Active energy"
        }
    }

    public var unit: String {
        switch self {
        case .recovery, .sleepScore, .sleepEfficiency, .spo2: return "%"
        case .strain: return ""
        case .sleepHours: return "h"
        case .hrv: return "ms"
        case .restingHR: return "bpm"
        case .respRate: return "rpm"
        case .skinTempDev: return "°C"
        case .deepMin, .remMin: return "min"
        case .steps: return ""
        case .activeKcal: return "kcal"
        }
    }

    public var decimals: Int {
        switch self {
        case .strain, .sleepHours, .respRate, .skinTempDev: return 1
        default: return 0
        }
    }

    /// Whether a higher value is the good direction (nil: neither, e.g. skin temperature deviation).
    public var higherIsBetter: Bool? {
        switch self {
        case .recovery, .sleepScore, .sleepHours, .hrv, .deepMin, .remMin, .sleepEfficiency, .spo2, .steps: return true
        case .restingHR, .respRate: return false
        case .strain, .skinTempDev, .activeKcal: return nil
        }
    }

    public func format(_ v: Double) -> String {
        if self == .skinTempDev { return String(format: "%+.1f", v) }
        if self == .steps || self == .activeKcal { return LFormat.grouped(v) }
        return String(format: "%.\(decimals)f", v)
    }
}

public enum LScale {
    /// The strap pipeline stores strain on 0–100; athletes know it on 0–21.
    public static func strain21(_ strain100: Double) -> Double { strain100 * 21 / 100 }
    public static func strain100(_ strain21: Double) -> Double { strain21 * 100 / 21 }
}

public enum LFormat {
    public static func grouped(_ v: Double) -> String {
        let n = Int(v.rounded())
        var s = String(abs(n)), out = ""
        while s.count > 3 { out = "," + String(s.suffix(3)) + out; s = String(s.dropLast(3)) }
        return (n < 0 ? "-" : "") + s + out
    }

    /// "7h 42m" (or "42m" under an hour).
    public static func hm(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(String(format: "%02d", m % 60))m" : "\(m)m"
    }

    /// "7:42" hours:minutes.
    public static func clock(minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60):\(String(format: "%02d", m % 60))"
    }

    /// Minutes after local midnight (may exceed 1440 or be negative) → "23:10".
    public static func timeOfDay(minutes: Double) -> String {
        var m = Int(minutes.rounded()) % 1440
        if m < 0 { m += 1440 }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    public static func signed(_ v: Double, decimals: Int = 0) -> String {
        String(format: "%+.\(decimals)f", v)
    }
}

// MARK: - Sleep

public enum LStageKind: String, Codable, Sendable, CaseIterable {
    case awake, light, deep, rem

    public var title: String {
        switch self {
        case .awake: return "Awake"
        case .light: return "Light"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }
}

public struct LStage: Codable, Equatable, Sendable {
    /// Unix seconds.
    public var start: Double
    public var end: Double
    public var kind: LStageKind
    public init(start: Double, end: Double, kind: LStageKind) { self.start = start; self.end = end; self.kind = kind }
    public var minutes: Double { max(0, end - start) / 60 }
}

public struct LSleep: Codable, Equatable, Sendable, Identifiable {
    public var id: Double { start }
    /// Unix seconds.
    public var start: Double
    public var end: Double
    /// Wake-day key.
    public var day: String
    public var efficiency: Double?
    public var restingHR: Double?
    public var hrv: Double?
    public var stages: [LStage]
    public var isNap: Bool
    /// The strap flagged the staging as possibly incomplete.
    public var incomplete: Bool

    public init(start: Double, end: Double, day: String, efficiency: Double? = nil, restingHR: Double? = nil,
                hrv: Double? = nil, stages: [LStage] = [], isNap: Bool = false, incomplete: Bool = false) {
        self.start = start; self.end = end; self.day = day; self.efficiency = efficiency
        self.restingHR = restingHR; self.hrv = hrv; self.stages = stages; self.isNap = isNap; self.incomplete = incomplete
    }

    public var inBedMin: Double { max(0, end - start) / 60 }
    public func minutes(_ kind: LStageKind) -> Double { stages.filter { $0.kind == kind }.reduce(0) { $0 + $1.minutes } }
    public var asleepMin: Double { stages.isEmpty ? inBedMin * (efficiency ?? 90) / 100 : stages.filter { $0.kind != .awake }.reduce(0) { $0 + $1.minutes } }
}

// MARK: - Workouts and series

public struct LWorkout: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(Int(start))|\(sport)" }
    /// Unix seconds.
    public var start: Double
    public var end: Double
    public var sport: String
    public var source: String
    public var durationS: Double
    public var kcal: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    /// 0–100 axis, like `LDay.strain`.
    public var strain: Double?
    public var distanceM: Double?
    /// Percent of the session in zones 1…5 (may sum to less than 100).
    public var zonePct: [Double]?
    public var notes: String?
    /// Only sessions recorded or entered on this phone can be edited or deleted.
    public var editable: Bool

    public init(start: Double, end: Double, sport: String, source: String = "manual", durationS: Double? = nil,
                kcal: Double? = nil, avgHR: Double? = nil, maxHR: Double? = nil, strain: Double? = nil,
                distanceM: Double? = nil, zonePct: [Double]? = nil, notes: String? = nil, editable: Bool = true) {
        self.start = start; self.end = end; self.sport = sport; self.source = source
        self.durationS = durationS ?? max(0, end - start); self.kcal = kcal; self.avgHR = avgHR; self.maxHR = maxHR
        self.strain = strain; self.distanceM = distanceM; self.zonePct = zonePct; self.notes = notes; self.editable = editable
    }

    public var day: String { LDate.key(Date(timeIntervalSince1970: start)) }
    public var kind: LSportKind { LSportKind.classify(sport) }
    public var paceSPerKm: Double? {
        guard let d = distanceM, d > 200, durationS > 0 else { return nil }
        return durationS / (d / 1000)
    }
}

/// Coarse sport families used for colour, icons, load factors and plan matching.
public enum LSportKind: String, Codable, Sendable, CaseIterable {
    case run, hyrox, strength, conditioning, cycle, row, swim, walk, mobility, other

    public static func classify(_ sport: String) -> LSportKind {
        let s = sport.lowercased()
        if s.contains("hyrox") { return .hyrox }
        if s.contains("run") || s.contains("jog") || s.contains("treadmill") { return .run }
        if s.contains("strength") || s.contains("lift") || s.contains("weight") || s.contains("bodybuilding") { return .strength }
        if s.contains("hiit") || s.contains("crossfit") || s.contains("functional") || s.contains("boot") || s.contains("circuit") || s.contains("conditioning") || s.contains("class") { return .conditioning }
        if s.contains("cycl") || s.contains("bike") || s.contains("spin") { return .cycle }
        if s.contains("row") || s.contains("erg") { return .row }
        if s.contains("swim") { return .swim }
        if s.contains("walk") || s.contains("hik") { return .walk }
        if s.contains("yoga") || s.contains("stretch") || s.contains("mobility") || s.contains("pilates") { return .mobility }
        return .other
    }

    public var title: String {
        switch self {
        case .run: return "Run"
        case .hyrox: return "HYROX"
        case .strength: return "Strength"
        case .conditioning: return "Conditioning"
        case .cycle: return "Ride"
        case .row: return "Row"
        case .swim: return "Swim"
        case .walk: return "Walk"
        case .mobility: return "Mobility"
        case .other: return "Workout"
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .hyrox: return "flag.checkered"
        case .strength: return "dumbbell.fill"
        case .conditioning: return "bolt.heart.fill"
        case .cycle: return "figure.outdoor.cycle"
        case .row: return "figure.rower"
        case .swim: return "figure.pool.swim"
        case .walk: return "figure.walk"
        case .mobility: return "figure.cooldown"
        case .other: return "figure.mixed.cardio"
        }
    }
}

public struct LHRPoint: Codable, Equatable, Sendable {
    /// Unix seconds (bucket start).
    public var t: Double
    public var bpm: Double
    public var lo: Double
    public var hi: Double
    public init(t: Double, bpm: Double, lo: Double? = nil, hi: Double? = nil) {
        self.t = t; self.bpm = bpm; self.lo = lo ?? bpm; self.hi = hi ?? bpm
    }
}

public struct LPoint: Codable, Equatable, Sendable {
    public var t: Double
    public var v: Double
    public init(t: Double, v: Double) { self.t = t; self.v = v }
}

public struct LCoord: Codable, Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// Hour-by-hour daytime stress for one day (0–3: calm → high). `level` is nil when the hour had too
/// little data or was masked by exercise.
public struct LStressHour: Codable, Equatable, Sendable {
    public var hour: Int
    public var level: Double?
    public var meanHR: Double?
    public init(hour: Int, level: Double?, meanHR: Double? = nil) { self.hour = hour; self.level = level; self.meanHR = meanHR }
}

public struct LStressDay: Codable, Equatable, Sendable {
    public var hours: [LStressHour]
    public var mean: Double?
    public var highMinutes: Int
    public init(hours: [LStressHour], mean: Double?, highMinutes: Int) { self.hours = hours; self.mean = mean; self.highMinutes = highMinutes }

    public static func band(_ level: Double) -> String { level < 1 ? "Calm" : level < 2 ? "Moderate" : "High" }
}

/// Heart-rate recovery after a session: beats dropped from the end-of-session rate.
public struct LHRRecovery: Codable, Equatable, Sendable {
    public var endHR: Double
    public var drop1: Double?
    public var drop2: Double?
    public init(endHR: Double, drop1: Double?, drop2: Double?) { self.endHR = endHR; self.drop1 = drop1; self.drop2 = drop2 }
}

// MARK: - Data source

/// Everything Luma reads from (and the little it writes to) the strap database. The app implements
/// this once over the strap layer; `LumaDemoSource` implements it with synthetic data.
public protocol LumaDataSource: AnyObject {
    /// Every stored day, oldest first. Sparse: days with no data are absent.
    func loadDays() async -> [LDay]
    /// Every sleep block (nights and naps) in the last `days` days, oldest first.
    func loadSleeps(days: Int) async -> [LSleep]
    /// Sessions in the last `days` days, newest first.
    func loadWorkouts(days: Int) async -> [LWorkout]
    func heartRate(from: Double, to: Double, bucketSeconds: Int) async -> [LHRPoint]
    /// Rolling HRV (RMSSD, ms) through a window, when beat-to-beat data exists.
    func hrvSeries(from: Double, to: Double) async -> [LPoint]
    func route(for workout: LWorkout) async -> [LCoord]
    func stress(day: String) async -> LStressDay?
    func heartRateRecovery(for workout: LWorkout, maxHR: Double) async -> LHRRecovery?
    func saveWorkout(_ workout: LWorkout, replacing old: LWorkout?) async
    func deleteWorkout(_ workout: LWorkout) async
}
