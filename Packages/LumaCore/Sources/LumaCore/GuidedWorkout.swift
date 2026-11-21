import Foundation

// MARK: - A workout to be led through

/// How long one step lasts.
public enum GuidedMeasure: Codable, Equatable, Sendable {
    /// A set time, in seconds. The step ends by itself.
    case time(Double)
    case reps(Int)
    /// Metres.
    case distance(Double)
    /// Until the athlete moves on.
    case open
}

public struct GuidedStep: Codable, Equatable, Sendable {
    public var name: String
    public var measure: GuidedMeasure
    /// The load as it was written: "20 kg", "2 x 16 kg".
    public var load: String?
    /// Rest after the step, in seconds. 0 for none.
    public var restS: Double

    public init(name: String, measure: GuidedMeasure, load: String? = nil, restS: Double = 0) {
        self.name = name; self.measure = measure; self.load = load; self.restS = restS
    }
}

public struct GuidedBlock: Codable, Equatable, Sendable {
    public var name: String
    public var rounds: Int
    public var steps: [GuidedStep]
    /// Rest between rounds, in seconds. 0 for none.
    public var restBetweenRoundsS: Double

    public init(name: String, rounds: Int = 1, steps: [GuidedStep], restBetweenRoundsS: Double = 0) {
        self.name = name; self.rounds = rounds; self.steps = steps; self.restBetweenRoundsS = restBetweenRoundsS
    }
}

/// One stretch of a led workout: an effort or a rest.
public struct GuidedSegment: Equatable, Sendable, Identifiable {
    public var id: Int
    public var isRest: Bool
    public var title: String
    /// "20 reps · 6 kg", "45 s", "400 m".
    public var detail: String
    /// Its set length. Nil when it lasts until the athlete moves on.
    public var seconds: Double?
    public var block: String
    public var round: Int
    public var rounds: Int
}

