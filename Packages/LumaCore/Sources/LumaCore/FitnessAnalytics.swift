import Foundation

public struct LDatedValue: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let value: Double
    public init(day: String, value: Double) { self.day = day; self.value = value }
}

// MARK: - Trends in nightly signals

/// Whether a metric has genuinely moved over the last four weeks, or is just bouncing around.
public struct TrendRead: Equatable, Sendable, Identifiable {
    public var id: String { metric.rawValue }
    public let metric: LMetric
    /// Robust slope, in the metric's units per week.
    public let perWeek: Double
    /// Mann–Kendall p-value for a monotonic trend.
    public let p: Double
    /// Mean of the last 7 readings and of the 28 before them.
    public let recent: Double
    public let prior: Double
    public let count: Int

    /// +1 rising, −1 falling, 0 no reliable trend.
    public var direction: Int {
        guard p < 0.05 else { return 0 }
        return perWeek > 0 ? 1 : (perWeek < 0 ? -1 : 0)
    }
    /// Whether the movement is in the good direction (nil when there is none, or direction carries no judgement).
    public var improving: Bool? {
        guard direction != 0, let better = metric.higherIsBetter else { return nil }
        return better == (direction > 0)
    }
    public var changePct: Double { prior != 0 ? (recent - prior) / abs(prior) * 100 : 0 }

    public var sentence: String {
        let name = metric.title
        guard direction != 0 else { return "\(name) is steady: \(metric.show(recent)) this week against \(metric.format(prior)) before." }
        let verb = direction > 0 ? "rising" : "falling"
        return "\(name) has been \(verb) for four weeks, about \(metric.gap(abs(perWeek))) per week. This week averages \(metric.format(recent)) against \(metric.format(prior)) before."
    }
}

public enum TrendModel {
    public static func read(_ metric: LMetric, days: [LDay], today: String, calendar: Calendar = LDate.calendar) -> TrendRead? {
        let s = LumaAnalysis.series(metric, days: days, ending: today, count: 35, calendar: calendar)
        let last28 = Array(s.values.suffix(28)).compactMap { $0 }
        let recent = Array(s.values.suffix(7)).compactMap { $0 }
        let prior = Array(s.values.prefix(28)).compactMap { $0 }
        guard last28.count >= 14, recent.count >= 4, prior.count >= 10,
              let ts = LStat.theilSen(last28), let mk = LStat.mannKendall(last28),
              let r = LStat.mean(recent), let p = LStat.mean(prior) else { return nil }
        return TrendRead(metric: metric, perWeek: ts.slope * 7, p: mk.p, recent: r, prior: p, count: last28.count)
    }

    public static func all(days: [LDay], today: String, calendar: Calendar = LDate.calendar) -> [TrendRead] {
        [LMetric.hrv, .restingHR, .recovery, .sleepHours, .respRate, .strain].compactMap { read($0, days: days, today: today, calendar: calendar) }
    }
}

// MARK: - Aerobic fitness

public struct FitnessState: Equatable, Sendable {
    /// Estimated VO₂max, ml/kg/min.
    public var vo2max: Double?
    public var vo2maxFromRuns: Bool
    /// Per-run estimates, oldest first.
    public var vo2maxHistory: [LDatedValue]
    /// Critical speed (m/s): the fastest pace sustainable without drifting, from personal bests.
    public var criticalSpeed: Double?
    /// Metres of work available above critical speed.
    public var dPrime: Double?
    /// Running economy per run: metres per minute per heartbeat-per-minute, oldest first.
    public var efficiency: [LDatedValue]
    /// Change in running economy over the last eight weeks, percent.
    public var efficiencyChangePct: Double?
    /// Highest heart rate seen in a session in the last six months.
    public var observedMaxHR: Double?
    public var predictions: [PersonalBest]

    public static let empty = FitnessState(vo2max: nil, vo2maxFromRuns: false, vo2maxHistory: [], criticalSpeed: nil, dPrime: nil,
                                           efficiency: [], efficiencyChangePct: nil, observedMaxHR: nil, predictions: [])
}

public enum FitnessModel {
    /// VO₂max from one steady run: oxygen cost of the pace (ACSM level-running equation), scaled up by
    /// how much of the heart-rate reserve the run used. Only trusted between 55 and 95 % of reserve.
    public static func vo2max(distanceM: Double, seconds: Double, avgHR: Double, restHR: Double, maxHR: Double) -> Double? {
        guard seconds >= 720, distanceM >= 2000, maxHR > restHR + 30 else { return nil }
        let pace = seconds / (distanceM / 1000)
        guard pace >= 170, pace <= 480 else { return nil }
        let reserve = (avgHR - restHR) / (maxHR - restHR)
        guard reserve >= 0.55, reserve <= 0.95 else { return nil }
        let cost = 0.2 * (distanceM / (seconds / 60)) + 3.5
        return LStat.clamp(3.5 + (cost - 3.5) / reserve, 20, 85)
    }

