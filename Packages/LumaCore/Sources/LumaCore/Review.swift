import Foundation

// MARK: - The weekly review

public struct ReviewFigure: Codable, Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) { self.label = label; self.value = value }
}

/// One week's review as the coach wrote it, kept so a training block can be read back. The figures
/// beside it are Luma's own, worked out from the same week, not the coach's.
public struct WeeklyReview: Codable, Equatable, Sendable, Identifiable {
    public var id: String { weekStart }
    /// Monday of the week reviewed.
    public var weekStart: String
    public var createdAt: Date
    public var headline: String
    public var wentWell: [String]
    public var watch: [String]
    public var next: [String]
    public var figures: [ReviewFigure]

    public init(weekStart: String, createdAt: Date = Date(), headline: String, wentWell: [String], watch: [String], next: [String],
                figures: [ReviewFigure]) {
        self.weekStart = weekStart; self.createdAt = createdAt; self.headline = headline; self.wentWell = wentWell
        self.watch = watch; self.next = next; self.figures = figures
    }
}

public enum WeekDigest {
    /// The week a review written on `today` is about: the week in progress from Sunday on, when it
    /// has all but run, and the week before it until then.
    public static func weekStart(for today: String, calendar: Calendar = LDate.calendar) -> String {
        let monday = LDate.weekStart(today, calendar: calendar)
        return LDate.weekday(today, calendar: calendar) == 7 ? monday : LDate.adding(-7, to: monday, calendar: calendar)
    }

    /// Whether a review of that week has become due and has not been written.
    public static func due(today: String, reviews: [WeeklyReview], calendar: Calendar = LDate.calendar) -> String? {
        let week = weekStart(for: today, calendar: calendar)
        return reviews.contains { $0.weekStart == week } ? nil : week
    }

    /// "10 to 16 Nov"
    public static func title(_ weekStart: String, calendar: Calendar = LDate.calendar) -> String {
        let end = LDate.adding(6, to: weekStart, calendar: calendar)
        guard let a = LDate.date(weekStart, calendar: calendar), let b = LDate.date(end, calendar: calendar) else { return weekStart }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let ca = calendar.dateComponents([.day, .month], from: a), cb = calendar.dateComponents([.day, .month], from: b)
        let ma = months[max(0, min(11, (ca.month ?? 1) - 1))], mb = months[max(0, min(11, (cb.month ?? 1) - 1))]
        return ma == mb ? "\(ca.day ?? 1) to \(cb.day ?? 1) \(mb)" : "\(ca.day ?? 1) \(ma) to \(cb.day ?? 1) \(mb)"
    }

    /// The week's figures, Luma's own, shown beside the review.
    public static func figures(weekStart: String, days: [LDay], schedule: [ScheduleDay], fuel: [FuelEntry], profile: LProfile,
                               calendar: Calendar = LDate.calendar) -> [ReviewFigure] {
        let keys = Set((0..<7).map { LDate.adding($0, to: weekStart, calendar: calendar) })
        let week = days.filter { keys.contains($0.day) }
        var out: [ReviewFigure] = []
        let planned = schedule.flatMap { d in d.planned.filter { $0.kind != .rest && $0.status != .skipped } }
        let done = schedule.reduce(0) { n, d in n + d.planned.filter { $0.kind != .rest && d.isDone($0) }.count + d.unplannedWorkouts.count }
        out.append(ReviewFigure(label: "Sessions", value: planned.isEmpty ? "\(done)" : "\(done) of \(max(planned.count, done)) planned"))
        if let r = LStat.mean(week.compactMap { $0.recovery }) { out.append(ReviewFigure(label: "Recovery", value: "\(Int(r.rounded()))% average")) }
        if let s = LStat.mean(week.compactMap { $0.sleepMin }) { out.append(ReviewFigure(label: "Sleep", value: LFormat.hm(minutes: s) + " a night")) }
        if let s = LStat.mean(week.compactMap { $0.strain }) { out.append(ReviewFigure(label: "Strain", value: LScale.text(s, on21: profile.strainOn21) + " a day")) }
        let byDay = Dictionary(grouping: fuel, by: { $0.day })
        let usable = keys.filter { TrainingProgress.isUsable(byDay[$0] ?? []) }
        if usable.count >= 3, let p = LStat.mean(usable.map { FuelTotals.of(byDay[$0] ?? []).proteinG }) {
            out.append(ReviewFigure(label: "Protein", value: "\(Int(p.rounded())) g a day of \(Int(FuelPlanner.proteinTarget(profile)))"))
        }
        return out
    }