/// A workout written as blocks of steps, from a sentence or from a picture of the class board, that
/// Luma can lead the athlete through one stretch at a time.
public struct GuidedWorkout: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// The kind of session it is recorded as: "Class", "Strength", "Run", "HYROX".
    public var sport: String
    public var blocks: [GuidedBlock]
    public var note: String?

    public init(id: UUID = UUID(), title: String, sport: String = "Class", blocks: [GuidedBlock], note: String? = nil) {
        self.id = id; self.title = title; self.sport = sport; self.blocks = blocks; self.note = note
    }

    public static let maxBlocks = 12
    public static let maxSteps = 20
    public static let maxRounds = 50
    public static let maxStepS: Double = 3600
    public static let maxSegments = 400

    /// What is wrong with it, in plain words. Empty when it can be run.
    public var problems: [String] {
        var out: [String] = []
        if blocks.isEmpty { out.append("There is nothing to do in it yet.") }
        if blocks.count > GuidedWorkout.maxBlocks { out.append("It has more than \(GuidedWorkout.maxBlocks) blocks.") }
        for b in blocks {
            let name = b.name.isEmpty ? "A block" : b.name
            if b.steps.isEmpty { out.append("\(name) has no steps.") }
            if b.steps.count > GuidedWorkout.maxSteps { out.append("\(name) has more than \(GuidedWorkout.maxSteps) steps.") }
            if b.rounds < 1 || b.rounds > GuidedWorkout.maxRounds { out.append("\(name) should have between 1 and \(GuidedWorkout.maxRounds) rounds.") }
            for s in b.steps {
                if s.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("\(name) has a step with no name.") }
                if case .time(let t) = s.measure, t <= 0 || t > GuidedWorkout.maxStepS { out.append("\(s.name) needs a time between a second and an hour.") }
                if case .reps(let n) = s.measure, n <= 0 { out.append("\(s.name) needs at least one rep.") }
                if case .distance(let m) = s.measure, m <= 0 { out.append("\(s.name) needs a distance.") }
                if s.restS < 0 || s.restS > GuidedWorkout.maxStepS { out.append("The rest after \(s.name) should be under an hour.") }
            }
        }
        if out.isEmpty, segments.count > GuidedWorkout.maxSegments { out.append("It is too long to lead through in one go.") }
        return out
    }

    public var isReady: Bool { problems.isEmpty }

    /// Every effort and rest in the order they happen. The rest after the very last effort is left out.
    public var segments: [GuidedSegment] {
        var out: [GuidedSegment] = []
        func add(rest seconds: Double, block: GuidedBlock, round: Int) {
            guard seconds > 0 else { return }
            out.append(GuidedSegment(id: out.count, isRest: true, title: "Rest", detail: GuidedWorkout.lengthText(seconds), seconds: seconds,
                                     block: block.name, round: round, rounds: block.rounds))
        }
        for block in blocks {
            let rounds = max(1, min(GuidedWorkout.maxRounds, block.rounds))
            for round in 1...rounds {
                for step in block.steps {
                    var seconds: Double?
                    if case .time(let t) = step.measure { seconds = t }
                    out.append(GuidedSegment(id: out.count, isRest: false, title: step.name, detail: GuidedWorkout.detail(step), seconds: seconds,
                                             block: block.name, round: round, rounds: rounds))
                    add(rest: step.restS, block: block, round: round)
                }
                if round < rounds { add(rest: block.restBetweenRoundsS, block: block, round: round) }
            }
        }
        while let last = out.last, last.isRest { out.removeLast() }
        return out
    }

    /// The set time it adds up to, when every stretch has one.
    public var plannedS: Double? {
        let all = segments
        guard !all.isEmpty, all.allSatisfy({ $0.seconds != nil }) else { return nil }
        return all.reduce(0) { $0 + ($1.seconds ?? 0) }
    }

    static func detail(_ step: GuidedStep) -> String {
        var parts: [String] = []
        switch step.measure {
        case .time(let t): parts.append(lengthText(t))
        case .reps(let n): parts.append(n == 1 ? "1 rep" : "\(n) reps")
        case .distance(let m): parts.append(m >= 1000 ? String(format: "%.2g km", m / 1000) : "\(LNum.int(m.rounded())) m")
        case .open: break
        }
        if let load = step.load?.trimmingCharacters(in: .whitespaces), !load.isEmpty { parts.append(load) }
        return parts.joined(separator: " · ")
    }

    /// "45 s", "1:30", "12:00".
    public static func lengthText(_ seconds: Double) -> String {
        let s = LNum.int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    /// One line a session note can carry: "3 blocks, 14 stretches".
    public var summary: String {
        let efforts = segments.filter { !$0.isRest }.count
        return "\(blocks.count) \(blocks.count == 1 ? "block" : "blocks"), \(efforts) \(efforts == 1 ? "effort" : "efforts")"
    }
}

// MARK: - Reading one from words or a picture

public enum GuidedReading {
    public static let toolName = "submit_workout_plan"

