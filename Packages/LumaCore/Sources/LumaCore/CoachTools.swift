import Foundation

/// Everything the coach can see, as plain values captured at the start of a turn.
public struct CoachWorld: Sendable {
    public var today: String
    public var now: Date
    public var profile: LProfile
    public var days: [LDay]
    public var workouts: [LWorkout]
    public var analysis: LumaAnalysis
    public var planned: [PlannedSession]
    public var routine: [RoutineSlot]
    public var fuel: [FuelEntry]
    public var supplements: [SupplementPlan]
    public var checkIns: [CheckIn]
    public var lifts: [LiftSession]
    public var sessions: [HXSession]
    public var benchmarks: Benchmarks
    public var personalBests: [PersonalBest]
    public var notes: [String]
    /// False when the athlete has not agreed to share health data: read tools then return nothing.
    public var shareHealth: Bool

    public init(today: String, now: Date = Date(), profile: LProfile, days: [LDay], workouts: [LWorkout], analysis: LumaAnalysis,
                planned: [PlannedSession], routine: [RoutineSlot], fuel: [FuelEntry], supplements: [SupplementPlan], checkIns: [CheckIn],
                lifts: [LiftSession], sessions: [HXSession], benchmarks: Benchmarks, personalBests: [PersonalBest], notes: [String],
                shareHealth: Bool) {
        self.today = today; self.now = now; self.profile = profile; self.days = days; self.workouts = workouts; self.analysis = analysis
        self.planned = planned; self.routine = routine; self.fuel = fuel; self.supplements = supplements; self.checkIns = checkIns
        self.lifts = lifts; self.sessions = sessions; self.benchmarks = benchmarks; self.personalBests = personalBests
        self.notes = notes; self.shareHealth = shareHealth
    }

    public func fuelTargets(on day: String) -> FuelTargets {
        let ps = planned.filter { $0.day == day }
        let strain = days.last { $0.day == day }?.strain.map(LScale.strain21)
        let minutes = ps.filter { $0.status != .removed && $0.kind != .rest }.reduce(0.0) { $0 + Double($1.durationMin) }
        return FuelPlanner.targets(profile: profile, dayClass: FuelPlanner.dayClass(planned: ps, strain21: strain),
                                   trainingMinutes: max(45, minutes), on: now)
    }
}

/// A change the coach asked for. The app applies it and reports back.
public enum CoachCommand: Equatable, Sendable {
    case logFuel([FuelEntry])
    case plan([PlannedSession], replaceFrom: String?, replaceTo: String?)
    case updateSession(PlannedSession)
    case removeSession(UUID)
    case setRoutine([RoutineSlot])
    case checkIn(CheckIn)
    case remember(String)
    case logWorkout(LWorkout)
    case logStrength(LiftSession)
    case updateProfile(LProfile)
    case showChart(LMetric, days: Int)
}

public struct CoachToolError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public enum CoachTools {
    // MARK: Definitions

    static let foodItem: JSONValue = AISchema.object([
        "name": AISchema.string("Food or drink, e.g. \"Grilled chicken thigh\""),
        "quantity": AISchema.string("Amount as eaten, e.g. \"180 g\", \"1 medium\", \"330 ml\""),
        "kcal": AISchema.number("Energy in kcal for this amount"),
        "protein_g": AISchema.number("Protein in grams"),
        "carbs_g": AISchema.number("Carbohydrate in grams"),
        "fat_g": AISchema.number("Fat in grams"),
        "fiber_g": AISchema.number("Fibre in grams, if known"),
        "caffeine_mg": AISchema.number("Caffeine in mg, for coffee, tea, energy drinks, pre-workout"),
        "alcohol_g": AISchema.number("Pure alcohol in grams, for alcoholic drinks"),
    ], required: ["name", "quantity", "kcal", "protein_g", "carbs_g", "fat_g"])

    public static func foodTool(name: String = "log_food", description: String? = nil) -> AITool {
        AITool(name: name, description: description ?? "Log something the athlete ate or drank. Break a meal into its items with your best estimate of amount and macros for each. Use this for photos of meals and nutrition labels as well as typed descriptions.", properties: [
            "title": AISchema.string("Short name for the entry, e.g. \"Chicken, rice and greens\""),
            "kind": AISchema.string("What kind of entry this is", enum: ["meal", "snack", "drink"]),
            "date": AISchema.string("Day eaten as YYYY-MM-DD. Omit for today."),
            "time": AISchema.string("Time eaten as HH:MM (24 h). Omit for now."),
            "items": AISchema.array("Each food or drink in the entry", items: foodItem),
            "source": AISchema.string("Where the numbers come from: label = read from a nutrition label; photo = estimated from a photo; typed = from the athlete's description", enum: ["label", "photo", "typed"]),
            "note": AISchema.string("Assumptions worth showing, e.g. \"assumed 1 tbsp oil in cooking\""),
        ], required: ["title", "kind", "items", "source"])
    }

