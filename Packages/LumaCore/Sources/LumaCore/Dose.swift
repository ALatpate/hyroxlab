import Foundation

// MARK: - How much and how late

/// One day's amount of something set against the next morning's figure.
public struct DosePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// The mornings that followed a range of amounts.
public struct DoseBin: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let mean: Double?
    public let n: Int
}

/// How firmly a pattern stands: clear once it survives a check across everything that was tested,
/// early while it shows but could still be chance, none when the days show nothing.
public enum PatternStrength: String, Sendable { case clear, early, none }

/// How one amount goes with one next-morning figure across the athlete's own days.
public struct DoseFinding: Equatable, Sendable, Identifiable {
    public typealias Strength = PatternStrength

    public var id: String { key + "|" + outcome.rawValue }
    public let key: String
    public let title: String
    public let outcome: LMetric
    public let points: [DosePoint]
    public let bins: [DoseBin]
    /// Change in the outcome for each `step` of the amount.
    public let perStep: Double
    public let stepLabel: String
    /// Spearman rank correlation and its p-value.
    public let r: Double
    public let p: Double
    public let n: Int
    public let strength: Strength
    public let sentence: String
}

/// A time of day after which the next morning has run differently.
public struct DoseCutoff: Equatable, Sendable, Identifiable {
    public var id: String { key + "|" + outcome.rawValue }
    public let key: String
    public let outcome: LMetric
    /// Clock hour, e.g. 14.5 for 14:30.
    public let hour: Double
    public let delta: Double
    public let nLate: Int
    public let nEarly: Int
    public let p: Double
    public let firm: Bool
    public let sentence: String

    public var clock: String { LFormat.timeOfDay(minutes: hour * 60) }
}

public struct DoseRead: Equatable, Sendable {
    public let findings: [DoseFinding]
    public let cutoffs: [DoseCutoff]
    /// Days with a food log, which is what the amounts are read from.
    public let loggedDays: Int
    public static let empty = DoseRead(findings: [], cutoffs: [], loggedDays: 0)

    public func cutoff(_ key: String) -> DoseCutoff? { cutoffs.filter { $0.key == key }.max { abs($0.delta) < abs($1.delta) } }
}

public enum DoseModel {
    /// Days needed for one amount before it is set against a morning figure.
    public static let minimumDays = 14
    /// One drink is taken as 10 g of alcohol, the Irish standard drink.
    public static let gramsPerDrink = 10.0

    struct Factor {
        let key: String
        let title: String
        let step: Double
        let stepLabel: String
        let outcomes: [LMetric]
        let edges: [Double]
        let labels: [String]
        /// The amount on a day, or nil when it is not known for that day.
        let value: (String) -> Double?
        /// Days where the amount is zero still count (a day with no caffeine is a real amount).
        let needsNonZero: Int
    }

