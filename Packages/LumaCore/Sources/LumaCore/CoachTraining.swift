import Foundation

// MARK: - Reading and logging training sessions

public extension CoachTools {
    private static let setSchema: JSONValue = AISchema.object([
        "reps": AISchema.integer("Repetitions, for a movement that is counted"),
        "kg": AISchema.number("Load in kg, only where one is written for the athlete or stated by them. Leave out otherwise; never guess one."),
        "meters": AISchema.number("Distance in metres: a sled length, a carry, a run, a row, a ski"),
        "seconds": AISchema.number("Duration in seconds: a hold or a timed effort"),
        "calories": AISchema.number("Calories, for a machine counted in calories"),
    ])

    private static let movementSchema: JSONValue = AISchema.object([
        "name": AISchema.string("The movement. Use the name from Luma's list when it is one of them, otherwise the name as written."),
        "sets": AISchema.array("One entry per set or round, in order. \"4 x 8\" is four sets of 8 reps.", items: setSchema),
        "note": AISchema.string("How it is done, as written: tempo, \"each side\", \"AMRAP 12 min\", \"every 90 s\""),
        "muscles": AISchema.array("Main muscles worked, only for a movement that is not on Luma's list",
                                  items: AISchema.string("One muscle group", enum: Muscle.allCases.map { $0.rawValue })),
    ], required: ["name", "sets"])

    private static let loggedKinds: [String] = SessionKind.allCases.filter { $0 != .rest }.map { $0.rawValue }

    private static let sessionFields: [String: JSONValue] = [
        "title": AISchema.string("Short and specific, e.g. \"Lower body strength\", \"HYROX class\", \"Engine: ski and sleds\""),
        "kind": AISchema.string("What kind of session it is", enum: loggedKinds),
        "date": AISchema.string("YYYY-MM-DD, only when the day is shown or stated. Leave out otherwise."),
        "duration_min": AISchema.number("Length in minutes, when shown or stated"),
        "movements": AISchema.array("Every movement of the session, in order", items: movementSchema),
        "as_written": AISchema.string("The session transcribed as it is written, line by line"),
        "note": AISchema.string("Anything worth keeping that the fields above do not hold"),
    ]

    /// The tool a one-shot read of workout photos answers with: several sessions at once.
    static func workoutsTool(name: String = "log_workouts") -> AITool {
        var fields = sessionFields
        fields["photos"] = AISchema.array("Which photos this session was read from (1 is the first)", items: AISchema.integer("Photo number"))
        return AITool(name: name, description: "Record the training sessions shown in the photos or described in the note: one entry per separate session, each sorted into its kind, with its movements and sets.", properties: [
            "workouts": AISchema.array("Each separate session", items: AISchema.object(fields, required: ["title", "kind", "movements", "photos"])),
        ], required: ["workouts"])
    }

    /// The coach's tool for logging one session it was told about or shown.
    static func sessionTool() -> AITool {
        AITool(name: "log_strength_session", description: "Record what was done in a training session: a strength session, a class, a HYROX or conditioning session. Give each movement with its sets. Use it for typed descriptions and for photos of whiteboards, class screens and tracking apps.",
               properties: sessionFields, required: ["title", "movements"])
    }

    private static func positive(_ v: Double?, max: Double) -> Double? {
        guard let v, v > 0, v.isFinite else { return nil }
        return Swift.min(v, max)
    }

