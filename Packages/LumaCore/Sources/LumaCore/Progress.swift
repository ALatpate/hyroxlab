import Foundation

// MARK: - Lifts over time

public struct LiftPoint: Equatable, Sendable {
    public let day: String
    public let e1RM: Double
}

public enum ProgressTrend: String, Sendable { case up, steady, down }

/// One lift's estimated one-rep max over time, and where that puts it on Luma's scale.
public struct LiftProgress: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// The best estimate of each day the lift was logged, oldest first.
    public let points: [LiftPoint]
    /// What the lift is taken to be now: the best estimate of the last six weeks, or of the six before
    /// them when it has not been lifted since. Nil for a lift not logged in twelve weeks.
    public let current: Double?
    /// Best in the last six weeks, and in the six before them.
    public let recentBest: Double?
    public let previousBest: Double?
    public let allTime: Double
    public let allTimeDay: String
    public let lastDay: String
    /// The estimate counts bodyweight as part of the load (a pull-up, a dip).
    public let bodyweight: Bool
    /// `current` as a multiple of bodyweight.
    public let ratio: Double?
    /// 0…5 on the lift's scale; nil for a lift Luma does not grade or one not lifted lately.
    public let level: Double?
    /// The muscles the lift is a fair gauge of (graded lifts only).
    public let measures: [Muscle]

    /// Change of the six-week best against the six weeks before, as a fraction.
    public var change: Double? {
        guard let r = recentBest, let p = previousBest, p > 0 else { return nil }
        return (r - p) / p
    }

    public var trend: ProgressTrend? {
        change.map { $0 >= TrainingProgress.movedBy ? .up : ($0 <= -TrainingProgress.movedBy ? .down : .steady) }
    }

    /// "est. max 128 kg, 1.6 × bodyweight"
    public var figure: String {
        guard let c = current else { return String(format: "best est. max %.0f kg", allTime) }
        var text = String(format: "est. max %.0f kg", c)
        if bodyweight { text += " with bodyweight" }
        if let r = ratio { text += String(format: ", %.1f × bodyweight", r) }
        return text
    }
}

// MARK: - Muscles

/// How many sets a muscle had in a week, in the three groups studies of weekly sets have compared.
public enum SetBand: Int, Sendable {
    case none, low, middle, high

    public init(_ sets: Double) {
        self = sets <= 0 ? .none : (sets < 5 ? .low : (sets < 10 ? .middle : .high))
    }

    public var title: String {
        switch self {
        case .none: return "No sets"
        case .low: return "Under 5 sets"
        case .middle: return "5 to 9 sets"
        case .high: return "10 or more sets"
        }
    }
}

public struct MuscleState: Equatable, Sendable, Identifiable {
    public var id: String { muscle.rawValue }
    public let muscle: Muscle
    /// The graded lift the muscle's level is read from; nil when no graded lift logged in the last
    /// twelve weeks measures it.
    public let basis: LiftProgress?
    /// Sets in the last seven days: a set that trains the muscle directly counts 1, one where it
    /// assists counts ½.
    public let weekSets: Double
    /// The weekly average over the four weeks before those seven days; nil while the log is too short.
    public let usualSets: Double?
    /// The last day a set trained the muscle directly.
    public let lastDirect: String?
    /// What trained it directly in the last four weeks, most sets first.
    public let movements: [String]

    public var level: Double? { basis?.level }
    public var trend: ProgressTrend? { basis?.trend }
    public var band: SetBand { SetBand(weekSets) }
}

public struct ProgressNote: Equatable, Sendable, Identifiable {
    public let id: String
    public let muscles: [Muscle]
    public let title: String
    public let detail: String
}

// MARK: - Fuel and supplements beside training

