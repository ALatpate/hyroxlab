import Foundation

// MARK: - Luma Doctor
//
// A weekly check of the athlete's own numbers against their own usual range. It is not a doctor and
// finds no illness: it says which readings sat outside the range they usually sit in, for how many
// nights, and whether one has been drifting. Every rule it applies to a single night is the rule the
// daily read already applies (`BodyWatch`), so the weekly check and the daily one cannot disagree
// about a night.

/// How a week's reading stands against the athlete's own usual range.
public enum DoctorLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Too little data to say.
    case noData = 0
    /// Inside the usual range.
    case steady = 1
    /// Outside the range on a couple of nights, or drifting towards its edge.
    case watch = 2
    /// Outside the usual range for much of the week.
    case outside = 3

    public static func < (a: DoctorLevel, b: DoctorLevel) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .noData: return "Not enough data"
        case .steady: return "In your usual range"
        case .watch: return "Worth watching"
        case .outside: return "Outside your usual range"
        }
    }
}

/// One thing the weekly check looked at.
public struct DoctorFinding: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var level: DoctorLevel
    /// The week's figure as shown: "54 bpm". A dash when there is none.
    public var figure: String
    /// What it usually is: "usually 49 to 53 bpm".
    public var usual: String?
    /// What was seen, in a sentence, with its figures.
    public var line: String
    /// The last four weeks, oldest first, nil for a day with no reading.
    public var series: [Double?]

    public init(id: String, title: String, level: DoctorLevel, figure: String, usual: String?, line: String, series: [Double?]) {
        self.id = id; self.title = title; self.level = level; self.figure = figure; self.usual = usual; self.line = line; self.series = series
    }
}

/// One run of the check, kept in the log.
public struct DoctorReport: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var weekStart: String
    public var weekEnd: String
    public var ranAt: Date
    /// True for the weekly check, false for one asked for by hand.
    public var scheduled: Bool
    /// Nights of the week with a reading, of seven. A night only part recorded is not one.
    public var nights: Int
    public var findings: [DoctorFinding]
    /// The written read, the model that wrote it and when; nil until there is one.
    public var read: String?
    public var readModel: String?
    public var readAt: Date?
    /// Why there is no written read, when one was asked for and could not be had.
    public var readNote: String?

    public init(id: String, weekStart: String, weekEnd: String, ranAt: Date, scheduled: Bool, nights: Int, findings: [DoctorFinding]) {
        self.id = id; self.weekStart = weekStart; self.weekEnd = weekEnd; self.ranAt = ranAt; self.scheduled = scheduled
        self.nights = nights; self.findings = findings
    }

    /// The most notable level among what was checked.
    public var level: DoctorLevel { findings.map { $0.level }.max() ?? .noData }
    public var outside: [DoctorFinding] { findings.filter { $0.level == .outside } }
    public var watching: [DoctorFinding] { findings.filter { $0.level == .watch } }

    /// The result in one line: counts, never a conclusion about health.
    public var headline: String {
        let o = outside.count, w = watching.count
        if o > 0 {
            let first = o == 1 ? "1 reading outside your usual range" : "\(o) readings outside your usual range"
            return w > 0 ? "\(first), \(w) worth watching" : first
        }
        if w > 0 { return w == 1 ? "1 thing worth watching" : "\(w) things worth watching" }
        // "Everything" is only said when everything was judged: what there was too little data for is
        // not passed off as fine.
        let judged = findings.filter { $0.level != .noData }.count
        if judged == 0 { return "Not enough data to check yet" }
        return judged == findings.count ? "Everything checked is in your usual range" : "What could be checked is in your usual range"
    }
}

public enum Doctor {
    public static let seriesDays = 28
    /// Readings a week needs before it is judged, and reports kept in the log.
    public static let minimumNights = 3
    public static let kept = 60