    /// `days` are the strap's days (a night's figures sit on the day it ended) and `nights` the sleep
    /// summary's nights; a part-recorded night is left out by the caller. The amount on day D is set
    /// against the figures of day D+1.
    public static func read(days: [LDay], nights: [SleepNight], fuel: [FuelEntry], usualBedtime: Double?,
                            calendar: Calendar = LDate.calendar) -> DoseRead {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let nightByDay = Dictionary(nights.filter { !$0.partial }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let food = fuel.filter { $0.kind != .water && $0.kind != .supplement }
        let foodByDay = Dictionary(grouping: food, by: { $0.day })
        let logged = Set(foodByDay.keys)
        func clockHour(_ e: FuelEntry) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: e.at)
            return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        }
        // When the night after `day` began, as a moment.
        func bedtime(after day: String) -> Date? {
            let next = LDate.adding(1, to: day, calendar: calendar)
            guard let n = nightByDay[next], let bed = n.bedtime, let midnight = LDate.startOfDay(next, calendar: calendar) else { return nil }
            return midnight.addingTimeInterval(bed * 60)
        }
        func entries(_ day: String) -> [FuelEntry] { foodByDay[day] ?? [] }
        func caffeine(_ day: String) -> Double? {
            guard logged.contains(day) else { return nil }
            var total = 0.0
            for e in entries(day) { total += e.caffeineMg }
            return total
        }
        func lastCaffeine(_ day: String) -> Double? {
            let hours: [Double] = entries(day).filter { $0.caffeineMg > 0 }.map { clockHour($0) }
            return hours.max()
        }
        func drinks(_ day: String) -> Double? {
            guard logged.contains(day) else { return nil }
            var grams = 0.0
            for e in entries(day) { grams += e.alcoholG }
            return grams / gramsPerDrink
        }
        func mealGap(_ day: String) -> Double? {
            let meals: [Date] = entries(day).filter { $0.kind != .drink && $0.kcal >= 200 }.map { $0.at }
            guard let bed = bedtime(after: day), let last = meals.max() else { return nil }
            let gap = bed.timeIntervalSince(last) / 3600
            return gap > 0 && gap < 12 ? gap : nil
        }
        func lateness(_ day: String) -> Double? {
            guard let usual = usualBedtime, let bed = nightByDay[LDate.adding(1, to: day, calendar: calendar)]?.bedtime else { return nil }
            return (bed - usual) / 60
        }
        let factors: [Factor] = [
            Factor(key: "caffeine", title: "Caffeine in the day", step: 100, stepLabel: "Each 100 mg of caffeine",
                   outcomes: [.deepMin, .sleepHours, .hrv], edges: [1, 151, 301],
                   labels: ["None", "Up to 150 mg", "151 to 300 mg", "Over 300 mg"], value: caffeine, needsNonZero: 5),
            Factor(key: "caffeineTime", title: "Last caffeine of the day", step: 1, stepLabel: "Each hour later the last caffeine was",
                   outcomes: [.deepMin, .sleepHours], edges: [12, 14, 16],
                   labels: ["Before 12:00", "12:00 to 14:00", "14:00 to 16:00", "After 16:00"], value: lastCaffeine, needsNonZero: 0),
            Factor(key: "alcohol", title: "Alcohol", step: 1, stepLabel: "Each drink",
                   outcomes: [.hrv, .recovery, .restingHR, .deepMin], edges: [0.5, 1.5, 2.5],
                   labels: ["None", "1 drink", "2 drinks", "3 or more"], value: drinks, needsNonZero: 4),
            Factor(key: "mealGap", title: "Last meal before bed", step: 1, stepLabel: "Each hour more between the last meal and bed",
                   outcomes: [.deepMin, .hrv, .restingHR], edges: [2, 3, 4],
                   labels: ["Under 2 h", "2 to 3 h", "3 to 4 h", "Over 4 h"], value: mealGap, needsNonZero: 0),
            Factor(key: "bedtime", title: "Bedtime against your usual", step: 1, stepLabel: "Each hour later to bed than usual",
                   outcomes: [.recovery, .hrv, .deepMin], edges: [-0.5, 0.5, 1.5],
                   labels: ["Earlier", "About usual", "Up to 1.5 h late", "Later still"], value: lateness, needsNonZero: 0),
        ]

        struct Raw { let factor: Factor; let outcome: LMetric; let xs: [Double]; let ys: [Double]; let r: Double; let p: Double; let slope: Double }
        var raw: [Raw] = []
        // The amount is logged on one day and the figure sits on the next, so the days walked are every
        // day that has either: a day with a food log and no strap row of its own still counts.
        var daySet = Set(logged)
        for d in days {
            daySet.insert(d.day)
            daySet.insert(LDate.adding(-1, to: d.day, calendar: calendar))
        }
        let allDays = daySet.sorted()
        for f in factors {
            for outcome in f.outcomes {
                var xs: [Double] = [], ys: [Double] = []
                for d in allDays {
                    guard let x = f.value(d), let next = byDay[LDate.adding(1, to: d, calendar: calendar)], let y = outcome.value(next) else { continue }
                    xs.append(x); ys.append(y)
                }
                guard xs.count >= minimumDays, Set(xs.map { ($0 * 10).rounded() }).count >= 4,
                      xs.filter({ $0 > 0 }).count >= f.needsNonZero,
                      let c = LStat.spearman(xs, ys), let fit = LStat.linearFit(xs, ys) else { continue }
                raw.append(Raw(factor: f, outcome: outcome, xs: xs, ys: ys, r: c.r, p: c.p, slope: fit.slope))
            }
        }
        let keep = LStat.benjaminiHochberg(raw.map { $0.p }, q: 0.1)
        let findings: [DoseFinding] = raw.enumerated().map { (i, r) -> DoseFinding in
            let strength: DoseFinding.Strength = abs(r.r) < 0.2 ? .none : (keep[i] && abs(r.r) >= 0.25 ? .clear : .early)
            let per = r.slope * r.factor.step
            let what = r.outcome.phrase
            let text: String
            if strength == .none {
                text = "No pattern between this and your \(what) the next morning (\(r.xs.count) days)."
            } else {
                let dir = per > 0 ? "more" : "less"
                let size = r.outcome.show(abs(per))
                let tail = strength == .clear ? "" : " Early signal: too few days to be sure."
                text = "\(r.factor.stepLabel) goes with \(size) \(dir) \(what) the next morning (\(r.xs.count) days).\(tail)"
            }
            return DoseFinding(key: r.factor.key, title: r.factor.title, outcome: r.outcome,
                               points: zip(r.xs, r.ys).map { DosePoint(x: $0.0, y: $0.1) },
                               bins: bins(xs: r.xs, ys: r.ys, edges: r.factor.edges, labels: r.factor.labels),
                               perStep: per, stepLabel: r.factor.stepLabel, r: r.r, p: r.p, n: r.xs.count, strength: strength, sentence: text)
        }

