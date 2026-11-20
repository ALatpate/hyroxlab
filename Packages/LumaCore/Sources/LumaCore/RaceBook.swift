import Foundation

// MARK: - Racing a past effort, setting two efforts side by side, and keeping an official race
//
// Three things one session can be to another. While it runs, an earlier effort of the same shape is
// something to race (`RaceGhost`). Once it is done, the two are set side by side, line by line
// (`RaceComparison`). And a race that was run elsewhere, with a chip on the ankle, is typed in from
// its results page (`RaceEntry`) and kept as a session like any other, so everything that reads a
// simulation reads it too.

/// How far ahead of a set of segment times an effort is.
public enum RacePace {
    /// Seconds ahead (+) or behind (−) of `times` at this moment: what the segments now done were
    /// to take, plus as much of the current one as has been spent (never more than it was to take),
    /// less the time on the clock. It moves only at a changeover, or once the current segment has
    /// run past its time. Worked out from the plan each time, so undoing a changeover undoes it here.
    public static func lead(over times: [Int: Double], done: [PlannedSegment], current: PlannedSegment?, segmentElapsed: Double,
                            elapsed: Double) -> Double {
        let through = done.reduce(0.0) { $0 + (times[$1.id] ?? 0) }
        let now = current.flatMap { times[$0.id] }.map { min(max(0, segmentElapsed), $0) } ?? 0
        return through + now - elapsed
    }
}

/// A past effort to race against: what each segment of the same plan took.
public struct RaceGhost: Equatable, Sendable {
    public let sessionID: UUID
    public let startedAt: Date
    /// The official race it was, when it was one.
    public let event: String?
    /// Seconds each segment took, by its place in the plan (`PlannedSegment.id`).
    public let segments: [Int: Double]
    public let totalS: Double

    /// A finished session as something to race, when it timed every segment of `plan` in order.
    /// One that was ended early is not: there is nothing to race past the point it stopped.
    public init?(_ session: HXSession, plan: [PlannedSegment]) {
        guard session.isComplete, !plan.isEmpty, session.segments.count == plan.count, let total = session.totalS, total > 0 else { return nil }
        var seconds: [Int: Double] = [:]
        for (planned, done) in zip(plan, session.segments) {
            guard planned.id == done.id, planned.kind == done.kind, planned.station == done.station, let took = done.durationS else { return nil }
            seconds[planned.id] = took
        }
        sessionID = session.id
        startedAt = session.startedAt
        event = session.event
        segments = seconds
        totalS = total
    }

    /// Every past effort of this shape, newest first: the same kind of session in the same format
    /// (so the same loads), every segment timed.
    public static func efforts(like kind: HXSessionKind, format: RaceFormat, sex: Sex, plan: [PlannedSegment], in sessions: [HXSession]) -> [RaceGhost] {
        sessions.filter { $0.kind == kind && $0.format == format && $0.sex == sex }
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { RaceGhost($0, plan: plan) }
    }

    /// Seconds ahead (+) or behind (−) of the past effort at this moment.
    public func lead(done: [PlannedSegment], current: PlannedSegment?, segmentElapsed: Double, elapsed: Double) -> Double {
        RacePace.lead(over: segments, done: done, current: current, segmentElapsed: segmentElapsed, elapsed: elapsed)
    }
}

/// One line of an effort set beside an earlier one: a run, a station, or all the roxzone together.
public struct RaceDelta: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let kind: SegmentKind
    public let station: Station?
    public let seconds: Double
    public let thenS: Double

    /// Negative is faster than then.
    public var deltaS: Double { seconds - thenS }
}

/// An effort set beside an earlier one of the same shape.
public struct RaceComparison: Equatable, Sendable {
    public let thenID: UUID
    public let thenAt: Date
    /// The official race the earlier one was, when it was one.
    public let thenEvent: String?
    public let totalS: Double
    public let thenTotalS: Double
    /// The runs in order, then the stations in order, then the roxzone as one line.
    public let lines: [RaceDelta]

