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
    /// Write a short read of the day each morning (one coach request a day).
    public var morningBrief: Bool = true
    /// Show live heart rate and today's numbers on the Lock Screen while the strap is streaming.
    public var lockScreenHeartRate: Bool = true
    /// Keep the strap streaming heart rate to the phone at all times, not only while Luma is on screen,
    /// so nights are recorded in full and the Lock Screen card stays live. Costs strap battery.
    public var continuousRecording: Bool = true
    /// 0 until the Luma setup flow has been completed.
    public var setupVersion: Int = 0

    public static let currentSetupVersion = 2

    public init() {}

    enum CodingKeys: String, CodingKey {
        case name, sex, birthYear, heightCm, weightKg, maxHR, lthr, format, fiveKSeconds, raceDate, raceName
        case sleepNeedHours, gym, goals, voiceCues, cueEveryKm, autoPause, strainOn21, shareHealthWithCoach
        case coachModel, morningBrief, lockScreenHeartRate, continuousRecording, setupVersion
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
        morningBrief = try c.decodeIfPresent(Bool.self, forKey: .morningBrief) ?? true
        lockScreenHeartRate = try c.decodeIfPresent(Bool.self, forKey: .lockScreenHeartRate) ?? true
        continuousRecording = try c.decodeIfPresent(Bool.self, forKey: .continuousRecording) ?? true
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
    /// What was logged of the day's training: sessions logged set by set, read from photos or told to
    /// the coach.
    public let logs: [LiftSession]
    /// Planned-session id → the logged session that fulfilled it, for an entry no recorded workout did.
    public let logged: [UUID: UUID]

    public init(day: String, planned: [PlannedSession], workouts: [LWorkout], matches: [UUID: String], logs: [LiftSession] = [],
                logged: [UUID: UUID] = [:]) {
        self.day = day; self.planned = planned; self.workouts = workouts; self.matches = matches; self.logs = logs; self.logged = logged
    }

    public func isDone(_ p: PlannedSession) -> Bool { p.status == .done || matches[p.id] != nil || logged[p.id] != nil }
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

    /// A plan entry is fulfilled by a recorded workout of a fitting sport, or failing that by a session
    /// logged that day of a fitting kind: a class logged from a photo of its board was done, whether or
    /// not the strap recorded it.
    public static func days(_ keys: [String], planned: [PlannedSession], workouts: [LWorkout], logs: [LiftSession] = []) -> [ScheduleDay] {
        let pByDay = Dictionary(grouping: planned.filter { $0.status != .removed }, by: { $0.day })
        let wByDay = Dictionary(grouping: workouts, by: { $0.day })
        let lByDay = Dictionary(grouping: logs, by: { $0.day })
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
            let ls = (lByDay[key] ?? []).sorted { $0.start < $1.start }
            var logged: [UUID: UUID] = [:]
            var taken = Set<UUID>()
            for p in ps where p.status != .skipped && matches[p.id] == nil {
                if let l = ls.first(where: { !taken.contains($0.id) && p.kind.matches($0.resolvedKind.sport) }) {
                    logged[p.id] = l.id; taken.insert(l.id)
                }
            }
            return ScheduleDay(day: key, planned: ps, workouts: ws, matches: matches, logs: ls, logged: logged)
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

// MARK: - Training log

/// One set of work. A lift counts reps at a load; a sled length, a carry or an erg counts distance,
/// time or calories instead, and any of them may come with a load.
public struct LiftSet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int
    /// Load in kg; 0 when the set had none or none was written down.
    public var kg: Double
    public var done: Bool
    public var meters: Double?
    public var seconds: Double?
    public var calories: Double?

    public init(id: UUID = UUID(), reps: Int, kg: Double, done: Bool = false, meters: Double? = nil, seconds: Double? = nil,
                calories: Double? = nil) {
        self.id = id; self.reps = reps; self.kg = kg; self.done = done
        self.meters = meters; self.seconds = seconds; self.calories = calories
    }

    /// Whether the set says anything at all about what was done.
    public var hasContent: Bool { reps > 0 || (meters ?? 0) > 0 || (seconds ?? 0) > 0 || (calories ?? 0) > 0 }

    /// "5 × 100 kg", "12 reps", "25 m · 140 kg", "500 m", "45 s", "20 cal".
    public var text: String {
        let load = kg > 0 ? LiftSet.number(kg) + " kg" : nil
        var parts: [String] = []
        if let m = meters, m > 0 { parts.append(m >= 1000 ? LiftSet.number(m / 1000) + " km" : LiftSet.number(m) + " m") }
        if let s = seconds, s > 0 {
            let whole = Int(s.rounded())
            parts.append(whole >= 90 ? String(format: "%d:%02d", whole / 60, whole % 60) : "\(whole) s")
        }
        if let c = calories, c > 0 { parts.append(LiftSet.number(c) + " cal") }
        if reps > 0 {
            if parts.isEmpty, let load { return "\(reps) × \(load)" }
            parts.insert(reps == 1 ? "1 rep" : "\(reps) reps", at: 0)
        }
        if parts.isEmpty { return load ?? "No detail" }
        if let load { parts.append(load) }
        return parts.joined(separator: " · ")
    }

    /// What the set counted, leaving its load aside: "5 reps", "25 m".
    public var amountText: String {
        var bare = self
        bare.kg = 0
        return bare.text
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// What a set counts.
public enum SetMeasure: String, CaseIterable, Sendable {
    case reps, meters, seconds, calories

    public var title: String {
        switch self {
        case .reps: return "reps"
        case .meters: return "m"
        case .seconds: return "sec"
        case .calories: return "cal"
        }
    }
}

public struct LiftExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var sets: [LiftSet]
    /// Muscles the movement works, as read from a photo, for a movement Luma's own list does not know.
    public var muscles: [String]?
    /// How the movement was to be done, as written: "tempo 3-1-1", "each side", "AMRAP 12 min".
    public var note: String?

    public init(id: UUID = UUID(), name: String, sets: [LiftSet] = [], muscles: [String]? = nil, note: String? = nil) {
        self.id = id; self.name = name; self.sets = sets; self.muscles = muscles; self.note = note
    }

    public var volumeKg: Double { sets.filter { $0.done }.reduce(0) { $0 + Double($1.reps) * $1.kg } }

    /// A set of this movement is normally done with a load, and none of its sets has one: the log is
    /// missing what was on the bar. False for a movement done with the body alone, and for one Luma
    /// does not know, where it cannot tell.
    public var needsLoad: Bool {
        guard sets.contains(where: { $0.hasContent }), sets.allSatisfy({ $0.kg <= 0 }) else { return false }
        return ExerciseLibrary.match(name)?.expectsLoad ?? false
    }

    /// An exercise typed in by hand: `count` sets alike, each of `amount` reps, metres, seconds or
    /// calories, at `kg` (0 for none). Nil when there is no name or nothing was counted.
    public static func typed(name: String, sets count: Int, amount: Double, measure: SetMeasure, kg: Double) -> LiftExercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, count >= 1, amount > 0, amount.isFinite else { return nil }
        let load = min(1000, max(0, kg.isFinite ? kg : 0))
        var set = LiftSet(reps: 0, kg: load, done: true)
        switch measure {
        case .reps: set.reps = min(1000, max(1, Int(amount.rounded())))
        case .meters: set.meters = min(100_000, amount)
        case .seconds: set.seconds = min(36_000, amount)
        case .calories: set.calories = min(5000, amount)
        }
        let sets: [LiftSet] = (0..<min(30, count)).map { _ in
            var copy = set
            copy.id = UUID()
            return copy
        }
        return LiftExercise(name: ExerciseLibrary.filedName(trimmed), sets: sets)
    }

    /// The done sets in a line: "4 × 5 × 100 kg" when they are all alike, each one listed otherwise.
    public var setsText: String {
        let done = sets.filter { $0.done && $0.hasContent }
        guard let first = done.first else { return "No sets" }
        let texts = done.map { $0.text }
        if texts.allSatisfy({ $0 == first.text }) { return done.count == 1 ? first.text : "\(done.count) × \(first.text)" }
        return texts.joined(separator: ", ")
    }
}

/// What was done in one training session: a strength session logged set by set, or a class, a HYROX
/// session or a conditioning piece read from a photo or told to the coach.
public struct LiftSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date?
    public var title: String
    public var exercises: [LiftExercise]
    public var note: String
    /// What kind of session it was; nil for logs made before sessions carried a kind (strength).
    public var kind: SessionKind?
    /// Where the log came from: "live" (logged set by set), "photo", "coach".
    public var source: String?
    /// File names of the photos the log was read from.
    public var photos: [String]?
    /// The workout as it was written on the board or screen, kept word for word.
    public var asWritten: String?

    public init(id: UUID = UUID(), start: Date = Date(), end: Date? = nil, title: String = "Strength", exercises: [LiftExercise] = [],
                note: String = "", kind: SessionKind? = nil, source: String? = nil, photos: [String]? = nil, asWritten: String? = nil) {
        self.id = id; self.start = start; self.end = end; self.title = title; self.exercises = exercises; self.note = note
        self.kind = kind; self.source = source; self.photos = photos; self.asWritten = asWritten
    }

    public var volumeKg: Double { exercises.reduce(0) { $0 + $1.volumeKg } }
    public var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count } }
    public var day: String { LDate.key(start) }
    public var resolvedKind: SessionKind { kind ?? .strength }
    /// How long the session ran, when both ends are known and differ.
    public var minutes: Double? { end.map { $0.timeIntervalSince(start) / 60 }.flatMap { $0 >= 1 ? $0 : nil } }
}

