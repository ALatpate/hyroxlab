import Foundation

// MARK: - Training load

/// A session's training load. Preference order: HR-zone TRIMP when HR coverage is good, then
/// duration × RPE (session-RPE), then duration alone at a conservative weight.
public enum TrainingLoad {
    /// Edwards-style zone-weighted TRIMP: minutes in zone × zone number.
    public static func trimp(zoneShares: [HRZoneShare]) -> Double {
        zoneShares.reduce(0) { $0 + ($1.seconds / 60) * Double($1.zone) }
    }

    public static func sessionRPE(minutes: Double, rpe: Int) -> Double { minutes * Double(rpe) }

    /// Picks the best available estimate and reports which one it used.
    public static func load(minutes: Double, rpe: Int?, zoneShares: [HRZoneShare]?, hrQuality: Double?) -> (load: Double, method: String) {
        if let z = zoneShares, (hrQuality ?? 0) >= 0.7 { return (trimp(zoneShares: z), "HR zones") }
        if let r = rpe { return (sessionRPE(minutes: minutes, rpe: r), "RPE") }
        return (minutes * 5, "Duration")
    }

    /// Exponentially weighted acute (7 d) and chronic (28 d) loads and their ratio, from daily loads
    /// oldest → newest (one entry per day, zero for rest days).
    public static func acuteChronic(dailyLoads: [Double]) -> (acute: Double, chronic: Double, ratio: Double?) {
        let la = 2.0 / (7 + 1), lc = 2.0 / (28 + 1)
        var a = 0.0, c = 0.0
        for x in dailyLoads { a = la * x + (1 - la) * a; c = lc * x + (1 - lc) * c }
        return (a, c, c > 1 ? a / c : nil)
    }
}

// MARK: - HXReadiness

public struct ReadinessInputs: Equatable, Sendable {
    /// NOOP Charge 0–100 for today, if available.
    public var charge: Double?
    public var hrvToday: Double?
    /// HRV history oldest → newest, excluding today.
    public var hrvHistory: [Double]
    public var rhrToday: Double?
    public var rhrHistory: [Double]
    public var sleepHoursLastNight: Double?
    public var sleepNeedHours: Double
    /// Last 28 days of daily training load, oldest → newest, including yesterday as the last element.
    public var dailyLoads: [Double]
    public var hasHardSessionPlannedToday: Bool

    public init(charge: Double? = nil, hrvToday: Double? = nil, hrvHistory: [Double] = [], rhrToday: Double? = nil,
                rhrHistory: [Double] = [], sleepHoursLastNight: Double? = nil, sleepNeedHours: Double = 7.5,
                dailyLoads: [Double] = [], hasHardSessionPlannedToday: Bool = false) {
        self.charge = charge; self.hrvToday = hrvToday; self.hrvHistory = hrvHistory; self.rhrToday = rhrToday
        self.rhrHistory = rhrHistory; self.sleepHoursLastNight = sleepHoursLastNight; self.sleepNeedHours = sleepNeedHours
        self.dailyLoads = dailyLoads; self.hasHardSessionPlannedToday = hasHardSessionPlannedToday
    }
}

public enum SessionAdvice: String, Codable, Sendable {
    case goAsPlanned, easeOff, rest
    public var title: String {
        switch self {
        case .goAsPlanned: return "Train as planned"
        case .easeOff: return "Ease off today"
        case .rest: return "Rest or very easy"
        }
    }
}

public struct ReadinessDriver: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    /// Contribution in points (negative pulls readiness down).
    public let points: Double
}

public struct HXReadiness: Equatable, Sendable {
    public let score: Int               // 0–100
    public let advice: SessionAdvice
    public let drivers: [ReadinessDriver]
    /// 0–1: how much of the input set was present.
    public let confidence: Double
}