    /// Negative is faster than then.
    public var deltaS: Double { totalS - thenTotalS }

    /// Where the most time was won, largest first, at most three; a second either way is not a win.
    public var won: [RaceDelta] { Array(lines.filter { $0.deltaS <= -1 }.sorted { $0.deltaS < $1.deltaS }.prefix(3)) }
    /// Where the most time was lost, largest first, at most three.
    public var lost: [RaceDelta] { Array(lines.filter { $0.deltaS >= 1 }.sorted { $0.deltaS > $1.deltaS }.prefix(3)) }

    /// `now` set beside `then`, when the two are the same shape: the same kind of session in the same
    /// format, both finished, with the same runs and stations. Different loads are not compared.
    public static func of(_ now: HXSession, against then: HXSession) -> RaceComparison? {
        guard now.id != then.id, now.kind == then.kind, now.format == then.format, now.sex == then.sex, now.isComplete, then.isComplete,
              let total = now.totalS, let thenTotal = then.totalS else { return nil }
        let a = RaceAnalytics.report(now), b = RaceAnalytics.report(then)
        guard a.runs.count == b.runs.count, a.stations.map({ $0.station }) == b.stations.map({ $0.station }),
              !(a.runs.isEmpty && a.stations.isEmpty) else { return nil }
        var lines: [RaceDelta] = []
        for (x, y) in zip(a.runs, b.runs) {
            lines.append(RaceDelta(id: "run-\(x.index)", label: "Run \(x.index)", kind: .run, station: nil, seconds: x.seconds, thenS: y.seconds))
        }
        // The same station more than once (a practice of four efforts) is told apart by its turn.
        var turns: [Station: Int] = [:]
        let repeated = Set(a.stations.map { $0.station }).count < a.stations.count
        for (x, y) in zip(a.stations, b.stations) {
            let turn = (turns[x.station] ?? 0) + 1
            turns[x.station] = turn
            lines.append(RaceDelta(id: "station-\(x.station.rawValue)-\(turn)", label: repeated ? "\(x.station.title) \(turn)" : x.station.title,
                                   kind: .station, station: x.station, seconds: x.seconds, thenS: y.seconds))
        }
        if a.roxzoneTotalS > 0 || b.roxzoneTotalS > 0 {
            lines.append(RaceDelta(id: "roxzone", label: "Roxzone", kind: .roxzone, station: nil, seconds: a.roxzoneTotalS, thenS: b.roxzoneTotalS))
        }
        return RaceComparison(thenID: then.id, thenAt: then.startedAt, thenEvent: then.event, totalS: total, thenTotalS: thenTotal, lines: lines)
    }

    /// A session set beside the one before it of the same shape, when there is one.
    public static func withPrevious(_ session: HXSession, in sessions: [HXSession]) -> RaceComparison? {
        for earlier in sessions.filter({ $0.startedAt < session.startedAt }).sorted(by: { $0.startedAt > $1.startedAt }) {
            if let found = RaceComparison.of(session, against: earlier) { return found }
        }
        return nil
    }
}

// MARK: - A race typed in from its results page

