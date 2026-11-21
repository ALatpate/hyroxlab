import Foundation

// MARK: - HRV against its own normal band

/// One day of the HRV trend: the night's figure and the week's average ending on it, both in ms.
public struct HRVTrendDay: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let nightMs: Double?
    public let weekMs: Double?
}

/// HRV read the way the sports-science guides read it: a week's rolling average set against the
/// athlete's own normal band, instead of one night's figure. Averages are taken over the natural log
/// of RMSSD and shown back in milliseconds. The band is the 60-day average plus or minus half of the
/// athlete's own day-to-day spread.
public struct HRVTrend: Equatable, Sendable {
    public enum Place: String, Sendable { case below, within, above }

    /// The days charted, oldest first, ending today.
    public let days: [HRVTrendDay]
    public let lowMs: Double?
    public let highMs: Double?
    /// The week's average today, in ms.
    public let weekMs: Double?
    /// Where the week's average sits against the band. Nil until the band exists.
    public let place: Place?
    /// Days in a row, ending today, that the week's average has been on that side of the band.
    public let daysThere: Int
    /// Day-to-day spread over the last week and over the 60 days, as a percentage of the average.
    public let weekSpread: Double?
    public let usualSpread: Double?
    /// Nights with a figure in the 60 days.
    public let nights: Int
    public let headline: String
    public let detail: String

    public var ready: Bool { place != nil }
    /// Under the band for two days or more: a reason to keep the day light.
    public var holdsBack: Bool { place == .below && daysThere >= 2 }
}

public enum HRVTrendModel {
    public static let weekDays = 7
    public static let minInWeek = 3
    public static let baseDays = 60
    public static let minInBase = 20
    /// Half of the athlete's own spread on either side of the 60-day average.
    public static let bandShare = 0.5

    public static func build(days: [LDay], today: String, count: Int = 42, calendar: Calendar = LDate.calendar) -> HRVTrend {
        var byDay: [String: Double] = [:]
        for d in days { if let v = d.hrv, v > 0, d.day <= today { byDay[d.day] = log(v) } }
        let span = LDate.range(ending: today, count: max(count, baseDays) + weekDays, calendar: calendar)
        let logs: [Double?] = span.map { byDay[$0] }
        let rolling = LStat.rollingMean(logs, window: weekDays, minCount: minInWeek)

        let base = logs.suffix(baseDays).compactMap { $0 }
        var low: Double?, high: Double?, usualSpread: Double?
        if base.count >= minInBase, let mean = LStat.mean(base), let sd = LStat.sd(base), mean > 0 {
            low = mean - bandShare * sd
            high = mean + bandShare * sd
            usualSpread = sd / mean * 100
        }
        let week = logs.suffix(weekDays).compactMap { $0 }
        var weekSpread: Double?
        if week.count >= minInWeek, let mean = LStat.mean(week), let sd = LStat.sd(week), mean > 0 { weekSpread = sd / mean * 100 }

        func side(_ v: Double?) -> HRVTrend.Place? {
            guard let v, let low, let high else { return nil }
            return v < low ? .below : (v > high ? .above : .within)
        }
        let place = side(rolling.last ?? nil)
        var there = 0
        if let place {
            for v in rolling.reversed() {
                guard side(v) == place else { break }
                there += 1
            }
        }
        let shown = Array(zip(span, zip(logs, rolling)).suffix(count)).map { key, pair in
            HRVTrendDay(day: key, nightMs: pair.0.map { exp($0) }, weekMs: pair.1.map { exp($0) })
        }
        let weekMs = (rolling.last ?? nil).map { exp($0) }
        let lowMs = low.map { exp($0) }, highMs = high.map { exp($0) }

        let headline: String, detail: String
        if let place, let weekMs, let lowMs, let highMs {
            let range = "\(LNum.int(lowMs.rounded())) to \(LNum.int(highMs.rounded())) ms"
            let now = "\(LNum.int(weekMs.rounded())) ms"
            let forDays = there == 1 ? "for a day" : "for \(there) days"
            switch place {
            case .below:
                headline = "HRV is under your normal"
                detail = "The week's average is \(now); your normal range is \(range). It has been under \(forDays). Keep hard work short until it is back inside."
            case .above:
                headline = "HRV is above your normal"
                detail = "The week's average is \(now); your normal range is \(range). It has been above \(forDays), which often follows easier days."
            case .within:
                headline = "HRV is in your normal range"
                detail = "The week's average is \(now); your normal range is \(range)."
            }
        } else if lowMs != nil {
            headline = "Too few nights this week"
            detail = "The week's average needs \(minInWeek) nights with HRV in the last \(weekDays) days."
        } else {
            headline = "Building your normal range"
            detail = "\(base.count) of \(minInBase) nights with HRV in the last \(baseDays) days. The range appears once there are \(minInBase)."
        }
        return HRVTrend(days: shown, lowMs: lowMs, highMs: highMs, weekMs: weekMs, place: place, daysThere: there,
                        weekSpread: weekSpread, usualSpread: usualSpread, nights: base.count, headline: headline, detail: detail)
    }
}

// MARK: - Resting heart rate creeping up