public enum LiftMath {
    /// Sets of more reps than this say little about a one-rep max, so they give no estimate.
    public static let maxRepsForEstimate = 12

    /// Estimated one-rep max (Epley). A single is its own max.
    public static func e1RM(kg: Double, reps: Int) -> Double { reps <= 1 ? kg : kg * (1 + Double(reps) / 30) }

    /// The one-rep max a done set stands for, or nil when it says nothing about one: no reps, more
    /// than `maxRepsForEstimate`, or no load. A lift that moves the body as well (a pull-up, a dip)
    /// is worked out on bodyweight plus whatever was added, so it needs no added load.
    public static func estimate(_ set: LiftSet, bodyweightLift: Bool, bodyKg: Double) -> Double? {
        guard set.done, set.reps > 0, set.reps <= maxRepsForEstimate else { return nil }
        let load = bodyweightLift ? bodyKg + set.kg : set.kg
        return load > 0 ? e1RM(kg: load, reps: set.reps) : nil
    }

    /// The best estimate among an exercise's sets.
    public static func best(_ e: LiftExercise, bodyKg: Double) -> Double? {
        let own = ExerciseLibrary.match(e.name)?.bodyweight ?? false
        return e.sets.compactMap { estimate($0, bodyweightLift: own, bodyKg: bodyKg) }.max()
    }

