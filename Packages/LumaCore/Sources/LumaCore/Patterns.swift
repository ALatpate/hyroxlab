import Foundation

// MARK: - What helps training

/// A habit of the week set against how much the lifts moved that week.
public struct TrainingHelp: Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let weeksWith: Int
    public let weeksWithout: Int
    /// Mean change of the week's lifts against their best of the six weeks before, as a fraction.
    public let meanWith: Double
    public let meanWithout: Double
    public let p: Double
    public let strength: PatternStrength
    public let sentence: String
}

public struct TrainingHelpRead: Equatable, Sendable {
    /// Weeks in which a lift could be compared with its recent best.
    public let weeks: Int
    public let findings: [TrainingHelp]

    public static let empty = TrainingHelpRead(weeks: 0, findings: [])
    public var ready: Bool { weeks >= TrainingHelpModel.minimumWeeks }
}

public enum TrainingHelpModel {
    public static let minimumWeeks = 12
    public static let minimumEach = 4
    public static let lookBackWeeks = 39

    struct Week {
        let start: String
        var liftChange: Double?
        var facts: [String: Bool] = [:]
    }

    /// Week by week (Monday to Sunday, finished weeks only): how the lifts trained that week stood
    /// against their best of the six weeks before, and whether each habit held that week. It works on
    /// weeks, so it needs months of logs, and it shows patterns, not causes.
    public static func read(progress: TrainingProgress, days: [LDay], fuel: [FuelEntry], supplements: [SupplementPlan], profile: LProfile,
                            today: String, calendar: Calendar = LDate.calendar) -> TrainingHelpRead {
        let thisWeek = LDate.weekStart(today, calendar: calendar)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let food = fuel.filter { $0.kind != .water && $0.kind != .supplement }
        let foodByDay = Dictionary(grouping: food, by: { $0.day })
        let target = FuelPlanner.proteinTarget(profile)
        let plans = supplements.filter { $0.active }
        let taken: [String: Set<String>] = Dictionary(plans.map { ($0.dose.name, TrainingProgress.supplementDays($0.dose.name, fuel: fuel)) },
                                                      uniquingKeysWith: { a, _ in a })
        var weeks: [Week] = []
        var sleepMeans: [String: Double] = [:]
        for back in 1...lookBackWeeks {
            let start = LDate.adding(-7 * back, to: thisWeek, calendar: calendar)
            let keys = (0..<7).map { LDate.adding($0, to: start, calendar: calendar) }
            var week = Week(start: start)
            // How the lifts trained this week stood against their best of the six weeks before it.
            var changes: [Double] = []
            for lift in progress.lifts {
                let inWeek = lift.points.filter { keys.contains($0.day) }.map { $0.e1RM }.max()
                let before = lift.points.filter { p in
                    let d = LDate.daysBetween(p.day, start, calendar: calendar)
                    return d > 0 && d <= TrainingProgress.trendDays
                }.map { $0.e1RM }.max()
                if let inWeek, let before, before > 0 { changes.append(inWeek / before - 1) }
            }
            week.liftChange = LStat.mean(changes)
            let usable = keys.filter { TrainingProgress.isUsable(foodByDay[$0] ?? []) }
            if usable.count >= 3 {
                let met = usable.filter { FuelTotals.of(foodByDay[$0] ?? []).proteinG >= target }.count
                week.facts["protein"] = Double(met) / Double(usable.count) >= 0.6
            }
            let known = keys.filter { foodByDay[$0] != nil }
            if known.count >= 3 {
                let drinking = known.filter { FuelTotals.of(foodByDay[$0] ?? []).alcoholG > 0 }.count
                week.facts["dry"] = drinking <= 1
            }
            let slept = keys.compactMap { byDay[$0]?.sleepMin }.map { $0 / 60 }
            if slept.count >= 4, let m = LStat.mean(slept) { sleepMeans[start] = m }
            for plan in plans {
                guard let takenDays = taken[plan.dose.name], let first = takenDays.min(), first <= start else { continue }
                week.facts["supplement:" + plan.dose.name] = keys.filter { takenDays.contains($0) }.count >= 5
            }
            weeks.append(week)
        }
        if let median = LStat.median(Array(sleepMeans.values)) {
            for i in weeks.indices { if let m = sleepMeans[weeks[i].start] { weeks[i].facts["sleep"] = m >= median } }
        }
        let comparable = weeks.filter { $0.liftChange != nil }
        guard comparable.count >= minimumWeeks else { return TrainingHelpRead(weeks: comparable.count, findings: []) }

        var specs: [(key: String, title: String, with: String)] = [
            ("protein", "Protein target", "you hit your protein target on most logged days"),
            ("sleep", "Sleep", "you slept more than your usual week"),
            ("dry", "Alcohol", "you drank on no more than one day"),
        ]
        for plan in plans { specs.append(("supplement:" + plan.dose.name, plan.dose.name, "you took \(plan.dose.name.lowercased()) on five days or more")) }
        var raw: [(spec: (key: String, title: String, with: String), test: LStat.GroupTest)] = []
        for spec in specs {
            let with = comparable.filter { $0.facts[spec.key] == true }.compactMap { $0.liftChange }
            let without = comparable.filter { $0.facts[spec.key] == false }.compactMap { $0.liftChange }
            guard with.count >= minimumEach, without.count >= minimumEach, let t = LStat.welch(with, without) else { continue }
            raw.append((spec, t))
        }
        let keep = LStat.benjaminiHochberg(raw.map { $0.test.p }, q: 0.1)
        func pct(_ v: Double) -> String { String(format: "%+.1f%%", v * 100) }
        let findings: [TrainingHelp] = raw.enumerated().map { (i, r) -> TrainingHelp in
            let strength: PatternStrength = abs(r.test.g) < 0.3 ? .none : (keep[i] ? .clear : .early)
            let text: String
            if strength == .none {
                text = "No difference in how your lifts moved between weeks \(r.spec.with) and the others (\(r.test.nA) and \(r.test.nB) weeks)."
            } else {
                let tail = strength == .clear ? "" : " Early signal: too few weeks to be sure."
                text = "In the \(r.test.nA) weeks \(r.spec.with), your lifts moved \(pct(r.test.meanA)) on average, against \(pct(r.test.meanB)) in the other \(r.test.nB).\(tail)"
            }
            return TrainingHelp(key: r.spec.key, title: r.spec.title, weeksWith: r.test.nA, weeksWithout: r.test.nB, meanWith: r.test.meanA,
                                meanWithout: r.test.meanB, p: r.test.p, strength: strength, sentence: text)
        }
        let order: [PatternStrength: Int] = [.clear: 0, .early: 1, .none: 2]
        return TrainingHelpRead(weeks: comparable.count, findings: findings.sorted { (order[$0.strength] ?? 3, $0.p) < (order[$1.strength] ?? 3, $1.p) })
    }
}

