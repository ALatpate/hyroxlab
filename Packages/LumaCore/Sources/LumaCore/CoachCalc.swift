import Foundation

// MARK: - Sums the coach can ask for

/// A calculation over the athlete's own records, run on the phone at the coach's request. The coach
/// gets the result, with how many days it rests on, instead of raw rows it would have to add up
/// itself, so a question no screen was built for is answered from a worked figure and not a guess.
public enum CoachCalc {
    public static let toolName = "run_numbers"

    /// Daily series beyond the strap's own metrics, worked out from recorded sessions.
    public static let sessionMetrics = ["training_minutes", "sessions", "run_km"]
    public static var metricNames: [String] { LMetric.allCases.map { $0.rawValue } + sessionMetrics }
    public static let operations = ["summary", "trend", "compare", "relate", "by_weekday"]
    public static let maxDays = 365

    public static func tool() -> AITool {
        AITool(name: toolName,
               description: "Work something out from the athlete's records on their phone and get the figure back: an average, a trend, one period against another, how two things move together, or a pattern by weekday. Use it whenever the answer needs arithmetic over many days instead of adding up rows yourself.",
               properties: [
                "operation": AISchema.string("summary: count, mean, median, lowest, highest and spread. trend: change per week and whether it is clear. compare: period A against period B. relate: how metric and other_metric move together, with other_metric shifted by lag_days. by_weekday: the mean for each day of the week.",
                                             enum: operations),
                "metric": AISchema.string("What to work on. training_minutes, sessions and run_km come from recorded sessions; the rest are the strap's daily figures.",
                                          enum: metricNames),
                "from": AISchema.string("First day of period A as YYYY-MM-DD. Left out: 28 days before `to`."),
                "to": AISchema.string("Last day of period A as YYYY-MM-DD. Left out: today."),
                "from_b": AISchema.string("compare only: first day of period B."),
                "to_b": AISchema.string("compare only: last day of period B."),
                "other_metric": AISchema.string("relate only: the second metric.", enum: metricNames),
                "lag_days": AISchema.integer("relate only: days by which other_metric follows metric. 1 sets each day's metric against the next day's other_metric. 0 to 7."),
               ],
               required: ["operation", "metric"])
    }

    // MARK: Series

    static func series(_ name: String, days: [LDay], workouts: [LWorkout], keys: [String]) -> [Double?]? {
        if let metric = LMetric(rawValue: name) {
            let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            return keys.map { byDay[$0].flatMap { metric.value($0) } }
        }
        guard sessionMetrics.contains(name) else { return nil }
        var sums: [String: Double] = [:]
        for w in workouts {
            switch name {
            case "training_minutes": sums[w.day, default: 0] += w.durationS / 60
            case "sessions": sums[w.day, default: 0] += 1
            default: if w.kind == .run, let m = w.distanceM { sums[w.day, default: 0] += m / 1000 }
            }
        }
        // A day with nothing recorded is a real zero for these, not a gap.
        return keys.map { sums[$0] ?? 0 }
    }

    static func keys(from: String?, to: String?, today: String, calendar: Calendar) -> [String] {
        let end = min(valid(to) ?? today, today)
        let start = valid(from) ?? LDate.adding(-27, to: end, calendar: calendar)
        let count = LDate.daysBetween(start, end, calendar: calendar) + 1
        guard count >= 1 else { return [] }
        return LDate.range(ending: end, count: min(count, maxDays), calendar: calendar)
    }

    static func valid(_ day: String?) -> String? {
        guard let day, LDate.date(day) != nil else { return nil }
        return day
    }

    // MARK: Run

