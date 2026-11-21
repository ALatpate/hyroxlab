import Foundation

// MARK: - Session load

public enum SessionLoad {
    /// Banister training impulse from average heart rate: minutes × ΔHR ratio × sex-specific weighting.
    public static func trimp(minutes: Double, avgHR: Double, restHR: Double, maxHR: Double, sex: Sex) -> Double? {
        guard minutes > 0, maxHR > restHR + 20, avgHR > restHR else { return nil }
        let x = LStat.clamp((avgHR - restHR) / (maxHR - restHR), 0, 1)
        let (a, b): (Double, Double) = sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        return minutes * x * a * exp(b * x)
    }

    /// Load from a 0–21 strain score when there is no heart-rate average: strain is log-compressed,
    /// so it is expanded back to a roughly additive scale that lines up with TRIMP.
    public static func fromStrain21(_ s: Double) -> Double {
        -log(1 - LStat.clamp(s, 0, 20.5) / 21.5) * 100
    }

    /// Duration-only fallback, in TRIMP-like points per minute by sport family.
    public static func fromDuration(minutes: Double, kind: LSportKind) -> Double {
        let perMin: Double
        switch kind {
        case .hyrox: perMin = 2.2
        case .run, .conditioning, .row: perMin = 1.6
        case .cycle, .swim: perMin = 1.3
        case .strength: perMin = 0.9
        case .walk, .mobility: perMin = 0.4
        case .other: perMin = 1.0
        }
        return minutes * perMin
    }

    public static func load(_ w: LWorkout, restHR: Double, maxHR: Double, sex: Sex) -> Double {
        let minutes = w.durationS / 60
        if let hr = w.avgHR, let t = trimp(minutes: minutes, avgHR: hr, restHR: restHR, maxHR: maxHR, sex: sex) { return t }
        if let s = w.strain, s > 0 { return fromStrain21(LScale.strain21(s)) }
        return fromDuration(minutes: minutes, kind: w.kind)
    }
}

// MARK: - Fitness / fatigue / form

public struct LoadDay: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let load: Double
    /// Fitness: 42-day exponentially weighted load.
    public let fitness: Double
    /// Fatigue: 7-day exponentially weighted load.
    public let fatigue: Double
    /// Form going into the day: yesterday's fitness minus yesterday's fatigue.
    public let form: Double
}

public enum LoadStatus: String, Codable, Sendable {
    case building, fresh, productive, pushing, spike

    public var title: String {
        switch self {
        case .building: return "Building a baseline"
        case .fresh: return "Fresh"
        case .productive: return "Productive"
        case .pushing: return "Pushing"
        case .spike: return "Load spike"
        }
    }
}

public struct LoadState: Equatable, Sendable {
    /// Contiguous days, oldest first, ending today.
    public let days: [LoadDay]
    /// Acute:chronic ratio (fatigue ÷ fitness). Kept for the record; nothing is judged by it any more,
    /// since the research found no support for it as a warning. The week is judged by `weekShare`.
    public let acwr: Double?
    /// The athlete's usual week: the middle one of the six weeks before this one. Nil with fewer than three.
    public let usualWeek: Double?
    /// Foster's monotony: mean ÷ SD of the last 7 daily loads. Above 2 means every day looks the same.
    public let monotony: Double?
    public let weekLoad: Double
    public let prevWeekLoad: Double
    /// Change in fitness over the last 7 days.
    public let ramp: Double?
    public let status: LoadStatus
    public let headline: String
    public let detail: String
    /// Enough history (4 weeks) for a week to be set against the usual one.
    public let ready: Bool
    public let historyDays: Int

    public var today: LoadDay? { days.last }
    public var weekChangePct: Double? { prevWeekLoad > 0 ? (weekLoad - prevWeekLoad) / prevWeekLoad * 100 : nil }
    /// This week's load as a share of the usual week: 1 is a usual week, 1.5 is half as much again.
    public var weekShare: Double? {
        guard let usual = usualWeek, usual > 0 else { return nil }
        return weekLoad / usual
    }
}

public enum LoadModel {
    public static let fitnessDays = 42.0
    public static let fatigueDays = 7.0
    public static let minimumHistory = 28

    /// Daily loads keyed by day, summed over the day's sessions.
    public static func dailyLoads(workouts: [LWorkout], restHR: Double, maxHR: Double, sex: Sex) -> [String: Double] {
        var out: [String: Double] = [:]
        for w in workouts { out[w.day, default: 0] += SessionLoad.load(w, restHR: restHR, maxHR: maxHR, sex: sex) }
        return out
    }