    /// The one tool a reading request offers. The model fills it in from the sentence or the board.
    public static func tool() -> AITool {
        let step = AISchema.object([
            "name": AISchema.string("The movement, as written: \"Wall balls\", \"Run\", \"SkiErg\"."),
            "seconds": AISchema.number("Set time of the step in seconds, when it is done for time. Leave out otherwise."),
            "reps": AISchema.integer("Number of reps, when it is done for reps. Leave out otherwise."),
            "distance_m": AISchema.number("Distance in metres, when it is done for distance. Leave out otherwise."),
            "load": AISchema.string("The load as written, with its unit: \"20 kg\". Leave out when none is given."),
            "rest_s": AISchema.number("Rest after this step in seconds. 0 or left out for none."),
        ], required: ["name"])
        let block = AISchema.object([
            "name": AISchema.string("What the block is called: \"Warm-up\", \"Part A\", \"EMOM 12\", \"Finisher\"."),
            "rounds": AISchema.integer("How many times the steps are repeated. 1 when not repeated."),
            "rest_between_rounds_s": AISchema.number("Rest between rounds in seconds. 0 or left out for none."),
            "steps": AISchema.array("The steps of one round, in order.", items: step),
        ], required: ["name", "rounds", "steps"])
        return AITool(name: toolName,
                      description: "Hand over the workout as blocks of steps so the app can lead the athlete through it.",
                      properties: [
                        "title": AISchema.string("A short name for the workout."),
                        "sport": AISchema.string("What kind of session it is.", enum: ["Class", "Strength", "Run", "HYROX"]),
                        "blocks": AISchema.array("The blocks in the order they are done.", items: block),
                        "note": AISchema.string("Anything written that did not fit a step. Leave out when there is nothing."),
                      ],
                      required: ["title", "sport", "blocks"])
    }

    public static let system = """
    You turn a workout, written as a sentence or shown in a picture of a gym board, into blocks of steps.
    Call \(toolName) exactly once. Copy what is written; do not invent movements, loads, times or rounds.
    A step done for time gets seconds; a step done for reps gets reps; a step done for distance gets distance_m. \
    Give only the one that is written. A step with none of them is done until the athlete moves on.
    Formats: "EMOM 12" with two movements is one block of 6 rounds, each movement a 60-second step. \
    "4 rounds" repeats the steps 4 times. "AMRAP 10" is one step of 600 seconds named with its movements. \
    "Tabata" is 8 rounds of 20 seconds of work with 10 seconds of rest after it. \
    "40/20" means 40 seconds of work and 20 seconds of rest after it.
    Loads are copied with their unit. If two loads are written for men and women, give them as written.
    If something cannot be read, leave it out and say so in note.
    """

    /// The workout the tool call describes, or nil when nothing usable came back.
    public static func workout(from input: JSONValue) -> GuidedWorkout? {
        guard let rawBlocks = input["blocks"]?.array else { return nil }
        var blocks: [GuidedBlock] = []
        for raw in rawBlocks.prefix(GuidedWorkout.maxBlocks) {
            var steps: [GuidedStep] = []
            for s in (raw["steps"]?.array ?? []).prefix(GuidedWorkout.maxSteps) {
                guard let name = s["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
                let measure: GuidedMeasure
                if let t = s["seconds"]?.number, t > 0 { measure = .time(min(t, GuidedWorkout.maxStepS)) }
                else if let n = s["reps"]?.int, n > 0 { measure = .reps(n) }
                else if let m = s["distance_m"]?.number, m > 0 { measure = .distance(m) }
                else { measure = .open }
                let load = s["load"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = LStat.clamp(s["rest_s"]?.number ?? 0, 0, GuidedWorkout.maxStepS)
                steps.append(GuidedStep(name: name, measure: measure, load: (load?.isEmpty ?? true) ? nil : load, restS: rest))
            }
            guard !steps.isEmpty else { continue }
            let rounds = max(1, min(GuidedWorkout.maxRounds, raw["rounds"]?.int ?? 1))
            let between = LStat.clamp(raw["rest_between_rounds_s"]?.number ?? 0, 0, GuidedWorkout.maxStepS)
            let name = raw["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            blocks.append(GuidedBlock(name: name.isEmpty ? "Block \(blocks.count + 1)" : name, rounds: rounds, steps: steps,
                                      restBetweenRoundsS: between))
        }
        guard !blocks.isEmpty else { return nil }
        let title = input["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sport = input["sport"]?.string ?? "Class"
        let note = input["note"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GuidedWorkout(title: title.isEmpty ? "Workout" : title,
                             sport: ["Class", "Strength", "Run", "HYROX"].contains(sport) ? sport : "Class",
                             blocks: blocks, note: (note?.isEmpty ?? true) ? nil : note)
    }
}