/// The food log of the last two weeks, read against training days.
public struct FuelTrainingRead: Equatable, Sendable {
    public let window: Int
    /// Days with a food log full enough to read (`TrainingProgress.isUsable`).
    public let loggedDays: Int
    public let proteinPerKg: Double?
    public let proteinTargetPerKg: Double
    public let proteinDaysMet: Int
    public let trainingDays: Int
    public let restDays: Int
    public let trainingKcal: Double?
    public let restKcal: Double?
    public let trainingCarbsPerKg: Double?
    public let restCarbsPerKg: Double?
}

public struct SupplementRead: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let dose: String
    public let daysTaken: Int
    /// Days looked at: fourteen, or fewer for a supplement first logged inside them.
    public let window: Int
    /// Days in a row up to today (or yesterday, when today's is still to come).
    public let streak: Int
}

/// Two sides of the body's work set against each other: the sets each side had over four weeks.
public struct BalanceRead: Equatable, Sendable, Identifiable {
    public let id: String
    public let left: String
    public let leftSets: Double
    public let right: String
    public let rightSets: Double

    /// The left side's share of the two, 0…1; nil when neither had any work.
    public var share: Double? {
        let total = leftSets + rightSets
        return total > 0 ? leftSets / total : nil
    }
}

/// Sessions logged in one week (Monday to Sunday).
public struct WeekCount: Equatable, Sendable, Identifiable {
    public var id: String { weekStart }
    public let weekStart: String
    public let sessions: Int
}

public struct KindCount: Equatable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: SessionKind
    public let count: Int
}

// MARK: - The whole read

/// Everything the Progress view shows, worked out in one pass from the training log, the food log
/// and the supplement log, so a figure that appears twice is the same figure.
public struct TrainingProgress: Sendable {
    /// Progress compares the best of this many days with the best of the same span before it. A lift
    /// not logged in twice this long has no current figure.
    public static let trendDays = 42
    /// A change smaller than this fraction is "steady".
    public static let movedBy = 0.025

    public let muscles: [MuscleState]
    public let lifts: [LiftProgress]
    public let strengths: [ProgressNote]
    public let weakPoints: [ProgressNote]
    /// Logged sessions of the last four weeks by kind, most frequent first.
    public let mix: [KindCount]
    /// Sessions logged in each of the last eight weeks, oldest first; the last is the week in progress.
    public let weeks: [WeekCount]
    /// Push against pull, front of the legs against the back, upper body against lower: sets over the
    /// last four weeks. Only pairs where either side had work.
    public let balance: [BalanceRead]
    public let sessionsLogged: Int
    public let fuel: FuelTrainingRead?
    public let supplements: [SupplementRead]

    public static let empty = TrainingProgress.build(lifts: [], workouts: [], fuel: [], supplements: [], profile: LProfile(),
                                                     today: LDate.key(Date()))

    public func state(_ m: Muscle) -> MuscleState {
        muscles.first { $0.muscle == m } ?? MuscleState(muscle: m, basis: nil, weekSets: 0, usualSets: nil, lastDirect: nil, movements: [])
    }

    /// Lifts on Luma's scale with a figure from the last twelve weeks, strongest first.
    public var graded: [LiftProgress] { lifts.filter { $0.level != nil }.sorted { ($0.level ?? 0) > ($1.level ?? 0) } }

