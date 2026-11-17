import Foundation

public extension CoachTools {
    // MARK: Decoding tool input

    /// Reads the items of a food entry from tool input, tolerating missing optional fields.
    static func foodItems(_ input: JSONValue) -> [FuelItem] {
        (input["items"]?.array ?? []).compactMap { i in
            guard let name = i["name"]?.string, !name.isEmpty else { return nil }
            return FuelItem(name: name, quantity: i["quantity"]?.string ?? "", kcal: max(0, i["kcal"]?.number ?? 0),
                            proteinG: max(0, i["protein_g"]?.number ?? 0), carbsG: max(0, i["carbs_g"]?.number ?? 0),
                            fatG: max(0, i["fat_g"]?.number ?? 0), fiberG: i["fiber_g"]?.number,
                            caffeineMg: i["caffeine_mg"]?.number.flatMap { $0 > 0 ? $0 : nil },
                            alcoholG: i["alcohol_g"]?.number.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    static func foodEntry(_ input: JSONValue, world w: CoachWorld, calendar: Calendar = LDate.calendar) -> Result<FuelEntry, CoachToolError> {
        let items = foodItems(input)
        guard !items.isEmpty else { return .failure(CoachToolError("No items were given. Provide at least one item with name, quantity and macros.")) }
        let day = self.day(input["date"], world: w, calendar: calendar)
        let kind = FuelKind(rawValue: input["kind"]?.string ?? "meal") ?? .meal
        let source: FuelSource
        switch input["source"]?.string {
        case "label": source = .label
        case "photo": source = .photo
        default: source = .coach
        }
        let title = input["title"]?.string ?? items.map { $0.name }.prefix(3).joined(separator: ", ")
        return .success(FuelEntry(at: date(day: day, time: input["time"], world: w, calendar: calendar), kind: kind == .supplement || kind == .water ? .meal : kind,
                                  title: title, items: items, note: input["note"]?.string ?? "", source: source))
    }

    static func supplementEntries(_ input: JSONValue, world w: CoachWorld, calendar: Calendar = LDate.calendar) -> Result<[FuelEntry], CoachToolError> {
        let day = self.day(input["date"], world: w, calendar: calendar)
        let at = date(day: day, time: input["time"], world: w, calendar: calendar)
        let entries: [FuelEntry] = (input["supplements"]?.array ?? []).compactMap { s in
            guard let name = s["name"]?.string, !name.isEmpty else { return nil }
            let dose = SupplementDose(name: name, amount: s["amount"]?.number ?? 1, unit: s["unit"]?.string ?? "tablet")
            return FuelEntry(at: at, kind: .supplement, title: name, supplement: dose, source: .coach)
        }
        return entries.isEmpty ? .failure(CoachToolError("No supplements were given.")) : .success(entries)
    }

    private static func session(from i: JSONValue, base: PlannedSession?, world w: CoachWorld, calendar: Calendar) -> PlannedSession? {
        let day = i["date"]?.string.map { _ in self.day(i["date"], world: w, calendar: calendar) } ?? base?.day
        guard let day else { return nil }
        let kind = i["kind"]?.string.flatMap { SessionKind(rawValue: $0) } ?? base?.kind ?? .other
        var p = base ?? PlannedSession(day: day, kind: kind, title: kind.title, origin: .coach)
        p.day = day
        p.kind = kind
        if let t = i["title"]?.string, !t.isEmpty { p.title = t }
        if let d = i["detail"]?.string { p.detail = d }
        if let m = i["duration_min"]?.int, m > 0 { p.durationMin = min(600, m) }
        if let x = i["intensity"]?.string.flatMap({ Intensity(rawValue: $0) }) { p.intensity = x } else if base == nil { p.intensity = kind.defaultIntensity }
        if let m = minutes(i["start_time"]) { p.startMinutes = m }
        if let pace = i["target_pace_s_per_km"]?.number, pace > 120 { p.targetPaceSPerKm = pace }
        if let s = i["status"]?.string.flatMap({ PlannedSession.Status(rawValue: $0) }), s != .removed { p.status = s }
        return p
    }

    /// Turns a write tool call into a command for the app to apply. Returns nil when `name` is not a write tool.
    static func command(_ name: String, input: JSONValue, world w: CoachWorld, calendar: Calendar = LDate.calendar) -> Result<CoachCommand, CoachToolError>? {
        switch name {
        case "log_food":
            return foodEntry(input, world: w, calendar: calendar).map { .logFuel([$0]) }
        case "log_supplement":
            return supplementEntries(input, world: w, calendar: calendar).map { .logFuel($0) }
        case "log_water":
            guard let ml = input["ml"]?.number, ml > 0, ml <= 5000 else { return .failure(CoachToolError("ml must be between 1 and 5000.")) }
            return .success(.logFuel([FuelEntry(at: date(day: w.today, time: input["time"], world: w, calendar: calendar), kind: .water,
                                                title: "Water", waterMl: ml, source: .coach)]))
        case "plan_sessions":
            let sessions = (input["sessions"]?.array ?? []).compactMap { session(from: $0, base: nil, world: w, calendar: calendar) }
            guard !sessions.isEmpty else { return .failure(CoachToolError("No valid sessions were given. Each needs date, kind, title and duration_min.")) }
            let from = input["replace_from"]?.string, to = input["replace_to"]?.string
            return .success(.plan(sessions, replaceFrom: from, replaceTo: to))
        case "update_session":
            guard let id = input["id"]?.string.flatMap({ UUID(uuidString: $0) }), let existing = w.planned.first(where: { $0.id == id }) else {
                return .failure(CoachToolError("No planned session has that id. Call get_schedule to see current ids."))
            }
            guard let updated = session(from: input, base: existing, world: w, calendar: calendar) else { return .failure(CoachToolError("Could not read the changes.")) }
            return .success(.updateSession(updated))
        case "remove_session":
            guard let id = input["id"]?.string.flatMap({ UUID(uuidString: $0) }), w.planned.contains(where: { $0.id == id }) else {
                return .failure(CoachToolError("No planned session has that id. Call get_schedule to see current ids."))
            }
            return .success(.removeSession(id))
        case "set_weekly_routine":
            let slots: [RoutineSlot] = (input["slots"]?.array ?? []).compactMap { s in
                guard let wd = s["weekday"]?.int, (1...7).contains(wd), let kind = s["kind"]?.string.flatMap({ SessionKind(rawValue: $0) }) else { return nil }
                return RoutineSlot(weekday: wd, kind: kind, title: s["title"]?.string ?? kind.title, startMinutes: minutes(s["start_time"]),
                                   durationMin: max(10, s["duration_min"]?.int ?? 60))
            }
            return .success(.setRoutine(slots))
        case "log_checkin":
            let day = self.day(input["date"], world: w, calendar: calendar)
            var c = w.checkIns.first { $0.day == day } ?? CheckIn(day: day)
            if let tags = input["tags"]?.array { c.tags = tags.compactMap { $0.string.flatMap { CheckInTag(rawValue: $0) } } }
            if let e = input["energy"]?.int { c.energy = min(5, max(1, e)) }
            if let s = input["soreness"]?.int { c.soreness = min(5, max(1, s)) }
            if let n = input["note"]?.string { c.note = n }
            return .success(.checkIn(c))
        case "log_workout":
            guard let sport = input["sport"]?.string, !sport.isEmpty, let minutes = input["duration_min"]?.number, minutes > 0, minutes <= 900 else {
                return .failure(CoachToolError("sport and duration_min (1–900) are required."))
            }
            let day = self.day(input["date"], world: w, calendar: calendar)
            let end = self.minutes(input["start_time"]) == nil && day == w.today ? w.now : date(day: day, time: input["start_time"], world: w, calendar: calendar).addingTimeInterval(minutes * 60)
            let start = end.addingTimeInterval(-minutes * 60)
            return .success(.logWorkout(LWorkout(start: start.timeIntervalSince1970, end: end.timeIntervalSince1970, sport: sport, source: "manual",
                                                 avgHR: input["avg_hr"]?.number, distanceM: input["distance_km"]?.number.map { $0 * 1000 },
                                                 notes: input["notes"]?.string)))
        case "log_strength_session":
            // A session that has been done is not dated after today.
            let day = min(self.day(input["date"], world: w, calendar: calendar), w.today)
            var fields = input
            // The day has been resolved against the athlete's own clock ("yesterday", a missing date).
            if case .object(var o) = fields { o["date"] = .string(day); fields = .object(o) }
            guard let session = loggedSession(fields, day: day, source: "coach", now: w.now, calendar: calendar), !session.exercises.isEmpty else {
                return .failure(CoachToolError("No movements were given. Provide each movement with its sets."))
            }
            return .success(.logStrength(session))
        case "update_profile":
            var p = w.profile
            if let v = input["weight_kg"]?.number, (30...250).contains(v) { p.weightKg = v }
            if let v = input["max_hr"]?.number, (120...230).contains(v) { p.maxHR = v }
            if let v = input["threshold_hr"]?.number, (100...220).contains(v) { p.lthr = v }
            if let v = input["five_k_seconds"]?.number, (700...3600).contains(v) { p.fiveKSeconds = v }
            if let v = input["sleep_need_hours"]?.number, (5...11).contains(v) { p.sleepNeedHours = v }
            if let v = input["race_name"]?.string { p.raceName = v }
            if let v = input["race_date"]?.string, let d = LDate.date(v, calendar: calendar) { p.raceDate = d }
            if let v = input["goals"]?.string { p.goals = v }
            return p == w.profile ? .failure(CoachToolError("No valid profile fields were given.")) : .success(.updateProfile(p))
        case "remember":
            guard let fact = input["fact"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), fact.count >= 3 else {
                return .failure(CoachToolError("fact is required."))
            }
            return .success(.remember(String(fact.prefix(300))))
        case "show_chart":
            guard let m = input["metric"]?.string.flatMap({ LMetric(rawValue: $0) }) else { return .failure(CoachToolError("Unknown metric.")) }
            return .success(.showChart(m, days: min(180, max(7, input["days"]?.int ?? 30))))
        default:
            return nil
        }
    }
}

// MARK: - System prompt

public enum CoachPrompt {
    /// The coach's standing instructions plus who the athlete is. Data comes through tools; only a
    /// one-line status is inlined so trivial questions do not need a tool call.
    public static func system(world w: CoachWorld, calendar: Calendar = LDate.calendar) -> String {
        let p = w.profile
        let a = w.analysis
        var lines: [String] = []
        lines.append("""
        You are the coach inside Luma, a personal training and health app. You coach one athlete: a hybrid (strength + endurance) athlete who trains for HYROX and running, wears a WHOOP strap, and logs food, supplements and sessions here. You have tools that read everything Luma knows about them and tools that change their calendar and logs.

        How to work
        - Ground every claim about the athlete in tool results from this conversation. Do not guess numbers. If the data is missing or thin, say so plainly and say what would fill the gap.
        - Call tools without asking permission, including several in a row. Read before you advise: for "how am I doing" start with get_overview; for trends pull the date range you need.
        - When the athlete tells you something they ate, drank or took, or sends a photo of it, log it straight away with log_food / log_supplement / log_water, then confirm in one or two lines with the totals. Do not ask them to confirm first; they can undo.
        - Photos of meals: identify each item, estimate portions from plate and utensil scale, and be conservative with oils and sauces. Photos of nutrition labels: use the label's numbers for the amount eaten (ask only if servings are truly unclear, otherwise assume one serving and say so). Photos of supplement bottles or facts panels: read the product and dose per serving. Photos of whiteboards, class screens or tracking apps: read the session and log it with log_strength_session, movement by movement, with loads only where they are written or the athlete states them.
        - When asked to plan training, read the calendar and routine first, work around standing classes, respect recovery and load, and write sessions with plan_sessions. Give each session a clear main set with paces, loads or heart-rate zones.
        - Use remember for durable facts the athlete tells you (injuries, constraints, preferences). Use update_profile for profile facts.
        - For strength, muscles, weak points, balance or progress, read get_progress. Its levels are Luma's own scale and its maxes are estimates from logged sets: say so once, and treat a muscle that is "not measured" as missing data, not as weak.
        - Use show_chart when a picture helps.

        How to answer
        - Be direct and specific: numbers, units, and what to do next. Short paragraphs or a few bullets; no preamble, no restating the question.
        - Explain the reasoning in a sentence when you recommend something. Name trade-offs honestly.
        - Strain is on a 0–21 scale. Recovery is a percentage: 67+ high, 34–66 moderate, under 34 low. HRV is RMSSD in ms measured overnight; compare it only with the athlete's own baseline.
        - You are a coach, not a clinician. Do not diagnose. For chest pain, fainting, signs of illness that persist, or injuries that do not settle, tell them to see a doctor or physio. Estimates from photos are estimates: say so once, briefly.
        - Metric units, 24-hour times, dates as written in the data.
        """)
        lines.append("")
        lines.append("Athlete")
        var who: [String] = []
        if !p.name.isEmpty { who.append("Name: \(p.name)") }
        let sexWord = p.sex == .male ? "Male" : "Female"
        let mass = String(format: "%.1f", p.weightKg)
        who.append("\(sexWord), \(p.age(on: w.now, calendar: calendar)) years, \(Int(p.heightCm)) cm, \(mass) kg")
        let maxBasis = p.maxHR == nil ? "age estimate" : "measured"
        who.append("Max heart rate \(Int(p.resolvedMaxHR(on: w.now))) bpm (\(maxBasis))")
        if let t = p.fiveKSeconds { who.append("Current 5 km: " + String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)) }
        if !p.gym.isEmpty { who.append("Trains at \(p.gym) (coach-led classes with full HYROX equipment)") }
        who.append("HYROX format of interest: \(p.format.title)")
        if !p.raceName.isEmpty || p.raceDate != nil {
            let raceName = p.raceName.isEmpty ? "unnamed" : p.raceName
            var raceLine = "Next race: " + raceName
            if let d = p.raceDate { raceLine += " on " + LDate.key(d, calendar: calendar) }
            who.append(raceLine)
        }
        if !p.goals.isEmpty { who.append("Goals in their words: \(p.goals)") }
        lines.append(contentsOf: who.map { "- \($0)" })
        if !w.notes.isEmpty {
            lines.append("")
            lines.append("Things you have been asked to remember")
            lines.append(contentsOf: w.notes.suffix(40).map { "- \($0)" })
        }
        lines.append("")
        let weekday = CoachTools.weekdayName(w.today, calendar)
        lines.append("Now: \(weekday) \(w.today), \(LFormat.timeOfDay(minutes: CoachTools.minutesOfDay(w.now, calendar))).")
        if w.shareHealth {
            var status: [String] = []
            if let n = a.lastNight, n.day == w.today, let r = n.recovery { status.append("recovery \(Int(r.rounded()))%") }
            else { status.append("no recovery score yet today") }
            if let s = a.day?.strain { status.append(String(format: "strain so far %.1f", LScale.strain21(s))) }
            status.append("\(a.baselines.nights) nights of data")
            lines.append("Status: \(status.joined(separator: ", ")). Use get_overview for the detail.")
        } else {
            lines.append("The athlete has not enabled sharing health data with you. Read tools will return nothing: coach from what they tell you, and mention once that turning sharing on in Coach settings lets you use their data.")
        }
        return lines.joined(separator: "\n")
    }

    /// Instructions for a one-shot read of photos or text into a log entry (no conversation).
    public static func extraction(kind: String) -> String {
        """
        You read \(kind) for a nutrition log inside a training app. Respond only by calling the tool provided; do not write prose unless nothing usable is visible, in which case say in one sentence what is missing.

        - Several photos may show the same meal from different angles or a meal plus its label: combine them into one entry.
        - Meals: list each item separately with your best estimate of the amount eaten and its energy and macros. Judge portions from plate, cutlery and hand scale. Be conservative with added oil and sauces, and mention notable assumptions in `note`.
        - Nutrition labels: use the label's per-serving or per-100 g values scaled to the amount stated or visible; if the amount eaten is unknown, assume one serving and say so in `note`. Set source to "label".
        - Supplements: read the product name and the amount per serving from the facts panel; one entry per active product. If the athlete's text says how many they took, use that.
        - Metric units. Do not invent items that are not visible or described.
        """
    }
}
