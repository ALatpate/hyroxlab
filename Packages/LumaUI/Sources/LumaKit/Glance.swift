import Foundation

/// What Luma's widgets show. The app writes it into the shared container after every analysis
/// refresh; the widget extension reads it and never opens the database.
public struct LumaGlance: Codable, Equatable, Sendable {
    public struct Session: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// "06:30", or nil when the session has no fixed time.
        public var time: String?
        public var symbol: String
        public var done: Bool

        public init(id: String, title: String, time: String?, symbol: String, done: Bool) {
            self.id = id; self.title = title; self.time = time; self.symbol = symbol; self.done = done
        }
    }

    /// The training day (it rolls over at 04:00) these figures belong to.
    public var day: String
    public var recovery: Int?
    /// Strain as displayed, on a scale of 0…`strainMax`.
    public var strain: Double?
    public var strainMax: Double
    public var sleepScore: Int?
    public var sleepMinutes: Int?
    public var hrv: Int?
    public var restingHR: Int?
    /// The day's call in a few words, and one supporting line.
    public var call: String?
    public var callDetail: String?
    public var sessions: [Session]
    /// Tomorrow's first session, as "Gym class · 06:30".
    public var tomorrow: String?
    public var kcal: Int
    public var kcalTarget: Int
    public var protein: Int
    public var proteinTarget: Int
    public var waterMl: Int
    public var waterTargetMl: Int
    /// The coach's morning brief, when one has been written today.
    public var brief: String?
    /// Recovery for the seven days ending on `day`, oldest first; nil where a day has no score.
    public var week: [Int?]
    /// The companion: its name, its build and how it looks from now until the morning after next.
    /// Absent in a glance written by an earlier build.
    public var buddy: Buddy?
    public var updated: Date

    public init(day: String, recovery: Int? = nil, strain: Double? = nil, strainMax: Double = 21, sleepScore: Int? = nil,
                sleepMinutes: Int? = nil, hrv: Int? = nil, restingHR: Int? = nil, call: String? = nil, callDetail: String? = nil,
                sessions: [Session] = [], tomorrow: String? = nil, kcal: Int = 0, kcalTarget: Int = 0, protein: Int = 0,
                proteinTarget: Int = 0, waterMl: Int = 0, waterTargetMl: Int = 0, brief: String? = nil, week: [Int?] = [],
                updated: Date = Date()) {
        self.day = day; self.recovery = recovery; self.strain = strain; self.strainMax = strainMax; self.sleepScore = sleepScore
        self.sleepMinutes = sleepMinutes; self.hrv = hrv; self.restingHR = restingHR; self.call = call; self.callDetail = callDetail
        self.sessions = sessions; self.tomorrow = tomorrow; self.kcal = kcal; self.kcalTarget = kcalTarget; self.protein = protein
        self.proteinTarget = proteinTarget; self.waterMl = waterMl; self.waterTargetMl = waterTargetMl; self.brief = brief
        self.week = week; self.updated = updated
    }

    /// The companion as the widgets draw it. The app works out every state ahead of time with its one
    /// set of rules; a widget only looks up the moment that has begun.
    public struct Buddy: Codable, Equatable, Sendable {
        public struct Moment: Codable, Equatable, Sendable {
            public var at: Date
            /// A `BuddyKind` raw value.
            public var kind: String
            public var title: String
            public var line: String
            /// 0…1 from the recovery score; negative when there is no score.
            public var energy: Double

            public init(at: Date, kind: String, title: String, line: String, energy: Double) {
                self.at = at; self.kind = kind; self.title = title; self.line = line; self.energy = energy
            }
        }

        public var name: String
        /// Strength levels 0…5 for shoulders, chest, back, arms, core and legs; negative where no lift
        /// measures the part, which is then drawn at the plain build.
        public var levels: [Double]
        public var moments: [Moment]

        public init(name: String, levels: [Double], moments: [Moment]) {
            self.name = name; self.levels = levels; self.moments = moments
        }

        /// The moment that has begun at `date`.
        public func moment(at date: Date) -> Moment? { moments.last { $0.at <= date } ?? moments.first }

        /// What is still to be shown from `date` on: the moment under way, with the time it began taken
        /// out, and those after it. Two schedules that agree on this draw the same widget.
        func ahead(of date: Date) -> Buddy {
            var copy = self
            var rest = moments.filter { $0.at > date }
            if var now = moment(at: date) {
                now.at = .distantPast
                rest.removeAll { $0 == now }
                rest.insert(now, at: 0)
            }
            copy.moments = rest
            return copy
        }
    }

    /// The training-day key for a moment in time: the local date, with the day rolling over at 04:00.
    public static func dayKey(for date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date.addingTimeInterval(-4 * 3600))
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The next 04:00 after `date`, when a glance for the current day stops being today's.
    public static func nextRollover(after date: Date = Date()) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.nextDate(after: date, matching: DateComponents(hour: 4, minute: 0, second: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(6 * 3600)
    }

    /// Whether these figures describe the training day that contains `date`.
    public func isCurrent(at date: Date = Date()) -> Bool { day == LumaGlance.dayKey(for: date) }

    public var strainText: String? {
        strain.map { String(format: strainMax <= 21 ? "%.1f" : "%.0f", $0) }
    }

    public var strainFraction: Double {
        guard let strain, strainMax > 0 else { return 0 }
        return min(1, max(0, strain / strainMax))
    }

    public var sleepText: String? {
        sleepMinutes.map { "\($0 / 60)h \(String(format: "%02d", $0 % 60))" }
    }

    /// A filled-in example for widget galleries and previews. Never shown as the athlete's data.
    public static var sample: LumaGlance {
        LumaGlance(day: dayKey(), recovery: 74, strain: 9.4, strainMax: 21, sleepScore: 82, sleepMinutes: 452, hrv: 64, restingHR: 52,
                   call: "Good to push today", callDetail: "Recovery is high and your load is steady.",
                   sessions: [Session(id: "a", title: "Gym class", time: "06:30", symbol: "figure.highintensity.intervaltraining", done: true),
                              Session(id: "b", title: "Easy run", time: "18:00", symbol: "figure.run", done: false)],
                   tomorrow: "Strength · 06:30", kcal: 1840, kcalTarget: 2650, protein: 96, proteinTarget: 150, waterMl: 1400,
                   waterTargetMl: 2800, brief: "Recovered well after seven and a half hours. Keep tonight's run easy and get to bed by 22:30.",
                   week: [58, 66, 41, 72, 80, 63, 74], updated: Date())
    }
}

