import Foundation

// MARK: - What moves your numbers

/// A habit or circumstance compared against the nights without it.
public struct EffectFinding: Equatable, Sendable, Identifiable {
    public var id: String { "\(factorKey)|\(outcome.rawValue)" }
    public let factorKey: String
    public let factor: String
    /// The factor as it reads after the word "After".
    public let phrase: String
    public let outcome: LMetric
    public let withMean: Double
    public let withoutMean: Double
    /// withMean − withoutMean, in the outcome's units.
    public let delta: Double
    /// Hedges' g: the difference in units of night-to-night spread.
    public let g: Double
    public let p: Double
    public let nWith: Int
    public let nWithout: Int
    /// Survives false-discovery control across everything tested.
    public let reliable: Bool

    public var pct: Double { withoutMean != 0 ? delta / abs(withoutMean) * 100 : 0 }

    /// Whether the factor moves the outcome in the good direction.
    public var helps: Bool? { outcome.higherIsBetter.map { $0 == (delta > 0) } }

    public var sentence: String {
        // The difference is worded as it reads from the two averages printed after it.
        let shown = outcome.shownDifference(withMean, withoutMean)
        let size = shown != 0 ? shown : delta
        let dir = size > 0 ? "higher" : "lower"
        let certainty = reliable ? "" : " Early signal: too few nights to be sure."
        return "After \(phrase), your \(outcome.phrase) runs \(outcome.gap(abs(size))) \(dir) (\(outcome.format(withMean)) vs \(outcome.format(withoutMean)), \(nWith) and \(nWithout) nights).\(certainty)"
    }
}

/// Two daily numbers that move together.
public struct LinkFinding: Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let xLabel: String
    public let yLabel: String
    /// Spearman rank correlation.
    public let r: Double
    public let p: Double
    public let n: Int
    public let reliable: Bool
    public let xs: [Double]
    public let ys: [Double]
    public let sentence: String
}

/// A habit or circumstance, as the set of days it applied to.
public struct EffectFactor: Sendable {
    public let key: String
    public let title: String
    /// How it reads after the word "After".
    public let phrase: String
    public let days: Set<String>
    /// The days on which it is known whether the factor applied. A habit read from a log is only
    /// known on days that have the log; nil means every day with strap data.
    public let known: Set<String>?
}

public enum EffectModel {
    public static let minimumWith = 4
    public static let minimumWithout = 8
    /// Caffeine from this hour of the day counts as late; a meal from `lateMealHour` does.
    public static let lateCaffeineHour = 14
    public static let lateMealHour = 21

