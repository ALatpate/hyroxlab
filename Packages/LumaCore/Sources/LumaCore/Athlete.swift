import Foundation

// MARK: - Profile

/// What Luma knows about the athlete. Decoding is tolerant: every field has a default, so profiles
/// written by earlier builds keep loading as fields are added.
public struct LProfile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var sex: Sex = .male
    public var birthYear: Int = 1992
    public var heightCm: Double = 178
    public var weightKg: Double = 75
    /// Measured maximum heart rate; nil uses the age estimate.
    public var maxHR: Double?
    public var lthr: Double?
    public var format: RaceFormat = .openSingles
    public var fiveKSeconds: Double?
    public var raceDate: Date?
    public var raceName: String = ""
    /// Fixed nightly sleep need in hours; nil lets Luma estimate it.
    public var sleepNeedHours: Double?
    public var gym: String = ""
    public var goals: String = ""
    public var voiceCues: Bool = true
    public var cueEveryKm: Bool = true
    public var autoPause: Bool = true
    /// Show strain on the 0–21 scale (otherwise 0–100).
    public var strainOn21: Bool = true
    /// The athlete agreed to send the health data a question needs to the coach's AI provider.
    public var shareHealthWithCoach: Bool = false
    public var coachModel: String?
    /// 0 until the Luma setup flow has been completed.
    public var setupVersion: Int = 0

    public static let currentSetupVersion = 2

    public init() {}

    enum CodingKeys: String, CodingKey {
        case name, sex, birthYear, heightCm, weightKg, maxHR, lthr, format, fiveKSeconds, raceDate, raceName
        case sleepNeedHours, gym, goals, voiceCues, cueEveryKm, autoPause, strainOn21, shareHealthWithCoach
        case coachModel, setupVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        sex = try c.decodeIfPresent(Sex.self, forKey: .sex) ?? .male
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear) ?? 1992
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? 178
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 75
        maxHR = try c.decodeIfPresent(Double.self, forKey: .maxHR)
        lthr = try c.decodeIfPresent(Double.self, forKey: .lthr)
        format = try c.decodeIfPresent(RaceFormat.self, forKey: .format) ?? .openSingles
        fiveKSeconds = try c.decodeIfPresent(Double.self, forKey: .fiveKSeconds)
        raceDate = try c.decodeIfPresent(Date.self, forKey: .raceDate)
        raceName = try c.decodeIfPresent(String.self, forKey: .raceName) ?? ""
        sleepNeedHours = try c.decodeIfPresent(Double.self, forKey: .sleepNeedHours)
        gym = try c.decodeIfPresent(String.self, forKey: .gym) ?? ""
        goals = try c.decodeIfPresent(String.self, forKey: .goals) ?? ""
        voiceCues = try c.decodeIfPresent(Bool.self, forKey: .voiceCues) ?? true
        cueEveryKm = try c.decodeIfPresent(Bool.self, forKey: .cueEveryKm) ?? true
        autoPause = try c.decodeIfPresent(Bool.self, forKey: .autoPause) ?? true
        strainOn21 = try c.decodeIfPresent(Bool.self, forKey: .strainOn21) ?? true
        shareHealthWithCoach = try c.decodeIfPresent(Bool.self, forKey: .shareHealthWithCoach) ?? false
        coachModel = try c.decodeIfPresent(String.self, forKey: .coachModel)
        setupVersion = try c.decodeIfPresent(Int.self, forKey: .setupVersion) ?? 0
    }

    public func age(on date: Date = Date(), calendar: Calendar = LDate.calendar) -> Int {
        max(10, calendar.component(.year, from: date) - birthYear)
    }

    /// Measured max HR, else the Tanaka estimate (208 − 0.7 × age).
    public func resolvedMaxHR(on date: Date = Date()) -> Double {
        maxHR ?? (208 - 0.7 * Double(age(on: date))).rounded()
    }

    public func zones(on date: Date = Date()) -> HXZones {
        if let l = lthr, l > 100 { return HXZones.fromLTHR(l) }
        return HXZones.fromMaxHR(resolvedMaxHR(on: date))
    }

    public var isSetUp: Bool { setupVersion >= LProfile.currentSetupVersion }
}

// MARK: - Schedule