/// Clock times as a results page writes them.
public enum SplitText {
    /// "4:35", "62:33", "1:02:33" or "00:04:35" as seconds; nil for anything else. Minutes may run
    /// past 59 only when no hours are given.
    public static func raceSeconds(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var values: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return nil }
            values.append(value)
        }
        let hours = values.count == 3 ? values[0] : 0
        let minutes = values[values.count - 2], seconds = values[values.count - 1]
        guard seconds < 60, values.count == 2 || minutes < 60, hours < 24 else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds)
    }

    /// A time as it is typed on a form: with its colons; with a full stop or a comma where a colon
    /// would be, which is all a number pad has; or as digits alone, the last two being seconds and the
    /// two before them minutes ("435" is 4:35, "10233" is 1:02:33). Nil until it reads as a time.
    public static func typedSeconds(_ text: String) -> Double? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.contains(":") { return raceSeconds(typed) }
        if typed.contains(".") || typed.contains(",") {
            return raceSeconds(typed.replacingOccurrences(of: ".", with: ":").replacingOccurrences(of: ",", with: ":"))
        }
        guard !typed.isEmpty, typed.count <= 6, typed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let digits = Array(typed)
        let seconds = Int(String(digits.suffix(2))) ?? 0
        let minutes = Int(String(digits.dropLast(2).suffix(2))) ?? 0
        let hours = Int(String(digits.dropLast(4))) ?? 0
        guard seconds < 60, minutes < 60 || digits.count <= 4 else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds)
    }

    /// Seconds as "4:35", or "1:02:33" from an hour up.
    public static func raceClock(_ seconds: Double) -> String {
        let whole = max(0, LNum.int(seconds.rounded()))
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        let tail = (s < 10 ? "0" : "") + String(s)
        if h > 0 { return "\(h):" + (m < 10 ? "0" : "") + "\(m):" + tail }
        return "\(m):" + tail
    }
}

/// An official race as its results page gives it: eight runs, eight stations, all the roxzone time
/// together and the finish time. Typed in, or read from a picture of the page and then checked.
public struct RaceEntry: Equatable, Sendable {
    public var event: String
    public var startedAt: Date
    public var format: RaceFormat
    public var sex: Sex
    /// The eight runs in order, in seconds; nil where none is entered yet.
    public var runs: [Double?]
    /// The eight stations in race order.
    public var stations: [Double?]
    /// All the roxzone time together.
    public var roxzoneS: Double?
    /// The finish time.
    public var finishS: Double?

    /// What a kilometre and a station can take, widely drawn: outside them a time is a slip of the finger.
    public static let runRange = 150.0...1500.0
    public static let stationRange = 20.0...1800.0
    public static let roxzoneLimit = 2400.0
    /// How far the splits may stand from the finish time, in seconds: a page rounds each to the second.
    public static let slack = 3.0

    public init(event: String = "", startedAt: Date, format: RaceFormat, sex: Sex) {
        self.event = event
        self.startedAt = startedAt
        self.format = format
        self.sex = sex
        runs = Array(repeating: nil, count: Station.allCases.count)
        stations = Array(repeating: nil, count: Station.allCases.count)
    }

    /// A race that was typed in, read back to be corrected. Nil for a session recorded live.
    public init?(_ session: HXSession) {
        guard let event = session.event, session.kind == .fullSimulation, session.isComplete else { return nil }
        let runs = session.runs.compactMap { $0.durationS }, stations = session.stations.compactMap { $0.durationS }
        guard runs.count == Station.allCases.count, stations.count == Station.allCases.count, let total = session.totalS else { return nil }
        self.event = event
        startedAt = session.startedAt
        format = session.format
        sex = session.sex
        self.runs = runs.map { Optional($0) }
        self.stations = stations.map { Optional($0) }
        roxzoneS = session.roxzones.compactMap { $0.durationS }.reduce(0, +).rounded()
        finishS = total.rounded()
    }

    /// The runs and stations together, once all sixteen are in.
    public var splitsS: Double? {
        let all = runs + stations
        guard !all.contains(where: { $0 == nil }) else { return nil }
        return all.compactMap { $0 }.reduce(0, +)
    }

    /// The roxzone time to go by: as entered, else what the finish time leaves once the runs and stations are out of it.
    public var roxzone: Double? {
        if let roxzoneS { return roxzoneS }
        guard let finishS, let splits = splitsS else { return nil }
        return finishS - splits
    }

    /// The finish time to go by: as entered, else the splits and the roxzone together.
    public var total: Double? {
        if let finishS { return finishS }
        guard let roxzoneS, let splits = splitsS else { return nil }
        return splits + roxzoneS
    }