    public static func compute(loads: [String: Double], today: String, calendar: Calendar = LDate.calendar) -> LoadState {
        guard let first = loads.keys.min(), first <= today else {
            return LoadState(days: [], acwr: nil, usualWeek: nil, monotony: nil, weekLoad: 0, prevWeekLoad: 0, ramp: nil, status: .building,
                             headline: "No sessions yet", detail: "Record a few sessions and Luma will track how your training load is building.",
                             ready: false, historyDays: 0)
        }
        let span = max(1, LDate.daysBetween(first, today, calendar: calendar) + 1)
        let keys = LDate.range(ending: today, count: min(span, 400), calendar: calendar)
        var fitness = 0.0, fatigue = 0.0
        var days: [LoadDay] = []
        days.reserveCapacity(keys.count)
        for k in keys {
            let form = fitness - fatigue
            let l = loads[k] ?? 0
            fitness += (l - fitness) / fitnessDays
            fatigue += (l - fatigue) / fatigueDays
            days.append(LoadDay(day: k, load: l, fitness: fitness, fatigue: fatigue, form: form))
        }
        let last7 = days.suffix(7).map { $0.load }
        let prev7 = days.dropLast(7).suffix(7).map { $0.load }
        let week = last7.reduce(0, +), prevWeek = prev7.reduce(0, +)
        var monotony: Double?
        if last7.count == 7, let m = LStat.mean(last7), let s = LStat.sd(last7), s > 0 { monotony = m / s }
        let ready = span >= minimumHistory
        let acwr: Double? = fitness > 1 ? fatigue / fitness : nil
        let ramp: Double? = days.count > 7 ? fitness - days[days.count - 8].fitness : nil

        // The usual week: the middle one of up to six whole weeks before this one.
        var earlier: [Double] = []
        var rest = Array(days.dropLast(7))
        while rest.count >= 7, earlier.count < 6 {
            earlier.append(rest.suffix(7).reduce(0) { $0 + $1.load })
            rest.removeLast(7)
        }
        let usual: Double? = earlier.count >= 3 ? LStat.median(earlier).flatMap { $0 > 0 ? $0 : nil } : nil
        let share: Double? = usual.map { week / $0 }

        let status: LoadStatus
        let headline: String, detail: String
        if !ready {
            status = .building
            headline = "Building a baseline"
            detail = "\(span) of \(minimumHistory) days recorded. A week can be set against your usual one once four weeks of training are in."
        } else if share == nil {
            // The weeks before this one are empty or nearly so: there is no usual week to set this one against.
            status = week > 0 ? .building : .fresh
            headline = week > 0 ? "Building back" : "Fresh"
            detail = week > 0 ? "The weeks before this one hold too little training to set this week against. Build back gradually."
                              : "No training load in the last weeks. Fitness fades when that lasts, so start back gently."
        } else if let s = share, s > 1.5 {
            status = .spike
            headline = "Well above your usual week"
            detail = String(format: "This week's load is %.0f%% above your usual week. That is a lot to take on at once. A few steadier days let it settle.", (s - 1) * 100)
        } else if let s = share, s > 1.3 {
            status = .pushing
            headline = "Above your usual week"
            detail = "A heavier week than you are used to. Fine before an easier one, not for several in a row."
        } else if let s = share, s < 0.7 {
            status = .fresh
            headline = "Fresh"
            detail = "Load is well under your usual week. Good before a race or test; if it lasts beyond two weeks, fitness starts to fade."
        } else {
            status = .productive
            headline = "Productive"
            detail = "This week's load sits in the range your body is used to."
        }
        return LoadState(days: days, acwr: acwr, usualWeek: usual, monotony: monotony, weekLoad: week, prevWeekLoad: prevWeek, ramp: ramp,
                         status: status, headline: headline, detail: detail, ready: ready, historyDays: span)
    }

    /// Minutes per sport family over a day range, for the weekly mix.
    public static func minutesByKind(workouts: [LWorkout], from: String, to: String) -> [(kind: LSportKind, minutes: Double)] {
        var acc: [LSportKind: Double] = [:]
        for w in workouts where w.day >= from && w.day <= to { acc[w.kind, default: 0] += w.durationS / 60 }
        return acc.map { (kind: $0.key, minutes: $0.value) }.sorted { $0.minutes > $1.minutes }
    }

    /// Seconds in each of the five zones over a day range, from the sessions' zone percentages.
    public static func zoneSeconds(workouts: [LWorkout], from: String, to: String) -> [Double] {
        var z = [Double](repeating: 0, count: 5)
        for w in workouts where w.day >= from && w.day <= to {
            guard let p = w.zonePct, p.count == 5 else { continue }
            for i in 0..<5 { z[i] += w.durationS * p[i] / 100 }
        }
        return z
    }

    /// Share of training time that was easy (zones 1–2), moderate (zone 3) and hard (zones 4–5).
    public static func polarization(_ zoneSeconds: [Double]) -> (easy: Double, moderate: Double, hard: Double)? {
        let total = zoneSeconds.reduce(0, +)
        guard zoneSeconds.count == 5, total > 600 else { return nil }
        return ((zoneSeconds[0] + zoneSeconds[1]) / total, zoneSeconds[2] / total, (zoneSeconds[3] + zoneSeconds[4]) / total)
    }
}