public enum SessionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case gymClass, strength, conditioning, hyrox, simulation, easyRun, tempoRun, intervals, longRun, mobility, rest, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .gymClass: return "Gym class"
        case .strength: return "Strength"
        case .conditioning: return "Conditioning"
        case .hyrox: return "HYROX session"
        case .simulation: return "Race simulation"
        case .easyRun: return "Easy run"
        case .tempoRun: return "Tempo run"
        case .intervals: return "Run intervals"
        case .longRun: return "Long run"
        case .mobility: return "Mobility"
        case .rest: return "Rest day"
        case .other: return "Session"
        }
    }

    public var sport: LSportKind {
        switch self {
        case .gymClass, .conditioning: return .conditioning
        case .strength: return .strength
        case .hyrox, .simulation: return .hyrox
        case .easyRun, .tempoRun, .intervals, .longRun: return .run
        case .mobility: return .mobility
        case .rest, .other: return .other
        }
    }

    public var isRun: Bool { sport == .run }

    public var defaultIntensity: Intensity {
        switch self {
        case .simulation, .intervals, .tempoRun, .hyrox: return .hard
        case .gymClass, .strength, .conditioning, .longRun, .other: return .moderate
        case .easyRun, .mobility, .rest: return .easy
        }
    }

    /// Whether a recorded session of `sport` plausibly fulfils this plan entry.
    public func matches(_ sport: LSportKind) -> Bool {
        switch self {
        case .gymClass: return [.conditioning, .strength, .hyrox, .other, .row].contains(sport)
        case .strength: return [.strength, .conditioning].contains(sport)
        case .conditioning: return [.conditioning, .hyrox, .row, .cycle, .other].contains(sport)
        case .hyrox, .simulation: return [.hyrox, .conditioning].contains(sport)
        case .easyRun, .tempoRun, .intervals, .longRun: return sport == .run
        case .mobility: return [.mobility, .walk].contains(sport)
        case .rest: return false
        case .other: return true
        }
    }
}

public enum Intensity: String, Codable, CaseIterable, Sendable {
    case easy, moderate, hard
    public var title: String { rawValue.capitalized }
}

/// A standing weekly commitment, such as a class every Tuesday at 06:30.
public struct RoutineSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int
    public var kind: SessionKind
    public var title: String
    /// Minutes after midnight, if the time is fixed.
    public var startMinutes: Int?
    public var durationMin: Int

    public init(id: UUID = UUID(), weekday: Int, kind: SessionKind, title: String, startMinutes: Int? = nil, durationMin: Int = 60) {
        self.id = id; self.weekday = weekday; self.kind = kind; self.title = title
        self.startMinutes = startMinutes; self.durationMin = durationMin
    }
}

public struct PlannedSession: Codable, Equatable, Sendable, Identifiable {
    public enum Origin: String, Codable, Sendable { case routine, coach, you }
    public enum Status: String, Codable, Sendable { case planned, done, skipped, removed }

    public var id: UUID
    public var day: String
    public var kind: SessionKind
    public var title: String
    public var detail: String
    public var durationMin: Int
    public var intensity: Intensity
    public var origin: Origin
    public var status: Status
    public var startMinutes: Int?
    public var targetPaceSPerKm: Double?
    /// The routine slot this entry was created from, if any.
    public var slotID: UUID?

    public init(id: UUID = UUID(), day: String, kind: SessionKind, title: String, detail: String = "", durationMin: Int = 60,
                intensity: Intensity? = nil, origin: Origin = .you, status: Status = .planned, startMinutes: Int? = nil,
                targetPaceSPerKm: Double? = nil, slotID: UUID? = nil) {
        self.id = id; self.day = day; self.kind = kind; self.title = title; self.detail = detail
        self.durationMin = durationMin; self.intensity = intensity ?? kind.defaultIntensity; self.origin = origin
        self.status = status; self.startMinutes = startMinutes; self.targetPaceSPerKm = targetPaceSPerKm; self.slotID = slotID
    }
}

/// One day of the calendar: what was planned and what was actually done.
public struct ScheduleDay: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let planned: [PlannedSession]
    public let workouts: [LWorkout]
    /// Planned-session id → the recorded workout that fulfilled it.
    public let matches: [UUID: String]

    public func isDone(_ p: PlannedSession) -> Bool { p.status == .done || matches[p.id] != nil }
    public var unplannedWorkouts: [LWorkout] {
        let used = Set(matches.values)
        return workouts.filter { !used.contains($0.id) }
    }
}

