import Foundation

// MARK: - Body weight

/// One weigh-in.
public struct WeightEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var kg: Double

    public init(id: UUID = UUID(), at: Date = Date(), kg: Double) { self.id = id; self.at = at; self.kg = kg }

    public var day: String { LDate.key(at) }
}

public struct WeightPoint: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    /// The day's weigh-in (the mean when there were several); nil on a day without one.
    public let kg: Double?
    /// The smoothed weight on that day.
    public let trend: Double
}

/// The weight log read as a trend. One weigh-in is water, food and the hour as much as it is the body,
/// so the figure shown and used is the smoothed one.
public struct WeightRead: Equatable, Sendable {
    /// One point a day from the first weigh-in in the window to today.
    public let points: [WeightPoint]
    /// The trend today, when there has been a weigh-in lately; otherwise the log is too old to speak for today.
    public let current: Double?
    public let latest: WeightEntry?
    /// Trend now against the trend four weeks ago.
    public let change28: Double?
    public let weighIns: Int

    public static let empty = WeightRead(points: [], current: nil, latest: nil, change28: nil, weighIns: 0)
}

public enum BodyWeight {
    /// How many days of weigh-ins the trend leans on: each weigh-in moves it part of the way, and the
    /// longer since the last one the further.
    public static let smoothingDays = 5.0
    /// A log with no weigh-in in this many days no longer says what the athlete weighs today.
    public static let staleAfterDays = 21

    public static func read(_ entries: [WeightEntry], today: String, window: Int = 120, calendar: Calendar = LDate.calendar) -> WeightRead {
        let from = LDate.adding(-(window - 1), to: today, calendar: calendar)
        let usable = entries.filter { $0.kg >= 30 && $0.kg <= 250 && $0.day <= today }.sorted { $0.at < $1.at }
        guard let latest = usable.last else { return .empty }
        var byDay: [String: [Double]] = [:]
        for e in usable { byDay[e.day, default: []].append(e.kg) }
        let days = byDay.keys.sorted()
        guard let first = days.first else { return .empty }
        var points: [WeightPoint] = []
        var trend = LStat.mean(byDay[first] ?? []) ?? latest.kg
        var lastDay = first
        var day = first
        while day <= today {
            var value: Double?
            if let v = LStat.mean(byDay[day] ?? []) {
                value = v
                let gap = Double(max(1, LDate.daysBetween(lastDay, day, calendar: calendar)))
                trend += (1 - exp(-gap / smoothingDays)) * (v - trend)
                lastDay = day
            }
            if day >= from { points.append(WeightPoint(day: day, kg: value, trend: trend)) }
            day = LDate.adding(1, to: day, calendar: calendar)
        }
        let fresh = LDate.daysBetween(latest.day, today, calendar: calendar) <= staleAfterDays
        let then = LDate.adding(-28, to: today, calendar: calendar)
        let before = points.last { $0.day <= then }?.trend
        return WeightRead(points: points, current: fresh ? trend : nil, latest: latest,
                          change28: fresh ? before.map { trend - $0 } : nil, weighIns: usable.count)
    }
}

// MARK: - Energy in against weight change

/// What the athlete burns in a day, worked out from what they ate and how their weight moved, with
/// the range it lies in. It replaces a formula with the athlete's own numbers, and is only as good
/// as the food log: food that was not logged makes the real figure higher.
public struct EnergyRead: Equatable, Sendable {
    public let window: Int
    /// Days in the window whose food log is full enough to read.
    public let loggedDays: Int
    public let weighIns: Int
    public let intake: Double?
    public let kgPerWeek: Double?
    public let burn: Double?
    public let low: Double?
    public let high: Double?
    /// Intake minus burn: negative when the athlete has been eating under what they burn.
    public let balance: Double?
    /// What is still needed, when there is no estimate yet.
    public let missing: String?
    /// Raised when a shortfall has run for weeks alongside slipping overnight signals.
    public let shortfall: String?

    public static let empty = EnergyRead(window: EnergyModel.window, loggedDays: 0, weighIns: 0, intake: nil, kgPerWeek: nil, burn: nil,
                                         low: nil, high: nil, balance: nil, missing: nil, shortfall: nil)
}

public enum EnergyModel {
    public static let window = 28
    public static let minimumLoggedDays = 14
    public static let minimumWeighIns = 5
    public static let minimumSpanDays = 14
    /// The energy a kilo of body weight change stands for. The familiar 7,700 kcal holds for people
    /// carrying a lot of fat and overstates it for leaner ones, who lose and gain more lean tissue with
    /// each kilo (Hall, Int J Obes, 2008), so a range is carried through instead of one figure.
    public static let kcalPerKg: ClosedRange<Double> = 5500...7700