// MARK: - What drives recovery, all at once

/// One input's effect on the next morning's recovery with the others held level.
public struct DriverEffect: Equatable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let title: String
    /// "Each extra hour of sleep"
    public let per: String
    /// Recovery points for each unit, and the range it most likely lies in (90%).
    public let effect: Double
    public let low: Double
    public let high: Double
    public let p: Double
    public let strength: PatternStrength
    public let sentence: String
}

/// Tomorrow morning's recovery as the athlete's own nights suggest it, with its range.
public struct RecoveryForecast: Equatable, Sendable {
    public let value: Double
    public let low: Double
    public let high: Double
    public let basis: String
}

public struct DriverRead: Equatable, Sendable {
    /// Nights the model could use, and how many of them had a food log for the day before.
    public let nights: Int
    public let loggedNights: Int
    public let effects: [DriverEffect]
    /// How well the model predicts a night it was not fitted on (1 is perfectly, 0 is no better than the average).
    public let leftOutR2: Double?
    public let forecast: RecoveryForecast?

    public static let empty = DriverRead(nights: 0, loggedNights: 0, effects: [], leftOutR2: nil, forecast: nil)
    public var ready: Bool { nights >= DriverModel.minimumNights }
}

/// What today holds so far, for the forecast.
public struct DriverToday: Equatable, Sendable {
    public var strain21: Double?
    /// The sleep assumed for tonight: the athlete's recent average.
    public var sleepHours: Double?
    public var foodLogged: Bool
    public var drinks: Double
    public var lateCaffeineMg: Double
    public var lateMeal: Bool
    public var proteinPerKg: Double
    public var waterL: Double

