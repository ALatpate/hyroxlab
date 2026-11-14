import Foundation

// MARK: - Plan model

public enum PlannedSessionType: String, Codable, CaseIterable, Sendable {
    case gymClass          // coach-led strength + conditioning (UN1T)
    case easyRun, thresholdRun, intervalRun, longRun, compromisedRun
    case fullSimulation, halfSimulation, stationPractice
    case rest

    public var title: String {
        switch self {
        case .gymClass: return "Gym class"
        case .easyRun: return "Easy run"
        case .thresholdRun: return "Threshold run"
        case .intervalRun: return "Run intervals"
        case .longRun: return "Long run"
        case .compromisedRun: return "Compromised running"
        case .fullSimulation: return "Full simulation"
        case .halfSimulation: return "Half simulation"
        case .stationPractice: return "Station practice"
        case .rest: return "Rest"
        }
    }
    public var isRun: Bool {
        switch self {
        case .easyRun, .thresholdRun, .intervalRun, .longRun, .compromisedRun: return true
        default: return false
        }
    }
    public var isHard: Bool {
        switch self {
        case .thresholdRun, .intervalRun, .compromisedRun, .fullSimulation, .halfSimulation: return true
        default: return false
        }
    }
}

public struct PlannedSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var type: PlannedSessionType
    public var title: String
    /// One line on why this session is here.
    public var purpose: String
    /// Structured detail the Go tab can start directly.
    public var detail: String
    public var targetPaceSPerKm: Double?
    public var targetZone: Int?
    public var durationMin: Int
    public var completedSessionID: UUID?
    public var skipped: Bool

    public init(id: UUID = UUID(), date: Date, type: PlannedSessionType, title: String, purpose: String, detail: String,
                targetPaceSPerKm: Double? = nil, targetZone: Int? = nil, durationMin: Int, completedSessionID: UUID? = nil, skipped: Bool = false) {
        self.id = id; self.date = date; self.type = type; self.title = title; self.purpose = purpose; self.detail = detail
        self.targetPaceSPerKm = targetPaceSPerKm; self.targetZone = targetZone; self.durationMin = durationMin
        self.completedSessionID = completedSessionID; self.skipped = skipped
    }
}

/// What the generator needs to know about the athlete and their week.
public struct PlanProfile: Codable, Equatable, Sendable {
    /// Weekday numbers (1 = Sunday … 7 = Saturday, Calendar.component(.weekday)) the athlete is in class.
    public var classWeekdays: Set<Int>
    /// Current 5 km time in seconds (measured or estimated).
    public var fiveKSeconds: Double
    public var targetFormat: RaceFormat
    public var raceDate: Date?
    /// Runs the athlete is willing to do per week in addition to classes.
    public var runsPerWeek: Int
    public var weakestStations: [Station]

    public init(classWeekdays: Set<Int> = [2, 3, 4, 5, 6], fiveKSeconds: Double = 25 * 60, targetFormat: RaceFormat = .openSingles,
                raceDate: Date? = nil, runsPerWeek: Int = 3, weakestStations: [Station] = []) {
        self.classWeekdays = classWeekdays; self.fiveKSeconds = fiveKSeconds; self.targetFormat = targetFormat
        self.raceDate = raceDate; self.runsPerWeek = runsPerWeek; self.weakestStations = weakestStations
    }
}

// MARK: - Pace model

/// Training paces from a 5 km time (Daniels-style ratios, seconds per km).
public struct TrainingPaces: Equatable, Sendable {
    public let easy: Double
    public let threshold: Double
    public let interval: Double
    /// Race-effort 1 km pace inside a HYROX, i.e. slightly slower than 5 km pace.
    public let hyroxRace: Double

    public init(fiveKSeconds: Double) {
        let p5 = fiveKSeconds / 5
        easy = p5 * 1.30
        threshold = p5 * 1.08
        interval = p5 * 0.98
        hyroxRace = p5 * 1.10
    }
}