    public static func supplementTool(name: String = "log_supplement") -> AITool {
        AITool(name: name, description: "Log supplements or tablets the athlete took. One entry per product. Use for typed descriptions and for photos of bottles, blister packs or supplement-facts panels.", properties: [
            "supplements": AISchema.array("Each supplement taken", items: AISchema.object([
                "name": AISchema.string("Product or ingredient, e.g. \"Vitamin D3\", \"Creatine monohydrate\""),
                "amount": AISchema.number("Amount taken, in `unit`"),
                "unit": AISchema.string("mg, g, mcg, IU, ml, capsule, tablet, softgel, scoop, drop"),
            ], required: ["name", "amount", "unit"])),
            "date": AISchema.string("Day taken as YYYY-MM-DD. Omit for today."),
            "time": AISchema.string("Time taken as HH:MM (24 h). Omit for now."),
        ], required: ["supplements"])
    }

    static let sessionProps: [String: JSONValue] = [
        "date": AISchema.string("Day as YYYY-MM-DD"),
        "kind": AISchema.string("Type of session", enum: SessionKind.allCases.map { $0.rawValue }),
        "title": AISchema.string("Short title, e.g. \"Threshold intervals\""),
        "detail": AISchema.string("What to do: warm-up, main set with paces/loads/reps, cool-down. Plain text."),
        "duration_min": AISchema.integer("Planned duration in minutes"),
        "intensity": AISchema.string("How hard", enum: Intensity.allCases.map { $0.rawValue }),
        "start_time": AISchema.string("Start time HH:MM (24 h), if fixed"),
        "target_pace_s_per_km": AISchema.number("Target pace for runs, seconds per km"),
    ]

    public static let dateRange: [String: JSONValue] = [
        "start_date": AISchema.string("First day, YYYY-MM-DD"),
        "end_date": AISchema.string("Last day, YYYY-MM-DD. Omit for today."),
    ]

