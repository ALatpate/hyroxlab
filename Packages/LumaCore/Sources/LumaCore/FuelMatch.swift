import Foundation

// MARK: - Food matched to the work

/// One thing a day's food is checked against.
public struct FuelCheck: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Nil when the day gives nothing to judge it by.
    public let met: Bool?
    public let detail: String
}

/// A day's food log read against the training that day actually held.
public struct FuelDayRead: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let dayClass: FuelDayClass
    /// The log is full enough to read (`TrainingProgress.isUsable`).
    public let usable: Bool
    public let checks: [FuelCheck]

    public var judged: Int { checks.filter { $0.met != nil }.count }
    public var metCount: Int { checks.filter { $0.met == true }.count }

    /// "3 of 4 matched", or what is missing.
    public var headline: String {
        guard usable else { return "Log too thin to read" }
        return judged == 0 ? "Nothing to judge yet" : "\(metCount) of \(judged) matched"
    }
}

public enum FuelMatch {
    /// Carbohydrate for each kg of body mass that suits each kind of day: the same figures the day's
    /// targets are built from (`FuelPlanner.targets`), inside the ranges sports nutrition guidance gives
    /// (3 to 5 g on light days, 6 to 10 on hard ones).
    public static func carbsPerKg(_ c: FuelDayClass) -> Double {
        switch c {
        case .rest: return 3
        case .moderate: return 5
        case .hard: return 6.5
        case .race: return 8
        }
    }

    /// Protein in one meal, per kg, that counts as a protein meal. Around 0.4 g per kg at each of four
    /// meals is what reaches the daily amount recommended for building muscle; 0.3 is the floor used here.
    public static let proteinMealPerKg = 0.3
    public static let proteinMeals = 4

    /// The kind of day it was, from what was done: the day's strain and its sessions.
    public static func dayClass(strain21: Double?, sessions: Int, raced: Bool) -> FuelDayClass {
        if raced { return .race }
        if (strain21 ?? 0) >= 15 || sessions >= 2 { return .hard }
        if sessions >= 1 || (strain21 ?? 0) >= 9 { return .moderate }
        return .rest
    }

    /// `entries` are the day's food entries, `workouts` its recorded sessions. `closed` is false for a
    /// day still in progress, whose totals are "so far" and are not held against it.
    public static func read(day: String, entries: [FuelEntry], workouts: [LWorkout], strain21: Double?, raced: Bool = false,
                            profile: LProfile, closed: Bool, calendar: Calendar = LDate.calendar) -> FuelDayRead {
        let food = entries.filter { $0.kind != .water && $0.kind != .supplement }
        let body = max(30, profile.weightKg)
        let sessions = workouts.filter { $0.durationS >= 20 * 60 }.sorted { $0.start < $1.start }
        let kind = dayClass(strain21: strain21, sessions: sessions.count, raced: raced)
        let usable = TrainingProgress.isUsable(food)
        guard usable || !closed else { return FuelDayRead(day: day, dayClass: kind, usable: false, checks: []) }
        let totals = FuelTotals.of(food)
        var checks: [FuelCheck] = []
        let soFar = closed ? "" : " so far"

        // Carbohydrate for the work.
        let perKg = totals.carbsG / body
        let want = carbsPerKg(kind)
        let wantText = want == want.rounded() ? String(Int(want)) : String(format: "%.1f", want)
        let carbText = "\(String(format: "%.1f", perKg)) g of carbs per kg\(soFar). A \(kind.title.lowercased()) suits about \(wantText)."
        checks.append(FuelCheck(id: "carbs", title: "Carbs for the work", met: closed ? perKg >= want * 0.85 : (perKg >= want * 0.85 ? true : nil),
                                detail: carbText))

        // Protein, and how it was spread.
        let target = FuelPlanner.proteinTarget(profile)
        let meals = food.filter { $0.proteinG >= proteinMealPerKg * body }.count
        let enough = totals.proteinG >= target * 0.9
        let spread = meals >= proteinMeals - 1
        var proteinText = "\(Int(totals.proteinG.rounded())) g of \(Int(target))\(soFar), in \(meals) protein meal\(meals == 1 ? "" : "s")."
        if enough, !spread { proteinText += " Spread over \(proteinMeals), the same amount does more." }
        checks.append(FuelCheck(id: "protein", title: "Protein across the day", met: closed ? (enough && spread) : (enough && spread ? true : nil),
                                detail: proteinText))

        // Around the day's main session.
        if let main = sessions.max(by: { $0.durationS < $1.durationS }) {
            let start = Date(timeIntervalSince1970: main.start), end = Date(timeIntervalSince1970: main.end)
            let hard = kind == .hard || kind == .race
            let preWant = body * (hard ? 1.0 : 0.6)
            let before = food.filter { $0.at >= start.addingTimeInterval(-4 * 3600) && $0.at <= start.addingTimeInterval(-10 * 60) }
            let preCarbs = before.reduce(0) { $0 + $1.carbsG }
            let startClock = LFormat.timeOfDay(minutes: Double(calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)))
            let early = calendar.component(.hour, from: start) < 8
            let name = main.kind == .other ? "session" : main.kind.title.lowercased()
            if before.isEmpty, early {
                checks.append(FuelCheck(id: "before", title: "Before training", met: nil,
                                        detail: "Nothing logged before your \(startClock) \(name). An early session is often done fasted; a small carb snack helps if it felt flat."))
            } else {
                checks.append(FuelCheck(id: "before", title: "Before training", met: preCarbs >= preWant * 0.7,
                                        detail: "\(Int(preCarbs.rounded())) g of carbs in the 4 hours before your \(startClock) \(name). About \(Int(preWant.rounded())) g suits it."))
            }
            let after = food.filter { $0.at >= end && $0.at <= end.addingTimeInterval(2 * 3600) }
            let postProtein = after.reduce(0) { $0 + $1.proteinG }
            let postWant = body * proteinMealPerKg
            // A session that ended under two hours ago on a day still open has not had its chance yet.
            let waited = closed || food.contains { $0.at > end.addingTimeInterval(2 * 3600) }
            checks.append(FuelCheck(id: "after", title: "After training", met: postProtein >= postWant * 0.8 ? true : (waited ? false : nil),
                                    detail: "\(Int(postProtein.rounded())) g of protein in the 2 hours after. About \(Int(postWant.rounded())) g suits it."))
        }
        return FuelDayRead(day: day, dayClass: kind, usable: usable, checks: checks)
    }
}