    /// Reads movements from tool input. A movement keeps Luma's own name when Luma knows it, so its
    /// history lines up with what was logged before.
    static func exercises(_ v: JSONValue?) -> [LiftExercise] {
        (v?.array ?? []).compactMap { e in
            guard let raw = e["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            let known = ExerciseLibrary.match(raw)
            var sets: [LiftSet] = (e["sets"]?.array ?? []).compactMap { s in
                let reps = Swift.min(1000, Swift.max(0, s["reps"]?.int ?? 0))
                let kg = Swift.min(1000, Swift.max(0, s["kg"]?.number ?? 0))
                let set = LiftSet(reps: reps, kg: kg, done: true, meters: positive(s["meters"]?.number, max: 100_000),
                                  seconds: positive(s["seconds"]?.number, max: 36_000), calories: positive(s["calories"]?.number, max: 5000))
                return set.hasContent ? set : nil
            }
            // "sets": 4 with reps and kg beside it, which models sometimes send in place of a list.
            if sets.isEmpty, let n = e["sets"]?.int, n > 0, let reps = e["reps"]?.int, reps > 0 {
                let kg = Swift.min(1000, Swift.max(0, e["kg"]?.number ?? 0))
                sets = (0..<Swift.min(n, 30)).map { _ in LiftSet(reps: Swift.min(1000, reps), kg: kg, done: true) }
            }
            let muscles = known == nil ? (e["muscles"]?.array ?? []).compactMap { $0.string }.filter { Muscle(rawValue: $0) != nil } : []
            let note = e["note"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LiftExercise(name: known?.name ?? ExerciseLibrary.display(raw), sets: sets, muscles: muscles.isEmpty ? nil : muscles,
                                note: (note ?? "").isEmpty ? nil : note)
        }
    }

    /// One logged session from tool input, or nil when it holds nothing usable. `day` is used when
    /// the input names no day of its own; a day in the future or more than a year back is not believed.
    static func loggedSession(_ i: JSONValue, day fallback: String, source: String, now: Date,
                              calendar: Calendar = LDate.calendar) -> LiftSession? {
        let exercises = self.exercises(i["movements"] ?? i["exercises"])
        let written = i["as_written"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !exercises.isEmpty || !written.isEmpty else { return nil }
        var day = fallback
        let today = LDate.key(now, calendar: calendar)
        if let d = i["date"]?.string, d.count == 10, LDate.date(d, calendar: calendar) != nil, d <= today,
           LDate.daysBetween(d, today, calendar: calendar) <= 366 {
            day = d
        }
        let noon = LDate.startOfDay(day, calendar: calendar)?.addingTimeInterval(12 * 3600) ?? now
        let start = day == today ? now : noon
        var end: Date?
        if let m = i["duration_min"]?.number, m >= 1, m <= 600 { end = start.addingTimeInterval(m * 60) }
        let kind = i["kind"]?.string.flatMap { SessionKind(rawValue: $0) }
        let given = i["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = given.isEmpty ? (kind ?? .strength).title : given
        return LiftSession(start: start, end: end, title: String(title.prefix(80)), exercises: exercises,
                           note: i["note"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                           kind: kind == .rest ? nil : kind, source: source, asWritten: written.isEmpty ? nil : String(written.prefix(4000)))
    }

    /// The sessions a one-shot read returned, each with the numbers of the photos it came from.
    static func loggedSessions(_ input: JSONValue, day: String, now: Date,
                               calendar: Calendar = LDate.calendar) -> [(session: LiftSession, photos: [Int])] {
        (input["workouts"]?.array ?? []).compactMap { w in
            guard let s = loggedSession(w, day: day, source: "photo", now: now, calendar: calendar) else { return nil }
            let photos = (w["photos"]?.array ?? []).compactMap { $0.int }.filter { $0 >= 1 }
            return (s, photos)
        }
    }

    // MARK: Progress

    /// Everything the Progress view shows, for the coach.
    static func progressJSON(_ w: CoachWorld, calendar: Calendar = LDate.calendar) -> JSONValue {
        let p = TrainingProgress.build(lifts: w.lifts, workouts: w.workouts, fuel: w.fuel, supplements: w.supplements,
                                       profile: w.profile, today: w.today, calendar: calendar)
        func lift(_ l: LiftProgress) -> JSONValue {
            var o: [String: JSONValue] = ["lift": .string(l.name), "est_one_rep_max_kg": .rounded(l.current ?? l.allTime, 1),
                                          "last_logged": .string(l.lastDay), "days_logged": .number(Double(l.points.count))]
            if l.current == nil { o["note"] = "Not lifted in the last 12 weeks; the figure is its best ever." }
            if l.bodyweight { o["counts_bodyweight"] = true }
            if let r = l.ratio { o["times_bodyweight"] = .rounded(r, 2) }
            if let level = l.level {
                o["level"] = .string(StrengthLevel(level).title)
                o["level_0_to_5"] = .rounded(level, 1)
                o["gauges"] = .array(l.measures.map { JSONValue.string($0.rawValue) })
            }
            if let c = l.change { o["change_6_weeks_pct"] = .rounded(c * 100, 1) }
            return .object(o)
        }
        let muscles: [JSONValue] = p.muscles.map { m in
            var o: [String: JSONValue] = ["muscle": .string(m.muscle.rawValue), "sets_last_7_days": .rounded(m.weekSets, 1)]
            if let u = m.usualSets { o["usual_weekly_sets"] = .rounded(u, 1) }
            if let d = m.lastDirect { o["last_direct_work"] = .string(d) }
            if let b = m.basis, let level = b.level {
                o["level"] = .string(StrengthLevel(level).title)
                o["read_from"] = .string(b.name)
            } else {
                o["level"] = "not measured"
            }
            if !m.movements.isEmpty { o["trained_by"] = .array(m.movements.map { JSONValue.string($0) }) }
            return .object(o)
        }
        var out: [String: JSONValue] = [
            "lifts": .array(p.lifts.prefix(24).map(lift)),
            "muscles": .array(muscles),
            "strong_points": .array(p.strengths.map { ["title": .string($0.title), "detail": .string($0.detail)] }),
            "weak_points": .array(p.weakPoints.map { ["title": .string($0.title), "detail": .string($0.detail)] }),
            "sessions_logged_last_4_weeks": .object(Dictionary(p.mix.map { ($0.kind.rawValue, JSONValue.number(Double($0.count))) },
                                                               uniquingKeysWith: { a, _ in a })),
            "sessions_logged_per_week_oldest_first": .array(p.weeks.map { JSONValue.number(Double($0.sessions)) }),
            "sets_last_4_weeks_side_by_side": .array(p.balance.map { b -> JSONValue in
                ["left": .string(b.left), "left_sets": .rounded(b.leftSets, 1), "right": .string(b.right), "right_sets": .rounded(b.rightSets, 1)]
            }),
            "supplements_last_14_days": .array(p.supplements.map {
                ["name": .string($0.name), "dose": .string($0.dose), "days_taken": .number(Double($0.daysTaken)),
                 "of_days": .number(Double($0.window)), "streak_days": .number(Double($0.streak))]
            }),
            "how_to_read_it": "Estimated maxes come from logged sets of 12 reps or fewer (Epley). Levels are Luma's own scale of fixed multiples of bodyweight per lift, not a population percentile: Starting, Building, Solid, Strong, Very strong, Exceptional. A lift's figure is its best of the last six weeks (or of the six before, when it has not been lifted since). A muscle is 'not measured' when no graded lift logged in the last 12 weeks gauges it: that is missing data, not weakness. Sets count 1 where a movement trains the muscle directly and half where it assists; runs and ergs are not counted. Work written on a board without loads counts as sets but gives no estimated max.",
        ]
        if let f = p.fuel {
            out["food_log_last_14_days"] = [
                "days_with_a_usable_log": .number(Double(f.loggedDays)), "of_days": .number(Double(f.window)),
                "protein_g_per_kg": .rounded(f.proteinPerKg, 2), "protein_target_g_per_kg": .rounded(f.proteinTargetPerKg, 2),
                "days_at_protein_target": .number(Double(f.proteinDaysMet)),
                "training_days": ["logged": .number(Double(f.trainingDays)), "kcal": .rounded(f.trainingKcal, 0), "carbs_g_per_kg": .rounded(f.trainingCarbsPerKg, 1)],
                "rest_days": ["logged": .number(Double(f.restDays)), "kcal": .rounded(f.restKcal, 0), "carbs_g_per_kg": .rounded(f.restCarbsPerKg, 1)],
                "note": "Only days with at least two food entries and 1,000 kcal are read; the rest are taken as under-logged, not under-eaten.",
            ]
        }
        return .object(out)
    }
}

public extension CoachPrompt {
    /// Instructions for a one-shot read of workout photos or notes into the training log.
    static func workoutExtraction(today: String, sex: Sex, calendar: Calendar = LDate.calendar) -> String {
        let weekday = CoachTools.weekdayName(today, calendar)
        let names = ExerciseLibrary.names.joined(separator: ", ")
        let who = sex == .male ? "men" : "women"
        return """
        You read photos and notes of training sessions for the training log of an athlete who trains strength, conditioning and HYROX. Respond only by calling the tool provided; do not write prose unless nothing usable is visible, in which case say in one sentence what is missing.

        - The photos may show one session or several: a whiteboard, a class screen, a page of a gym's app, a printed programme, a notebook, a screenshot of a tracking app. Return one workout for each separate session. Photos that show parts of one session (the strength block on one, the conditioning block on another; one board from two angles) are one workout: list their numbers in `photos`.
        - Sort each workout into its kind: strength (sets of lifts for load); conditioning (circuits, intervals, AMRAPs, EMOMs); hyrox (HYROX stations or race-style work: ski, sled push and pull, burpee broad jumps, row, farmers carry, sandbag lunges, wall balls, with runs between); gymClass (a coached class that mixes a strength block and a conditioning block); simulation (a full or half race simulation); easyRun, tempoRun, intervals, longRun (runs); mobility; other.
        - Title: short and specific, the board's own title if it has one.
        - Date: only when the photo or the athlete's note shows or states the day; otherwise leave it out. Today is \(weekday) \(today).
        - Movements: every movement of the session, in order. Use the name from this list when the movement is one of them, otherwise the name as written: \(names).
        - Sets: one entry per set or round. "4 x 8" is four sets of 8 reps; "3 rounds of 10 wall balls" is three sets of 10. Use reps for counted movements, meters for distances, seconds for holds and timed efforts, calories for machines counted in calories. Where the number of rounds is open (an AMRAP), give one set with the amount per round and say so in the movement's note.
        - Loads: give kg only where a load is written for the athlete or stated by them (convert lb to kg). A board shows what is prescribed, not what this athlete lifted: never guess a load and never work one out from a percentage. Where a board gives separate loads for men and women, use the one for \(who).
        - `as_written`: the session transcribed as it is written, line by line, so nothing is lost.
        - For a movement that is not on the list, name the main muscles it works in `muscles`.
        - Do not invent movements, sets or sessions that are not visible or described.
        """
    }
}
