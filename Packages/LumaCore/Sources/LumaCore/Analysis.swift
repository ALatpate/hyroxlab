import Foundation

/// Everything Luma derives from the strap data for one moment in time. Built in one pass so every
/// screen reads the same numbers: a figure shown in two places comes from this one value.
public struct LumaAnalysis: Sendable {
    public var today: String
    /// Today's row, if the strap has produced one.
    public var day: LDay?
    /// The most recent day with a scored night (today's when it exists).
    public var lastNight: LDay?
    public var baselines: LBaselines
    public var recovery: RecoveryRead?
    public var sleep: SleepSummary
    public var load: LoadState
    public var watch: BodyWatch
    public var call: DayCall
    public var trends: [TrendRead]
    public var fitness: FitnessState
    public var effects: [EffectFinding]
    public var links: [LinkFinding]
    public var insights: [Insight]
    /// Days of data available in total.
    public var dayCount: Int

    public static let empty = LumaAnalysis.build(days: [], sleeps: [], workouts: [], profile: LProfile(), planned: [], today: LDate.key(Date()))

    public func trend(_ metric: LMetric) -> TrendRead? { trends.first { $0.metric == metric } }

    /// The training day rolls over at 04:00, so a late night still belongs to the day before.
    public static func todayKey(now: Date = Date(), calendar: Calendar = LDate.calendar) -> String {
        LDate.key(now.addingTimeInterval(-4 * 3600), calendar: calendar)
    }

    public static func build(days: [LDay], sleeps: [LSleep], workouts: [LWorkout], profile: LProfile, planned: [PlannedSession],
                             checkIns: [CheckIn] = [], personalBests: [PersonalBest] = [],
                             today: String, now: Date = Date(), calendar: Calendar = LDate.calendar) -> LumaAnalysis {
        let day = days.last { $0.day == today }
        let lastNight = days.last { $0.day <= today && $0.hasNight }
        let reference = lastNight?.day ?? today
        let baselines = LBaselines.compute(days: days, before: reference)
        let recovery = lastNight.map { RecoveryModel.read(day: $0, baselines: baselines) }
        let sleep = SleepModel.summarize(days: days, sleeps: sleeps, baseNeedMin: profile.sleepNeedHours.map { $0 * 60 },
                                         today: today, calendar: calendar)
        let rest = baselines.restingHR?.center ?? lastNight?.restingHR ?? 55
        let loads = LoadModel.dailyLoads(workouts: workouts, restHR: rest, maxHR: profile.resolvedMaxHR(on: now), sex: profile.sex)
        let load = LoadModel.compute(loads: loads, today: today, calendar: calendar)
        let watch = lastNight.map { BodyWatch.assess(day: $0, baselines: baselines) }
            ?? BodyWatch(level: .clear, signals: [], title: "No warning signs", detail: "Luma needs about two weeks of nights before it can watch for unusual patterns.")
        let plannedHard = planned.contains { $0.day == today && $0.status == .planned && $0.intensity == .hard }
        // Only a night that ended today counts as today's recovery; an older one must not drive the call.
        let todaysRecovery = lastNight?.day == today ? lastNight?.recovery : nil
        let call = DayCall.make(recovery: todaysRecovery, load: load, sleepDebtMin: sleep.debtMin, watch: lastNight?.day == today ? watch
                                : BodyWatch(level: .clear, signals: [], title: "", detail: ""), plannedHard: plannedHard)
        let trends = TrendModel.all(days: days, today: today, calendar: calendar)
        let fitness = FitnessModel.build(workouts: workouts, pbs: personalBests, restHR: rest, maxHR: profile.resolvedMaxHR(on: now),
                                         today: today, calendar: calendar)
        let effects = EffectModel.analyze(days: days, checkIns: checkIns, workouts: workouts, calendar: calendar)
        let links = EffectModel.links(days: days, calendar: calendar)
        let insights = InsightEngine.build(days: days, today: today, baselines: baselines, sleep: sleep, load: load, watch: watch,
                                           trends: trends, effects: effects, links: links, fitness: fitness, calendar: calendar)
        return LumaAnalysis(today: today, day: day, lastNight: lastNight, baselines: baselines, recovery: recovery, sleep: sleep,
                            load: load, watch: watch, call: call, trends: trends, fitness: fitness, effects: effects, links: links,
                            insights: insights, dayCount: days.count)
    }

    /// Daily values of a metric for the `count` days ending today, nil where there is no reading.
    public static func series(_ metric: LMetric, days: [LDay], ending today: String, count: Int,
                              calendar: Calendar = LDate.calendar) -> (keys: [String], values: [Double?]) {
        let byKey = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let keys = LDate.range(ending: today, count: count, calendar: calendar)
        return (keys, keys.map { byKey[$0].flatMap { metric.value($0) } })
    }
}
