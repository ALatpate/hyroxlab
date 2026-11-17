import Foundation

// MARK: - Muscles

/// The muscle groups Luma tracks. Sixteen is as fine as a training log can honestly tell apart.
public enum Muscle: String, Codable, CaseIterable, Sendable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, traps, upperBack, lats, abs, obliques, lowerBack, glutes, quads, hamstrings,
         adductors, calves

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .forearms: return "Forearms"
        case .traps: return "Traps"
        case .upperBack: return "Upper back"
        case .lats: return "Lats"
        case .abs: return "Abs"
        case .obliques: return "Obliques"
        case .lowerBack: return "Lower back"
        case .glutes: return "Glutes"
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .adductors: return "Adductors"
        case .calves: return "Calves"
        }
    }

    /// The muscle groups a training week is expected to reach. The rest are small or mostly trained
    /// along the way, so going without direct work for them is not worth pointing out.
    public static let major: [Muscle] = [.chest, .shoulders, .upperBack, .lats, .abs, .glutes, .quads, .hamstrings]
}

// MARK: - Strength scale

/// How a lift is graded: the estimated one-rep max, as a multiple of bodyweight, at which each of the
/// five levels above "Starting" begins. These are Luma's own yardstick, set around milestones lifters
/// commonly use (a bodyweight bench press, a squat at one and a half times bodyweight and a deadlift
/// at twice bodyweight each begin "Strong"). They are not a population percentile.
public struct StrengthScale: Equatable, Sendable {
    public let marks: [Double]
    /// The muscles the lift is a fair gauge of.
    public let measures: [Muscle]
    public let upperBody: Bool

    /// The marks for an athlete. Women's are scaled by a rule of thumb: 0.7 of the men's for the lower
    /// body, 0.6 for the upper body. A lift that moves the body's own weight starts from 1 for both.
    public func marks(for sex: Sex, bodyweightLift: Bool) -> [Double] {
        guard sex == .female else { return marks }
        if bodyweightLift { return marks.map { 1 + ($0 - 1) * 0.6 } }
        return marks.map { $0 * (upperBody ? 0.6 : 0.7) }
    }

    /// A level from 0 to 5, with the fraction showing how far into the level the lift is.
    public func level(ratio: Double, sex: Sex, bodyweightLift: Bool) -> Double {
        let m = marks(for: sex, bodyweightLift: bodyweightLift)
        guard let first = m.first, ratio > 0 else { return 0 }
        if ratio < first { return max(0, ratio / first) }
        for i in 1..<m.count where ratio < m[i] {
            return Double(i) + (ratio - m[i - 1]) / (m[i] - m[i - 1])
        }
        return Double(m.count)
    }
}

public enum StrengthLevel: Int, CaseIterable, Sendable {
    case starting, building, solid, strong, veryStrong, exceptional

    public init(_ level: Double) { self = StrengthLevel(rawValue: min(5, max(0, Int(level)))) ?? .starting }

    public var title: String {
        switch self {
        case .starting: return "Starting"
        case .building: return "Building"
        case .solid: return "Solid"
        case .strong: return "Strong"
        case .veryStrong: return "Very strong"
        case .exceptional: return "Exceptional"
        }
    }
}

// MARK: - Exercises

/// What Luma knows about a movement.
public struct ExerciseInfo: Equatable, Sendable {
    public let name: String
    /// Muscles the movement trains directly.
    public let primary: [Muscle]
    /// Muscles that assist.
    public let secondary: [Muscle]
    /// The scale the lift is graded on, when it is one Luma grades.
    public let scale: StrengthScale?
    /// The lift moves the body's own weight as well as any load added (a pull-up, a dip).
    public let bodyweight: Bool
    /// Work against a load or the body's weight. A run, an erg or a bike is not: it trains the engine,
    /// and its efforts are not counted as sets for a muscle.
    public let resistance: Bool
    /// The movement is normally done with a bar, a bell, a ball or a sled, so a set of it with no
    /// load written down is missing something. A push-up or a plank is not.
    public let expectsLoad: Bool
}