    /// Best estimated 1RM per exercise across sessions, with the day it was set.
    public static func records(_ sessions: [LiftSession], bodyKg: Double) -> [String: (e1RM: Double, day: String)] {
        var out: [String: (e1RM: Double, day: String)] = [:]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            for e in s.exercises {
                guard let best = best(e, bodyKg: bodyKg) else { continue }
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

    /// The load last used for an exercise, when one was written down.
    public static func lastLoad(_ name: String, in sessions: [LiftSession]) -> Double? {
        lastSets(name, in: sessions).map { $0.kg }.filter { $0 > 0 }.max()
    }

    public static let catalog: [String] = [
        "Back squat", "Front squat", "Deadlift", "Romanian deadlift", "Trap bar deadlift", "Bench press", "Overhead press",
        "Push press", "Pull-up", "Chin-up", "Barbell row", "Dumbbell row", "Hip thrust", "Bulgarian split squat",
        "Walking lunge", "Sandbag lunge", "Goblet squat", "Thruster", "Wall ball", "Kettlebell swing", "Farmers carry",
        "Sled push", "Sled pull", "Burpee broad jump", "Box jump", "Lat pulldown", "Dumbbell bench press", "Dip",
        "Face pull", "Plank", "Hanging leg raise", "Calf raise", "Hamstring curl", "Leg press",
    ]
}