    /// The week in plain lines, for the coach to write from: day by day, then what moved. Everything
    /// here is a figure Luma already shows; the coach is told to use nothing else.
    public static func text(weekStart: String, days: [LDay], schedule: [ScheduleDay], progress: TrainingProgress, fuel: [FuelEntry],
                            profile: LProfile, extra: [String] = [], calendar: Calendar = LDate.calendar) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let foodByDay = Dictionary(grouping: fuel, by: { $0.day })
        var lines: [String] = ["Week of \(title(weekStart, calendar: calendar)) (\(weekStart) is the Monday)."]
        for i in 0..<7 {
            let key = LDate.adding(i, to: weekStart, calendar: calendar)
            var parts: [String] = []
            if let d = byDay[key] {
                if let r = d.recovery { parts.append("recovery \(Int(r.rounded()))%") }
                if let s = d.sleepMin { parts.append("slept \(LFormat.hm(minutes: s))") }
                if let s = d.strain { parts.append("strain \(String(format: "%.1f", LScale.strain21(s)))") }
                if let h = d.hrv { parts.append("HRV \(Int(h.rounded())) ms") }
            }
            if let day = schedule.first(where: { $0.day == key }) {
                for p in day.planned where p.kind != .rest {
                    parts.append("\(p.title) \(p.durationMin) min \(p.intensity.rawValue): \(day.isDone(p) ? "done" : (p.status == .skipped ? "skipped" : "not done"))")
                }
                for w in day.unplannedWorkouts { parts.append("\(w.kind == .other ? w.sport : w.kind.title) \(Int(w.durationS / 60)) min (unplanned)") }
                for log in day.logs { parts.append("logged \(log.title): \(log.doneSets) sets") }
            }
            let entries = foodByDay[key] ?? []
            if TrainingProgress.isUsable(entries) {
                let t = FuelTotals.of(entries)
                parts.append("ate \(Int(t.kcal.rounded())) kcal, protein \(Int(t.proteinG.rounded())) g, carbs \(Int(t.carbsG.rounded())) g")
                if t.alcoholG > 0 { parts.append("alcohol \(Int(t.alcoholG.rounded())) g") }
            }
            lines.append("\(names[i]) \(key): " + (parts.isEmpty ? "no data" : parts.joined(separator: "; ")))
        }
        lines.append("")
        lines.append("Protein target \(Int(FuelPlanner.proteinTarget(profile))) g a day.")
        let moved = progress.lifts.filter { $0.trend != nil && $0.trend != .steady }
        for lift in moved.prefix(8) {
            let pct = Int(((lift.change ?? 0) * 100).rounded())
            lines.append("\(lift.name): \(lift.figure), \(pct >= 0 ? "+" : "")\(pct)% against the six weeks before.")
        }
        for note in progress.weakPoints.prefix(3) { lines.append("Weak point: \(note.title). \(note.detail)") }
        lines.append(contentsOf: extra)
        return lines.joined(separator: "\n")
    }
}

public extension CoachTools {
    /// The tool a weekly review is returned through.
    static func reviewTool() -> AITool {
        AITool(name: "write_weekly_review", description: "Return the athlete's review of the week, written only from the figures given.", properties: [
            "headline": AISchema.string("The week in one plain sentence, at most 14 words"),
            "went_well": AISchema.array("Two or three things that went well, each one short sentence with its figure",
                                        items: AISchema.string("One sentence")),
            "watch": AISchema.array("One to three things that slipped or need watching, each one short sentence with its figure",
                                    items: AISchema.string("One sentence")),
            "next_week": AISchema.array("Exactly three specific things to do next week, each one short sentence",
                                        items: AISchema.string("One action")),
        ], required: ["headline", "went_well", "watch", "next_week"])
    }