/// Where the glance is kept: the App Group container shared by the app and its widget extension.
public enum LumaGlanceStore {
    /// The App Group identifier. Each process sets it once at launch (the app and the widget extension
    /// resolve it the same way); until then, reads and writes use the process's own defaults.
    public static var suiteName: String?
    static let key = "luma.glance"

    private static var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public static func load() -> LumaGlance? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(LumaGlance.self, from: data)
    }

    /// Stores the glance. Returns true when something a widget draws has changed, so the caller can
    /// ask for new timelines only then.
    @discardableResult
    public static func save(_ glance: LumaGlance) -> Bool {
        var comparable = glance
        var previous = load()
        comparable.updated = previous?.updated ?? glance.updated
        // The companion's schedule is written from "now" each time; what counts is what is still ahead.
        comparable.buddy = comparable.buddy?.ahead(of: glance.updated)
        if let before = previous?.buddy { previous?.buddy = before.ahead(of: glance.updated) }
        guard previous != comparable else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(glance) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}

/// Things logged from outside the app: a widget button, a shortcut, Siri. The widget extension cannot
/// reach the app's records, so each is queued in the shared container and the app files it the next
/// time it runs. The glance is adjusted at once, so the widget that was tapped shows the new figure.
public enum LumaQuickLog {
    public struct Item: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case water, supplements, weight }
        public var id: UUID
        public var at: Date
        public var kind: Kind
        /// Millilitres of water, or kilograms of body weight.
        public var amount: Double

        public init(id: UUID = UUID(), at: Date = Date(), kind: Kind, amount: Double = 0) {
            self.id = id; self.at = at; self.kind = kind; self.amount = amount
        }
    }

    static let key = "luma.quicklog"
    static let pokeKey = "luma.buddy.poke"

    private static var defaults: UserDefaults {
        LumaGlanceStore.suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    private static func stored() -> [Item] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([Item].self, from: data)) ?? []
    }

    private static func store(_ items: [Item]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(items) { defaults.set(data, forKey: key) }
    }

    /// Queues an entry and moves the stored glance to match, when it is for the current day.
    public static func add(_ item: Item) {
        // A queue that nothing has drained for a long time is not allowed to grow without end.
        store(Array((stored() + [item]).suffix(200)))
        guard item.kind == .water, var glance = LumaGlanceStore.load(), glance.isCurrent(at: item.at) else { return }
        glance.waterMl += Int(item.amount.rounded())
        LumaGlanceStore.save(glance)
    }

    /// Everything queued, oldest first. The queue is emptied.
    public static func drain() -> [Item] {
        let items = stored()
        if !items.isEmpty { defaults.removeObject(forKey: key) }
        return items.sorted { $0.at < $1.at }
    }

    public static var isEmpty: Bool { defaults.data(forKey: key) == nil }

    /// A tap on the companion in a widget: when it happened.
    public static func poke(at date: Date = Date()) { defaults.set(date.timeIntervalSince1970, forKey: pokeKey) }

    public static var lastPoke: Date? {
        let t = defaults.double(forKey: pokeKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
}