    /// The check of the seven days ending `weekEnd`.
    ///
    /// `days` are the strap's days, with the night of any day in `partial` already left out
    /// (`LDay.withoutNight`): a night only part recorded says nothing about the body. `sleeps` give
    /// the bedtimes, and `loads` the training load of each day (`LoadModel.dailyLoads`).
    public static func check(days: [LDay], sleeps: [LSleep], loads: [String: Double], partial: Set<String> = [],
                             weekEnd: String, scheduled: Bool, now: Date = Date(), calendar: Calendar = LDate.calendar) -> DoctorReport {
        let week = LDate.range(ending: weekEnd, count: 7, calendar: calendar)
        let span = LDate.range(ending: weekEnd, count: seriesDays, calendar: calendar)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = week.compactMap { byDay[$0] }
        let known = days.filter { $0.day <= weekEnd }
        // Each night is judged as the daily read judged it: against the nights before it.
        let watches = rows.map { BodyWatch.assess(day: $0, baselines: LBaselines.compute(days: known, before: $0.day)) }
        let before = LBaselines.compute(days: known, before: week[0])

        func series(_ value: (LDay) -> Double?) -> [Double?] { span.map { byDay[$0].flatMap(value) } }
        func number(_ v: Double, _ decimals: Int) -> String { String(format: "%.\(decimals)f", v) }
        func flaggedNights(_ metric: LMetric) -> Int {
            watches.filter { $0.signals.contains { $0.metric == metric && $0.flagged } }.count
        }

        /// A signal read off each night and held against a baseline of the nights before the week.
        /// `worse` is +1 when higher is the direction to watch and −1 when lower is.
        func signal(_ metric: LMetric, base: LBaseline?, worse: Double, drift minimum: Double) -> DoctorFinding {
            let unit = metric.unit.isEmpty ? "" : " " + metric.unit
            let values = rows.compactMap { metric.value($0) }
            let line28 = series { metric.value($0) }
            guard let base, base.isEstablished else {
                return DoctorFinding(id: metric.rawValue, title: metric.title, level: .noData, figure: "–", usual: nil,
                                     line: "Luma needs about two weeks of nights before it knows what is usual for you.", series: line28)
            }
            let usual = "usually \(number(base.low, metric.decimals)) to \(number(base.high, metric.decimals))\(unit)"
            guard values.count >= minimumNights, let mid = LStat.median(values) else {
                let said = values.isEmpty ? "No night this week has a reading." : "Only \(values.count) of 7 nights have a reading, too few to judge a week by."
                return DoctorFinding(id: metric.rawValue, title: metric.title, level: .noData, figure: "–", usual: usual, line: said, series: line28)
            }
            let figure = number(mid, metric.decimals) + unit
            let side = worse > 0 ? "above" : "below"
            let flagged = flaggedNights(metric)
            if flagged >= 3 {
                return DoctorFinding(id: metric.rawValue, title: metric.title, level: .outside, figure: figure, usual: usual,
                                     line: "\(flagged) of \(values.count) nights were \(side) your usual range. The week sat at \(figure).", series: line28)
            }
            if flagged == 2 {
                return DoctorFinding(id: metric.rawValue, title: metric.title, level: .watch, figure: figure, usual: usual,
                                     line: "2 nights were \(side) your usual range. The week sat at \(figure).", series: line28)
            }
            // Inside the range night by night, but moving one way for four weeks.
            let history = line28.compactMap { $0 }
            if history.count >= 12, let fit = LStat.theilSen(history), let trend = LStat.mannKendall(history), trend.p < 0.05 {
                let change = fit.slope * Double(history.count - 1)
                if change * worse >= max(minimum, base.spread) {
                    let moved = worse > 0 ? "risen" : "fallen"
                    return DoctorFinding(id: metric.rawValue, title: metric.title, level: .watch, figure: figure, usual: usual,
                                         line: "Inside your range this week, but it has \(moved) by about \(number(abs(change), metric.decimals))\(unit) over four weeks.",
                                         series: line28)
                }
            }
            let one = flagged == 1 ? " One night was \(side) it." : ""
            return DoctorFinding(id: metric.rawValue, title: metric.title, level: .steady, figure: figure, usual: usual,
                                 line: "The week sat at \(figure), inside your usual range.\(one)", series: line28)
        }

        var findings: [DoctorFinding] = []
        findings.append(signal(.restingHR, base: before.restingHR, worse: 1, drift: 3))
        findings.append(signal(.hrv, base: before.hrv, worse: -1, drift: 5))
        findings.append(signal(.respRate, base: before.respRate, worse: 1, drift: 0.8))
        findings.append(skin(rows: rows, flagged: flaggedNights(.skinTempDev), series: series { $0.skinTempDev }))
        if let oxygen = oxygen(rows: rows, known: known, weekStart: week[0], series: series { $0.spo2 }) { findings.append(oxygen) }
        findings.append(together(watches))
        findings.append(sleepAmount(rows: rows, base: before.sleepMin, series: series { $0.sleepMin.map { $0 / 60 } }))
        if let timing = bedtimes(week: week, sleeps: sleeps, partial: partial, calendar: calendar) { findings.append(timing) }
        findings.append(recovery(rows: rows, base: before.recovery, series: series { $0.recovery }))
        findings.append(load(loads: loads, weekEnd: weekEnd, span: span, calendar: calendar))

        let nights = rows.filter { $0.hasNight }.count
        return DoctorReport(id: scheduled ? weekEnd : weekEnd + "-asked", weekStart: week[0], weekEnd: weekEnd, ranAt: now,
                            scheduled: scheduled, nights: nights, findings: findings)
    }