    /// Reads a review from the tool's input; nil when it holds nothing usable.
    static func review(from input: JSONValue, weekStart: String, figures: [ReviewFigure], now: Date = Date()) -> WeeklyReview? {
        func lines(_ key: String, limit: Int) -> [String] {
            let raw: [String] = (input[key]?.array ?? []).compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Array(raw.filter { !$0.isEmpty }.prefix(limit))
        }
        guard let headline = input["headline"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !headline.isEmpty else { return nil }
        let next = lines("next_week", limit: 3)
        guard !next.isEmpty else { return nil }
        return WeeklyReview(weekStart: weekStart, createdAt: now, headline: headline, wentWell: lines("went_well", limit: 3),
                            watch: lines("watch", limit: 3), next: next, figures: figures)
    }
}

public extension CoachPrompt {
    /// Instructions for writing a weekly review from the digest alone.
    static func weeklyReview(profile p: LProfile) -> String {
        let who = p.name.isEmpty ? "the athlete" : p.name
        return """
        You write the weekly review for \(who), a hybrid athlete who trains strength, conditioning and HYROX and wears a WHOOP strap. You are given the week as plain lines. Respond only by calling the tool provided.

        - Use only the figures in the lines given. Do not invent a number, a session or a cause. Where the week's data is thin, say so in one of the points instead of filling it in.
        - Write plainly and specifically, in short sentences, the way a coach who knows the athlete would say it. Name the figure behind each point.
        - "Went well" and "watch" are observations. Say what happened, and where two things moved together say that they did, without claiming one caused the other.
        - "Next week" is exactly three things the athlete can do: specific sessions, times or amounts, not general advice.
        - Strain is on a 0 to 21 scale. Recovery is a percentage: 67 and above is high, under 34 is low. No medical advice.
        """
    }
}

// MARK: - Reminders

public enum ReminderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case caffeine, supplements, protein, bedtime, trial, weighIn, review

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .caffeine: return "Last call for caffeine"
        case .supplements: return "Supplements not ticked"
        case .protein: return "Protein behind"
        case .bedtime: return "Bedtime"
        case .trial: return "Trial: on or off today"
        case .weighIn: return "Weigh-in mornings"
        case .review: return "Weekly review"
        }
    }

    public var detail: String {
        switch self {
        case .caffeine: return "Before your cut-off time, so tonight's sleep is left alone."
        case .supplements: return "Mid-morning and before bed, only for what is still unticked."
        case .protein: return "Late afternoon, when you are under half of the day's protein."
        case .bedtime: return "Half an hour before the lights-out that covers tonight's sleep."
        case .trial: return "Each morning of a supplement trial."
        case .weighIn: return "Monday, Wednesday and Friday at 07:30."
        case .review: return "Sunday evening, when the week is ready to review."
        }
    }
}

/// A reminder to be shown at a time, worked out on the phone from the athlete's own numbers.
public struct PlannedReminder: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: ReminderKind
    public let at: Date
    public let title: String
    public let body: String
}

/// What the reminders are worked out from.
public struct ReminderFacts: Sendable {
    public var now: Date
    /// The training day `now` falls in.
    public var today: String
    /// Usual bedtime and tonight's recommended lights-out, minutes from the midnight inside the night.
    public var usualBedtime: Double?
    public var bedtimeTonight: Double?
    /// The athlete's own caffeine cut-off, when their log has shown one.
    public var caffeineCutoff: DoseCutoff?
    /// Active supplements and whether each is ticked today.
    public var supplements: [(plan: SupplementPlan, taken: Bool)]
    /// Supplements on an off block of a trial today: not to be reminded about.
    public var paused: Set<String>
    public var proteinG: Double
    public var proteinTarget: Double
    public var foodEntries: Int
    /// The trial instruction for today and for tomorrow, when a trial is running.
    public var trialToday: String?
    public var trialTomorrow: String?
    public var weighsIn: Bool
    public var reviewDue: Bool

    public init(now: Date, today: String) {
        self.now = now; self.today = today
        supplements = []; paused = []; proteinG = 0; proteinTarget = 0; foodEntries = 0; weighsIn = false; reviewDue = false
    }
}

public enum ReminderPlanner {
    /// Coffee needs about this long before bed to leave sleep untouched (Gardiner et al., Sleep Med Rev, 2023).
    public static let caffeineHoursBeforeBed = 8.8