public enum Schedule {
    /// Turns the weekly routine into concrete entries for `days` days from `from`, skipping slots that
    /// already have an entry (including ones the athlete removed, which stay as tombstones).
    public static func materialize(routine: [RoutineSlot], existing: [PlannedSession], from: String, days: Int = 28,
                                   calendar: Calendar = LDate.calendar) -> [PlannedSession] {
        var out = existing
        let taken = Set(existing.compactMap { p in p.slotID.map { "\(p.day)|\($0.uuidString)" } })
        for offset in 0..<days {
            let day = LDate.adding(offset, to: from, calendar: calendar)
            let wd = LDate.weekday(day, calendar: calendar)
            for slot in routine where slot.weekday == wd && !taken.contains("\(day)|\(slot.id.uuidString)") {
                out.append(PlannedSession(day: day, kind: slot.kind, title: slot.title, durationMin: slot.durationMin,
                                          origin: .routine, startMinutes: slot.startMinutes, slotID: slot.id))
            }
        }
        return out
    }

    /// Removes future routine entries whose slot no longer exists (after the routine was edited),
    /// leaving past days and anything already done untouched.
    public static func pruneRoutine(_ planned: [PlannedSession], routine: [RoutineSlot], from: String) -> [PlannedSession] {
        let live = Set(routine.map { $0.id })
        return planned.filter { p in
            guard p.origin == .routine, let s = p.slotID, p.day >= from, p.status == .planned else { return true }
            return live.contains(s)
        }
    }

    public static func days(_ keys: [String], planned: [PlannedSession], workouts: [LWorkout]) -> [ScheduleDay] {
        let pByDay = Dictionary(grouping: planned.filter { $0.status != .removed }, by: { $0.day })
        let wByDay = Dictionary(grouping: workouts, by: { $0.day })
        return keys.map { key in
            let ps = (pByDay[key] ?? []).sorted { ($0.startMinutes ?? 720, $0.title) < ($1.startMinutes ?? 720, $1.title) }
            let ws = (wByDay[key] ?? []).sorted { $0.start < $1.start }
            var matches: [UUID: String] = [:]
            var used = Set<String>()
            for p in ps where p.status != .skipped {
                if let w = ws.first(where: { !used.contains($0.id) && p.kind.matches($0.kind) }) {
                    matches[p.id] = w.id; used.insert(w.id)
                }
            }
            return ScheduleDay(day: key, planned: ps, workouts: ws, matches: matches)
        }
    }

    /// Completed ÷ planned over the given days, ignoring rest entries and days still in the future.
    public static func adherence(_ days: [ScheduleDay], through today: String) -> (done: Int, planned: Int)? {
        var done = 0, planned = 0
        for d in days where d.day <= today {
            for p in d.planned where p.kind != .rest && p.status != .removed {
                planned += 1
                if d.isDone(p) { done += 1 }
            }
        }
        return planned > 0 ? (done, planned) : nil
    }
}

/// Training paces from a 5 km time (Daniels-style ratios, seconds per km).
public struct TrainingPaces: Equatable, Sendable {
    public let easy: Double
    public let steady: Double
    public let threshold: Double
    public let interval: Double
    public let race5k: Double

    public init(fiveKSeconds: Double) {
        let p = fiveKSeconds / 5
        race5k = p
        easy = p * 1.27
        steady = p * 1.15
        threshold = p * 1.06
        interval = p * 0.97
    }
}

// MARK: - Daily check-in

public enum CheckInTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case alcohol, lateCaffeine, lateMeal, lateScreens, sauna, coldPlunge, stretching, massage, travel, sick, highStress, nap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alcohol: return "Alcohol"
        case .lateCaffeine: return "Caffeine after 2 pm"
        case .lateMeal: return "Late meal"
        case .lateScreens: return "Screens in bed"
        case .sauna: return "Sauna"
        case .coldPlunge: return "Cold plunge"
        case .stretching: return "Stretching"
        case .massage: return "Massage"
        case .travel: return "Travel"
        case .sick: return "Felt unwell"
        case .highStress: return "Stressful day"
        case .nap: return "Nap"
        }
    }

    /// How the tag reads after the word "After".
    public var phrase: String {
        switch self {
        case .alcohol: return "alcohol"
        case .lateCaffeine: return "caffeine after 2 pm"
        case .lateMeal: return "a late meal"
        case .lateScreens: return "screens in bed"
        case .sauna: return "a sauna"
        case .coldPlunge: return "a cold plunge"
        case .stretching: return "stretching"
        case .massage: return "a massage"
        case .travel: return "travel"
        case .sick: return "feeling unwell"
        case .highStress: return "a stressful day"
        case .nap: return "a nap"
        }
    }

    public var symbol: String {
        switch self {
        case .alcohol: return "wineglass.fill"
        case .lateCaffeine: return "cup.and.saucer.fill"
        case .lateMeal: return "fork.knife"
        case .lateScreens: return "iphone"
        case .sauna: return "flame.fill"
        case .coldPlunge: return "snowflake"
        case .stretching: return "figure.flexibility"
        case .massage: return "hand.raised.fingers.spread.fill"
        case .travel: return "airplane"
        case .sick: return "thermometer.medium"
        case .highStress: return "bolt.fill"
        case .nap: return "moon.zzz.fill"
        }
    }
}