    public static let all: [AITool] = [
        AITool(name: "get_overview", description: "Today at a glance: recovery and what drives it, strain so far, last night's sleep, baselines, warning signs, training load, today's plan and nutrition so far. Call this first for any question about how the athlete is doing today."),
        AITool(name: "get_daily_metrics", description: "Daily strap metrics over a date range (up to 180 days): recovery, strain (0–21), sleep hours, HRV, resting HR, respiratory rate, skin temperature deviation, deep and REM minutes, sleep efficiency, steps, active energy.", properties: dateRange, required: ["start_date"]),
        AITool(name: "get_sleep", description: "Night-by-night sleep detail over a date range (up to 60 nights): time asleep, need, debt, score, stages, bed and wake times, efficiency, plus the schedule summary and tonight's recommended bedtime.", properties: dateRange, required: ["start_date"]),
        AITool(name: "get_workouts", description: "Recorded sessions over a date range (up to 200): sport, duration, heart rate, strain, distance, pace, heart-rate zone split.", properties: dateRange.merging(["sport": AISchema.string("Only this sport family", enum: LSportKind.allCases.map { $0.rawValue })]) { a, _ in a }, required: ["start_date"]),
        AITool(name: "get_training_load", description: "Training load: fitness (42-day), fatigue (7-day), form, load ratio, monotony, weekly totals for 12 weeks, the 4-week training mix by sport and the intensity split."),
        AITool(name: "get_trends_and_fitness", description: "Four-week trends in HRV, resting HR, recovery, sleep, respiratory rate and strain with significance, plus aerobic fitness: VO2max estimate, critical speed, running economy, personal bests and race-time predictions."),
        AITool(name: "get_insights", description: "Patterns found in the athlete's own data: the insight feed, measured effects of habits (alcohol, late caffeine, sauna, hard days…) on next-morning metrics, and day-to-day links between metrics."),
        AITool(name: "get_schedule", description: "The training calendar over a date range: planned sessions with their ids and whether each was done, recorded sessions, and the standing weekly routine.", properties: dateRange, required: ["start_date"]),
        AITool(name: "get_nutrition", description: "Food, drink, water and supplements over a date range: daily totals against targets, and every entry when the range is three days or fewer. Also returns the supplement stack.", properties: dateRange, required: ["start_date"]),
        AITool(name: "get_strength_log", description: "The training log of the last 90 days: every logged session (strength, class, HYROX, conditioning) with its kind, movements and sets as done, plus the best estimated one-rep max per lift.", properties: ["exercise": AISchema.string("Only this exercise")]),
        AITool(name: "get_progress", description: "Strength and training progress: each lift's estimated one-rep max, its level on Luma's scale and its six-week change; per-muscle level, weekly sets and last direct work; strong and weak points; the food log set against training days; supplement adherence. Call this for questions about strength, muscles, weak points, balance or progress."),
        AITool(name: "get_hyrox", description: "HYROX status: best time per station at race load, best 1 km, race simulations with splits, and an indicative readiness verdict and predicted finish range for each race format."),
        AITool(name: "get_checkins", description: "Daily check-ins over a date range: tags (alcohol, late caffeine, sauna, travel, unwell…), energy and soreness ratings, notes.", properties: dateRange, required: ["start_date"]),
        foodTool(),
        supplementTool(),
        AITool(name: "log_water", description: "Log water or other plain fluids.", properties: [
            "ml": AISchema.number("Volume in millilitres"),
            "time": AISchema.string("Time as HH:MM (24 h). Omit for now."),
        ], required: ["ml"]),
        AITool(name: "plan_sessions", description: "Put sessions on the training calendar. Use to build a week or block, or add a single session. Never plans over the athlete's standing routine classes unless they ask; work around them.", properties: [
            "sessions": AISchema.array("Sessions to add", items: AISchema.object(sessionProps, required: ["date", "kind", "title", "duration_min"])),
            "replace_from": AISchema.string("If set with replace_to, sessions you planned earlier in this date range are removed first (YYYY-MM-DD)"),
            "replace_to": AISchema.string("End of the range to clear (YYYY-MM-DD)"),
        ], required: ["sessions"]),
        AITool(name: "update_session", description: "Change a planned session (from get_schedule). Only the fields given are changed. Set status to skipped or done to mark it.", properties: sessionProps.merging([
            "id": AISchema.string("The session id from get_schedule"),
            "status": AISchema.string("Mark the session", enum: ["planned", "done", "skipped"]),
        ]) { a, _ in a }, required: ["id"]),
        AITool(name: "remove_session", description: "Remove a planned session from the calendar.", properties: ["id": AISchema.string("The session id from get_schedule")], required: ["id"]),
        AITool(name: "set_weekly_routine", description: "Replace the athlete's standing weekly routine (fixed classes and sessions that repeat every week).", properties: [
            "slots": AISchema.array("Every standing session in the week", items: AISchema.object([
                "weekday": AISchema.integer("1 = Monday … 7 = Sunday"),
                "kind": AISchema.string("Type of session", enum: SessionKind.allCases.map { $0.rawValue }),
                "title": AISchema.string("Name, e.g. \"Conditioning class\""),
                "start_time": AISchema.string("HH:MM (24 h), if fixed"),
                "duration_min": AISchema.integer("Minutes"),
            ], required: ["weekday", "kind", "title"])),
        ], required: ["slots"]),
        AITool(name: "log_checkin", description: "Record how a day went: habits and circumstances that may affect recovery, plus energy and soreness.", properties: [
            "date": AISchema.string("YYYY-MM-DD. Omit for today."),
            "tags": AISchema.array("What applied that day", items: AISchema.string("Tag", enum: CheckInTag.allCases.map { $0.rawValue })),
            "energy": AISchema.integer("1 (flat) to 5 (great)"),
            "soreness": AISchema.integer("1 (fresh) to 5 (very sore)"),
            "note": AISchema.string("Anything else worth keeping"),
        ]),
        AITool(name: "log_workout", description: "Record a session the strap or app did not capture, from the athlete's description or a photo of a whiteboard or machine screen.", properties: [
            "date": AISchema.string("YYYY-MM-DD. Omit for today."),
            "start_time": AISchema.string("HH:MM (24 h). Omit if unknown."),
            "sport": AISchema.string("Running, HYROX, Strength, Conditioning, Cycling, Rowing, Swimming, Walking, Mobility, or another name"),
            "duration_min": AISchema.number("Minutes"),
            "distance_km": AISchema.number("Distance, if any"),
            "avg_hr": AISchema.number("Average heart rate, if known"),
            "notes": AISchema.string("What was done: the workout as written, loads, times"),
        ], required: ["sport", "duration_min"]),
        sessionTool(),
        AITool(name: "update_profile", description: "Update facts in the athlete's profile when they tell you them. Only the fields given are changed.", properties: [
            "weight_kg": AISchema.number("Body mass in kg"),
            "max_hr": AISchema.number("Measured maximum heart rate"),
            "threshold_hr": AISchema.number("Lactate-threshold heart rate"),
            "five_k_seconds": AISchema.number("Current 5 km time in seconds"),
            "sleep_need_hours": AISchema.number("Fixed nightly sleep need in hours"),
            "race_name": AISchema.string("Next race"),
            "race_date": AISchema.string("Race day, YYYY-MM-DD"),
            "goals": AISchema.string("The athlete's goals in their words"),
        ]),
        AITool(name: "remember", description: "Keep a durable fact about the athlete for future conversations: injuries, preferences, constraints, equipment, how they like to be coached. One short sentence. Do not store things already in the profile or the data.", properties: [
            "fact": AISchema.string("The fact, as one sentence"),
        ], required: ["fact"]),
        AITool(name: "show_chart", description: "Show the athlete a chart of one metric's recent history inside the conversation. Use when a picture makes the point better than numbers.", properties: [
            "metric": AISchema.string("Which metric", enum: LMetric.allCases.map { $0.rawValue }),
            "days": AISchema.integer("How many days back, 7 to 180"),
        ], required: ["metric"]),
    ]

    public static let readNames: Set<String> = ["get_overview", "get_daily_metrics", "get_sleep", "get_workouts", "get_training_load",
                                                "get_trends_and_fitness", "get_insights", "get_schedule", "get_nutrition",
                                                "get_strength_log", "get_progress", "get_hyrox", "get_checkins"]

