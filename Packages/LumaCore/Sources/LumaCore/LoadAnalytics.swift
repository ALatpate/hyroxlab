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
    /// Acute:chronic ratio (fatigue ÷ fitness). 0.8–1.3 is the range where load is building safely.
    public let acwr: Double?
    /// Foster's monotony: mean ÷ SD of the last 7 daily loads. Above 2 means every day looks the same.
    public let monotony: Double?
    public let weekLoad: Double
    public let prevWeekLoad: Double
    /// Change in fitness over the last 7 days.
    public let ramp: Double?
    public let status: LoadStatus
    public let headline: String
    public let detail: String
    /// Enough history (4 weeks) for the ratio to mean something.
    public let ready: Bool
    public let historyDays: Int

    public var today: LoadDay? { days.last }
    public var weekChangePct: Double? { prevWeekLoad > 0 ? (weekLoad - prevWeekLoad) / prevWeekLoad * 100 : nil }
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
            return LoadState(days: [], acwr: nil, monotony: nil, weekLoad: 0, prevWeekLoad: 0, ramp: nil, status: .building,
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

        let status: LoadStatus
        let headline: String, detail: String
        if !ready {
            status = .building
            headline = "Building a baseline"
            detail = "\(span) of \(minimumHistory) days recorded. The load ratio becomes meaningful once four weeks of training are in."
        } else if let a = acwr, a > 1.5 {
            status = .spike
            headline = "Load has spiked"
            detail = String(format: "This week's load is %.0f%% above what your body is used to. Jumps like this are where injuries and illness cluster. Hold volume steady for a few days.", (a - 1) * 100)
        } else if let a = acwr, a > 1.3 {
            status = .pushing
            headline = "Pushing above your base"
            detail = "You are overreaching on purpose. Fine for a week before an easier one, not for several in a row."
        } else if let a = acwr, a < 0.8 {
            status = .fresh
            headline = "Fresh"
            detail = "Load is well under your recent normal. Good before a race or test; if it lasts beyond two weeks, fitness starts to fade."
        } else {
            status = .productive
            headline = "Productive"
            detail = "Load is building at a rate your body is prepared for."
        }
        return LoadState(days: days, acwr: acwr, monotony: monotony, weekLoad: week, prevWeekLoad: prevWeek, ramp: ramp,
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