    /// Resting estimate (Uth et al.): 15.3 × max HR ÷ resting HR. Coarse; used until runs exist.
    public static func vo2maxResting(restHR: Double, maxHR: Double) -> Double? {
        guard restHR > 30, maxHR > restHR else { return nil }
        return LStat.clamp(15.3 * maxHR / restHR, 20, 85)
    }

    /// Rough fitness band for an adult of this age and sex (after ACSM percentile tables).
    public static func category(vo2max: Double, age: Int, sex: Sex) -> String {
        let decade = Double(max(20, min(69, age)) - 20) / 10
        let good = (sex == .male ? 44.0 : 38.0) - decade * 3.3
        let delta = vo2max - good
        return delta >= 9 ? "Superior" : delta >= 4 ? "Excellent" : delta >= 0 ? "Good" : delta >= -5 ? "Fair" : "Below average"
    }

    /// Critical speed and D′ from personal bests lasting 2–30 minutes: distance = CS × time + D′.
    public static func criticalSpeed(_ pbs: [PersonalBest]) -> (cs: Double, dPrime: Double)? {
        let usable = pbs.filter { $0.seconds >= 120 && $0.seconds <= 1900 }
        guard usable.count >= 2 else { return nil }
        let t = usable.map { $0.seconds }, d = usable.map { $0.distanceM }
        if usable.count == 2 {
            guard t[1] != t[0] else { return nil }
            let cs = (d[1] - d[0]) / (t[1] - t[0])
            return cs > 1.5 && cs < 7.5 ? (cs, max(0, d[0] - cs * t[0])) : nil
        }
        guard let fit = LStat.linearFit(t, d), fit.slope > 1.5, fit.slope < 7.5 else { return nil }
        return (fit.slope, max(0, fit.intercept))
    }

    public static func build(workouts: [LWorkout], pbs: [PersonalBest], restHR: Double, maxHR: Double, today: String,
                             calendar: Calendar = LDate.calendar) -> FitnessState {
        var state = FitnessState.empty
        let runs = workouts.filter { $0.kind == .run }.sorted { $0.start < $1.start }
        var history: [LDatedValue] = [], economy: [LDatedValue] = []
        for r in runs {
            guard let d = r.distanceM, let hr = r.avgHR, hr > 80, r.durationS >= 600 else { continue }
            if let v = vo2max(distanceM: d, seconds: r.durationS, avgHR: hr, restHR: restHR, maxHR: maxHR) {
                history.append(LDatedValue(day: r.day, value: v))
            }
            economy.append(LDatedValue(day: r.day, value: (d / (r.durationS / 60)) / hr))
        }
        state.vo2maxHistory = history
        state.efficiency = economy
        let cutoff = LDate.adding(-60, to: today, calendar: calendar)
        let recent = history.filter { $0.day >= cutoff }.suffix(6).map { $0.value }
        if recent.count >= 2, let m = LStat.median(Array(recent)) {
            state.vo2max = m; state.vo2maxFromRuns = true
        } else {
            state.vo2max = vo2maxResting(restHR: restHR, maxHR: maxHR)
        }
        let eight = LDate.adding(-56, to: today, calendar: calendar)
        let window = economy.filter { $0.day >= eight }.map { $0.value }
        if window.count >= 5, let ts = LStat.theilSen(window), let first = window.first, first > 0 {
            state.efficiencyChangePct = ts.slope * Double(window.count - 1) / first * 100
        }
        let half = LDate.adding(-183, to: today, calendar: calendar)
        state.observedMaxHR = workouts.filter { $0.day >= half }.compactMap { $0.maxHR }.max()
        if let cs = criticalSpeed(pbs) { state.criticalSpeed = cs.cs; state.dPrime = cs.dPrime }
        if !pbs.isEmpty {
            let k = RunPredictor.fitExponent(pbs) ?? 1.06
            if let anchor = pbs.filter({ $0.distanceM >= 3000 }).max(by: { $0.distanceM < $1.distanceM }) ?? pbs.last {
                state.predictions = [5000.0, 10000, 21097, 42195].map {
                    PersonalBest(distanceM: $0, seconds: RunPredictor.predict(fromDistanceM: anchor.distanceM, timeS: anchor.seconds, toDistanceM: $0, exponent: k))
                }
            }
        }
        return state
    }
}