    // MARK: The other checks

    /// Skin temperature is already a difference from the athlete's own baseline, so it has no range
    /// of its own to be held against: the nights the daily read flagged are counted.
    private static func skin(rows: [LDay], flagged: Int, series: [Double?]) -> DoctorFinding {
        let values = rows.compactMap { $0.skinTempDev }.filter { abs($0) < 20 }
        let title = LMetric.skinTempDev.title
        let usual = "within about 0.5 °C of your own baseline"
        guard values.count >= minimumNights, let mid = LStat.median(values) else {
            let said = values.isEmpty ? "No night this week has a reading." : "Only \(values.count) of 7 nights have a reading, too few to judge a week by."
            return DoctorFinding(id: "skinTempDev", title: title, level: .noData, figure: "–", usual: usual, line: said, series: series)
        }
        // To the tenth it is shown at, so a week a hair under its baseline reads +0.0 and not −0.0.
        let tenth = (mid * 10).rounded() / 10
        let figure = LFormat.signed(tenth == 0 ? 0 : tenth, decimals: 1) + " °C"
        let level: DoctorLevel = flagged >= 3 ? .outside : (flagged == 2 ? .watch : .steady)
        let line: String
        switch level {
        case .outside: line = "\(flagged) of \(values.count) nights ran warm (0.6 °C or more above your baseline). The week sat at \(figure)."
        case .watch: line = "2 nights ran warm (0.6 °C or more above your baseline). The week sat at \(figure)."
        default: line = "The week sat at \(figure) against your baseline." + (flagged == 1 ? " One night ran warm." : "")
        }
        return DoctorFinding(id: "skinTempDev", title: title, level: level, figure: figure, usual: usual, line: line, series: series)
    }

    /// Blood oxygen, where the strap gives it: a night counts when it is two points or more, and two
    /// spreads or more, under the athlete's usual. Nil when the strap has given none.
    private static func oxygen(rows: [LDay], known: [LDay], weekStart: String, series: [Double?]) -> DoctorFinding? {
        let history = known.filter { $0.day < weekStart }.compactMap { $0.spo2 }
        let values = rows.compactMap { $0.spo2 }
        guard !history.isEmpty || !values.isEmpty else { return nil }
        let title = LMetric.spo2.title
        guard let base = LBaseline(history), base.isEstablished else {
            return DoctorFinding(id: "spo2", title: title, level: .noData, figure: "–", usual: nil,
                                 line: "Luma needs about two weeks of nights before it knows what is usual for you.", series: series)
        }
        let usual = String(format: "usually %.0f to %.0f%%", base.low, min(100, base.high))
        guard values.count >= minimumNights, let mid = LStat.median(values) else {
            return DoctorFinding(id: "spo2", title: title, level: .noData, figure: "–", usual: usual,
                                 line: values.isEmpty ? "No night this week has a reading." : "Only \(values.count) of 7 nights have a reading, too few to judge a week by.",
                                 series: series)
        }
        let floor = base.center - max(2, 2 * base.spread)
        let low = values.filter { $0 <= floor }.count
        let figure = String(format: "%.0f%%", mid)
        let level: DoctorLevel = low >= 3 ? .outside : (low == 2 ? .watch : .steady)
        let line: String
        switch level {
        case .outside: line = "\(low) of \(values.count) nights were below your usual range. The week sat at \(figure)."
        case .watch: line = "2 nights were below your usual range. The week sat at \(figure)."
        default: line = "The week sat at \(figure), inside your usual range." + (low == 1 ? " One night was below it." : "")
        }
        return DoctorFinding(id: "spo2", title: title, level: level, figure: figure, usual: usual, line: line, series: series)
    }