    public static func build(lifts logs: [LiftSession], workouts: [LWorkout], fuel: [FuelEntry], supplements: [SupplementPlan],
                             profile: LProfile, today: String, calendar: Calendar = LDate.calendar) -> TrainingProgress {
        let sessions = logs.filter { $0.day <= today }.sorted { $0.start < $1.start }
        let ago: [UUID: Int] = Dictionary(sessions.map { ($0.id, LDate.daysBetween($0.day, today, calendar: calendar)) },
                                          uniquingKeysWith: { a, _ in a })
        let lifts = liftProgress(sessions: sessions, profile: profile, today: today, calendar: calendar)
        let muscles = muscleStates(sessions: sessions, ago: ago, lifts: lifts)
        let recent = sessions.filter { (ago[$0.id] ?? 0) < 28 }
        var counts: [SessionKind: Int] = [:]
        for s in recent { counts[s.resolvedKind, default: 0] += 1 }
        let mix = counts.map { KindCount(kind: $0.key, count: $0.value) }.sorted { ($0.count, $1.kind.rawValue) > ($1.count, $0.kind.rawValue) }
        let fortnight = sessions.filter { s in
            (ago[s.id] ?? 0) < 14 && s.exercises.contains { ExerciseLibrary.work($0).resistance }
        }.count
        let thisWeek = LDate.weekStart(today, calendar: calendar)
        var perWeek: [String: Int] = [:]
        for s in sessions { perWeek[LDate.weekStart(s.day, calendar: calendar), default: 0] += 1 }
        let weeks: [WeekCount] = (0..<8).reversed().map { back in
            let start = LDate.adding(-7 * back, to: thisWeek, calendar: calendar)
            return WeekCount(weekStart: start, sessions: perWeek[start] ?? 0)
        }
        return TrainingProgress(muscles: muscles, lifts: lifts,
                                strengths: strengthNotes(lifts: lifts),
                                weakPoints: weakNotes(lifts: lifts, muscles: muscles, sessions: sessions, ago: ago, resistanceSessions14: fortnight),
                                mix: mix, weeks: weeks, balance: sides(sets(sessions: sessions, ago: ago, from: 0, to: 28)),
                                sessionsLogged: sessions.count,
                                fuel: fuelRead(fuel: fuel, workouts: workouts, sessions: sessions, profile: profile, today: today, calendar: calendar),
                                supplements: supplementReads(fuel: fuel, plans: supplements, today: today, calendar: calendar))
    }

    // MARK: Lifts

    static func liftProgress(sessions: [LiftSession], profile: LProfile, today: String, calendar: Calendar) -> [LiftProgress] {
        let body = max(30, profile.weightKg)
        var byName: [String: [String: Double]] = [:]
        for s in sessions {
            for e in s.exercises {
                guard let best = LiftMath.best(e, bodyKg: body) else { continue }
                if best > (byName[e.name]?[s.day] ?? 0) { byName[e.name, default: [:]][s.day] = best }
            }
        }
        var out: [LiftProgress] = []
        for (name, days) in byName {
            let points = days.map { LiftPoint(day: $0.key, e1RM: $0.value) }.sorted { $0.day < $1.day }
            guard let top = points.max(by: { $0.e1RM < $1.e1RM }), let last = points.last else { continue }
            func best(from: Int, to: Int) -> Double? {
                points.filter { p in
                    let d = LDate.daysBetween(p.day, today, calendar: calendar)
                    return d >= from && d < to
                }.map { $0.e1RM }.max()
            }
            let info = ExerciseLibrary.match(name)
            let own = info?.bodyweight ?? false
            let recent = best(from: 0, to: trendDays)
            let previous = best(from: trendDays, to: trendDays * 2)
            let current = recent ?? previous
            let ratio = current.map { $0 / body }
            var level: Double?
            if let scale = info?.scale, let r = ratio { level = scale.level(ratio: r, sex: profile.sex, bodyweightLift: own) }
            out.append(LiftProgress(name: name, points: points, current: current, recentBest: recent,
                                    previousBest: previous, allTime: top.e1RM, allTimeDay: top.day,
                                    lastDay: last.day, bodyweight: own, ratio: ratio, level: level,
                                    measures: info?.scale?.measures ?? []))
        }
        // Graded lifts first, then the ones logged most often.
        return out.sorted { a, b in
            if (a.level != nil) != (b.level != nil) { return a.level != nil }
            if a.points.count != b.points.count { return a.points.count > b.points.count }
            return a.name < b.name
        }
    }

    // MARK: Muscles