    public static func read(weights: [WeightEntry], fuel: [FuelEntry], days: [LDay], today: String,
                            calendar: Calendar = LDate.calendar) -> EnergyRead {
        let keys = LDate.range(ending: LDate.adding(-1, to: today, calendar: calendar), count: window, calendar: calendar)
        guard let first = keys.first else { return .empty }
        let byDay = Dictionary(grouping: fuel, by: { $0.day })
        let logged = keys.filter { TrainingProgress.isUsable(byDay[$0] ?? []) }
        var weighed: [String: [Double]] = [:]
        for w in weights where w.day >= first && w.day <= today && w.kg >= 30 && w.kg <= 250 { weighed[w.day, default: []].append(w.kg) }
        let weighDays = weighed.keys.sorted()
        let span = weighDays.first.flatMap { a in weighDays.last.map { LDate.daysBetween(a, $0, calendar: calendar) } } ?? 0

        var need: [String] = []
        if logged.count < minimumLoggedDays { need.append("\(minimumLoggedDays - logged.count) more day\(minimumLoggedDays - logged.count == 1 ? "" : "s") with a full food log") }
        if weighDays.count < minimumWeighIns {
            need.append("\(minimumWeighIns - weighDays.count) more weigh-in\(minimumWeighIns - weighDays.count == 1 ? "" : "s")")
        } else if span < minimumSpanDays {
            need.append("weigh-ins at least \(minimumSpanDays) days apart")
        }
        let intake = LStat.mean(logged.map { FuelTotals.of(byDay[$0] ?? []).kcal })
        guard need.isEmpty, let intake else {
            return EnergyRead(window: window, loggedDays: logged.count, weighIns: weighDays.count, intake: intake, kgPerWeek: nil, burn: nil,
                              low: nil, high: nil, balance: nil, missing: need.isEmpty ? nil : "Needs " + need.joined(separator: " and ") + ".",
                              shortfall: nil)
        }
        let xs = weighDays.map { [Double(LDate.daysBetween(first, $0, calendar: calendar))] }
        let ys = weighDays.map { LStat.mean(weighed[$0] ?? []) ?? 0 }
        guard let fit = LStat.regress(y: ys, rows: xs) else {
            return EnergyRead(window: window, loggedDays: logged.count, weighIns: weighDays.count, intake: intake, kgPerWeek: nil, burn: nil,
                              low: nil, high: nil, balance: nil, missing: "Needs weigh-ins that differ from one another.", shortfall: nil)
        }
        let slope = fit.coefficients[1]
        let range = fit.interval(1, level: 0.9)
        let middle = (kcalPerKg.lowerBound + kcalPerKg.upperBound) / 2
        let burn = intake - slope * middle
        var corners: [Double] = []
        for s in [range.low, range.high] { for k in [kcalPerKg.lowerBound, kcalPerKg.upperBound] { corners.append(intake - s * k) } }
        let low = corners.min() ?? burn, high = corners.max() ?? burn
        func ten(_ v: Double) -> Double { (v / 10).rounded() * 10 }

        // A long shortfall, said only when the whole range sits under intake and the body shows it too.
        var notice: String?
        if low - intake >= 150, span >= 21 {
            let recent = Set(LDate.range(ending: today, count: 14, calendar: calendar))
            let earlier = Set(LDate.range(ending: LDate.adding(-14, to: today, calendar: calendar), count: 42, calendar: calendar))
            func mean(_ m: LMetric, _ set: Set<String>) -> Double? { LStat.mean(days.filter { set.contains($0.day) }.compactMap { m.value($0) }) }
            var signs: [String] = []
            if let a = mean(.hrv, recent), let b = mean(.hrv, earlier), b > 0, (a - b) / b <= -0.05 {
                signs.append("your HRV is running \(Int((abs(a - b) / b * 100).rounded()))% under the six weeks before")
            }
            if let a = mean(.restingHR, recent), let b = mean(.restingHR, earlier), b > 0, (a - b) / b >= 0.03 {
                signs.append("your resting heart rate is up \(Int((a - b).rounded())) bpm")
            }
            if !signs.isEmpty {
                notice = "You have eaten about \(Int(ten(burn - intake))) kcal a day under what you burn for \(span / 7) weeks, and \(signs.joined(separator: " and ")). A long shortfall can do this. Eating more around training is the usual first step; see a doctor if it does not lift."
            }
        }
        return EnergyRead(window: window, loggedDays: logged.count, weighIns: weighDays.count, intake: ten(intake), kgPerWeek: slope * 7,
                          burn: ten(burn), low: ten(low), high: ten(high), balance: ten(intake - burn), missing: nil, shortfall: notice)
    }
}

// MARK: - Sweat rate

/// A weigh-in before and after one session, with what was drunk in between.
public struct SweatTest: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var day: String
    public var beforeKg: Double
    public var afterKg: Double
    public var drankMl: Double
    public var minutes: Double

    public init(id: UUID = UUID(), day: String, beforeKg: Double, afterKg: Double, drankMl: Double, minutes: Double) {
        self.id = id; self.day = day; self.beforeKg = beforeKg; self.afterKg = afterKg; self.drankMl = drankMl; self.minutes = minutes
    }

    /// Fluid lost: the weight that went, plus what was drunk and so replaced along the way.
    public var lostMl: Double { (beforeKg - afterKg) * 1000 + drankMl }

    /// Millilitres an hour; nil for a session too short to tell, or a figure outside what bodies do.
    public var mlPerHour: Double? {
        guard minutes >= 20 else { return nil }
        let rate = lostMl / (minutes / 60)
        return rate >= 150 && rate <= 3500 ? rate : nil
    }

    /// Body weight lost over the session, as a percentage. Guidance is to keep it under 2%.
    public var percentLost: Double { beforeKg > 0 ? (beforeKg - afterKg) / beforeKg * 100 : 0 }
}

public enum SweatModel {
    /// The allowance used until the athlete has measured their own.
    public static let standardMlPerHour = 600.0

    /// The athlete's sweat rate: the middle of their last three usable tests.
    public static func rate(_ tests: [SweatTest]) -> Double? {
        LStat.median(tests.sorted { $0.day < $1.day }.compactMap { $0.mlPerHour }.suffix(3).map { $0 })
    }
}
