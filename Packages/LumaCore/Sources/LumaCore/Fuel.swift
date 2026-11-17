import Foundation

// MARK: - Log entries

public enum FuelKind: String, Codable, CaseIterable, Sendable {
    case meal, snack, drink, supplement, water

    public var title: String {
        switch self {
        case .meal: return "Meal"
        case .snack: return "Snack"
        case .drink: return "Drink"
        case .supplement: return "Supplement"
        case .water: return "Water"
        }
    }
}

/// Where the numbers on an entry came from, shown beside them so an estimate is never read as a label.
public enum FuelSource: String, Codable, Sendable {
    case typed, photo, label, coach, quick

    public var title: String {
        switch self {
        case .typed: return "Entered"
        case .photo: return "Estimated from photo"
        case .label: return "From the label"
        case .coach: return "Logged by coach"
        case .quick: return "Quick add"
        }
    }
    public var isEstimate: Bool { self == .photo || self == .coach }
}

public struct FuelItem: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// Free text such as "180 g" or "1 bowl".
    public var quantity: String
    public var kcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var fiberG: Double?
    public var caffeineMg: Double?
    public var alcoholG: Double?

    public init(id: UUID = UUID(), name: String, quantity: String = "", kcal: Double = 0, proteinG: Double = 0,
                carbsG: Double = 0, fatG: Double = 0, fiberG: Double? = nil, caffeineMg: Double? = nil, alcoholG: Double? = nil) {
        self.id = id; self.name = name; self.quantity = quantity; self.kcal = kcal; self.proteinG = proteinG
        self.carbsG = carbsG; self.fatG = fatG; self.fiberG = fiberG; self.caffeineMg = caffeineMg; self.alcoholG = alcoholG
    }
}

public struct SupplementDose: Codable, Equatable, Sendable {
    public var name: String
    public var amount: Double
    /// mg, g, mcg, IU, ml, capsule, tablet, scoop…
    public var unit: String
    public init(name: String, amount: Double, unit: String) { self.name = name; self.amount = amount; self.unit = unit }

    public var text: String {
        let a = amount == amount.rounded() ? String(Int(amount)) : String(format: "%.1f", amount)
        let plural = amount != 1 && ["capsule", "tablet", "scoop", "softgel", "drop"].contains(unit)
        return "\(a) \(unit)\(plural ? "s" : "")"
    }
}

public struct FuelEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var kind: FuelKind
    public var title: String
    public var items: [FuelItem]
    public var waterMl: Double?
    public var supplement: SupplementDose?
    /// File names of photos kept with the entry.
    public var photos: [String]
    public var note: String
    public var source: FuelSource

    public init(id: UUID = UUID(), at: Date = Date(), kind: FuelKind, title: String, items: [FuelItem] = [], waterMl: Double? = nil,
                supplement: SupplementDose? = nil, photos: [String] = [], note: String = "", source: FuelSource = .typed) {
        self.id = id; self.at = at; self.kind = kind; self.title = title; self.items = items; self.waterMl = waterMl
        self.supplement = supplement; self.photos = photos; self.note = note; self.source = source
    }

    public var day: String { LDate.key(at) }
    public var kcal: Double { items.reduce(0) { $0 + $1.kcal } }
    public var proteinG: Double { items.reduce(0) { $0 + $1.proteinG } }
    public var carbsG: Double { items.reduce(0) { $0 + $1.carbsG } }
    public var fatG: Double { items.reduce(0) { $0 + $1.fatG } }
    public var caffeineMg: Double { items.reduce(0) { $0 + ($1.caffeineMg ?? 0) } }
    public var alcoholG: Double { items.reduce(0) { $0 + ($1.alcoholG ?? 0) } }
}

/// A supplement the athlete takes regularly, for one-tap logging and the daily checklist.
public struct SupplementPlan: Codable, Equatable, Sendable, Identifiable {
    public enum Timing: String, Codable, CaseIterable, Sendable {
        case morning, preSession, postSession, evening, anytime
        public var title: String {
            switch self {
            case .morning: return "Morning"
            case .preSession: return "Before training"
            case .postSession: return "After training"
            case .evening: return "Evening"
            case .anytime: return "Any time"
            }
        }
    }
    public var id: UUID
    public var dose: SupplementDose
    public var timing: Timing
    public var note: String
    public var active: Bool

    public init(id: UUID = UUID(), dose: SupplementDose, timing: Timing = .anytime, note: String = "", active: Bool = true) {
        self.id = id; self.dose = dose; self.timing = timing; self.note = note; self.active = active
    }
}

// MARK: - Totals and targets