    /// Mornings when the daily read found two, or three or more, overnight signals off together.
    private static func together(_ watches: [BodyWatch]) -> DoctorFinding {
        let judged = watches.filter { !$0.signals.isEmpty }
        let alerts = watches.filter { $0.level == .alert }.count
        let pairs = watches.filter { $0.level == .watch }.count
        let title = "Signals off together"
        guard !judged.isEmpty else {
            return DoctorFinding(id: "together", title: title, level: .noData, figure: "–", usual: nil,
                                 line: "No morning this week could be judged yet.", series: [])
        }
        let figure = alerts + pairs == 1 ? "1 morning" : "\(alerts + pairs) mornings"
        if alerts >= 1 {
            let said = alerts == 1 ? "On 1 morning" : "On \(alerts) mornings"
            return DoctorFinding(id: "together", title: title, level: .outside, figure: figure, usual: "usually none",
                                 line: "\(said) three or more overnight signals were outside your range at once. That pattern often comes with heavy fatigue, alcohol, travel, or an illness starting.",
                                 series: [])
        }
        if pairs >= 2 {
            return DoctorFinding(id: "together", title: title, level: .watch, figure: figure, usual: "usually none",
                                 line: "On \(pairs) mornings two overnight signals were outside your range at once.", series: [])
        }
        return DoctorFinding(id: "together", title: title, level: .steady, figure: figure, usual: "usually none",
                             line: pairs == 1 ? "On 1 morning two signals were off at once; on the rest, none." : "On no morning were two signals off at once.",
                             series: [])
    }

    private static func sleepAmount(rows: [LDay], base: LBaseline?, series: [Double?]) -> DoctorFinding {
        let title = "Sleep"
        let values = rows.compactMap { $0.sleepMin }
        guard let base, base.isEstablished else {
            return DoctorFinding(id: "sleep", title: title, level: .noData, figure: "–", usual: nil,
                                 line: "Luma needs about two weeks of nights before it knows what is usual for you.", series: series)
        }
        let usual = "usually \(LFormat.hm(minutes: base.low)) to \(LFormat.hm(minutes: base.high))"
        guard values.count >= minimumNights, let mean = LStat.mean(values) else {
            return DoctorFinding(id: "sleep", title: title, level: .noData, figure: "–", usual: usual,
                                 line: values.isEmpty ? "No night this week was recorded whole." : "Only \(values.count) of 7 nights were recorded whole, too few to judge a week by.",
                                 series: series)
        }
        let figure = LFormat.hm(minutes: mean)
        let short = base.center - mean
        let z = base.z(mean)
        if z <= -2, short >= 60 {
            return DoctorFinding(id: "sleep", title: title, level: .outside, figure: figure, usual: usual,
                                 line: "You averaged \(figure) a night, about \(LFormat.hm(minutes: short)) less than your usual \(LFormat.hm(minutes: base.center)).", series: series)
        }
        if z <= -1, short >= 30 {
            return DoctorFinding(id: "sleep", title: title, level: .watch, figure: figure, usual: usual,
                                 line: "You averaged \(figure) a night, about \(LFormat.hm(minutes: short)) less than your usual \(LFormat.hm(minutes: base.center)).", series: series)
        }
        return DoctorFinding(id: "sleep", title: title, level: .steady, figure: figure, usual: usual,
                             line: "You averaged \(figure) a night, in line with your usual.", series: series)
    }

    /// How far bedtime moved from night to night. Only ever worth watching: it is a habit, not a reading.
    private static func bedtimes(week: [String], sleeps: [LSleep], partial: Set<String>, calendar: Calendar) -> DoctorFinding? {
        var minutes: [Double] = []
        for day in week where !partial.contains(day) {
            guard let main = SleepModel.mainBlock(on: day, sleeps: sleeps), let midnight = LDate.startOfDay(day, calendar: calendar) else { continue }
            // From the midnight inside the night, so 23:10 is −50 and 00:40 is 40.
            minutes.append((main.start - midnight.timeIntervalSince1970) / 60)
        }
        guard minutes.count >= 4, let spread = LStat.sd(minutes), let early = minutes.min(), let late = minutes.max() else { return nil }
        let figure = "±" + LFormat.hm(minutes: spread)
        let range = "earliest \(LFormat.timeOfDay(minutes: early)), latest \(LFormat.timeOfDay(minutes: late))"
        if spread >= 75 {
            return DoctorFinding(id: "bedtime", title: "Bedtime", level: .watch, figure: figure, usual: nil,
                                 line: "Bedtime moved by about \(LFormat.hm(minutes: spread)) from night to night (\(range)). A steadier bedtime tends to steady the other readings.",
                                 series: [])
        }
        return DoctorFinding(id: "bedtime", title: "Bedtime", level: .steady, figure: figure, usual: nil,
                             line: "Bedtime held within about \(LFormat.hm(minutes: spread)) from night to night (\(range)).", series: [])
    }

