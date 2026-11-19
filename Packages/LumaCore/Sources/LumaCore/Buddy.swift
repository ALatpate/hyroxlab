import Foundation

// MARK: - The companion

/// The states the companion can be in. Exactly one holds at a time, chosen in a fixed order
/// (`Buddy.look`), so the app's own character and every widget show the same one.
public enum BuddyMood: String, Codable, CaseIterable, Sendable {
    case waiting, training, sleeping, celebrating, worked, unwell, sleepy, thirsty, hungry, drained, steady, charged
}

/// How the companion looks at one moment: its state, the words that name it and the line that says why.
public struct BuddyLook: Codable, Equatable, Sendable {
    public let mood: BuddyMood
    public let title: String
    /// The fact behind the state, with its figure. The companion never looks a way the data does not show.
    public let line: String
    /// 0…1, from the recovery score: how lively it moves. Nil when today has no score.
    public let energy: Double?

    public init(mood: BuddyMood, title: String, line: String, energy: Double?) {
        self.mood = mood; self.title = title; self.line = line; self.energy = energy
    }
}

/// From `at` on, the companion looks like this, until the next moment.
public struct BuddyMoment: Codable, Equatable, Sendable {
    public let at: Date
    public let look: BuddyLook

    public init(at: Date, look: BuddyLook) { self.at = at; self.look = look }
}

/// A lift's best estimated max, set in a session logged today.
public struct BuddyBest: Equatable, Sendable {
    public let lift: String
    public let kg: Double
    public let at: Date

    public init(lift: String, kg: Double, at: Date) { self.lift = lift; self.kg = kg; self.at = at }
}

/// What the companion goes by. Every field is a figure some screen already shows; a field left nil
/// is not known, and the state that would need it is simply not reached.
public struct BuddyFacts: Equatable, Sendable {
    /// The training day (it turns over at 04:00) these facts belong to.
    public var day: String
    /// Today's recovery score, when last night was scored.
    public var recovery: Double?
    /// The day's call in a few words ("Green light").
    public var call: String?
    /// Why there is no score, in the words the recovery ring uses.
    public var noScore: String?
    /// Usual bed and wake times, minutes from the midnight inside the night (23:10 is −50).
    public var usualBedtime: Double?
    public var usualWake: Double?
    /// Lights-out that covers tonight's sleep need, on the same scale.
    public var bedtimeTonight: Double?
    /// A session being recorded now.
    public var sessionStart: Date?
    public var sessionTitle: String?
    /// The last finished session of the day, as "Class done, strain 12.4".
    public var lastSessionEnd: Date?
    public var lastSession: String?
    public var best: BuddyBest?
    /// The early-warning read's headline, when it is raised.
    public var unwell: String?
    public var waterMl: Double = 0
    public var waterTargetMl: Double = 0
    /// Water is being logged these days, so a low figure says something.
    public var waterLogged: Bool = false
    public var foodEntries: Int = 0
    public var foodLogged: Bool = false

    public init(day: String) { self.day = day }
}

public enum Buddy {
    /// How long a new best is celebrated, a finished session is cooled down from, and how far ahead of
    /// bedtime winding down starts.
    public static let celebrationHours = 3.0
    public static let cooldownMinutes = 75.0
    public static let windDownMinutes = 45.0
    /// A session said to be under way is believed for this long after it started.
    public static let sessionHours = 4.0