    /// Sets per muscle among sessions `from`…`to` days ago: direct work counts 1, assisting work ½.
    /// Only work against a load or bodyweight counts; a run or an erg is not a set for a muscle.
    static func sets(sessions: [LiftSession], ago: [UUID: Int], from: Int, to: Int) -> [Muscle: Double] {
        var out: [Muscle: Double] = [:]
        for s in sessions {
            guard let d = ago[s.id], d >= from, d < to else { continue }
            for e in s.exercises {
                let w = ExerciseLibrary.work(e)
                guard w.resistance else { continue }
                let n = Double(e.sets.filter { $0.done && $0.hasContent }.count)
                guard n > 0 else { continue }
                for m in w.primary { out[m, default: 0] += n }
                for m in w.secondary where !w.primary.contains(m) { out[m, default: 0] += n / 2 }
            }
        }
        return out
    }

    static func muscleStates(sessions: [LiftSession], ago: [UUID: Int], lifts: [LiftProgress]) -> [MuscleState] {
        let week = sets(sessions: sessions, ago: ago, from: 0, to: 7)
        let before = sets(sessions: sessions, ago: ago, from: 7, to: 35)
        // "Usual" needs a log that goes back far enough to have a usual.
        let history = sessions.first.flatMap { ago[$0.id] } ?? 0
        var lastDirect: [Muscle: String] = [:]
        var movementSets: [Muscle: [String: Double]] = [:]
        for s in sessions {
            for e in s.exercises {
                let w = ExerciseLibrary.work(e)
                let n = Double(e.sets.filter { $0.done && $0.hasContent }.count)
                guard w.resistance, n > 0 else { continue }
                for m in w.primary {
                    lastDirect[m] = s.day
                    if (ago[s.id] ?? 99) < 28 { movementSets[m, default: [:]][e.name, default: 0] += n }
                }
            }
        }
        return Muscle.allCases.map { m in
            let basis = lifts.filter { $0.level != nil && $0.measures.contains(m) }.max { ($0.level ?? 0) < ($1.level ?? 0) }
            let names = (movementSets[m] ?? [:]).sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(4).map { $0.key }
            return MuscleState(muscle: m, basis: basis, weekSets: week[m] ?? 0, usualSets: history >= 21 ? (before[m] ?? 0) / 4 : nil,
                               lastDirect: lastDirect[m], movements: Array(names))
        }
    }

    static let pushing: [Muscle] = [.chest, .shoulders, .triceps]
    static let pulling: [Muscle] = [.lats, .upperBack, .biceps]
    static let legFront: [Muscle] = [.quads]
    static let legBack: [Muscle] = [.glutes, .hamstrings]
    static let upper: [Muscle] = [.chest, .shoulders, .triceps, .biceps, .lats, .upperBack, .traps, .forearms]
    static let lower: [Muscle] = [.quads, .glutes, .hamstrings, .calves, .adductors]

    /// The three pairs, from sets per muscle. A pair neither side of which had work is left out.
    static func sides(_ sets: [Muscle: Double]) -> [BalanceRead] {
        func sum(_ muscles: [Muscle]) -> Double { muscles.reduce(0) { $0 + (sets[$1] ?? 0) } }
        let pairs: [BalanceRead] = [
            BalanceRead(id: "push-pull", left: "Push", leftSets: sum(pushing), right: "Pull", rightSets: sum(pulling)),
            BalanceRead(id: "legs", left: "Quads", leftSets: sum(legFront), right: "Glutes and hamstrings", rightSets: sum(legBack)),
            BalanceRead(id: "upper-lower", left: "Upper body", leftSets: sum(upper), right: "Lower body", rightSets: sum(lower)),
        ]
        return pairs.filter { $0.share != nil }
    }

    // MARK: Strong and weak points

    static func kg(_ v: Double) -> String { String(format: "%.0f", v) }