    /// Named day sets: what the athlete ticked in a check-in or logged in the food and supplement
    /// logs, plus circumstances derived from the strap data itself. A factor on day D is tested
    /// against the night that ends on D+1.
    ///
    /// Alcohol, late caffeine and a late meal can be ticked in a check-in or read from the food log;
    /// either way they are one habit, so each is one factor fed by both.
    public static func factors(days: [LDay], checkIns: [CheckIn], workouts: [LWorkout], fuel: [FuelEntry] = [],
                               supplements: [SupplementPlan] = [], profile: LProfile? = nil,
                               calendar: Calendar = LDate.calendar) -> [EffectFactor] {
        var out: [EffectFactor] = []
        let checked = Set(checkIns.map { $0.day })
        let food = fuel.filter { $0.kind != .water && $0.kind != .supplement }
        let foodByDay = Dictionary(grouping: food, by: { $0.day })
        let foodDays = Set(foodByDay.keys)
        func hour(_ e: FuelEntry) -> Int { calendar.component(.hour, from: e.at) }
        var fromLog: [CheckInTag: Set<String>] = [:]
        fromLog[.alcohol] = Set(food.filter { $0.alcoholG > 0 }.map { $0.day })
        fromLog[.lateCaffeine] = Set(food.filter { $0.caffeineMg > 0 && hour($0) >= lateCaffeineHour }.map { $0.day })
        fromLog[.lateMeal] = Set(food.filter { $0.kind != .drink && $0.kcal >= 200 && hour($0) >= lateMealHour }.map { $0.day })
        for tag in CheckInTag.allCases {
            let ticked = Set(checkIns.filter { $0.tags.contains(tag) }.map { $0.day })
            let logged = fromLog[tag]
            let set = ticked.union(logged ?? [])
            // A check-in answers for every tag; the food log answers only for what it can show.
            let known = logged == nil ? checked : checked.union(foodDays)
            if !set.isEmpty { out.append(EffectFactor(key: tag.rawValue, title: tag.title, phrase: tag.phrase, days: set, known: known)) }
        }
        if let profile {
            // Protein is judged only on days whose food log is full enough to read.
            let usable = Set(foodByDay.filter { TrainingProgress.isUsable($0.value) }.keys)
            let target = FuelPlanner.proteinTarget(profile)
            let met = usable.filter { FuelTotals.of(foodByDay[$0] ?? []).proteinG >= target }
            if !met.isEmpty {
                out.append(EffectFactor(key: "proteinMet", title: "Protein target met", phrase: "a day at your protein target",
                                        days: met, known: usable))
            }
        }
        for plan in supplements where plan.active {
            let taken = TrainingProgress.supplementDays(plan.dose.name, fuel: fuel)
            guard let first = taken.min() else { continue }
            // Before the first log there is no telling whether it was being taken.
            let known = Set(days.map { $0.day }.filter { $0 >= first })
            out.append(EffectFactor(key: "supplement:" + plan.dose.name, title: plan.dose.name,
                                    phrase: "a day you took " + plan.dose.name.lowercased(), days: taken, known: known))
        }
        let hard = Set(days.filter { ($0.strain.map(LScale.strain21) ?? 0) >= 14 }.map { $0.day })
        if !hard.isEmpty { out.append(EffectFactor(key: "hardDay", title: "Hard training day", phrase: "a hard training day", days: hard, known: nil)) }
        let late = Set(workouts.filter { w in
            let end = Date(timeIntervalSince1970: w.end)
            let c = calendar.dateComponents([.hour, .minute], from: end)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= 19 * 60 + 30
        }.map { $0.day })
        if !late.isEmpty { out.append(EffectFactor(key: "lateSession", title: "Evening session", phrase: "an evening session", days: late, known: nil)) }
        let trained = Set(workouts.map { $0.day })
        let rest = Set(days.map { $0.day }).subtracting(trained)
        if !rest.isEmpty, !trained.isEmpty { out.append(EffectFactor(key: "restDay", title: "Rest day", phrase: "a rest day", days: rest, known: nil)) }
        return out
    }