    /// A short label for a tool call while it runs.
    public static func activity(_ name: String) -> String {
        switch name {
        case "get_overview": return "Reading today"
        case "get_daily_metrics": return "Reading your daily metrics"
        case "get_sleep": return "Reading your sleep"
        case "get_workouts": return "Reading your sessions"
        case "get_training_load": return "Checking training load"
        case "get_trends_and_fitness": return "Checking trends and fitness"
        case "get_insights": return "Looking for patterns"
        case "get_schedule": return "Reading your calendar"
        case "get_nutrition": return "Reading your food log"
        case "get_strength_log": return "Reading your training log"
        case "get_progress": return "Checking your progress"
        case "get_hyrox": return "Checking HYROX benchmarks"
        case "get_checkins": return "Reading your check-ins"
        case "log_food": return "Logging food"
        case "log_supplement": return "Logging supplements"
        case "log_water": return "Logging water"
        case "plan_sessions", "update_session", "remove_session", "set_weekly_routine": return "Updating your calendar"
        case "log_checkin": return "Saving the check-in"
        case "log_workout", "log_strength_session": return "Logging the session"
        case "update_profile": return "Updating your profile"
        case "remember": return "Making a note"
        case "show_chart": return "Drawing a chart"
        default: return "Working"
        }
    }

    // MARK: Argument helpers

    static func day(_ v: JSONValue?, world: CoachWorld, calendar: Calendar) -> String {
        guard let s = v?.string?.lowercased().trimmingCharacters(in: .whitespaces), !s.isEmpty else { return world.today }
        if s == "today" { return world.today }
        if s == "yesterday" { return LDate.adding(-1, to: world.today, calendar: calendar) }
        if s == "tomorrow" { return LDate.adding(1, to: world.today, calendar: calendar) }
        return LDate.date(s, calendar: calendar) != nil && s.count == 10 ? s : world.today
    }

    /// "HH:MM" → minutes after midnight.
    static func minutes(_ v: JSONValue?) -> Int? {
        guard let s = v?.string else { return nil }
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count >= 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else { return nil }
        return p[0] * 60 + p[1]
    }

    static func date(day: String, time: JSONValue?, world: CoachWorld, calendar: Calendar) -> Date {
        guard let start = LDate.startOfDay(day, calendar: calendar) else { return world.now }
        if let m = minutes(time) { return start.addingTimeInterval(Double(m) * 60) }
        return day == LDate.key(world.now, calendar: calendar) ? world.now : start.addingTimeInterval(12 * 3600)
    }

    static func range(_ input: JSONValue, world: CoachWorld, maxDays: Int, calendar: Calendar) -> [String] {
        let end = day(input["end_date"], world: world, calendar: calendar)
        var start = day(input["start_date"], world: world, calendar: calendar)
        if start > end { start = end }
        let n = min(maxDays, LDate.daysBetween(start, end, calendar: calendar) + 1)
        return LDate.range(ending: end, count: max(1, n), calendar: calendar)
    }

    // MARK: Read tools