    /// The reminders due from `now` to the end of tomorrow. Each has a stable id, so planning again
    /// replaces a reminder instead of repeating it, and one whose reason has gone is simply not planned.
    public static func plan(_ f: ReminderFacts, on kinds: Set<ReminderKind>, calendar: Calendar = LDate.calendar) -> [PlannedReminder] {
        guard let morning = LDate.startOfDay(f.today, calendar: calendar) else { return [] }
        let night = morning.addingTimeInterval(86_400)
        func at(_ minutes: Double) -> Date { morning.addingTimeInterval(minutes * 60) }
        var out: [PlannedReminder] = []
        func add(_ kind: ReminderKind, _ suffix: String, _ date: Date, _ title: String, _ body: String) {
            guard date > f.now else { return }
            out.append(PlannedReminder(id: "luma.reminder.\(kind.rawValue).\(suffix)", kind: kind, at: date, title: title, body: body))
        }
        let bed = f.usualBedtime ?? -60

        if kinds.contains(.caffeine) {
            if let cut = f.caffeineCutoff {
                add(.caffeine, f.today, at(cut.hour * 60 - 20), "Last call for caffeine",
                    "After \(cut.clock) it has gone with \(cut.outcome.gap(abs(cut.delta))) \(cut.delta < 0 ? "less" : "more") \(cut.outcome.phrase) for you.")
            } else {
                let minutes = 1440 + bed - caffeineHoursBeforeBed * 60
                add(.caffeine, f.today, at(minutes - 20), "Last call for caffeine",
                    "Coffee needs about 9 hours before bed to leave sleep alone. Yours is at about \(LFormat.timeOfDay(minutes: bed)).")
            }
        }
        if kinds.contains(.supplements) {
            let open = f.supplements.filter { !$0.taken && !f.paused.contains($0.plan.dose.name) }
            let morningOnes = open.filter { $0.plan.timing == .morning || $0.plan.timing == .anytime }.map { $0.plan.dose.name }
            let eveningOnes = open.filter { $0.plan.timing == .evening }.map { $0.plan.dose.name }
            if !morningOnes.isEmpty { add(.supplements, f.today + ".am", at(10 * 60 + 30), "Not ticked yet", morningOnes.joined(separator: ", ") + ".") }
            if !eveningOnes.isEmpty { add(.supplements, f.today + ".pm", at(1440 + bed - 60), "Not ticked yet", eveningOnes.joined(separator: ", ") + ".") }
        }
        if kinds.contains(.protein), f.foodEntries > 0, f.proteinTarget > 0, f.proteinG < f.proteinTarget * 0.5 {
            add(.protein, f.today, at(16 * 60 + 30), "Protein is behind",
                "\(Int(f.proteinG.rounded())) g of \(Int(f.proteinTarget.rounded())) so far. Two protein meals still fit in today.")
        }
        if kinds.contains(.bedtime), let lights = f.bedtimeTonight {
            add(.bedtime, f.today, night.addingTimeInterval((lights - 30) * 60), "Half an hour to lights out",
                "In bed by \(LFormat.timeOfDay(minutes: lights)) covers tonight's sleep.")
        }
        if kinds.contains(.trial) {
            if let text = f.trialToday { add(.trial, f.today, at(8 * 60), "Supplement trial", text) }
            if let text = f.trialTomorrow { add(.trial, LDate.adding(1, to: f.today, calendar: calendar), at(1440 + 8 * 60), "Supplement trial", text) }
        }
        if kinds.contains(.weighIn), f.weighsIn {
            for offset in 0...1 {
                let key = LDate.adding(offset, to: f.today, calendar: calendar)
                if [1, 3, 5].contains(LDate.weekday(key, calendar: calendar)) {
                    add(.weighIn, key, at(Double(offset) * 1440 + 7 * 60 + 30), "Weigh-in morning", "Step on before breakfast. It takes five seconds.")
                }
            }
        }
        if kinds.contains(.review), f.reviewDue {
            for offset in 0...1 {
                let key = LDate.adding(offset, to: f.today, calendar: calendar)
                if LDate.weekday(key, calendar: calendar) == 7 {
                    add(.review, key, at(Double(offset) * 1440 + 18 * 60), "Your week is ready to review", "Open Luma and the coach writes it up.")
                }
            }
        }
        return out.sorted { $0.at < $1.at }
    }
}