    /// What is missing or does not add up, in plain words. Empty when the race can be kept.
    public var problems: [String] {
        var out: [String] = []
        let missing = runs.indices.filter { runs[$0] == nil }.map { "Run \($0 + 1)" }
            + stations.indices.filter { stations[$0] == nil }.map { Station.allCases[$0].title }
        if !missing.isEmpty { out.append("Still to enter: " + missing.joined(separator: ", ") + ".") }
        for (i, run) in runs.enumerated() {
            if let run, !RaceEntry.runRange.contains(run) { out.append("Run \(i + 1) reads \(SplitText.raceClock(run)), which is not a time for a kilometre.") }
        }
        for (i, station) in stations.enumerated() {
            if let station, !RaceEntry.stationRange.contains(station) {
                out.append("\(Station.allCases[i].title) reads \(SplitText.raceClock(station)), which is not a time for a station.")
            }
        }
        if roxzoneS == nil, finishS == nil { out.append("Enter the roxzone time or the finish time. Either is enough.") }
        if let roxzoneS, roxzoneS < 0 || roxzoneS > RaceEntry.roxzoneLimit { out.append("The roxzone time reads \(SplitText.raceClock(roxzoneS)), which is too long for the transitions of one race.") }
        if let splits = splitsS {
            if let roxzoneS, let finishS {
                if abs(splits + roxzoneS - finishS) > RaceEntry.slack {
                    out.append("The splits and the roxzone add up to \(SplitText.raceClock(splits + roxzoneS)) and the finish time is \(SplitText.raceClock(finishS)). One of them is mistyped.")
                }
            } else if let finishS, roxzoneS == nil {
                let left = finishS - splits
                if left < 0 {
                    out.append("The runs and stations add up to \(SplitText.raceClock(splits)), which is more than the finish time of \(SplitText.raceClock(finishS)).")
                } else if left > RaceEntry.roxzoneLimit {
                    out.append("The finish time leaves \(SplitText.raceClock(left)) for the roxzone, which is too long. One of the times is mistyped.")
                }
            }
        }
        return out
    }

    public var isReady: Bool { problems.isEmpty }

    /// The race as a session: a full race in its format, every segment timed, the roxzone shared
    /// evenly over its transitions because a results page gives only their total. Nil until the
    /// entry is ready.
    public func session(id: UUID = UUID()) -> HXSession? {
        guard isReady, let roxzone, let total else { return nil }
        let plan = RacePlanBuilder.fullRace(format: format, sex: sex)
        let transitions = plan.filter { $0.kind == .roxzone }.count
        let each = transitions > 0 ? max(0, roxzone) / Double(transitions) : 0
        var runsLeft = runs.compactMap { $0 }[...], stationsLeft = stations.compactMap { $0 }[...]
        var at = 0.0
        var segments: [HXSegment] = []
        for planned in plan {
            let took: Double
            switch planned.kind {
            case .run: took = runsLeft.popFirst() ?? 0
            case .station: took = stationsLeft.popFirst() ?? 0
            default: took = each
            }
            let start = Int64(LNum.int((at * 1000).rounded()))
            at += took
            segments.append(HXSegment(id: planned.id, kind: planned.kind, station: planned.station, label: planned.label, startMs: start,
                                      endMs: Int64(LNum.int((at * 1000).rounded())), distanceM: planned.distanceM, reps: planned.reps, loadKg: planned.loadKg))
        }
        let name = event.trimmingCharacters(in: .whitespacesAndNewlines)
        return HXSession(id: id, kind: .fullSimulation, format: format, sex: sex, startedAt: startedAt, endedAt: startedAt.addingTimeInterval(total),
                         segments: segments, event: name.isEmpty ? "Race" : String(name.prefix(60)))
    }
}

public extension Benchmarks {
    /// The bests as the sessions still kept give them, from nothing: what is left once a session has
    /// been removed or corrected.
    static func rebuilt(from sessions: [HXSession]) -> Benchmarks {
        var bests = Benchmarks()
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where session.isComplete { bests.ingest(session) }
        bests.updateRoxzone(from: sessions)
        return bests
    }
}

public extension HXSession {
    /// What to call it: the official race it was, else the kind of session.
    var title: String { event ?? kind.title }
    /// An official race typed in from its results page, not a session recorded here.
    var isOfficialRace: Bool { event != nil }
}

