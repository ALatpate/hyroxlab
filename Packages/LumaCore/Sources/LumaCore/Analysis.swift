import Foundation

/// Everything Luma derives from the strap data for one moment in time. Built in one pass so every
/// screen reads the same numbers: a figure shown in two places comes from this one value.
public struct LumaAnalysis: Sendable {
    public var today: String
    /// Today's row, if the strap has produced one.
    public var day: LDay?
    /// The most recent day with any night data (today's when it exists). It need not have been scored.
    public var lastNight: LDay?
    /// How complete the record behind today's night is.
    public var night: NightRecord
    /// Why today has no recovery score; nil when it has one.
    public var gap: RecoveryGap?
    /// The most recent day that does have a recovery score, when that is not today.
    public var lastScored: LDay?
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

    /// `record` is where the heart-rate record has readings and `recordAsOf` when it was read, `reading`
    /// whether the strap's stored record is still arriving, `calibration` how far the recovery baseline
    /// has got, and `partialNights` the earlier wake days whose night was only partly recorded. Left at
    /// their defaults, nothing is held back: every night is taken as complete.
    public static func build(days: [LDay], sleeps: [LSleep], workouts: [LWorkout], profile: LProfile, planned: [PlannedSession],
                             checkIns: [CheckIn] = [], personalBests: [PersonalBest] = [],
                             record: [RecordStretch] = [], recordAsOf: Double? = nil, reading: Bool = false,
                             calibration: LCalibration? = nil, partialNights: Set<String> = [],
                             today: String, now: Date = Date(), calendar: Calendar = LDate.calendar) -> LumaAnalysis {
        let day = days.last { $0.day == today }
        let lastNight = days.last { $0.day <= today && $0.hasNight }
        let lastScored = days.last { $0.day < today && $0.recovery != nil }

        // Today's night, and how much of it the record holds.
        let night: NightRecord
        if let main = SleepModel.mainBlock(on: today, sleeps: sleeps) {
            night = RecordCheck.night(start: main.start, end: main.end, stretches: record,
                                      now: recordAsOf ?? now.timeIntervalSince1970)
        } else {
            night = lastNight?.day == today ? .complete : .none
        }
        // Today's verdict is the one just reached; earlier days keep the one they were given.
        var partial = partialNights
        if night.isPartial { partial.insert(today) } else { partial.remove(today) }
        // What a part-recorded night measured describes only that part, so it shapes no baseline, trend
        // or pattern. The night's own row is still shown, marked for what it is.
        let whole: [LDay] = partial.isEmpty ? days : days.map { partial.contains($0.day) ? $0.withoutNight : $0 }

        let reference = lastNight?.day ?? today
        let baselines = LBaselines.compute(days: whole, before: reference)
        let todaysRecovery = lastNight?.day == today ? lastNight?.recovery : nil
        let gap = RecordCheck.gap(recovery: todaysRecovery, night: night, reading: reading, calibration: calibration)
        let recovery = lastNight.map { RecoveryModel.read(day: $0, baselines: baselines, gap: gap) }
        let sleep = SleepModel.summarize(days: days, sleeps: sleeps, baseNeedMin: profile.sleepNeedHours.map { $0 * 60 },
                                         partial: partial, today: today, calendar: calendar)
        let rest = baselines.restingHR?.center ?? lastNight?.restingHR ?? 55
        let loads = LoadModel.dailyLoads(workouts: workouts, restHR: rest, maxHR: profile.resolvedMaxHR(on: now), sex: profile.sex)
        let load = LoadModel.compute(loads: loads, today: today, calendar: calendar)
        // A night with part of its record missing is not compared with the athlete's normal: its resting
        // heart rate and HRV describe only the part that was recorded.
        let judged = !night.isPartial || lastNight?.day != today
        let assessed: BodyWatch? = judged ? lastNight.map { BodyWatch.assess(day: $0, baselines: baselines) } : BodyWatch(
            level: .clear, signals: [], title: "Not assessed",
            detail: "Part of last night's record is missing, so Luma has not compared the night with your normal.")
        let watch = assessed
            ?? BodyWatch(level: .clear, signals: [], title: "No warning signs", detail: "Luma needs about two weeks of nights before it can watch for unusual patterns.")
        let plannedHard = planned.contains { $0.day == today && $0.status == .planned && $0.intensity == .hard }
        // Only a night that ended today counts as today's recovery; an older one must not drive the call.
        var call = DayCall.make(recovery: todaysRecovery, gap: gap, load: load, sleepDebtMin: sleep.debtMin, watch: lastNight?.day == today ? watch
                                : BodyWatch(level: .clear, signals: [], title: "", detail: ""), plannedHard: plannedHard)
        // A score worked out from part of a night is a rough guide, and the call built on it says so.
        if todaysRecovery != nil, case .cutOff = night { call = call.qualified("This is scored from part of a night, so treat it as a rough guide.") }
        let trends = TrendModel.all(days: whole, today: today, calendar: calendar)
        let fitness = FitnessModel.build(workouts: workouts, pbs: personalBests, restHR: rest, maxHR: profile.resolvedMaxHR(on: now),
                                         today: today, calendar: calendar)
        let effects = EffectModel.analyze(days: whole, checkIns: checkIns, workouts: workouts, calendar: calendar)
        let links = EffectModel.links(days: whole, calendar: calendar)
        let insights = InsightEngine.build(days: whole, today: today, baselines: baselines, sleep: sleep, load: load, watch: watch,
                                           trends: trends, effects: effects, links: links, fitness: fitness, calendar: calendar)
        return LumaAnalysis(today: today, day: day, lastNight: lastNight, night: night, gap: gap, lastScored: lastScored,
                            baselines: baselines, recovery: recovery, sleep: sleep,
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
