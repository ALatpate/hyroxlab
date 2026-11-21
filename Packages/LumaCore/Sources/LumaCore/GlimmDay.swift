import Foundation

// MARK: - Small jobs Glimm can offer to do

/// A part of the app Glimm can open when asked.
public enum GlimmPlace: String, Codable, CaseIterable, Sendable {
    case breathing, run, session, coach, sleep, plan

    public var title: String {
        switch self {
        case .breathing: return "Breathing"
        case .run: return "Start a run"
        case .session: return "Start a session"
        case .coach: return "The coach"
        case .sleep: return "Sleep"
        case .plan: return "The plan"
        }
    }
}

/// One small job Glimm offers after being asked for it. It is shown as a button; nothing is done
/// until the button is tapped.
public enum GlimmAction: Equatable, Sendable {
    case logWater(Int)
    case open(GlimmPlace)

    public static let waterRange = 50...2000

    public var label: String {
        switch self {
        case .logWater(let ml): return "Log \(ml) ml of water"
        case .open(let place): return "Open: \(place.title)"
        }
    }

    /// The job a reply asks for, when it is one the app allows.
    public static func from(_ value: JSONValue?) -> GlimmAction? {
        guard let value, let kind = value["kind"]?.string else { return nil }
        switch kind {
        case "log_water":
            guard let ml = value["ml"]?.int, waterRange.contains(ml) else { return nil }
            return .logWater(ml)
        case "open":
            return value["place"]?.string.flatMap { GlimmPlace(rawValue: $0) }.map { .open($0) }
        default:
            return nil
        }
    }
}

// MARK: - What the day holds

/// The day in plain facts, put together on the phone for Glimm to talk about. Every one of them comes
/// from the athlete's records, so none is shared unless sharing health data with the coach is on.
public enum GlimmBrief {
    public static let limit = 8

    public static func facts(analysis a: LumaAnalysis, planned: [PlannedSession], workouts: [LWorkout], today: String,
                             shareHealth: Bool, calendar: Calendar = LDate.calendar) -> [String] {
        guard shareHealth else { return [] }
        var out: [String] = []
        if let night = a.lastNight, night.day == today {
            if let asleep = night.sleepMin {
                var line = "Last night: \(LFormat.hm(minutes: asleep)) asleep"
                if a.sleep.debtMin >= 30 { line += ", with a sleep debt of \(LFormat.hm(minutes: a.sleep.debtMin))" }
                out.append(line + ".")
            }
            if let r = night.recovery { out.append("Recovery this morning is \(LNum.int(r.rounded()))%. The day's call: \(a.call.title).") }
        } else {
            out.append("Last night has not reached the phone yet, so there is no score for today.")
        }
        if a.hrvTrend.place == .below { out.append("HRV has been under its normal range for \(a.hrvTrend.daysThere) days.") }
        if a.watch.level != .clear { out.append("Overnight signals: \(a.watch.title).") }
        let plans = planned.filter { $0.day == today && $0.status == .planned }
        if let first = plans.first {
            out.append("Planned today: \(first.title)" + (plans.count > 1 ? " and \(plans.count - 1) more" : "") + ".")
        } else {
            out.append("Nothing is planned for today.")
        }
        let done = workouts.filter { $0.day == today }
        if let last = done.max(by: { $0.start < $1.start }) {
            out.append("Trained today: \(last.sport), \(LNum.int((last.durationS / 60).rounded())) minutes.")
        } else if let last = workouts.filter({ $0.day < today }).max(by: { $0.start < $1.start }) {
            let ago = LDate.daysBetween(last.day, today, calendar: calendar)
            let when = ago == 1 ? "yesterday" : "\(ago) days ago"
            out.append("Last session: \(when), \(last.sport), \(LNum.int((last.durationS / 60).rounded())) minutes.")
        }
        let weekStart = LDate.weekStart(today, calendar: calendar)
        let thisWeek = workouts.filter { $0.day >= weekStart && $0.day <= today }.count
        out.append("Sessions so far this week: \(thisWeek).")
        return Array(out.prefix(limit))
    }
}

// MARK: - The day's own lines

/// One thing Glimm says, with the mood it is said in.
public struct GlimmLine: Codable, Equatable, Sendable {
    public var text: String
    public var mood: GlimmMood

    public init(text: String, mood: GlimmMood) { self.text = text; self.mood = mood }
}

/// The lines written for one day, kept on the phone so Glimm still has them with no connection.
public struct GlimmDayLines: Codable, Equatable, Sendable {
    public var day: String
    public var morning: GlimmLine
    public var afterTraining: GlimmLine
    public var evening: GlimmLine
    /// A shorter line for the widget and the Lock Screen.
    public var widget: String?