    /// Runs a read-only tool. Returns nil when `name` is not a read tool.
    public static func read(_ name: String, input: JSONValue, world w: CoachWorld, calendar: Calendar = LDate.calendar) -> JSONValue? {
        guard readNames.contains(name) else { return nil }
        guard w.shareHealth else {
            return ["error": "The athlete has not turned on sharing health data with the coach, so this is unavailable. They can enable it in Coach settings."]
        }
        let a = w.analysis
        let byDay = Dictionary(w.days.map { ($0.day, $0) }, uniquingKeysWith: { x, _ in x })
        switch name {
        case "get_overview":
            return overview(w, calendar: calendar)
        case "get_daily_metrics":
            let keys = range(input, world: w, maxDays: 180, calendar: calendar)
            let metrics: [LMetric] = [.recovery, .strain, .sleepHours, .hrv, .restingHR, .respRate, .skinTempDev, .deepMin, .remMin, .sleepEfficiency, .steps, .activeKcal]
            let rows: [JSONValue] = keys.compactMap { k in
                guard let d = byDay[k] else { return nil }
                return .array([.string(k)] + metrics.map { m in JSONValue.rounded(m.value(d), m.decimals) })
            }
            // Nights only partly recorded are named, so their rows are not read as short or poor nights.
            let partNights: [JSONValue] = a.sleep.nights.filter { $0.partial && keys.contains($0.day) }.map { JSONValue.string($0.day) }
            var out: [String: JSONValue] = [
                "columns": .array([.string("date")] + metrics.map { JSONValue.string($0.rawValue) }),
                "units": "recovery %, strain 0-21, sleepHours h, hrv ms (RMSSD), restingHR bpm, respRate breaths/min, skinTempDev °C from baseline, deepMin/remMin min, sleepEfficiency %, activeKcal kcal",
                "rows": .array(rows), "days_without_data": .number(Double(keys.count - rows.count)),
            ]
            if !partNights.isEmpty {
                out["partly_recorded_nights"] = .array(partNights)
                out["how_to_read_them"] = .string(Self.partNightNote)
            }
            return .object(out)
        case "get_sleep":
            let keys = Set(range(input, world: w, maxDays: 60, calendar: calendar))
            let nights: [JSONValue] = a.sleep.nights.filter { keys.contains($0.day) }.map { n -> JSONValue in
                ["date": .string(n.day), "asleep_min": .rounded(n.asleepMin, 0), "need_min": .rounded(n.needMin, 0), "debt_before_min": .rounded(n.debtMin, 0),
                 "score": .rounded(n.score, 0), "efficiency_pct": .rounded(n.efficiency, 0), "deep_min": .rounded(n.deepMin, 0), "rem_min": .rounded(n.remMin, 0),
                 "light_min": .rounded(n.lightMin, 0), "awake_min": .rounded(n.awakeMin, 0), "wake_ups": .whole(n.awakenings),
                 "bedtime": .optional(n.bedtime.map { LFormat.timeOfDay(minutes: $0) }), "wake_time": .optional(n.wake.map { LFormat.timeOfDay(minutes: $0) }),
                 "nap_min": .rounded(n.napMin, 0), "partly_recorded": .bool(n.partial)]
            }
            return ["nights": .array(nights), "summary": [
                "avg_7_nights_min": .rounded(a.sleep.avg7Min, 0), "avg_30_nights_min": .rounded(a.sleep.avg30Min, 0),
                "sleep_debt_now_min": .rounded(a.sleep.debtMin, 0), "consistency_pct": .rounded(a.sleep.consistency, 0),
                "usual_bedtime": .optional(a.sleep.typicalBedtime.map { LFormat.timeOfDay(minutes: $0) }),
                "usual_wake": .optional(a.sleep.typicalWake.map { LFormat.timeOfDay(minutes: $0) }),
                "weekend_shift_min": .rounded(a.sleep.socialJetlagMin, 0), "need_tonight_min": .rounded(a.sleep.tonightNeedMin, 0),
                "recommended_bedtime_tonight": .optional(a.sleep.recommendedBedtime.map { LFormat.timeOfDay(minutes: $0) }),
            ]]
        case "get_workouts":
            let keys = Set(range(input, world: w, maxDays: 365, calendar: calendar))
            let kind = input["sport"]?.string.flatMap { LSportKind(rawValue: $0) }
            let list = w.workouts.filter { keys.contains($0.day) && (kind == nil || $0.kind == kind) }.prefix(200)
            return ["sessions": .array(list.map(workoutJSON)), "count": .number(Double(list.count))]
        case "get_training_load":
            let l = a.load
            let weeks: [JSONValue] = stride(from: 0, to: min(l.days.count, 84), by: 7).map { off -> JSONValue in
                let end = l.days.count - off
                let slice = l.days[max(0, end - 7)..<end]
                return ["week_starting": .string(slice.first?.day ?? ""), "load": .rounded(slice.reduce(0) { $0 + $1.load }, 0)]
            }
            let from = LDate.adding(-27, to: w.today, calendar: calendar)
            let mix = LoadModel.minutesByKind(workouts: w.workouts, from: from, to: w.today)
            var split: JSONValue = .null
            if let pol = LoadModel.polarization(LoadModel.zoneSeconds(workouts: w.workouts, from: from, to: w.today)) {
                split = ["easy_z1_2": .rounded(pol.easy * 100, 0), "moderate_z3": .rounded(pol.moderate * 100, 0), "hard_z4_5": .rounded(pol.hard * 100, 0)]
            }
            return ["status": .string(l.status.title), "explanation": .string(l.detail), "ready": .bool(l.ready), "history_days": .number(Double(l.historyDays)),
                    "fitness_42d": .rounded(l.today?.fitness), "fatigue_7d": .rounded(l.today?.fatigue), "form": .rounded(l.today?.form),
                    "load_ratio_acwr": .rounded(l.acwr, 2), "monotony": .rounded(l.monotony, 2), "this_week_load": .rounded(l.weekLoad, 0),
                    "last_week_load": .rounded(l.prevWeekLoad, 0), "weekly_loads_newest_first": .array(weeks),
                    "mix_minutes_4_weeks": .object(Dictionary(mix.map { ($0.kind.rawValue, JSONValue.rounded($0.minutes, 0)) }, uniquingKeysWith: { x, _ in x })),
                    "intensity_split_4_weeks": split,
                    "note": "Load is Banister TRIMP from session heart rate. Ratio 0.8–1.3 builds safely; above 1.5 is a spike."]
        case "get_trends_and_fitness":
            let f = a.fitness
            return ["trends_4_weeks": .array(a.trends.map { t -> JSONValue in
                        ["metric": .string(t.metric.rawValue), "per_week": .rounded(t.perWeek, 2), "p_value": .rounded(t.p, 3), "this_week_mean": .rounded(t.recent, 1),
                         "previous_4_weeks_mean": .rounded(t.prior, 1), "reliable_direction": .string(t.direction == 0 ? "none" : (t.direction > 0 ? "rising" : "falling")),
                         "improving": .flag(t.improving)]
                    }),
                    "vo2max_estimate": .rounded(f.vo2max), "vo2max_basis": .string(f.vo2maxFromRuns ? "steady runs with heart rate" : "resting and maximum heart rate (coarse)"),
                    "critical_speed_m_per_s": .rounded(f.criticalSpeed, 2), "d_prime_m": .rounded(f.dPrime, 0),
                    "running_economy_change_8_weeks_pct": .rounded(f.efficiencyChangePct), "observed_max_hr_6_months": .rounded(f.observedMaxHR, 0),
                    "personal_bests": .array(w.personalBests.map { ["distance_m": .rounded($0.distanceM, 0), "seconds": .rounded($0.seconds, 0)] }),
                    "predicted_times": .array(f.predictions.map { ["distance_m": .rounded($0.distanceM, 0), "seconds": .rounded($0.seconds, 0)] })]
        case "get_insights":
            return ["insights": .array(a.insights.prefix(14).map { ["topic": .string($0.topic.rawValue), "tone": .string($0.tone.rawValue), "title": .string($0.title), "detail": .string($0.body)] }),
                    "habit_effects_on_next_morning": .array(a.effects.prefix(14).map { e -> JSONValue in
                        ["habit": .string(e.factor), "metric": .string(e.outcome.rawValue), "mean_after": .rounded(e.withMean), "mean_otherwise": .rounded(e.withoutMean),
                         "nights_after": .number(Double(e.nWith)), "nights_otherwise": .number(Double(e.nWithout)), "effect_size_g": .rounded(e.g, 2),
                         "p_value": .rounded(e.p, 3), "survives_false_discovery_control": .bool(e.reliable)]
                    }),
                    "links": .array(a.links.map { ["x": .string($0.xLabel), "y": .string($0.yLabel), "rank_correlation": .rounded($0.r, 2), "days": .number(Double($0.n)), "reliable": .bool($0.reliable)] })]
        case "get_schedule":
            let keys = range(input, world: w, maxDays: 60, calendar: calendar)
            let days = Schedule.days(keys, planned: w.planned, workouts: w.workouts, logs: w.lifts)
            let rows: [JSONValue] = days.filter { !$0.planned.isEmpty || !$0.workouts.isEmpty || !$0.logs.isEmpty }.map { d -> JSONValue in
                ["date": .string(d.day), "weekday": .string(weekdayName(d.day, calendar)),
                 "planned": .array(d.planned.map { p -> JSONValue in
                    ["id": .string(p.id.uuidString), "kind": .string(p.kind.rawValue), "title": .string(p.title), "detail": .string(p.detail),
                     "duration_min": .number(Double(p.durationMin)), "intensity": .string(p.intensity.rawValue),
                     "start_time": .optional(p.startMinutes.map { LFormat.timeOfDay(minutes: Double($0)) }), "from": .string(p.origin.rawValue),
                     "status": .string(d.isDone(p) ? "done" : p.status.rawValue)]
                 }),
                 "recorded": .array(d.workouts.map(workoutJSON)),
                 "logged": .array(d.logs.map { l -> JSONValue in
                    ["title": .string(l.title), "kind": .string(l.resolvedKind.rawValue), "movements": .number(Double(l.exercises.count))]
                 })]
            }
            return ["today": .string(w.today), "days": .array(rows),
                    "weekly_routine": .array(w.routine.map { ["weekday": .number(Double($0.weekday)), "kind": .string($0.kind.rawValue), "title": .string($0.title),
                                                             "start_time": .optional($0.startMinutes.map { LFormat.timeOfDay(minutes: Double($0)) }),
                                                             "duration_min": .number(Double($0.durationMin))] })]
        case "get_nutrition":
            let keys = range(input, world: w, maxDays: 60, calendar: calendar)
            let listEntries = keys.count <= 3
            let rows: [JSONValue] = keys.map { k in
                let entries = w.fuel.filter { $0.day == k }.sorted { $0.at < $1.at }
                let t = FuelTotals.of(entries)
                let target = w.fuelTargets(on: k)
                var o: [String: JSONValue] = ["date": .string(k), "kcal": .rounded(t.kcal, 0), "protein_g": .rounded(t.proteinG, 0), "carbs_g": .rounded(t.carbsG, 0),
                                              "fat_g": .rounded(t.fatG, 0), "water_ml": .rounded(t.waterMl, 0), "caffeine_mg": .rounded(t.caffeineMg, 0),
                                              "alcohol_g": .rounded(t.alcoholG, 0), "entries_logged": .number(Double(t.entries)),
                                              "target": ["day_type": .string(target.dayClass.rawValue), "kcal": .rounded(target.kcal, 0), "protein_g": .rounded(target.proteinG, 0),
                                                         "carbs_g": .rounded(target.carbsG, 0), "fat_g": .rounded(target.fatG, 0), "water_ml": .rounded(target.waterMl, 0)]]
                if listEntries {
                    o["entries"] = .array(entries.map { e -> JSONValue in
                        ["time": .string(LFormat.timeOfDay(minutes: minutesOfDay(e.at, calendar))), "kind": .string(e.kind.rawValue), "title": .string(e.title),
                         "kcal": .rounded(e.kcal, 0), "protein_g": .rounded(e.proteinG, 0), "carbs_g": .rounded(e.carbsG, 0), "fat_g": .rounded(e.fatG, 0),
                         "water_ml": .rounded(e.waterMl, 0), "supplement": .optional(e.supplement?.text), "source": .string(e.source.rawValue)]
                    })
                }
                return .object(o)
            }
            return ["days": .array(rows), "supplement_stack": .array(w.supplements.filter { $0.active }.map {
                ["name": .string($0.dose.name), "dose": .string($0.dose.text), "timing": .string($0.timing.rawValue)] }),
                    "note": "Days with few entries_logged are probably under-logged rather than under-eaten."]
        case "get_strength_log":
            let only = input["exercise"]?.string?.lowercased()
            let cutoff = w.now.addingTimeInterval(-90 * 86_400)
            let sessions = w.lifts.filter { $0.start >= cutoff }.sorted { $0.start > $1.start }.prefix(40)
            let rec = LiftMath.records(w.lifts, bodyKg: w.profile.weightKg)
            return ["sessions": .array(sessions.map { s -> JSONValue in
                        var o: [String: JSONValue] = ["date": .string(s.day), "title": .string(s.title), "kind": .string(s.resolvedKind.rawValue),
                                                      "volume_kg": .rounded(s.volumeKg, 0)]
                        if let m = s.minutes { o["duration_min"] = .rounded(m, 0) }
                        if let src = s.source { o["logged_from"] = .string(src) }
                        if !s.note.isEmpty { o["note"] = .string(s.note) }
                        o["movements"] = .array(s.exercises.filter { only == nil || $0.name.lowercased().contains(only ?? "") }.map { e -> JSONValue in
                            var m: [String: JSONValue] = ["name": .string(e.name), "sets": .array(e.sets.filter { $0.done }.map { JSONValue.string($0.text) })]
                            if let n = e.note { m["note"] = .string(n) }
                            return .object(m)
                        })
                        return .object(o)
                    }),
                    "best_estimated_1rm_kg": .object(Dictionary(rec.map { ($0.key, JSONValue.rounded($0.value.e1RM)) }, uniquingKeysWith: { x, _ in x })),
                    "note": "A set with no kg had no load written down. Estimated maxes use sets of 12 reps or fewer; pull-ups, chin-ups and dips count bodyweight plus any added load."]
        case "get_progress":
            return progressJSON(w, calendar: calendar)
        case "get_hyrox":
            let ready = RaceReadiness.assess(benchmarks: w.benchmarks, sessions: w.sessions, sex: w.profile.sex, personalBests: w.personalBests)
            return ["station_bests_s": .object(Dictionary(Station.allCases.compactMap { st -> (String, JSONValue)? in
                        let load = st.loadKg(format: w.profile.format, sex: w.profile.sex)
                        guard let best = w.benchmarks.bestStationS(st, loadKg: load) else { return nil }
                        return (st.title, .rounded(best, 0))
                    }, uniquingKeysWith: { x, _ in x })),
                    "best_1k_run_s": .rounded(w.benchmarks.bestRun1kS?.seconds, 0),
                    "simulations": .array(w.sessions.filter { $0.kind.isHyrox && $0.isComplete }.prefix(8).map { s -> JSONValue in
                        ["date": .string(LDate.key(s.startedAt, calendar: calendar)), "kind": .string(s.kind.title), "total_s": .rounded(s.totalS, 0),
                         "run_splits_s": .array(s.runs.compactMap { $0.durationS }.map { .rounded($0, 0) }),
                         "stations_s": .object(Dictionary(s.stations.compactMap { seg -> (String, JSONValue)? in
                            guard let st = seg.station, let d = seg.durationS else { return nil }
                            return (st.title, .rounded(d, 0))
                         }, uniquingKeysWith: { x, _ in x }))]
                    }),
                    "readiness_by_format": .array(ready.map { r -> JSONValue in
                        ["format": .string(r.format.title), "verdict": .string("\(r.verdict)"), "predicted_low_s": .rounded(r.predictedLowS, 0),
                         "predicted_high_s": .rounded(r.predictedHighS, 0), "confidence_0_1": .rounded(r.confidence, 2), "gaps": .array(r.gaps.map { JSONValue.string($0) }),
                         "assumption": .optional(r.assumption)]
                    }),
                    "note": "Readiness is indicative: it comes from the athlete's own benchmark and simulation times, not from a lab or race result."]
        case "get_checkins":
            let keys = Set(range(input, world: w, maxDays: 120, calendar: calendar))
            return ["checkins": .array(w.checkIns.filter { keys.contains($0.day) }.sorted { $0.day < $1.day }.map { c -> JSONValue in
                ["date": .string(c.day), "tags": .array(c.tags.map { JSONValue.string($0.rawValue) }), "energy_1_5": .whole(c.energy),
                 "soreness_1_5": .whole(c.soreness), "note": .string(c.note)]
            })]
        default:
            return nil
        }
    }