    public static func run(_ input: JSONValue, days: [LDay], workouts: [LWorkout], today: String,
                           calendar: Calendar = LDate.calendar) -> JSONValue {
        guard let operation = input["operation"]?.string, operations.contains(operation) else {
            return ["error": .string("operation must be one of: " + operations.joined(separator: ", "))]
        }
        guard let metric = input["metric"]?.string, metricNames.contains(metric) else {
            return ["error": .string("metric must be one of: " + metricNames.joined(separator: ", "))]
        }
        let aKeys = keys(from: input["from"]?.string, to: input["to"]?.string, today: today, calendar: calendar)
        guard !aKeys.isEmpty, let aSeries = series(metric, days: days, workouts: workouts, keys: aKeys) else {
            return ["error": "That period has no days in it. Check from and to."]
        }
        let a = aSeries.compactMap { $0 }
        var out: [String: JSONValue] = ["operation": .string(operation), "metric": .string(metric),
                                        "from": .string(aKeys.first ?? ""), "to": .string(aKeys.last ?? ""),
                                        "days_in_period": .number(Double(aKeys.count)), "days_with_a_value": .number(Double(a.count))]
        func few(_ n: Int, _ need: Int) {
            if n < need { out["caution"] = .string("Only \(n) days have a value, so treat this as a hint, not a finding.") }
        }
        switch operation {
        case "summary":
            out["mean"] = .rounded(LStat.mean(a), 2)
            out["median"] = .rounded(LStat.median(a), 2)
            out["lowest"] = .rounded(a.min(), 2)
            out["highest"] = .rounded(a.max(), 2)
            out["spread_sd"] = .rounded(LStat.sd(a), 2)
            if sessionMetrics.contains(metric) { out["total"] = .rounded(a.reduce(0, +), 1) }
            few(a.count, 7)
        case "trend":
            if let fit = LStat.theilSen(a) {
                out["change_per_week"] = .rounded(fit.slope * 7, 3)
                out["start_level"] = .rounded(fit.intercept, 2)
            }
            if let test = LStat.mannKendall(a) {
                out["p_value"] = .rounded(test.p, 3)
                out["clear"] = .bool(test.p < 0.05)
            }
            few(a.count, 14)
        case "compare":
            let bKeys = keys(from: input["from_b"]?.string, to: input["to_b"]?.string, today: today, calendar: calendar)
            guard input["from_b"]?.string != nil, !bKeys.isEmpty,
                  let bSeries = series(metric, days: days, workouts: workouts, keys: bKeys) else {
                return ["error": "compare needs from_b and to_b for the second period."]
            }
            let b = bSeries.compactMap { $0 }
            out["from_b"] = .string(bKeys.first ?? "")
            out["to_b"] = .string(bKeys.last ?? "")
            out["mean_a"] = .rounded(LStat.mean(a), 2)
            out["mean_b"] = .rounded(LStat.mean(b), 2)
            out["days_with_a_value_b"] = .number(Double(b.count))
            if let test = LStat.welch(a, b) {
                out["a_minus_b"] = .rounded(test.delta, 2)
                out["p_value"] = .rounded(test.p, 3)
                out["clear"] = .bool(test.p < 0.05)
            }
            few(min(a.count, b.count), 7)
        case "relate":
            guard let other = input["other_metric"]?.string, metricNames.contains(other),
                  let otherSeries = series(other, days: days, workouts: workouts, keys: aKeys) else {
                return ["error": "relate needs other_metric."]
            }
            let lag = max(0, min(7, input["lag_days"]?.int ?? 0))
            var xs: [Double] = [], ys: [Double] = []
            for i in 0..<aSeries.count where i + lag < otherSeries.count {
                if let x = aSeries[i], let y = otherSeries[i + lag] {
                    xs.append(x)
                    ys.append(y)
                }
            }
            out["other_metric"] = .string(other)
            out["lag_days"] = .number(Double(lag))
            out["pairs"] = .number(Double(xs.count))
            if let rank = LStat.spearman(xs, ys) {
                out["rank_correlation"] = .rounded(rank.r, 2)
                out["p_value"] = .rounded(rank.p, 3)
                out["clear"] = .bool(rank.p < 0.05)
            }
            out["note"] = "Moving together is not one causing the other."
            few(xs.count, 14)
        default:
            var byWeekday: [Int: [Double]] = [:]
            for (key, value) in zip(aKeys, aSeries) {
                if let value { byWeekday[LDate.weekday(key, calendar: calendar), default: []].append(value) }
            }
            let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            var rows: [JSONValue] = []
            for (i, name) in names.enumerated() {
                let values = byWeekday[i + 1] ?? []
                rows.append(["day": .string(name), "mean": .rounded(LStat.mean(values), 2), "days": .number(Double(values.count))])
            }
            out["by_weekday"] = .array(rows)
            few(a.count, 21)
        }
        return .object(out)
    }
}