    /// The companion's state at `now`, from the facts. The order is the rule: what is happening now
    /// comes before how the body is, and how the body is comes before what the logs are missing.
    public static func look(_ facts: BuddyFacts, at now: Date, calendar: Calendar = LDate.calendar) -> BuddyLook {
        let f = onTheMinute(facts)
        let energy = f.recovery.map { LStat.clamp($0 / 100, 0, 1) }
        // The usual night, when `now` is inside it. It runs on past the turn of the day at 04:00, and the
        // companion sleeps through that, so the look is the same on both sides of it.
        var asleep: BuddyLook?
        if isUsualNight(f, at: now, calendar: calendar), let bed = f.usualBedtime, let wake = f.usualWake {
            let line = "Usual night: \(LFormat.timeOfDay(minutes: bed)) to \(LFormat.timeOfDay(minutes: wake))."
            asleep = BuddyLook(mood: .sleeping, title: "Asleep", line: line, energy: nil)
        }
        guard LumaAnalysis.todayKey(now: now, calendar: calendar) == f.day else {
            return asleep ?? BuddyLook(mood: .waiting, title: "Waiting", line: "Open Luma to bring today's numbers in.", energy: nil)
        }
        if let start = f.sessionStart, now >= start, now.timeIntervalSince(start) < sessionHours * 3600 {
            let what = f.sessionTitle.map { "\($0) under way." } ?? "A session is under way."
            return BuddyLook(mood: .training, title: "In session", line: what, energy: energy)
        }
        if let asleep { return asleep }
        if let best = f.best, now >= best.at, now.timeIntervalSince(best.at) < celebrationHours * 3600 {
            return BuddyLook(mood: .celebrating, title: "New best", line: "\(best.lift): est. max \(weight(best.kg)) kg.", energy: energy)
        }
        if let end = f.lastSessionEnd, now >= end, now.timeIntervalSince(end) < cooldownMinutes * 60 {
            return BuddyLook(mood: .worked, title: "Session done", line: f.lastSession ?? "Today's session is in.", energy: energy)
        }
        if let unwell = f.unwell {
            return BuddyLook(mood: .unwell, title: "Run down", line: unwell, energy: energy)
        }
        let clock = eveningMinutes(now, calendar: calendar)
        if let bed = f.bedtimeTonight ?? f.usualBedtime, bed - clock <= windDownMinutes {
            let line = "Lights out by \(LFormat.timeOfDay(minutes: bed)) covers tonight's sleep."
            return BuddyLook(mood: .sleepy, title: "Winding down", line: line, energy: energy)
        }
        // Minutes since the morning's midnight, running on past 24:00 until the day turns.
        let since = clock + 1440
        if f.waterLogged, f.waterTargetMl > 0, since >= 11 * 60, since < 22 * 60 {
            let start = f.usualWake ?? 7 * 60
            let end = 1440 + (f.usualBedtime ?? -60) - 60
            let through = end > start ? LStat.clamp((since - start) / (end - start), 0, 1) : 1
            if f.waterMl < through * f.waterTargetMl - 0.25 * f.waterTargetMl {
                let line = "\(litres(f.waterMl)) of \(litres(f.waterTargetMl)) L so far."
                return BuddyLook(mood: .thirsty, title: "Thirsty", line: line, energy: energy)
            }
        }
        if f.foodLogged, f.foodEntries == 0, since >= 13 * 60, since < 22 * 60 {
            return BuddyLook(mood: .hungry, title: "Hungry", line: "No food logged yet today.", energy: energy)
        }
        guard let score = f.recovery else {
            return BuddyLook(mood: .waiting, title: "No score yet", line: f.noScore ?? "Last night has not been scored yet.", energy: nil)
        }
        let figure = "Recovery \(LNum.int(score.rounded()))%." + (f.call.map { " \($0)." } ?? "")
        switch RecoveryBand.of(score) {
        case .high: return BuddyLook(mood: .charged, title: "Charged", line: figure, energy: energy)
        case .moderate: return BuddyLook(mood: .steady, title: "Steady", line: figure, energy: energy)
        case .low: return BuddyLook(mood: .drained, title: "Drained", line: figure, energy: energy)
        }
    }