public enum ExerciseLibrary {
    private struct Entry {
        let info: ExerciseInfo
        let keys: [String]
    }

    private static func entry(_ name: String, _ primary: [Muscle], _ secondary: [Muscle] = [], also: [String] = [],
                              marks: [Double]? = nil, measures: [Muscle] = [], upper: Bool = false, bodyweight: Bool = false,
                              resistance: Bool = true, load: Bool = true) -> Entry {
        let scale = marks.map { StrengthScale(marks: $0, measures: measures, upperBody: upper) }
        let info = ExerciseInfo(name: name, primary: primary, secondary: secondary, scale: scale, bodyweight: bodyweight,
                                resistance: resistance, expectsLoad: load && resistance && !bodyweight)
        return Entry(info: info, keys: ([name] + also).map { key($0) })
    }

    private static let entries: [Entry] = [legs, hinge, push, pull, trunk, stations, engine].flatMap { $0 }

    private static let legs: [Entry] = [
        entry("Back squat", [.quads, .glutes], [.adductors, .lowerBack, .abs], also: ["barbell squat", "high bar squat", "low bar squat"],
              marks: [0.75, 1.1, 1.5, 2.0, 2.5], measures: [.quads, .glutes]),
        entry("Air squat", [.quads, .glutes], also: ["squat", "bodyweight squat", "bw squat"], load: false),
        entry("Front squat", [.quads], [.glutes, .abs, .upperBack], marks: [0.6, 0.9, 1.25, 1.65, 2.1], measures: [.quads]),
        entry("Goblet squat", [.quads], [.glutes, .abs], also: ["kb goblet squat", "db goblet squat"]),
        entry("Leg press", [.quads], [.glutes]),
        entry("Leg extension", [.quads]),
        entry("Bulgarian split squat", [.quads, .glutes], [.hamstrings, .adductors],
              also: ["split squat", "rear foot elevated split squat", "rfess"]),
        entry("Walking lunge", [.quads, .glutes], [.hamstrings, .adductors], also: ["db walking lunge", "kb walking lunge"], load: false),
        entry("Lunge", [.quads, .glutes], [.hamstrings, .adductors],
              also: ["reverse lunge", "forward lunge", "db lunge", "dumbbell lunge", "kb lunge", "lateral lunge", "overhead lunge"], load: false),
        entry("Sandbag lunge", [.quads, .glutes], [.hamstrings, .abs], also: ["sandbag walking lunge"]),
        entry("Step-up", [.quads, .glutes], [.hamstrings], also: ["box step up", "db step up", "step over"], load: false),
        entry("Box jump", [.quads, .glutes], [.calves], also: ["jump squat", "squat jump", "broad jump", "box jump over"], load: false),
        entry("Wall sit", [.quads], [.glutes], load: false),
        entry("Calf raise", [.calves], also: ["standing calf raise", "seated calf raise"], load: false),
    ]