/// A slow rise in resting heart rate that no single night would flag. Each night's distance above the
/// athlete's usual is added up, less a little slack, and the sum falls back to zero on a normal night.
/// Published early-warning work on wearables uses the same adding-up idea. It says a rise is under way,
/// never why: alcohol, travel, stress and a hard block raise resting heart rate as well as illness.
public struct RestingDrift: Equatable, Sendable {
    /// The running sum today, in units of the athlete's usual night-to-night spread.
    public let score: Double
    /// Nights above the usual since the sum last stood at zero.
    public let nights: Int
    /// Average rise over those nights, in beats a minute.
    public let riseBpm: Double
    public let raised: Bool

    public var line: String {
        let rise = String(format: "%.0f", max(1, riseBpm.rounded()))
        return "Resting heart rate has been creeping up for \(nights) nights, about \(rise) bpm above your usual."
    }
}

public enum RestingDriftModel {
    /// Slack taken off each night, in spreads: a night this close to usual adds nothing.
    public static let slack = 0.5
    /// The most one night can add, so a single bad night cannot stand in for a rise.
    public static let cap = 2.0
    /// The sum at which the rise is worth saying.
    public static let limit = 4.0
    /// Nights above the usual a rise needs before it is said.
    public static let minNights = 3
    public static let baseDays = 28
    /// The usual is taken from the nights ending this many days before the night being judged.
    public static let gapDays = 3
    public static let minInBase = 14
    public static let lookBack = 14

    public static func assess(days: [LDay], today: String, calendar: Calendar = LDate.calendar) -> RestingDrift? {
        var byDay: [String: Double] = [:]
        for d in days { if let v = d.restingHR, v > 0, d.day <= today { byDay[d.day] = v } }
        guard byDay[today] != nil else { return nil }
        var sum = 0.0, above = 0, judged = 0, lastStep = 0.0
        var rises: [Double] = []
        for key in LDate.range(ending: today, count: lookBack, calendar: calendar) {
            guard let v = byDay[key] else { continue }
            let end = LDate.adding(-gapDays, to: key, calendar: calendar)
            let base = LDate.range(ending: end, count: baseDays, calendar: calendar).compactMap { byDay[$0] }
            guard base.count >= minInBase, let mean = LStat.mean(base) else { continue }
            let spread = max(1.0, LStat.sd(base) ?? 1.0)
            judged += 1
            let step = min(cap, (v - mean) / spread - slack)
            sum = max(0, sum + step)
            if sum <= 0 {
                above = 0
                rises = []
            } else if step > 0 {
                above += 1
                rises.append(v - mean)
            }
            if key == today { lastStep = step }
        }
        guard judged > 0 else { return nil }
        // Said only while it is still going on: enough nights above the usual, and last night one of them.
        let raised = sum >= limit && above >= minNights && lastStep > 0
        return RestingDrift(score: sum, nights: above, riseBpm: LStat.mean(rises) ?? 0, raised: raised)
    }
}

// MARK: - Sleep Regularity Index

/// The Sleep Regularity Index: how often the athlete is in the same state, asleep or awake, at the same
/// clock time on consecutive days. 100 is the same pattern every day; a pattern with no regularity at
/// all scores about 0. It is the measure used in the large studies of sleep regularity, so the figure
/// can be set beside published ones.
public struct SleepRegularity: Equatable, Sendable {
    public let index: Double
    /// Pairs of consecutive days compared.
    public let pairs: Int
    public let headline: String
    public let detail: String
}

public enum SleepRegularityModel {
    public static let epochS: Double = 300
    public static let minPairs = 5
    public static let days = 14

    public static func read(sleeps: [LSleep], today: String, calendar: Calendar = LDate.calendar) -> SleepRegularity? {
        let horizon = (LDate.startOfDay(today, calendar: calendar)?.timeIntervalSince1970 ?? 0) - Double(days + 3) * 86_400
        let whole = sleeps.filter { !$0.incomplete && $0.end > $0.start && $0.end >= horizon }
        let nights = Set(whole.filter { !$0.isNap }.map { $0.day })
        func asleep(_ t: Double) -> Bool { whole.contains { t >= $0.start && t < $0.end } }
        var same = 0, total = 0, pairs = 0
        for key in LDate.range(ending: today, count: days, calendar: calendar) {
            let before = LDate.adding(-1, to: key, calendar: calendar)
            guard nights.contains(key), nights.contains(before), let start = LDate.startOfDay(before, calendar: calendar) else { continue }
            // The 24 hours from noon two days back to noon the day before, against the 24 hours after them:
            // each stretch holds one whole night.
            let from = start.timeIntervalSince1970 - 12 * 3600
            pairs += 1
            var t = from
            while t < from + 24 * 3600 {
                if asleep(t) == asleep(t + 24 * 3600) { same += 1 }
                total += 1
                t += epochS
            }
        }
        guard pairs >= minPairs, total > 0 else { return nil }
        let index = LStat.clamp(-100 + 200 * Double(same) / Double(total), 0, 100)
        let figure = LNum.int(index.rounded())
        let headline = index >= 85 ? "Very regular sleep" : (index >= 70 ? "Fairly regular sleep" : "Sleep times are scattered")
        let detail = "Sleep Regularity Index \(figure) of 100 over \(pairs) pairs of days: how often you are asleep or awake at the same clock time as the day before."
        return SleepRegularity(index: index, pairs: pairs, headline: headline, detail: detail)
    }
}