    static func pct(_ fraction: Double) -> String { String(format: "%.0f%%", abs(fraction) * 100) }

    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }

    static func strengthNotes(lifts: [LiftProgress]) -> [ProgressNote] {
        var out: [ProgressNote] = []
        let graded = lifts.filter { $0.level != nil }.sorted { ($0.level ?? 0) > ($1.level ?? 0) }
        if let top = graded.first, let level = top.level {
            let title = graded.count > 1 ? "\(top.name) is your strongest lift for your weight" : "\(top.name): \(StrengthLevel(level).title)"
            let lead = graded.count > 1 ? "\(StrengthLevel(level).title): " : ""
            out.append(ProgressNote(id: "top-\(top.name)", muscles: top.measures, title: title, detail: lead + top.figure + "."))
        }
        let rising = lifts.filter { ($0.change ?? 0) >= 0.03 }.sorted { ($0.change ?? 0) > ($1.change ?? 0) }.prefix(2)
        for l in rising {
            guard let c = l.change, let r = l.recentBest, let p = l.previousBest else { continue }
            out.append(ProgressNote(id: "up-\(l.name)", muscles: worked(by: l), title: "\(l.name) is climbing",
                                    detail: "Est. max up \(pct(c)) in six weeks (\(kg(p)) to \(kg(r)) kg)."))
        }
        return out
    }

    static func worked(by l: LiftProgress) -> [Muscle] {
        l.measures.isEmpty ? (ExerciseLibrary.match(l.name)?.primary ?? []) : l.measures
    }

    static func weakNotes(lifts: [LiftProgress], muscles: [MuscleState], sessions: [LiftSession], ago: [UUID: Int],
                           resistanceSessions14: Int) -> [ProgressNote] {
        var out: [ProgressNote] = []
        // A lift graded well below the rest.
        let graded = lifts.filter { $0.level != nil }.sorted { ($0.level ?? 0) < ($1.level ?? 0) }
        if graded.count >= 3, let low = graded.first, let level = low.level {
            let levels = graded.compactMap { $0.level }
            let median = levels[levels.count / 2]
            if level <= median - 0.75 {
                let gauged = list(low.measures.map { $0.title.lowercased() })
                let grades = low.measures.isEmpty ? "" : " It is Luma's gauge of your \(gauged)."
                let here = StrengthLevel(level).title
                let rest = StrengthLevel(median).title
                let detail = "\(here): \(low.figure). Your other graded lifts sit around \(rest)." + grades
                out.append(ProgressNote(id: "low-\(low.name)", muscles: low.measures, title: "\(low.name) is your lowest-graded lift", detail: detail))
            }
        }
        // Lifts that have gone backwards.
        let slipping = lifts.filter { ($0.change ?? 0) <= -0.03 }.sorted { ($0.change ?? 0) < ($1.change ?? 0) }.prefix(2)
        for l in slipping {
            guard let c = l.change, let r = l.recentBest, let p = l.previousBest else { continue }
            out.append(ProgressNote(id: "down-\(l.name)", muscles: worked(by: l), title: "\(l.name) is slipping",
                                    detail: "Est. max down \(pct(c)) in six weeks (\(kg(p)) to \(kg(r)) kg)."))
        }
        // Muscle groups nothing has reached in two weeks, once there is enough logged to say so.
        if resistanceSessions14 >= 3 {
            let reached = sets(sessions: sessions, ago: ago, from: 0, to: 14)
            let untouched = Muscle.major.filter { (reached[$0] ?? 0) <= 0 }
            if !untouched.isEmpty {
                let names = list(untouched.map { $0.title.lowercased() })
                let them = untouched.count == 1 ? "it" : "them"
                let detail = "Nothing in the \(resistanceSessions14) sessions logged in the last 14 days trains \(them), directly or as an assisting muscle."
                out.append(ProgressNote(id: "untouched", muscles: untouched, title: "No work for your \(names) in two weeks", detail: detail))
            }
        }
        // Muscle groups getting half their usual work or less.
        let behind = muscles.filter { s in
            guard let usual = s.usualSets, usual >= 6, s.weekSets > 0 else { return false }
            return s.weekSets <= usual / 2
        }.sorted { ($0.usualSets ?? 0) - $0.weekSets > ($1.usualSets ?? 0) - $1.weekSets }.prefix(3)
        if !behind.isEmpty {
            let parts: [String] = behind.map { s in
                let now = LiftSet.number((s.weekSets * 2).rounded() / 2)
                let usual = LiftSet.number(((s.usualSets ?? 0) * 2).rounded() / 2)
                return s.muscle.title.lowercased() + " " + now + " against a usual " + usual
            }
            out.append(ProgressNote(id: "behind", muscles: behind.map { $0.muscle }, title: "Less work than usual this week",
                                    detail: "Sets in the last seven days: " + list(parts) + "."))
        }
        return out
    }

    // MARK: Fuel

    /// A day's food log is full enough to read when it has at least two entries and 1,000 kcal.
    public static func isUsable(_ entries: [FuelEntry]) -> Bool {
        let food = entries.filter { $0.kind != .water && $0.kind != .supplement && $0.kcal > 0 }
        return food.count >= 2 && food.reduce(0) { $0 + $1.kcal } >= 1000
    }

    static func fuelRead(fuel: [FuelEntry], workouts: [LWorkout], sessions: [LiftSession], profile: LProfile, today: String,
                         calendar: Calendar) -> FuelTrainingRead? {
        // The fourteen days before today: today's log is still being written.
        let keys = LDate.range(ending: LDate.adding(-1, to: today, calendar: calendar), count: 14, calendar: calendar)
        let byDay = Dictionary(grouping: fuel, by: { $0.day })
        let logged = keys.filter { isUsable(byDay[$0] ?? []) }
        guard !logged.isEmpty else { return nil }
        let trained = Set(workouts.map { $0.day }).union(sessions.map { $0.day })
        let body = max(30, profile.weightKg)
        let target = FuelPlanner.proteinTarget(profile)
        func total(_ k: String) -> FuelTotals { FuelTotals.of(byDay[k] ?? []) }
        let protein = logged.map { total($0).proteinG }
        let onTraining = logged.filter { trained.contains($0) }
        let onRest = logged.filter { !trained.contains($0) }
        func mean(_ keys: [String], _ value: (FuelTotals) -> Double) -> Double? { LStat.mean(keys.map { value(total($0)) }) }
        return FuelTrainingRead(window: keys.count, loggedDays: logged.count,
                                proteinPerKg: LStat.mean(protein).map { $0 / body }, proteinTargetPerKg: target / body,
                                proteinDaysMet: protein.filter { $0 >= target }.count,
                                trainingDays: onTraining.count, restDays: onRest.count,
                                trainingKcal: mean(onTraining) { $0.kcal }, restKcal: mean(onRest) { $0.kcal },
                                trainingCarbsPerKg: mean(onTraining) { $0.carbsG }.map { $0 / body },
                                restCarbsPerKg: mean(onRest) { $0.carbsG }.map { $0 / body })
    }

    // MARK: Supplements

    /// The days a supplement of this name was logged.
    public static func supplementDays(_ name: String, fuel: [FuelEntry]) -> Set<String> {
        Set(fuel.filter { $0.kind == .supplement && $0.title == name }.map { $0.day })
    }

    static func supplementReads(fuel: [FuelEntry], plans: [SupplementPlan], today: String, calendar: Calendar) -> [SupplementRead] {
        plans.filter { $0.active }.map { plan in
            let days = supplementDays(plan.dose.name, fuel: fuel)
            var window = 14
            if let first = days.min() { window = min(14, max(1, LDate.daysBetween(first, today, calendar: calendar) + 1)) }
            let keys = LDate.range(ending: today, count: window, calendar: calendar)
            var streak = 0
            var cursor = days.contains(today) ? today : LDate.adding(-1, to: today, calendar: calendar)
            while days.contains(cursor) {
                streak += 1
                cursor = LDate.adding(-1, to: cursor, calendar: calendar)
            }
            return SupplementRead(name: plan.dose.name, dose: plan.dose.text, daysTaken: keys.filter { days.contains($0) }.count,
                                  window: window, streak: streak)
        }
    }
}