// MARK: - Generator

public enum PlanGenerator {
    public enum Block: String, Codable, Sendable { case base, build, peak, taper, maintain }

    /// Which block a week falls in given weeks to race (nil race date → maintain).
    public static func block(weeksToRace: Int?) -> Block {
        guard let w = weeksToRace else { return .maintain }
        switch w {
        case ..<0: return .maintain
        case 0...1: return .taper
        case 2...4: return .peak
        case 5...8: return .build
        default: return .base
        }
    }

    /// Generates one week starting at `weekStart` (a Monday). Classes are fixed; runs and HYROX work
    /// fill the remaining days. `readiness` (0–100) below 55 downgrades the hard session of the week.
    public static func week(starting weekStart: Date, profile p: PlanProfile, readiness: Int?, calendar: Calendar = .current) -> [PlannedSession] {
        let paces = TrainingPaces(fiveKSeconds: p.fiveKSeconds)
        let weeksToRace: Int? = p.raceDate.map { calendar.dateComponents([.weekOfYear], from: weekStart, to: $0).weekOfYear ?? 0 }
        let blk = block(weeksToRace: weeksToRace)
        let lowReadiness = (readiness ?? 100) < 55

        var days: [(date: Date, weekday: Int, isClass: Bool)] = []
        for i in 0..<7 {
            let d = calendar.date(byAdding: .day, value: i, to: weekStart)!
            let wd = calendar.component(.weekday, from: d)
            days.append((d, wd, p.classWeekdays.contains(wd)))
        }

        var out: [PlannedSession] = []
        // 1. Classes.
        for d in days where d.isClass {
            out.append(PlannedSession(date: d.date, type: .gymClass, title: "UN1T class",
                                      purpose: "Strength and station work — log it from the whiteboard photo after.",
                                      detail: "Coach-led. Photograph the board and send it to the coach to log.", durationMin: 50))
        }

        // 2. Runs: short runs can share a day with a class (after it); the long run and the
        //    simulation take the free days.
        let freeDays = days.filter { !$0.isClass }.map(\.date)
        var runSlots: [Date] = freeDays
        // Add class days spaced out (Tue/Thu style) for short runs when free days are scarce.
        let classDays = days.filter { $0.isClass }.map(\.date)
        for (i, d) in classDays.enumerated() where i % 2 == 0 { runSlots.append(d) }
        runSlots.sort()

        var runPlan: [PlannedSessionType] = []
        switch blk {
        case .base: runPlan = [.easyRun, .thresholdRun, .longRun]
        case .build: runPlan = [.intervalRun, .compromisedRun, .longRun]
        case .peak: runPlan = [.compromisedRun, .thresholdRun, .longRun]
        case .taper: runPlan = [.easyRun, .intervalRun]
        case .maintain: runPlan = [.easyRun, .thresholdRun, .longRun]
        }
        runPlan = Array(runPlan.prefix(max(1, p.runsPerWeek)))
        if lowReadiness, let idx = runPlan.firstIndex(where: { $0.isHard }) { runPlan[idx] = .easyRun }

        // Long run goes on the last free day; the rest fill from the first free day.
        var slots = runSlots
        if let li = runPlan.firstIndex(of: .longRun), let lastFree = freeDays.last {
            out.append(session(.longRun, on: lastFree, paces: paces, blk: blk))
            runPlan.remove(at: li)
            slots.removeAll { calendar.isDate($0, inSameDayAs: lastFree) }
        }
        for t in runPlan {
            guard let d = slots.first else { break }
            slots.removeFirst()
            out.append(session(t, on: d, paces: paces, blk: blk))
        }

        // 3. HYROX work: a simulation every other week in build/peak, half-sim otherwise; station
        //    practice on the weakest station when there is a spare slot.
        let weekNumber = calendar.component(.weekOfYear, from: weekStart)
        if let simDay = freeDays.first(where: { d in !out.contains { calendar.isDate($0.date, inSameDayAs: d) && $0.type == .longRun } }) {
            let type: PlannedSessionType
            switch blk {
            case .build, .peak: type = weekNumber % 2 == 0 ? .fullSimulation : .halfSimulation
            case .taper: type = .halfSimulation
            default: type = weekNumber % 3 == 0 ? .halfSimulation : .stationPractice
            }
            if !(lowReadiness && type == .fullSimulation) {
                out.append(session(type, on: simDay, paces: paces, blk: blk, station: p.weakestStations.first))
            }
        }

        // 4. Anything left is rest.
        for d in days where !out.contains(where: { calendar.isDate($0.date, inSameDayAs: d.date) }) {
            out.append(PlannedSession(date: d.date, type: .rest, title: "Rest", purpose: "Adaptation happens here.", detail: "Walk, mobility, sleep.", durationMin: 0))
        }
        return out.sorted { $0.date < $1.date }
    }