        // A cut-off: the time of day after which caffeine has gone with a different night. Days with
        // no caffeine at all sit on the "before" side.
        var cutoffs: [DoseCutoff] = []
        for outcome in [LMetric.deepMin, .sleepHours] {
            var rows: [(hour: Double?, y: Double)] = []
            for d in allDays where logged.contains(d) {
                guard let next = byDay[LDate.adding(1, to: d, calendar: calendar)], let y = outcome.value(next) else { continue }
                rows.append((lastCaffeine(d), y))
            }
            guard rows.count >= minimumDays else { continue }
            var best: (hour: Double, test: LStat.GroupTest)?
            var h = 12.0
            while h <= 18.0 {
                let late = rows.filter { ($0.hour ?? -1) >= h }.map { $0.y }
                let early = rows.filter { ($0.hour ?? -1) < h }.map { $0.y }
                if late.count >= 5, early.count >= 5, let t = LStat.welch(late, early), t.p < (best?.test.p ?? 0.05) { best = (h, t) }
                h += 0.5
            }
            guard let found = best else { continue }
            let dir = found.test.delta > 0 ? "higher" : "lower"
            // Several times of day were tried, so only a strong split is given as firm.
            let firm = found.test.p < 0.01
            // The time given is the earliest caffeine actually logged on the late side, to the half hour,
            // not the mark that happened to split the days.
            let earliest = rows.compactMap { $0.hour }.filter { $0 >= found.hour }.min() ?? found.hour
            let hour = (earliest * 2).rounded(.down) / 2
            let clock = LFormat.timeOfDay(minutes: hour * 60)
            let text = "On days with caffeine from \(clock) on, your \(outcome.phrase) ran \(outcome.show(abs(found.test.delta))) \(dir) (\(found.test.nA) and \(found.test.nB) nights)." + (firm ? "" : " Early signal.")
            cutoffs.append(DoseCutoff(key: "caffeine", outcome: outcome, hour: hour, delta: found.test.delta, nLate: found.test.nA,
                                      nEarly: found.test.nB, p: found.test.p, firm: firm, sentence: text))
        }
        let order: [DoseFinding.Strength: Int] = [.clear: 0, .early: 1, .none: 2]
        return DoseRead(findings: findings.sorted { (order[$0.strength] ?? 3, -abs($0.r)) < (order[$1.strength] ?? 3, -abs($1.r)) },
                        cutoffs: cutoffs, loggedDays: logged.count)
    }

    static func bins(xs: [Double], ys: [Double], edges: [Double], labels: [String]) -> [DoseBin] {
        var groups = [[Double]](repeating: [], count: edges.count + 1)
        for (x, y) in zip(xs, ys) {
            let i = edges.firstIndex { x < $0 } ?? edges.count
            groups[i].append(y)
        }
        return groups.enumerated().map { DoseBin(label: labels[$0.offset], mean: LStat.mean($0.element), n: $0.element.count) }
    }
}