    static func weekdayName(_ key: String, _ calendar: Calendar) -> String {
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][LDate.weekday(key, calendar: calendar) - 1]
    }

    static func minutesOfDay(_ date: Date, _ calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    static func workoutJSON(_ w: LWorkout) -> JSONValue {
        var o: [String: JSONValue] = ["id": .string(w.id), "date": .string(w.day), "sport": .string(w.sport)]
        o["duration_min"] = .rounded(w.durationS / 60, 0)
        o["avg_hr"] = .rounded(w.avgHR, 0)
        o["max_hr"] = .rounded(w.maxHR, 0)
        o["strain_0_21"] = .rounded(w.strain.map(LScale.strain21))
        o["distance_km"] = .rounded(w.distanceM.map { $0 / 1000 }, 2)
        o["pace_s_per_km"] = .rounded(w.paceSPerKm, 0)
        o["kcal"] = .rounded(w.kcal, 0)
        if let z = w.zonePct { o["zone_pct_z1_to_z5"] = .array(z.map { JSONValue.rounded($0, 0) }) }
        o["notes"] = .optional(w.notes)
        return .object(o)
    }

    /// What the coach is told about a night only part of which reached the phone, wherever one appears.
    static let partNightNote = "Only part of such a night reached the phone. Its sleep, HRV, resting heart rate and breathing figures describe the recorded part and are not the night's. It is not a short or poor night: do not advise as if the athlete slept that little, do not compare its figures with other nights, and say plainly that the night was only partly recorded. It is left out of sleep debt, averages and baselines."

    /// The snapshot used both by `get_overview` and, in brief, by the system prompt.
    public static func overview(_ w: CoachWorld, calendar: Calendar = LDate.calendar) -> JSONValue {
        let a = w.analysis
        let night = a.lastNight
        let fresh = night?.day == w.today
        let t = FuelTotals.of(w.fuel.filter { $0.day == w.today })
        let target = w.fuelTargets(on: w.today)
        let todaysPlan = Schedule.days([w.today], planned: w.planned, workouts: w.workouts, logs: w.lifts).first

        let factors: [JSONValue] = (a.recovery?.factors ?? []).map { f -> JSONValue in
            let pull = f.direction > 0 ? "helping" : (f.direction < 0 ? "dragging" : "neutral")
            return ["metric": .string(f.metric.rawValue), "value": .rounded(f.value), "your_usual": .rounded(f.baseline),
                    "note": .string(f.note), "pull": .string(pull)]
        }
        var recoveryFields: [String: JSONValue] = [
            "score_pct": .rounded(night?.recovery, 0), "from_night_ending": .optional(night?.day), "is_todays": .bool(fresh),
            "band": .optional(a.recovery?.band?.title), "headline": .optional(a.recovery?.headline), "factors": .array(factors),
        ]
        // The reason today has no score, as the app states it, so the coach gives the same one.
        if let gap = a.gap {
            let words = DayCall.waiting(gap)
            recoveryFields["why_today_has_no_score"] = .string(words.title + ". " + words.body)
        }
        let recovery: JSONValue = .object(recoveryFields)
        let baselines: JSONValue = [
            "nights_recorded": .number(Double(a.baselines.nights)), "hrv_ms": .rounded(a.baselines.hrv?.center),
            "resting_hr": .rounded(a.baselines.restingHR?.center), "resp_rate": .rounded(a.baselines.respRate?.center),
            "established": .bool(a.baselines.nights >= LBaseline.established),
        ]
        let call: JSONValue = [
            "title": .string(a.call.title), "advice": .string(a.call.body),
            "strain_target": .optional(a.call.strainTarget.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" }),
        ]
        let last = fresh ? a.sleep.last : nil
        var sleepFields: [String: JSONValue] = [
            "asleep_min": .rounded(last?.asleepMin, 0), "need_min": .rounded(last?.needMin, 0), "score": .rounded(last?.score, 0),
            "debt_now_min": .rounded(a.sleep.debtMin, 0), "need_tonight_min": .rounded(a.sleep.tonightNeedMin, 0),
            "recommended_bedtime": .optional(a.sleep.recommendedBedtime.map { LFormat.timeOfDay(minutes: $0) }),
        ]
        if a.night.isPartial {
            sleepFields["partly_recorded"] = .bool(true)
            sleepFields["its_record"] = .string(RecordReport.nightLine(a.night, calendar: calendar))
            sleepFields["how_to_read_it"] = .string(partNightNote)
        }
        let sleep: JSONValue = .object(sleepFields)
        let plan: [JSONValue] = (todaysPlan?.planned ?? []).map { p -> JSONValue in
            let status = todaysPlan?.isDone(p) == true ? "done" : p.status.rawValue
            return ["id": .string(p.id.uuidString), "title": .string(p.title), "kind": .string(p.kind.rawValue),
                    "duration_min": .number(Double(p.durationMin)), "intensity": .string(p.intensity.rawValue), "status": .string(status)]
        }
        let nutrition: JSONValue = [
            "kcal": .rounded(t.kcal, 0), "protein_g": .rounded(t.proteinG, 0), "carbs_g": .rounded(t.carbsG, 0), "fat_g": .rounded(t.fatG, 0),
            "water_ml": .rounded(t.waterMl, 0), "caffeine_mg": .rounded(t.caffeineMg, 0), "entries_logged": .number(Double(t.entries)),
            "target_kcal": .rounded(target.kcal, 0), "target_protein_g": .rounded(target.proteinG, 0), "target_carbs_g": .rounded(target.carbsG, 0),
            "target_water_ml": .rounded(target.waterMl, 0), "day_type": .string(target.dayClass.rawValue),
        ]
        var o: [String: JSONValue] = ["date": .string(w.today)]
        o["recovery"] = recovery
        o["baselines"] = baselines
        o["strain_today_0_21"] = .rounded(a.day?.strain.map(LScale.strain21))
        o["todays_call"] = call
        o["warning_signs"] = ["level": .string("\(a.watch.level)"), "detail": .string(a.watch.detail)]
        o["sleep_last_night"] = sleep
        o["training_load"] = ["status": .string(a.load.status.title), "load_ratio": .rounded(a.load.acwr, 2), "ready": .bool(a.load.ready)]
        o["today_plan"] = .array(plan)
        o["sessions_recorded_today"] = .array((todaysPlan?.workouts ?? []).map(workoutJSON))
        o["nutrition_today"] = nutrition
        return .object(o)
    }
}