    private static func session(_ t: PlannedSessionType, on d: Date, paces: TrainingPaces, blk: Block, station: Station? = nil) -> PlannedSession {
        switch t {
        case .easyRun:
            return PlannedSession(date: d, type: t, title: "Easy run 40 min", purpose: "Aerobic base; conversational the whole way.",
                                  detail: "40 min at easy pace, zone 2.", targetPaceSPerKm: paces.easy, targetZone: 2, durationMin: 40)
        case .thresholdRun:
            return PlannedSession(date: d, type: t, title: "Threshold 3 × 8 min", purpose: "Raises the pace you can hold for 8 × 1 km.",
                                  detail: "10 min easy · 3 × 8 min at threshold, 2 min jog · 10 min easy.", targetPaceSPerKm: paces.threshold, targetZone: 4, durationMin: 50)
        case .intervalRun:
            return PlannedSession(date: d, type: t, title: "Intervals 6 × 1 km", purpose: "Race-pace repeats with short rest, like the race.",
                                  detail: "10 min easy · 6 × 1 km at interval pace, 90 s jog · 10 min easy.", targetPaceSPerKm: paces.interval, targetZone: 5, durationMin: 55)
        case .longRun:
            let mins = blk == .taper ? 50 : 75
            return PlannedSession(date: d, type: t, title: "Long run \(mins) min", purpose: "Durability for the back half of the race.",
                                  detail: "\(mins) min easy; last 10 min at HYROX race pace.", targetPaceSPerKm: paces.easy, targetZone: 2, durationMin: mins)
        case .compromisedRun:
            let st = station ?? .wallBalls
            return PlannedSession(date: d, type: t, title: "Compromised 4 × (\(st.shortTitle) + 1 km)", purpose: "Teaches the legs to run straight off a station.",
                                  detail: "4 rounds: \(st.title) at race load, then 1 km at HYROX race pace. 2 min rest.", targetPaceSPerKm: paces.hyroxRace, targetZone: 4, durationMin: 45)
        case .fullSimulation:
            return PlannedSession(date: d, type: t, title: "Full simulation", purpose: "The only true rehearsal; feeds pacing and race readiness.",
                                  detail: "8 × (1 km + station) at race loads. Race mode, hands-free.", targetPaceSPerKm: paces.hyroxRace, durationMin: 90)
        case .halfSimulation:
            return PlannedSession(date: d, type: t, title: "Half simulation", purpose: "Race rehearsal at half the fatigue cost.",
                                  detail: "Stations 1–4 or 5–8 with their runs, race loads.", targetPaceSPerKm: paces.hyroxRace, durationMin: 50)
        case .stationPractice:
            let st = station ?? .sledPush
            return PlannedSession(date: d, type: t, title: "\(st.title) practice", purpose: "Your weakest station gets its own session.",
                                  detail: "4 × \(st.measure.label) at race load, 3 min rest.", durationMin: 35)
        case .gymClass, .rest:
            return PlannedSession(date: d, type: t, title: t.title, purpose: "", detail: "", durationMin: 0)
        }
    }
}