    private static let hinge: [Entry] = [
        entry("Deadlift", [.hamstrings, .glutes, .lowerBack], [.traps, .forearms, .quads], also: ["conventional deadlift", "barbell deadlift"],
              marks: [1.0, 1.5, 2.0, 2.5, 3.0], measures: [.hamstrings, .glutes, .lowerBack]),
        entry("Trap bar deadlift", [.quads, .glutes, .hamstrings], [.lowerBack, .traps, .forearms], also: ["hex bar deadlift"],
              marks: [1.1, 1.6, 2.15, 2.7, 3.2], measures: [.glutes, .hamstrings, .lowerBack]),
        entry("Romanian deadlift", [.hamstrings, .glutes], [.lowerBack, .forearms], also: ["rdl", "barbell rdl", "stiff leg deadlift"],
              marks: [0.75, 1.1, 1.5, 1.9, 2.3], measures: [.hamstrings]),
        entry("Sumo deadlift", [.glutes, .hamstrings, .adductors], [.quads, .lowerBack]),
        entry("Hip thrust", [.glutes], [.hamstrings], also: ["barbell hip thrust", "glute bridge", "barbell glute bridge"],
              marks: [1.0, 1.5, 2.0, 2.5, 3.0], measures: [.glutes]),
        entry("Hamstring curl", [.hamstrings], [.calves], also: ["leg curl", "nordic curl", "nordic", "lying leg curl", "seated leg curl"]),
        entry("Good morning", [.hamstrings, .lowerBack], [.glutes]),
        entry("Back extension", [.lowerBack, .glutes], [.hamstrings], also: ["hyperextension", "reverse hyper", "superman"], load: false),
        entry("Kettlebell swing", [.glutes, .hamstrings], [.lowerBack, .forearms, .shoulders],
              also: ["kb swing", "russian swing", "american swing", "swing"]),
        entry("Clean", [.glutes, .hamstrings, .quads, .traps], [.lowerBack, .forearms, .shoulders],
              also: ["power clean", "hang clean", "hang power clean", "clean and jerk", "db clean", "kb clean"]),
        entry("Snatch", [.glutes, .hamstrings, .shoulders, .traps], [.quads, .lowerBack],
              also: ["power snatch", "hang snatch", "db snatch", "kb snatch", "dumbbell snatch"]),
    ]

    private static let push: [Entry] = [
        entry("Bench press", [.chest], [.triceps, .shoulders], also: ["barbell bench press", "flat bench", "flat bench press", "bench"],
              marks: [0.5, 0.75, 1.0, 1.5, 2.0], measures: [.chest, .triceps], upper: true),
        entry("Dumbbell bench press", [.chest], [.triceps, .shoulders], also: ["db bench press", "db bench", "db press", "db chest press"]),
        entry("Incline bench press", [.chest, .shoulders], [.triceps],
              also: ["incline press", "incline db press", "incline dumbbell press", "incline db bench press", "incline bench"]),
        entry("Chest press", [.chest], [.triceps, .shoulders], also: ["machine chest press", "floor press"]),
        entry("Chest fly", [.chest], also: ["pec fly", "cable fly", "db fly", "pec deck"]),
        entry("Push-up", [.chest], [.triceps, .shoulders, .abs], also: ["press up", "pushup", "hand release push up", "hrpu"], load: false),
        entry("Dip", [.triceps, .chest], [.shoulders], also: ["ring dip", "bar dip", "bench dip"],
              marks: [1.0, 1.2, 1.45, 1.75, 2.1], measures: [.triceps], upper: true, bodyweight: true),
        entry("Overhead press", [.shoulders], [.triceps, .abs],
              also: ["ohp", "strict press", "shoulder press", "military press", "barbell overhead press", "barbell shoulder press"],
              marks: [0.35, 0.5, 0.7, 0.95, 1.2], measures: [.shoulders], upper: true),
        entry("Dumbbell shoulder press", [.shoulders], [.triceps], also: ["db shoulder press", "seated shoulder press", "arnold press",
                                                                              "db overhead press", "kb press", "z press"]),
        entry("Push press", [.shoulders], [.triceps, .quads, .abs], also: ["barbell push press", "push jerk", "jerk"],
              marks: [0.45, 0.65, 0.9, 1.2, 1.5], measures: [.shoulders], upper: true),
        entry("Handstand push-up", [.shoulders, .triceps], also: ["hspu", "pike push up"], load: false),
        entry("Lateral raise", [.shoulders], also: ["side raise", "front raise", "db lateral raise"]),
        entry("Triceps extension", [.triceps], also: ["tricep pushdown", "pushdown", "skull crusher", "overhead tricep extension",
                                                        "tricep extension", "tricep dip"]),
    ]