    /// The companion's states from `now` until the morning after the day turns, each from the moment
    /// it begins. A widget shows the last moment that has begun, so it needs no rules of its own.
    public static func schedule(_ facts: BuddyFacts, from now: Date, calendar: Calendar = LDate.calendar) -> [BuddyMoment] {
        let f = onTheMinute(facts)
        var times: [Date] = [now]
        let midnight = LDate.startOfDay(LDate.adding(1, to: f.day, calendar: calendar), calendar: calendar)
        var horizon = now.addingTimeInterval(20 * 3600)
        if let midnight {
            let turn = midnight.addingTimeInterval(4 * 3600)
            let wake = midnight.addingTimeInterval((f.usualWake ?? 8 * 60) * 60)
            horizon = max(turn, wake).addingTimeInterval(120)
            times += [turn.addingTimeInterval(1), wake.addingTimeInterval(1)]
            for bed in [f.bedtimeTonight, f.usualBedtime].compactMap({ $0 }) {
                times += [midnight.addingTimeInterval((bed - windDownMinutes) * 60 + 1), midnight.addingTimeInterval(bed * 60 + 1)]
            }
        }
        horizon = min(horizon, now.addingTimeInterval(36 * 3600))
        if let best = f.best { times.append(best.at.addingTimeInterval(celebrationHours * 3600 + 1)) }
        if let end = f.lastSessionEnd { times.append(end.addingTimeInterval(cooldownMinutes * 60 + 1)) }
        if let start = f.sessionStart { times.append(start.addingTimeInterval(sessionHours * 3600 + 1)) }
        // Half-hour marks, for the states that grow with the clock (water falling behind, nothing eaten).
        let step = 1800.0
        var mark = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / step).rounded(.up) * step)
        while mark <= horizon { times.append(mark); mark = mark.addingTimeInterval(step) }

        var out: [BuddyMoment] = []
        for t in times.filter({ $0 >= now && $0 <= horizon }).sorted() {
            let l = look(f, at: t, calendar: calendar)
            if out.last?.look != l { out.append(BuddyMoment(at: t, look: l)) }
        }
        return out
    }

    /// The look to show at `date`: the last moment that has begun.
    public static func look(in moments: [BuddyMoment], at date: Date) -> BuddyLook? {
        (moments.last { $0.at <= date } ?? moments.first)?.look
    }

    /// The facts with their bed and wake times on whole minutes, as the lines print them. Those times
    /// are averages and seldom fall on a minute; the rule and the schedule both read them through this,
    /// so a change begins on the minute its own line names ("Usual night: 23:06" starts at 23:06).
    static func onTheMinute(_ f: BuddyFacts) -> BuddyFacts {
        var g = f
        g.usualBedtime = f.usualBedtime.map { $0.rounded() }
        g.usualWake = f.usualWake.map { $0.rounded() }
        g.bedtimeTonight = f.bedtimeTonight.map { $0.rounded() }
        return g
    }

    /// Whether `now` falls inside the athlete's usual night.
    static func isUsualNight(_ f: BuddyFacts, at now: Date, calendar: Calendar) -> Bool {
        guard let bed = f.usualBedtime, let wake = f.usualWake, wake > 0, wake < 15 * 60, wake - bed >= 180 else { return false }
        let m = clockMinutes(now, calendar: calendar)
        return m - 1440 >= bed || (m >= bed && m < wake)
    }

    /// Minutes from the midnight inside this training day's night: 23:00 is −60, 00:30 is 30.
    static func eveningMinutes(_ now: Date, calendar: Calendar) -> Double {
        let m = clockMinutes(now, calendar: calendar)
        return m >= 240 ? m - 1440 : m
    }

    /// The time of day in minutes, to the second, so that a moment the schedule sets just after a time
    /// is already past it when the rule is asked.
    static func clockMinutes(_ now: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    static func litres(_ ml: Double) -> String { String(format: "%.1f", ml / 1000) }
    static func weight(_ kg: Double) -> String { kg == kg.rounded() ? String(LNum.int(kg)) : String(format: "%.1f", kg) }
}

// MARK: - Its build

/// One part of the companion's body and the strength level it is drawn at.
public struct BuddyPart: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let title: String
    /// 0…5 on Luma's strength scale: the mean over the part's muscles that a graded lift measures.
    /// Nil when none is measured; the part is then drawn at the plain build, not as weak.
    public let level: Double?
    /// The lifts the level is read from.
    public let from: [String]

    public init(key: String, title: String, level: Double?, from: [String]) {
        self.key = key; self.title = title; self.level = level; self.from = from
    }
}

/// The companion's build: the athlete's own strength levels, part by part.
public struct BuddyBuild: Codable, Equatable, Sendable {
    public let parts: [BuddyPart]

    public init(parts: [BuddyPart]) { self.parts = parts }

    public func level(_ key: String) -> Double? { parts.first { $0.key == key }?.level }

    /// The levels in `Buddy.partKeys` order, −1 where a part is not measured.
    public var levels: [Double] { Buddy.partKeys.map { level($0) ?? -1 } }

    public var measured: Int { parts.filter { $0.level != nil }.count }
}

extension Buddy {
    public static let partKeys = ["shoulders", "chest", "back", "arms", "core", "legs"]

    static let partMuscles: [(key: String, title: String, muscles: [Muscle])] = [
        ("shoulders", "Shoulders", [.shoulders, .traps]),
        ("chest", "Chest", [.chest]),
        ("back", "Back", [.lats, .upperBack]),
        ("arms", "Arms", [.biceps, .triceps, .forearms]),
        ("core", "Core", [.abs, .obliques, .lowerBack]),
        ("legs", "Legs", [.quads, .hamstrings, .glutes, .adductors, .calves]),
    ]

    /// The build that goes with a training log. It reads the same muscle levels the body figure shows.
    public static func build(_ progress: TrainingProgress) -> BuddyBuild {
        BuddyBuild(parts: partMuscles.map { part in
            let states = part.muscles.map { progress.state($0) }
            let levels = states.compactMap { $0.level }
            var lifts: [String] = []
            for s in states { if let name = s.basis?.name, s.level != nil, !lifts.contains(name) { lifts.append(name) } }
            return BuddyPart(key: part.key, title: part.title, level: LStat.mean(levels), from: lifts)
        })
    }
}