    public init(day: String, morning: GlimmLine, afterTraining: GlimmLine, evening: GlimmLine, widget: String? = nil) {
        self.day = day; self.morning = morning; self.afterTraining = afterTraining; self.evening = evening; self.widget = widget
    }

    /// The line for this point of the day: the evening one from six, the after-training one once a
    /// session is done, the morning one otherwise.
    public func line(hour: Int, trainedToday: Bool) -> GlimmLine {
        if hour >= 18 { return evening }
        return trainedToday ? afterTraining : morning
    }
}

/// The once-a-day request that writes Glimm's lines for the day and lets it add to its notebook.
public enum GlimmDaily {
    public static let lineLimit = 160
    public static let widgetLimit = 60
    public static let noticedLimit = 2
    public static let noteLength = 140

    public static let system: String = {
        let moods = GlimmMood.allCases.map { $0.rawValue }.joined(separator: ", ")
        return """
        You are Glimm, the user's little in-app fitness and everyday-life companion: warm, curious, gently cheeky, never preachy.
        You are writing the few lines you will say today, from the facts the app shares. Plain words, no markdown, no lists, at most one exclamation mark in all of them.

        Manners that never change: no guilt and no nagging; nothing is ever lost or punished because the user was away; no claim that you and the user have a special or exclusive bond; you are a software companion and do not claim a body, a life or real feelings; never diagnose from a reading and never tell the user to push through pain; say nothing happened unless the facts say so. If there are no health facts, do not mention readings at all.

        The notebook holds what you have worked out about the user so far. Let it shape what you say, as a friend who knows them would, without reciting it back.

        Return ONLY a JSON object with these fields:
        - morning: {"text": at most \(lineLimit) characters, "mood": one of \(moods)}. For the start of the day.
        - after_training: the same shape. For after a session today. Write it so it still makes sense if the session was a different one from the one planned.
        - evening: the same shape. For winding down.
        - widget: at most \(widgetLimit) characters, for a small widget. No full stop needed.
        - noticed: a list of at most \(noticedLimit) short sentences, each at most \(noteLength) characters, with something new you have worked out about the user from today's facts that the notebook does not already hold: a pattern, a preference, a rhythm of their week. Never a diagnosis, never a judgement of them. An empty list when nothing is new, or when the request says learning is off.
        """
    }()

    /// The shape the answer must have, for a request that asks the API to hold the model to it.
    public static let format: JSONValue = {
        let line: JSONValue = ["type": "object",
                               "properties": ["text": ["type": "string"],
                                              "mood": ["type": "string", "enum": .array(GlimmMood.allCases.map { .string($0.rawValue) })]],
                               "required": ["text", "mood"], "additionalProperties": false]
        return ["type": "json_schema",
                "schema": ["type": "object",
                           "properties": ["morning": line, "after_training": line, "evening": line,
                                          "widget": ["type": "string"],
                                          "noticed": ["type": "array", "items": ["type": "string"]]],
                           "required": ["morning", "after_training", "evening", "widget", "noticed"],
                           "additionalProperties": false]]
    }()

    /// The request as the model is given it.
    public static func request(day: String, clock: String, name: String?, facts: [String], notebook: [String], wearing: String,
                               learns: Bool) -> String {
        var body: [String: JSONValue] = [
            "date": .string(day),
            "clock": .string(clock),
            "facts": .array(facts.prefix(12).map { .string(String($0.prefix(240))) }),
            "notebook": .array(notebook.suffix(30).map { .string(String($0.prefix(noteLength))) }),
            "wearing": .string(String(wearing.prefix(160))),
            "learning": .string(learns ? "on" : "off"),
        ]
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { body["first_name"] = .string(name) }
        return JSONValue.object(body).text
    }

    /// What came back, checked: three lines Glimm can say, and anything new for the notebook.
    public static func parse(_ raw: String, day: String) -> (lines: GlimmDayLines, noticed: [String])? {
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close,
              let json = JSONValue.parse(String(raw[open...close])) else { return nil }
        func line(_ key: String) -> GlimmLine? {
            guard let text = json[key]?["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let mood = json[key]?["mood"]?.string.flatMap { GlimmMood(rawValue: $0) } ?? .steady
            return GlimmLine(text: GlimmChat.clip(text, lineLimit), mood: mood)
        }
        guard let morning = line("morning"), let after = line("after_training"), let evening = line("evening") else { return nil }
        var widget = json["widget"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let w = widget { widget = w.isEmpty ? nil : GlimmChat.clip(w, widgetLimit) }
        let noticed = (json["noticed"]?.array ?? []).compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.prefix(noticedLimit).map { String($0.prefix(noteLength)) }
        return (GlimmDayLines(day: day, morning: morning, afterTraining: after, evening: evening, widget: widget), Array(noticed))
    }
}