    public init(strain21: Double?, sleepHours: Double?, foodLogged: Bool = false, drinks: Double = 0, lateCaffeineMg: Double = 0,
                lateMeal: Bool = false, proteinPerKg: Double = 0, waterL: Double = 0) {
        self.strain21 = strain21; self.sleepHours = sleepHours; self.foodLogged = foodLogged; self.drinks = drinks
        self.lateCaffeineMg = lateCaffeineMg; self.lateMeal = lateMeal; self.proteinPerKg = proteinPerKg; self.waterL = waterL
    }
}

public enum DriverModel {
    public static let minimumNights = 60
    public static let minimumLogged = 40
    /// A forecast is only given when the model predicts left-out nights at least this well.
    public static let minimumLeftOutR2 = 0.1

    struct Input {
        let key: String
        let title: String
        let per: String
        let noun: String
    }

    static let base: [Input] = [
        Input(key: "strain", title: "Strain the day before", per: "Each point of strain the day before", noun: "the day's strain"),
        Input(key: "sleep", title: "Sleep", per: "Each extra hour of sleep", noun: "sleep"),
        Input(key: "late", title: "Bedtime", per: "Each hour later to bed than usual", noun: "a later bedtime"),
    ]
    static let logged: [Input] = [
        Input(key: "drinks", title: "Alcohol", per: "Each drink", noun: "alcohol"),
        Input(key: "caffeine", title: "Caffeine after 14:00", per: "Each 100 mg of caffeine after 14:00", noun: "late caffeine"),
        Input(key: "lateMeal", title: "A late meal", per: "A meal after 21:00", noun: "a late meal"),
        Input(key: "protein", title: "Protein", per: "Each extra 0.5 g of protein per kg", noun: "protein"),
        Input(key: "water", title: "Water", per: "Each extra litre of water", noun: "water"),
    ]