// MARK: - Reading a results page

public extension CoachTools {
    /// The stations by the names the reading tool uses, in race order.
    static let raceStationNames = ["ski_erg", "sled_push", "sled_pull", "burpee_broad_jump", "row", "farmers_carry", "sandbag_lunges", "wall_balls"]

    /// One call that carries a results page: what is on it, as it is written there.
    static func raceTool(name: String = "submit_race") -> AITool {
        let time = "exactly as the page shows it (h:mm:ss or m:ss). An empty string when it is not on the page or cannot be read"
        var stations: [String: JSONValue] = [:]
        for (key, station) in zip(raceStationNames, Station.allCases) { stations[key] = AISchema.string("\(station.title), \(time)") }
        return AITool(name: name, description: "Record one athlete's official HYROX race result as its results page shows it: the eight run splits, the eight station times, the roxzone time and the finish time.", properties: [
            "event": AISchema.string("The race as the page names it, e.g. \"HYROX Dublin\". Omit when the page does not say."),
            "date": AISchema.string("Race day as YYYY-MM-DD. Omit when the page does not say."),
            "division": AISchema.string("The division raced, when the page says", enum: RaceFormat.allCases.map { $0.rawValue }),
            "runs": AISchema.array("Running 1 to Running 8, in order, eight entries", items: AISchema.string("A run split, \(time)")),
            "stations": AISchema.object(stations, required: raceStationNames),
            "roxzone": AISchema.string("Roxzone Time, \(time)"),
            "finish": AISchema.string("The overall finish time, \(time)"),
        ], required: ["runs", "stations"])
    }

    /// What a reading of a results page gave, as an entry to check: every time that was read is
    /// filled in, and nothing is made up for one that was not. The athlete's own format and the day
    /// stand in where the page said neither.
    static func raceEntry(_ input: JSONValue, format: RaceFormat, sex: Sex, now: Date, calendar: Calendar = LDate.calendar) -> RaceEntry {
        let day = input["date"]?.string.flatMap { LDate.date($0, calendar: calendar) }.map { calendar.date(byAdding: .hour, value: 9, to: $0) ?? $0 }
        var entry = RaceEntry(event: String((input["event"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)),
                              startedAt: day.map { min($0, now) } ?? now,
                              format: input["division"]?.string.flatMap { RaceFormat(rawValue: $0) } ?? format, sex: sex)
        for (i, run) in (input["runs"]?.array ?? []).prefix(entry.runs.count).enumerated() { entry.runs[i] = run.string.flatMap { SplitText.raceSeconds($0) } }
        for (i, key) in raceStationNames.enumerated() { entry.stations[i] = input["stations"]?[key]?.string.flatMap { SplitText.raceSeconds($0) } }
        entry.roxzoneS = input["roxzone"]?.string.flatMap { SplitText.raceSeconds($0) }
        entry.finishS = input["finish"]?.string.flatMap { SplitText.raceSeconds($0) }
        return entry
    }
}

public extension CoachPrompt {
    /// Instructions for a one-shot read of a results page into a race to check.
    static let raceExtraction = """
        You read a photo or a screenshot of one athlete's official HYROX race result for a training app. Respond only by calling the tool provided; do not write prose unless no result is visible, in which case say in one sentence what is missing.

        - Copy every time exactly as the page shows it. Never work a time out, round it or estimate one that is not there: leave it empty.
        - The page lists Running 1 to Running 8 and the eight stations in race order: 1000 m SkiErg, 50 m Sled Push, 50 m Sled Pull, 80 m Burpee Broad Jump, 1000 m Row, 200 m Farmers Carry, 100 m Sandbag Lunges, Wall Balls. It also gives Roxzone Time and the overall time.
        - Run Total, Best Run Lap, ranks, age group and other athletes are not asked for. Do not put them anywhere.
        - Several pictures may show parts of the same result: put them together into one.
        """
}