    private static let pull: [Entry] = [
        entry("Pull-up", [.lats, .biceps], [.upperBack, .forearms], also: ["pullup", "chest to bar", "weighted pull up", "strict pull up"],
              marks: [1.0, 1.15, 1.35, 1.6, 1.9], measures: [.lats, .biceps], upper: true, bodyweight: true),
        entry("Chin-up", [.lats, .biceps], [.upperBack, .forearms], also: ["chinup", "weighted chin up"],
              marks: [1.0, 1.15, 1.35, 1.6, 1.9], measures: [.lats, .biceps], upper: true, bodyweight: true),
        entry("Lat pulldown", [.lats], [.biceps, .upperBack], also: ["pulldown", "lat pull down", "cable pulldown"],
              marks: [0.5, 0.7, 0.9, 1.15, 1.4], measures: [.lats], upper: true),
        entry("Barbell row", [.upperBack, .lats], [.biceps, .lowerBack, .forearms], also: ["bent over row", "pendlay row", "bb row", "t bar row"],
              marks: [0.5, 0.7, 0.95, 1.25, 1.55], measures: [.upperBack, .lats], upper: true),
        entry("Dumbbell row", [.lats, .upperBack], [.biceps, .forearms],
              also: ["db row", "single arm row", "single arm db row", "kb row", "renegade row", "gorilla row"]),
        entry("Seated row", [.upperBack, .lats], [.biceps], also: ["cable row", "machine row", "seated cable row"]),
        entry("Ring row", [.upperBack, .lats], [.biceps], also: ["trx row", "inverted row", "body row"], load: false),
        entry("Face pull", [.shoulders, .upperBack], [.traps], also: ["rear delt fly", "reverse fly", "band pull apart"]),
        entry("Upright row", [.shoulders, .traps], [.biceps], also: ["high pull"]),
        entry("Biceps curl", [.biceps], [.forearms], also: ["curl", "barbell curl", "db curl", "hammer curl", "bicep curl", "dumbbell curl"]),
        entry("Shrug", [.traps], [.forearms]),
        entry("Rope climb", [.lats, .biceps, .forearms], load: false),
        entry("Dead hang", [.forearms], [.lats], load: false),
    ]

    private static let trunk: [Entry] = [
        entry("Plank", [.abs], [.obliques], also: ["hollow hold", "dead bug", "front plank", "plank hold"], load: false),
        entry("Side plank", [.obliques], [.abs], also: ["pallof press", "russian twist", "woodchop", "side bend"], load: false),
        entry("Hanging leg raise", [.abs], [.obliques, .forearms], also: ["toe to bar", "knee raise", "leg raise", "hanging knee raise"], load: false),
        entry("Sit-up", [.abs], also: ["situp", "crunch", "v up", "ab wheel", "ab rollout", "ghd sit up", "butterfly sit up"], load: false),
        entry("Mountain climber", [.abs], [.shoulders, .quads], load: false),
    ]

    private static let stations: [Entry] = [
        entry("Sled push", [.quads, .glutes, .calves], [.abs, .shoulders], also: ["prowler push", "sled"]),
        entry("Sled pull", [.lats, .upperBack, .biceps], [.quads, .glutes, .forearms, .lowerBack], also: ["rope pull", "sled drag"]),
        entry("Farmers carry", [.forearms, .traps], [.abs, .obliques, .calves],
              also: ["farmer carry", "farmer walk", "farmers walk", "kb carry", "suitcase carry", "carry"]),
        entry("Burpee broad jump", [.quads, .glutes, .chest], [.shoulders, .triceps, .abs, .calves], also: ["bbj", "broad jump burpee"], load: false),
        entry("Burpee", [.chest, .quads], [.shoulders, .triceps, .abs, .glutes], also: ["bar facing burpee", "burpee over bar", "devil press"], load: false),
        entry("Wall ball", [.quads, .glutes, .shoulders], [.triceps, .abs, .calves], also: ["wall ball shot", "wallball"]),
        entry("Thruster", [.quads, .glutes, .shoulders], [.triceps, .abs], also: ["db thruster", "barbell thruster", "kb thruster"]),
        entry("Ball slam", [.lats, .abs], [.shoulders, .triceps], also: ["med ball slam", "medicine ball slam", "slam ball", "slam"]),
        entry("Sandbag carry", [.abs, .upperBack], [.biceps, .glutes, .forearms], also: ["bear hug carry", "sandbag hold", "front carry"]),
    ]