public struct FuelTotals: Equatable, Sendable {
    public var kcal = 0.0
    public var proteinG = 0.0
    public var carbsG = 0.0
    public var fatG = 0.0
    public var waterMl = 0.0
    public var caffeineMg = 0.0
    public var alcoholG = 0.0
    public var entries = 0

    public init() {}

    public static func of(_ entries: [FuelEntry]) -> FuelTotals {
        var t = FuelTotals()
        for e in entries {
            t.kcal += e.kcal; t.proteinG += e.proteinG; t.carbsG += e.carbsG; t.fatG += e.fatG
            t.waterMl += e.waterMl ?? 0; t.caffeineMg += e.caffeineMg; t.alcoholG += e.alcoholG
            if e.kind != .water && e.kind != .supplement { t.entries += 1 }
        }
        return t
    }
}

public enum FuelDayClass: String, Codable, Sendable {
    case rest, moderate, hard, race

    public var title: String {
        switch self {
        case .rest: return "Rest day"
        case .moderate: return "Training day"
        case .hard: return "Hard day"
        case .race: return "Race day"
        }
    }
}

public struct FuelTargets: Equatable, Sendable {
    public let dayClass: FuelDayClass
    public let kcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let waterMl: Double
    /// Sensible daily ceiling (about 6 mg per kg, capped at 400 mg).
    public let caffeineLimitMg: Double
}

public enum FuelPlanner {
    /// Mifflin–St Jeor resting energy, kcal per day.
    public static func restingEnergy(massKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        10 * massKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    /// Classifies the day for fuelling from what is planned or already done.
    public static func dayClass(planned: [PlannedSession], strain21: Double?) -> FuelDayClass {
        let live = planned.filter { $0.status != .removed && $0.status != .skipped && $0.kind != .rest }
        if live.contains(where: { $0.kind == .simulation }) { return .race }
        if live.contains(where: { $0.intensity == .hard }) || (strain21 ?? 0) >= 15 || live.count >= 2 { return .hard }
        if !live.isEmpty || (strain21 ?? 0) >= 9 { return .moderate }
        return .rest
    }

    /// The day's protein target: 2 g for each kg of body mass.
    public static func proteinTarget(_ p: LProfile) -> Double { (p.weightKg * 2).rounded() }

    /// Daily targets for a hybrid athlete: energy from resting need × an activity factor for the day,
    /// protein at 2 g/kg, carbohydrate scaled to the day's work, fat as the remainder (never under
    /// 0.8 g/kg), and fluid from body mass plus what training sweats out: the athlete's own measured
    /// rate when they have one (`SweatModel.rate`), a standard allowance otherwise.
    public static func targets(profile p: LProfile, dayClass: FuelDayClass, trainingMinutes: Double = 60,
                               sweatMlPerHour: Double = SweatModel.standardMlPerHour, on date: Date = Date()) -> FuelTargets {
        let rest = restingEnergy(massKg: p.weightKg, heightCm: p.heightCm, age: p.age(on: date), sex: p.sex)
        let factor: Double, carbPerKg: Double
        switch dayClass {
        case .rest: factor = 1.4; carbPerKg = 3
        case .moderate: factor = 1.65; carbPerKg = 5
        case .hard: factor = 1.85; carbPerKg = 6.5
        case .race: factor = 2.0; carbPerKg = 8
        }
        let kcal = (rest * factor / 10).rounded() * 10
        let protein = proteinTarget(p)
        var carbs = (p.weightKg * carbPerKg).rounded()
        let minFat = p.weightKg * 0.8
        var fat = (kcal - protein * 4 - carbs * 4) / 9
        if fat < minFat {
            fat = minFat
            carbs = max(p.weightKg * 2.5, (kcal - protein * 4 - fat * 9) / 4).rounded()
        }
        let water = p.weightKg * 35 + (dayClass == .rest ? 0 : trainingMinutes / 60 * LStat.clamp(sweatMlPerHour, 300, 2000))
        let waterRounded = (water / 50).rounded() * 50
        return FuelTargets(dayClass: dayClass, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat.rounded(),
                           waterMl: waterRounded, caffeineLimitMg: min(400, (p.weightKg * 6 / 10).rounded() * 10))
    }

    /// Practical fuelling cues around a session.
    public static func sessionCues(massKg: Double, intensity: Intensity, durationMin: Int) -> [String] {
        var out: [String] = []
        let pre = Int((massKg * (intensity == .hard ? 1.0 : 0.6)).rounded())
        out.append("1–3 h before: about \(pre) g of carbohydrate, low in fat and fibre.")
        if durationMin >= 75 || intensity == .hard {
            out.append("During: 30–60 g of carbohydrate per hour once you pass 60 minutes, with fluids.")
        }
        out.append("Within an hour after: \(Int((massKg * 0.3).rounded())) g of protein plus carbohydrate to refill.")
        return out
    }
}