/// How the day went, logged in the evening (or the next morning for "yesterday").
public struct CheckIn: Codable, Equatable, Sendable, Identifiable {
    public var id: String { day }
    public var day: String
    public var tags: [CheckInTag]
    /// 1 (flat) … 5 (great).
    public var energy: Int?
    /// 1 (fresh) … 5 (very sore).
    public var soreness: Int?
    public var note: String

    public init(day: String, tags: [CheckInTag] = [], energy: Int? = nil, soreness: Int? = nil, note: String = "") {
        self.day = day; self.tags = tags; self.energy = energy; self.soreness = soreness; self.note = note
    }
}

// MARK: - Strength log

public struct LiftSet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int
    public var kg: Double
    public var done: Bool
    public init(id: UUID = UUID(), reps: Int, kg: Double, done: Bool = false) { self.id = id; self.reps = reps; self.kg = kg; self.done = done }
}

public struct LiftExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: [LiftSet]
    public init(id: UUID = UUID(), name: String, sets: [LiftSet] = []) { self.id = id; self.name = name; self.sets = sets }

    public var volumeKg: Double { sets.filter { $0.done }.reduce(0) { $0 + Double($1.reps) * $1.kg } }
    public var bestE1RM: Double? { sets.filter { $0.done && $0.reps > 0 && $0.kg > 0 }.map { LiftMath.e1RM(kg: $0.kg, reps: $0.reps) }.max() }
}

public struct LiftSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var title: String
    public var exercises: [LiftExercise]
    public var note: String
    public init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil, title: String = "Strength", exercises: [LiftExercise] = [], note: String = "") {
        self.id = id; self.start = start; self.end = end; self.title = title; self.exercises = exercises; self.note = note
    }

    public var volumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    public var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count } }
    public var day: String { LDate.key(start) }
}

public enum LiftMath {
    /// Estimated one-rep max (Epley). A single is its own max.
    public static func e1RM(kg: Double, reps: Int) -> Double { reps <= 1 ? kg : kg * (1 + Double(reps) / 30) }

    /// Best estimated 1RM per exercise across sessions, with the day it was set.
    public static func records(_ sessions: [LiftSession]) -> [String: (e1RM: Double, day: String)] {
        var out: [String: (e1RM: Double, day: String)] = [:]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            for e in s.exercises {
                guard let best = e.bestE1RM else { continue }
                if best > (out[e.name]?.e1RM ?? 0) { out[e.name] = (best, s.day) }
            }
        }
        return out
    }

    /// The most recent done sets for an exercise, to prefill the next session.
    public static func lastSets(_ name: String, in sessions: [LiftSession]) -> [LiftSet] {
        for s in sessions.sorted(by: { $0.start > $1.start }) {
            if let e = s.exercises.first(where: { $0.name == name }), e.sets.contains(where: { $0.done }) {
                return e.sets.filter { $0.done }
            }
        }
        return []
    }

    public static let catalog: [String] = [
        "Back squat", "Front squat", "Deadlift", "Romanian deadlift", "Trap bar deadlift", "Bench press", "Overhead press",
        "Push press", "Pull-up", "Chin-up", "Barbell row", "Dumbbell row", "Hip thrust", "Bulgarian split squat",
        "Walking lunge", "Sandbag lunge", "Goblet squat", "Thruster", "Wall ball", "Kettlebell swing", "Farmers carry",
        "Sled push", "Sled pull", "Burpee broad jump", "Box jump", "Lat pulldown", "Dumbbell bench press", "Dip",
        "Face pull", "Plank", "Hanging leg raise", "Calf raise", "Hamstring curl", "Leg press",
    ]
}