public enum HXReadinessEngine {
    /// Weights sum to 100 when all inputs exist; missing inputs redistribute to the rest.
    public static func compute(_ i: ReadinessInputs) -> HXReadiness {
        var parts: [(label: String, score01: Double, weight: Double)] = []

        if let c = i.charge { parts.append(("Charge \(Int(c))", c / 100, 35)) }

        if let h = i.hrvToday, let base = RobustBaseline(history: i.hrvHistory) {
            let z = base.z(h)
            // Above baseline is fine (cap), below costs; −2 MAD ≈ 0.
            let s = HXStats.clamp(0.75 + z * 0.125, 0, 1)
            let pct = base.percentDelta(h)
            parts.append((String(format: "HRV %+.0f%% vs baseline", pct), s, 25))
        } else if let h = i.hrvToday {
            parts.append(("HRV \(Int(h)) ms (baseline forming)", 0.7, 10))
        }

        if let r = i.rhrToday, let base = RobustBaseline(history: i.rhrHistory) {
            let z = base.z(r)
            let s = HXStats.clamp(0.75 - z * 0.125, 0, 1)
            parts.append((String(format: "Resting HR %+.0f bpm vs baseline", r - base.median), s, 10))
        }

        if let sl = i.sleepHoursLastNight {
            let ratio = HXStats.clamp(sl / max(5, i.sleepNeedHours), 0, 1.1)
            let s = HXStats.clamp((ratio - 0.6) / 0.4, 0, 1)
            parts.append((String(format: "Slept %.1f h", sl), s, 20))
        }

        if i.dailyLoads.count >= 7 {
            let ac = TrainingLoad.acuteChronic(dailyLoads: i.dailyLoads)
            if let ratio = ac.ratio {
                // 0.8–1.3 sweet spot; above 1.5 is a spike.
                let s: Double
                if ratio <= 1.3 { s = 1 } else if ratio >= 1.8 { s = 0 } else { s = 1 - (ratio - 1.3) / 0.5 }
                parts.append((String(format: "Load ratio %.2f", ratio), s, 10))
            }
            if let y = i.dailyLoads.last, let mean = HXStats.mean(i.dailyLoads), mean > 0, y > 2 * mean {
                parts.append(("Hard session yesterday", 0.4, 10))
            }
        }

        let totalW = parts.reduce(0) { $0 + $1.weight }
        guard totalW > 0 else {
            return HXReadiness(score: 0, advice: .goAsPlanned, drivers: [], confidence: 0)
        }
        let score01 = parts.reduce(0) { $0 + $1.score01 * $1.weight } / totalW
        let score = Int((score01 * 100).rounded())

        // Drivers: contribution relative to a neutral 0.75.
        let drivers = parts.map { ReadinessDriver(label: $0.label, points: ($0.score01 - 0.75) * $0.weight * (100 / totalW)) }
            .sorted { abs($0.points) > abs($1.points) }

        let advice: SessionAdvice
        switch score {
        case ..<40: advice = .rest
        case 40..<62: advice = i.hasHardSessionPlannedToday ? .easeOff : .goAsPlanned
        default: advice = .goAsPlanned
        }
        let confidence = HXStats.clamp(totalW / 100, 0, 1)
        return HXReadiness(score: score, advice: advice, drivers: Array(drivers.prefix(3)), confidence: confidence)
    }
}

// MARK: - Nutrition targets

public struct NutritionTargets: Equatable, Sendable {
    public let kcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let waterMl: Double
}

public enum DayLoadClass: String, Codable, Sendable { case rest, moderate, hard, race }

public enum NutritionPlanner {
    /// Simple, defensible targets: Mifflin-St Jeor × activity, protein 1.6–2.2 g/kg, carbs by day type.
    public static func targets(massKg: Double, heightCm: Double, age: Int, sex: Sex, day: DayLoadClass) -> NutritionTargets {
        let bmr = 10 * massKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
        let factor: Double
        let carbPerKg: Double
        let proteinPerKg: Double
        switch day {
        case .rest: factor = 1.4; carbPerKg = 3; proteinPerKg = 2.0
        case .moderate: factor = 1.6; carbPerKg = 5; proteinPerKg = 1.8
        case .hard: factor = 1.8; carbPerKg = 7; proteinPerKg = 1.8
        case .race: factor = 1.9; carbPerKg = 8; proteinPerKg = 1.6
        }
        let kcal = bmr * factor
        let protein = proteinPerKg * massKg
        let carbs = carbPerKg * massKg
        let fat = max(0.8 * massKg, (kcal - protein * 4 - carbs * 4) / 9)
        let water = 35 * massKg + (day == .rest ? 0 : 500)
        return NutritionTargets(kcal: kcal.rounded(), proteinG: protein.rounded(), carbsG: carbs.rounded(),
                                fatG: fat.rounded(), waterMl: water.rounded())
    }
}