    private static let engine: [Entry] = [
        entry("Run", [], also: ["running", "treadmill", "treadmill run", "jog", "sprint", "shuttle run", "shuttle"], resistance: false),
        entry("Row", [], also: ["rowing", "row erg", "rower", "rowing machine", "rowerg", "erg"], resistance: false),
        entry("SkiErg", [], also: ["ski erg", "ski"], resistance: false),
        entry("Bike", [], also: ["assault bike", "echo bike", "air bike", "bikeerg", "bike erg", "spin bike", "airdyne", "cycling"], resistance: false),
        entry("Skipping", [], also: ["jump rope", "double under", "single under", "skip", "rope skip"], resistance: false),
        entry("Battle rope", [], also: ["battle rope wave"], resistance: false),
    ]

    private static let index: [String: ExerciseInfo] = {
        var out: [String: ExerciseInfo] = [:]
        for e in entries { for k in e.keys where out[k] == nil { out[k] = e.info } }
        return out
    }()

    /// Words that say how a lift was loaded without making it a different lift.
    private static let neutral: Set<String> = ["barbell", "bb", "weighted", "heavy", "strict", "standing", "the", "a", "with", "and", "of"]
    /// Units and counts that come along with a name on a board ("500 m row", "back squat 5x5").
    private static let units: Set<String> = ["m", "km", "cal", "kcal", "min", "sec", "kg", "lb", "x", "rep"]
    /// Names that mean one thing alone and another inside a longer name: "Row" on a board is the
    /// rowing machine, an "upright row" is a lift.
    private static let aloneOnly: Set<String> = ["row"]

    /// A name reduced to what identifies the movement: lower case, punctuation dropped, plurals folded.
    public static func key(_ name: String) -> String {
        tokens(name).joined(separator: " ")
    }

    static func tokens(_ name: String) -> [String] {
        let lowered = name.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let split = lowered.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        return split.map(singular).filter { t in !units.contains(t) && !t.contains(where: { $0.isNumber }) }
    }

    /// "squats" and "squat" are one word, as are "crunches" and "crunch", "pull-ups" and "pull-up".
    private static func singular(_ t: String) -> String {
        if t.count > 4, t.hasSuffix("ches") || t.hasSuffix("shes") || t.hasSuffix("sses") || t.hasSuffix("xes") {
            return String(t.dropLast(2))
        }
        if t.count > 2, t.hasSuffix("s"), !t.hasSuffix("ss") { return String(t.dropLast()) }
        return t
    }

    /// What Luma knows about a movement by this name, or nil when the name tells it nothing.
    ///
    /// A name Luma has under exactly that wording (or a known other wording of it) comes back under
    /// Luma's own name, graded if the lift is one Luma grades. A variation ("paused back squat",
    /// "single leg RDL") keeps the name it was given and the muscles of the lift it varies, and is
    /// not graded: its loads say nothing about the standard lift.
    public static func match(_ name: String) -> ExerciseInfo? {
        let all = tokens(name)
        guard !all.isEmpty else { return nil }
        if let hit = index[all.joined(separator: " ")] { return hit }
        let core = all.filter { !neutral.contains($0) }
        if !core.isEmpty, core.count != all.count, let hit = index[core.joined(separator: " ")] { return hit }
        let shown = display(name)
        // The longest known name that appears whole inside this one.
        let words = core.isEmpty ? all : core
        var best: (info: ExerciseInfo, length: Int)?
        for width in stride(from: min(words.count, 5), through: 1, by: -1) where best == nil {
            for start in 0...(words.count - width) {
                let run = words[start..<(start + width)].joined(separator: " ")
                if !aloneOnly.contains(run), let hit = index[run] { best = (hit, width); break }
            }
        }
        if let best {
            return ExerciseInfo(name: shown, primary: best.info.primary, secondary: best.info.secondary, scale: nil,
                                bodyweight: best.info.bodyweight, resistance: best.info.resistance, expectsLoad: best.info.expectsLoad)
        }
        return guess(words: Set(words), name: shown)
    }