    private static func recovery(rows: [LDay], base: LBaseline?, series: [Double?]) -> DoctorFinding {
        let title = "Recovery"
        let values = rows.compactMap { $0.recovery }
        let usual = base.map { String(format: "usually %.0f to %.0f%%", max(0, $0.low), min(100, $0.high)) }
        guard values.count >= minimumNights, let mean = LStat.mean(values) else {
            return DoctorFinding(id: "recovery", title: title, level: .noData, figure: "–", usual: usual,
                                 line: values.isEmpty ? "No morning this week has a score." : "Only \(values.count) of 7 mornings have a score, too few to judge a week by.",
                                 series: series)
        }
        let figure = String(format: "%.0f%%", mean)
        let red = values.filter { RecoveryBand.of($0) == .low }.count
        let reds = red == 1 ? "1 morning was in the red" : "\(red) mornings were in the red"
        if red >= 3 {
            return DoctorFinding(id: "recovery", title: title, level: .outside, figure: figure, usual: usual,
                                 line: "Recovery averaged \(figure), and \(reds).", series: series)
        }
        if red == 2 {
            return DoctorFinding(id: "recovery", title: title, level: .watch, figure: figure, usual: usual,
                                 line: "Recovery averaged \(figure), and \(reds).", series: series)
        }
        if let base, base.isEstablished, base.center - mean >= max(12, base.spread) {
            return DoctorFinding(id: "recovery", title: title, level: .watch, figure: figure, usual: usual,
                                 line: "Recovery averaged \(figure), about \(LNum.int((base.center - mean).rounded())) points under your usual.", series: series)
        }
        return DoctorFinding(id: "recovery", title: title, level: .steady, figure: figure, usual: usual,
                             line: "Recovery averaged \(figure)." + (red == 1 ? " One morning was in the red." : ""), series: series)
    }

    /// The training load as at the end of the week, by the same model the Load screen uses.
    private static func load(loads: [String: Double], weekEnd: String, span: [String], calendar: Calendar) -> DoctorFinding {
        let state = LoadModel.compute(loads: loads.filter { $0.key <= weekEnd }, today: weekEnd, calendar: calendar)
        let series: [Double?] = span.map { loads[$0] ?? 0 }
        let title = "Training load"
        guard state.ready, let share = state.weekShare else {
            return DoctorFinding(id: "load", title: title, level: .noData, figure: "–", usual: nil,
                                 line: "Luma needs four weeks of sessions before a week can be set against your usual one.", series: series)
        }
        let figure = String(format: "%.1f×", share)
        let usual = "0.7 to 1.3 times your usual week is the steady band"
        let change = state.weekChangePct.map { String(format: " (%+.0f%% on the week before)", $0) } ?? ""
        if share >= 2 {
            return DoctorFinding(id: "load", title: title, level: .outside, figure: figure, usual: usual,
                                 line: "This week's load was \(figure) your usual week\(change). That is a lot to take on at once.",
                                 series: series)
        }
        if state.status == .spike {
            return DoctorFinding(id: "load", title: title, level: .watch, figure: figure, usual: usual,
                                 line: "This week's load was \(figure) your usual week\(change).", series: series)
        }
        return DoctorFinding(id: "load", title: title, level: .steady, figure: figure, usual: usual,
                             line: "This week's load was \(figure) your usual week\(change): \(state.headline.lowercased()).", series: series)
    }
}

// MARK: - When the check runs

public enum DoctorSchedule {
    /// The last day of the week a check is due for at `now`: the day before the most recent Sunday
    /// 00:00, a Saturday. The check is due from Sunday 00:00; iOS cannot promise that moment, so it
    /// runs at the first chance after it.
    public static func weekEnd(asOf now: Date, calendar: Calendar = LDate.calendar) -> String {
        let today = LDate.key(now, calendar: calendar)
        // 1 is Sunday in the Gregorian calendar, whatever day the week is taken to start on.
        let weekday = calendar.component(.weekday, from: LDate.date(today, calendar: calendar) ?? now)
        let sunday = LDate.adding(-(weekday - 1), to: today, calendar: calendar)
        return LDate.adding(-1, to: sunday, calendar: calendar)
    }