    public static func analyze(days: [LDay], checkIns: [CheckIn], workouts: [LWorkout], fuel: [FuelEntry] = [],
                               supplements: [SupplementPlan] = [], profile: LProfile? = nil,
                               outcomes: [LMetric] = [.recovery, .hrv, .restingHR, .sleepHours, .deepMin],
                               calendar: Calendar = LDate.calendar) -> [EffectFinding] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var raw: [(key: String, title: String, phrase: String, outcome: LMetric, test: LStat.GroupTest)] = []
        let all = factors(days: days, checkIns: checkIns, workouts: workouts, fuel: fuel, supplements: supplements, profile: profile,
                          calendar: calendar)
        for f in all {
            // Only days on which the habit is known either way count as "without".
            let universe = f.known ?? Set(byDay.keys)
            for outcome in outcomes {
                var with: [Double] = [], without: [Double] = []
                for d in universe {
                    guard let next = byDay[LDate.adding(1, to: d, calendar: calendar)], let v = outcome.value(next) else { continue }
                    if f.days.contains(d) { with.append(v) } else { without.append(v) }
                }
                guard with.count >= minimumWith, without.count >= minimumWithout, let t = LStat.welch(with, without) else { continue }
                raw.append((f.key, f.title, f.phrase, outcome, t))
            }
        }
        let keep = LStat.benjaminiHochberg(raw.map { $0.test.p }, q: 0.1)
        let findings: [EffectFinding] = raw.enumerated().map { (i, r) -> EffectFinding in
            EffectFinding(factorKey: r.key, factor: r.title, phrase: r.phrase, outcome: r.outcome, withMean: r.test.meanA, withoutMean: r.test.meanB,
                          delta: r.test.delta, g: r.test.g, p: r.test.p, nWith: r.test.nA, nWithout: r.test.nB, reliable: keep[i])
        }
        return findings.filter { abs($0.g) >= 0.3 }.sorted { ($0.reliable ? 1 : 0, abs($0.g)) > ($1.reliable ? 1 : 0, abs($1.g)) }
    }

    /// Day-level links between pairs of numbers, e.g. yesterday's strain against this morning's recovery.
    public static func links(days: [LDay], calendar: Calendar = LDate.calendar) -> [LinkFinding] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        struct Spec { let key: String; let x: LMetric; let y: LMetric; let lag: Int; let xLabel: String; let yLabel: String }
        let specs = [
            Spec(key: "strain>recovery", x: .strain, y: .recovery, lag: 1, xLabel: "Strain the day before", yLabel: "Recovery"),
            Spec(key: "sleep>recovery", x: .sleepHours, y: .recovery, lag: 0, xLabel: "Hours slept", yLabel: "Recovery"),
            Spec(key: "strain>sleep", x: .strain, y: .sleepHours, lag: 1, xLabel: "Strain the day before", yLabel: "Hours slept"),
            Spec(key: "sleep>hrv", x: .sleepHours, y: .hrv, lag: 0, xLabel: "Hours slept", yLabel: "HRV"),
            Spec(key: "steps>deep", x: .steps, y: .deepMin, lag: 1, xLabel: "Steps the day before", yLabel: "Deep sleep"),
        ]
        var raw: [(spec: Spec, xs: [Double], ys: [Double], r: Double, p: Double)] = []
        for s in specs {
            var xs: [Double] = [], ys: [Double] = []
            for d in days {
                guard let x = s.x.value(d), let later = byDay[LDate.adding(s.lag, to: d.day, calendar: calendar)], let y = s.y.value(later) else { continue }
                xs.append(x); ys.append(y)
            }
            guard xs.count >= 14, let c = LStat.spearman(xs, ys) else { continue }
            raw.append((s, xs, ys, c.r, c.p))
        }
        let keep = LStat.benjaminiHochberg(raw.map { $0.p }, q: 0.1)
        return raw.enumerated().compactMap { (i, r) -> LinkFinding? in
            guard abs(r.r) >= 0.2 else { return nil }
            let strength = abs(r.r) >= 0.5 ? "strongly" : (abs(r.r) >= 0.3 ? "clearly" : "slightly")
            let dir = r.r > 0 ? "higher" : "lower"
            let text = "\(r.spec.yLabel) tends to be \(strength) \(dir) when \(r.spec.xLabel.lowercased()) is higher (\(r.xs.count) days)."
            return LinkFinding(key: r.spec.key, xLabel: r.spec.xLabel, yLabel: r.spec.yLabel, r: r.r, p: r.p, n: r.xs.count,
                               reliable: keep[i], xs: r.xs, ys: r.ys, sentence: text)
        }.sorted { abs($0.r) > abs($1.r) }
    }

    /// Mean of a metric by weekday (1 = Monday), for "your Mondays" patterns.
    public static func weekdayMeans(_ metric: LMetric, days: [LDay], calendar: Calendar = LDate.calendar) -> [Int: (mean: Double, n: Int)] {
        var acc: [Int: [Double]] = [:]
        for d in days { if let v = metric.value(d) { acc[LDate.weekday(d.day, calendar: calendar), default: []].append(v) } }
        var out: [Int: (mean: Double, n: Int)] = [:]
        for (k, v) in acc { if let m = LStat.mean(v) { out[k] = (m, v.count) } }
        return out
    }
}