    /// The name a movement is filed under: Luma's own when it knows the movement by that wording,
    /// otherwise the name as given, tidied.
    public static func filedName(_ name: String) -> String {
        match(name)?.name ?? display(name)
    }

    static func display(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return t }
        return first.uppercased() + t.dropFirst()
    }

    /// A last resort for names Luma does not know: the word that names the kind of movement.
    private static func guess(words w: Set<String>, name: String) -> ExerciseInfo? {
        func info(_ primary: [Muscle], _ secondary: [Muscle] = [], resistance: Bool = true) -> ExerciseInfo {
            ExerciseInfo(name: name, primary: primary, secondary: secondary, scale: nil, bodyweight: false, resistance: resistance,
                         expectsLoad: false)
        }
        if !w.isDisjoint(with: ["run", "running", "jog", "sprint", "ski", "bike", "erg", "rower", "rowing", "skip", "swim"]) {
            return info([], resistance: false)
        }
        if w.contains("squat") { return info([.quads, .glutes]) }
        if w.contains("deadlift") { return info([.hamstrings, .glutes, .lowerBack]) }
        if w.contains("lunge") { return info([.quads, .glutes], [.hamstrings]) }
        if w.contains("bench") || w.contains("chest") || w.contains("pec") { return info([.chest], [.triceps, .shoulders]) }
        if w.contains("curl") { return info(w.isDisjoint(with: ["leg", "hamstring", "nordic"]) ? [.biceps] : [.hamstrings]) }
        if w.contains("raise") {
            if w.contains("calf") || w.contains("calve") { return info([.calves]) }
            if w.contains("leg") || w.contains("knee") { return info([.abs]) }
            return info([.shoulders])
        }
        if w.contains("row") { return info([.upperBack, .lats], [.biceps]) }
        if w.contains("pull") || w.contains("pulldown") || w.contains("chin") { return info([.lats], [.biceps]) }
        if w.contains("press") || w.contains("jerk") { return info([.shoulders], [.triceps]) }
        if w.contains("carry") || w.contains("hold") || w.contains("hang") { return info([.forearms], [.abs]) }
        if w.contains("jump") || w.contains("hop") || w.contains("bound") { return info([.quads, .glutes], [.calves]) }
        if !w.isDisjoint(with: ["plank", "crunch", "core", "ab", "abs", "hollow"]) { return info([.abs]) }
        if w.contains("tricep") { return info([.triceps]) }
        if w.contains("bicep") { return info([.biceps]) }
        if w.contains("glute") || w.contains("hip") { return info([.glutes]) }
        if w.contains("hamstring") { return info([.hamstrings]) }
        if w.contains("shoulder") || w.contains("delt") { return info([.shoulders]) }
        if w.contains("lat") { return info([.lats]) }
        if w.contains("push") { return info([.chest], [.triceps, .shoulders]) }
        return nil
    }

    /// The muscles one logged exercise worked: Luma's own reading of the name, or, for a movement it
    /// does not know, the muscles read from the photo along with it.
    public static func work(_ e: LiftExercise) -> (primary: [Muscle], secondary: [Muscle], resistance: Bool) {
        if let info = match(e.name) { return (info.primary, info.secondary, info.resistance) }
        let read = (e.muscles ?? []).compactMap { Muscle(rawValue: $0) }
        return (read, [], !read.isEmpty)
    }

    /// The lifts Luma grades that are a fair gauge of a muscle, in the order they are listed.
    public static func gauges(of muscle: Muscle) -> [String] {
        entries.filter { $0.info.scale?.measures.contains(muscle) ?? false }.map { $0.info.name }
    }

    /// Every name Luma files a movement under, for the list a photo is read against.
    public static var names: [String] { entries.map { $0.info.name } }
}