    /// The week a scheduled check has still to be run for; nil when the log already holds it.
    public static func due(now: Date, reports: [DoctorReport], calendar: Calendar = LDate.calendar) -> String? {
        let end = weekEnd(asOf: now, calendar: calendar)
        return reports.contains { $0.scheduled && $0.weekEnd == end } ? nil : end
    }

    /// The next Sunday 00:00 after `now`.
    public static func next(after now: Date, calendar: Calendar = LDate.calendar) -> Date {
        let end = weekEnd(asOf: now, calendar: calendar)
        // The Sunday that follows the Saturday after this one: eight days on from the week's last day.
        let sunday = LDate.adding(8, to: end, calendar: calendar)
        return LDate.startOfDay(sunday, calendar: calendar) ?? now.addingTimeInterval(7 * 86_400)
    }
}

// MARK: - The written read

/// What is sent for the written read, and the words that frame it. The read is written by the most
/// capable model the athlete's key reaches, whatever the coach is set to.
public enum DoctorPrompt {
    public static let system = """
    You write the weekly read for Luma Doctor, a feature of a personal training app. You are given one person's own wearable figures for the last week, held against their own usual range. You are not a doctor and this is not a medical assessment.

    Say plainly what stands out, using their numbers. Where something is outside its range, offer everyday explanations as possibilities, never as conclusions: training load, short or irregular sleep, alcohol, a late meal, travel, heat, stress, or an illness starting. Never name a disease and never diagnose. Say what to keep an eye on next week and one or two concrete things worth doing. If several signals have been outside their range for days, say once, without alarm, that it is sensible to see a doctor if it continues or they feel unwell. If everything is in range, say so in two or three sentences and do not invent concerns. Do not comment on what the data cannot show.

    Plain text only: no headings, no lists, no markdown. At most 130 words. Use only the figures given.
    """

    /// The findings and, when health data may be shared, the last four weeks day by day.
    public static func ask(_ report: DoctorReport, days: [LDay], shareDays: Bool, calendar: Calendar = LDate.calendar) -> String {
        var out = "Week checked: \(report.weekStart) to \(report.weekEnd). Nights with a reading: \(report.nights) of 7.\n\nWhat the check found:\n"
        for f in report.findings {
            out += "- \(f.title): \(f.level.title). \(f.line)" + (f.usual.map { " (\($0))" } ?? "") + "\n"
        }
        guard shareDays else { return out }
        let span = Set(LDate.range(ending: report.weekEnd, count: Doctor.seriesDays, calendar: calendar))
        let rows = days.filter { span.contains($0.day) }.sorted { $0.day < $1.day }
        guard !rows.isEmpty else { return out }
        func cell(_ v: Double?, _ decimals: Int) -> String { v.map { String(format: "%.\(decimals)f", $0) } ?? "-" }
        out += "\nThe last four weeks, a dash where nothing was read. Day: recovery %, HRV ms, resting heart rate bpm, respiratory rate, skin temperature against baseline °C, sleep hours, strain 0 to 21.\n"
        for d in rows {
            let cells = [cell(d.recovery, 0), cell(d.hrv, 0), cell(d.restingHR, 0), cell(d.respRate, 1), cell(d.skinTempDev, 1),
                         cell(d.sleepMin.map { $0 / 60 }, 1), cell(d.strain.map(LScale.strain21), 1)]
            out += "\(d.day): " + cells.joined(separator: ", ") + "\n"
        }
        return out
    }

    /// The read as kept: trimmed, and no longer than a screen holds.
    public static func tidy(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 1200 ? String(trimmed.prefix(1200)) : trimmed
    }
}

public extension AIModel {
    /// The lines of model from most to least capable, as Anthropic describes them. A line not named
    /// here comes after these, in the order the service lists it.
    static let linesByStrength = ["fable", "mythos", "opus", "sonnet", "haiku"]

    /// The models a key reaches, most capable first: by line, and within a line in the order the
    /// service lists them, which is newest first. The line is read from the service's own field.
    static func byStrength(_ models: [AIModel]) -> [AIModel] {
        func rank(_ model: AIModel) -> Int {
            guard let line = model.line?.lowercased(), let i = linesByStrength.firstIndex(of: line) else { return linesByStrength.count }
            return i
        }
        return models.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { $0.element }
    }
}