    /// One least-squares model of the next morning's recovery on the day before and the night between.
    /// Inputs that travel together (a late night and a drink) are fitted side by side, so each effect is
    /// what is left once the others are held level; comparing one habit at a time cannot separate them.
    /// Strap-only inputs use every night; inputs read from the food log use the nights whose day before
    /// has a log. Effects are patterns in the athlete's own nights, not causes.
    public static func read(days: [LDay], nights: [SleepNight], fuel: [FuelEntry], usualBedtime: Double?, profile: LProfile,
                            today: DriverToday? = nil, calendar: Calendar = LDate.calendar) -> DriverRead {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let nightByDay = Dictionary(nights.filter { !$0.partial }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let food = fuel.filter { $0.kind != .water && $0.kind != .supplement }
        let foodByDay = Dictionary(grouping: food, by: { $0.day })
        let waterByDay = Dictionary(grouping: fuel.filter { $0.kind == .water }, by: { $0.day })
        let body = max(30, profile.weightKg)

        struct Row { let y: Double; let base: [Double]; let log: [Double]? }
        var rows: [Row] = []
        for d in days {
            let nextKey = LDate.adding(1, to: d.day, calendar: calendar)
            guard let next = byDay[nextKey], let y = next.recovery, let strain = d.strain.map(LScale.strain21),
                  let sleep = next.sleepMin.map({ $0 / 60 }) else { continue }
            var late = 0.0
            if let usual = usualBedtime, let bed = nightByDay[nextKey]?.bedtime { late = (bed - usual) / 60 }
            var log: [Double]?
            if let entries = foodByDay[d.day] {
                var grams = 0.0, caffeine = 0.0, protein = 0.0
                var lateMeal = false
                for e in entries {
                    grams += e.alcoholG
                    protein += e.proteinG
                    let hour = calendar.component(.hour, from: e.at)
                    if hour >= EffectModel.lateCaffeineHour { caffeine += e.caffeineMg }
                    if e.kind != .drink, e.kcal >= 200, hour >= EffectModel.lateMealHour { lateMeal = true }
                }
                var water = 0.0
                for e in waterByDay[d.day] ?? [] { water += e.waterMl ?? 0 }
                log = [grams / DoseModel.gramsPerDrink, caffeine / 100, lateMeal ? 1 : 0, protein / body / 0.5, water / 1000]
            }
            rows.append(Row(y: y, base: [strain, sleep, late], log: log))
        }
        let withLog = rows.filter { $0.log != nil }
        guard rows.count >= minimumNights, let fit = LStat.regress(y: rows.map { $0.y }, rows: rows.map { $0.base }) else {
            return DriverRead(nights: rows.count, loggedNights: withLog.count, effects: [], leftOutR2: nil, forecast: nil)
        }
        // The food-log inputs, fitted beside the strap ones on the nights that have a log. One that never
        // varies on those nights says nothing and is left out.
        var extended: LStat.Regression?
        var used: [Int] = []
        if withLog.count >= minimumLogged {
            for j in logged.indices {
                let column = withLog.compactMap { $0.log?[j] }
                if column.filter({ $0 != 0 }).count >= 5, (LStat.sd(column) ?? 0) > 0 { used.append(j) }
            }
            if !used.isEmpty {
                let x: [[Double]] = withLog.map { row in row.base + used.map { row.log?[$0] ?? 0 } }
                extended = LStat.regress(y: withLog.map { $0.y }, rows: x)
            }
        }
        // With the fuller model every effect is read from it, the strap inputs included: a late night
        // fitted without the drink that went with it would be given the drink's share.
        let model = extended ?? fit
        var inputs = base
        if extended != nil { inputs += used.map { logged[$0] } }
        var found: [(input: Input, effect: Double, low: Double, high: Double, p: Double)] = []
        for (i, input) in inputs.enumerated() {
            let range = model.interval(i + 1)
            found.append((input, model.coefficients[i + 1], range.low, range.high, model.p[i + 1]))
        }
        let keep = LStat.benjaminiHochberg(found.map { $0.p }, q: 0.1)
        let effects: [DriverEffect] = found.enumerated().map { (i, f) -> DriverEffect in
            let sure = f.low > 0 || f.high < 0
            let strength: PatternStrength = keep[i] && sure ? .clear : (f.p < 0.1 ? .early : .none)
            let text: String
            if strength == .none {
                text = "No clear effect of \(f.input.noun) on your recovery, with the rest held level."
            } else {
                let dir = f.effect > 0 ? "more" : "fewer"
                let a = String(format: "%.1f", min(abs(f.low), abs(f.high))), b = String(format: "%.1f", max(abs(f.low), abs(f.high)))
                let tail = strength == .clear ? "" : " Early signal."
                text = "\(f.input.per) goes with \(String(format: "%.1f", abs(f.effect))) \(dir) points of recovery the next morning (between \(a) and \(b)), with the rest held level.\(tail)"
            }
            return DriverEffect(key: f.input.key, title: f.input.title, per: f.input.per, effect: f.effect, low: f.low, high: f.high, p: f.p,
                                strength: strength, sentence: text)
        }

        var forecast: RecoveryForecast?
        if let t = today, let strain = t.strain21, let sleep = t.sleepHours, fit.leftOutR2 >= minimumLeftOutR2 {
            var forecastModel = fit
            var x: [Double] = [strain, sleep, 0]
            if let extended, t.foodLogged, extended.leftOutR2 >= minimumLeftOutR2 {
                let all = [t.drinks, t.lateCaffeineMg / 100, t.lateMeal ? 1 : 0, t.proteinPerKg / 0.5, t.waterL]
                x += used.map { all[$0] }
                forecastModel = extended
            }
            let value = LStat.clamp(forecastModel.predict(x), 1, 99)
            let spread = 1.28 * forecastModel.residualSD
            let basis = "From \(forecastModel.n) of your nights. Assumes \(String(format: "%.1f", sleep)) h of sleep tonight at your usual time, and today's strain of \(String(format: "%.1f", strain)) so far."
            forecast = RecoveryForecast(value: value, low: LStat.clamp(value - spread, 1, 99), high: LStat.clamp(value + spread, 1, 99), basis: basis)
        }
        let order: [PatternStrength: Int] = [.clear: 0, .early: 1, .none: 2]
        return DriverRead(nights: rows.count, loggedNights: withLog.count,
                          effects: effects.sorted { (order[$0.strength] ?? 3, $0.p) < (order[$1.strength] ?? 3, $1.p) },
                          leftOutR2: model.leftOutR2, forecast: forecast)
    }
}
