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
        let previous = load()
        comparable.updated = previous?.updated ?? glance.updated
        guard previous != comparable else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(glance) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
