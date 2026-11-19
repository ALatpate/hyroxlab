import Foundation

/// One finding worth the athlete's attention, with the evidence behind it.
public struct Insight: Equatable, Sendable, Identifiable {
    public enum Tone: String, Sendable { case good, neutral, caution }
    public enum Topic: String, Sendable { case body, sleep, training, habits, fitness }

    /// What to draw beside the text.
    public enum Evidence: Equatable, Sendable {
        case none
        /// A metric's recent history.
        case series(LMetric)
        /// Two group means, e.g. nights with and without a habit.
        case compare(aLabel: String, a: Double, bLabel: String, b: Double, metric: LMetric)
        /// Paired values with a fitted line.
        case scatter(key: String)
        /// Mean by weekday, Monday first.
        case weekdays([Double?], metric: LMetric)
    }

    public let id: String
    public let topic: Topic
    public let tone: Tone
    public let title: String
    public let body: String
    public let evidence: Evidence
    /// Higher first.
    public let priority: Double
}

public enum InsightEngine {
    public static let weekdayNames = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]

    public static func build(days: [LDay], today: String, baselines: LBaselines, sleep: SleepSummary, load: LoadState, watch: BodyWatch,
                             trends: [TrendRead], effects: [EffectFinding], links: [LinkFinding], fitness: FitnessState,
                             calendar: Calendar = LDate.calendar) -> [Insight] {
        var out: [Insight] = []

        if watch.level >= .watch {
            out.append(Insight(id: "watch", topic: .body, tone: .caution, title: watch.title, body: watch.detail,
                               evidence: .series(watch.signals.first { $0.flagged }?.metric ?? .restingHR), priority: 100))
        }

        for t in trends where t.direction != 0 {
            guard let improving = t.improving else { continue }
            let title: String
            switch (t.metric, improving) {
            case (.hrv, true): title = "HRV is climbing"
            case (.hrv, false): title = "HRV is sliding"
            case (.restingHR, true): title = "Resting heart rate is coming down"
            case (.restingHR, false): title = "Resting heart rate is creeping up"
            case (.recovery, true): title = "Recovery is trending up"
            case (.recovery, false): title = "Recovery is trending down"
            case (.sleepHours, true): title = "You are sleeping longer"
            case (.sleepHours, false): title = "Sleep is getting shorter"
            default: title = "\(t.metric.title) is \(t.direction > 0 ? "rising" : "falling")"
            }
            let meaning: String
            switch (t.metric, improving) {
            case (.hrv, true), (.restingHR, true): meaning = " That is the usual signature of fitness building while recovery keeps up."
            case (.hrv, false), (.restingHR, false): meaning = " If training has not eased, that points to fatigue accumulating faster than you clear it."
            default: meaning = ""
            }
            out.append(Insight(id: "trend-\(t.metric.rawValue)", topic: t.metric == .sleepHours ? .sleep : .body,
                               tone: improving ? .good : .caution, title: title, body: t.sentence + meaning,
                               evidence: .series(t.metric), priority: 70 + min(15, abs(t.changePct))))
        }

        if sleep.debtMin >= 90 {
            out.append(Insight(id: "sleep-debt", topic: .sleep, tone: .caution, title: "You are carrying \(LFormat.hm(minutes: sleep.debtMin)) of sleep debt",
                               body: "Over the last week you have slept less than your body needed. Tonight's need is \(LFormat.hm(minutes: sleep.tonightNeedMin))."
                                + (sleep.recommendedBedtime.map { " Lights out by \(LFormat.timeOfDay(minutes: $0)) would cover it." } ?? ""),
                               evidence: .series(.sleepHours), priority: 80 + min(15, sleep.debtMin / 30)))
        } else if sleep.nights.count >= 7, sleep.debtMin < 20 {
            out.append(Insight(id: "sleep-banked", topic: .sleep, tone: .good, title: "No sleep debt",
                               body: "You have met your sleep need across the last week. That is the cheapest performance gain there is.",
                               evidence: .series(.sleepHours), priority: 35))
        }

        if let c = sleep.consistency, sleep.nights.count >= 7 {
            if c < 60 {
                out.append(Insight(id: "sleep-consistency", topic: .sleep, tone: .caution, title: "Your sleep times are scattered",
                                   body: "Bed and wake times have varied a lot this week (consistency \(LNum.int(c.rounded()))%). Regular timing improves sleep quality even at the same duration.",
                                   evidence: .none, priority: 55))
            } else if c >= 85 {
                out.append(Insight(id: "sleep-consistency", topic: .sleep, tone: .good, title: "Rock-steady sleep schedule",
                                   body: "Bed and wake times have barely moved this week (consistency \(LNum.int(c.rounded()))%).",
                                   evidence: .none, priority: 25))
            }
        }

        if let j = sleep.socialJetlagMin, abs(j) >= 60 {
            out.append(Insight(id: "jetlag", topic: .sleep, tone: .neutral, title: "Weekends shift your body clock by \(LFormat.hm(minutes: abs(j)))",
                               body: "Your sleep midpoint is \(LFormat.hm(minutes: abs(j))) \(j > 0 ? "later" : "earlier") at weekends than on weekdays. Monday mornings then feel like a small time-zone change.",
                               evidence: .none, priority: 45))
        }

        if load.ready {
            switch load.status {
            case .spike:
                out.append(Insight(id: "load", topic: .training, tone: .caution, title: load.headline, body: load.detail, evidence: .none, priority: 90))
            case .pushing:
                out.append(Insight(id: "load", topic: .training, tone: .neutral, title: load.headline, body: load.detail, evidence: .none, priority: 60))
            case .fresh:
                out.append(Insight(id: "load", topic: .training, tone: .neutral, title: "Training load is low", body: load.detail, evidence: .none, priority: 50))
            case .productive, .building:
                break
            }
            if let m = load.monotony, m > 2.2 {
                out.append(Insight(id: "monotony", topic: .training, tone: .neutral, title: "Every day looks the same",
                                   body: String(format: "Training monotony is %.1f. Mixing truly easy days with hard ones lets you absorb more work for the same fatigue.", m),
                                   evidence: .none, priority: 40))
            }
        }

        // One card per habit: its strongest measured effect.
        var seenFactors = Set<String>()
        for e in effects {
            guard seenFactors.count < 3, !seenFactors.contains(e.factorKey), let helps = e.helps else { continue }
            seenFactors.insert(e.factorKey)
            out.append(Insight(id: "effect-\(e.id)", topic: .habits, tone: helps ? .good : .caution,
                               title: "\(e.factor) \(helps ? "helps" : "costs") your \(e.outcome.phrase)",
                               body: e.sentence,
                               evidence: .compare(aLabel: e.factor, a: e.withMean, bLabel: "Otherwise", b: e.withoutMean, metric: e.outcome),
                               priority: (e.reliable ? 75 : 42) + min(10, abs(e.g) * 5)))
        }

        for l in links.prefix(2) where l.reliable {
            out.append(Insight(id: "link-\(l.key)", topic: .habits, tone: .neutral, title: "\(l.xLabel) and \(l.yLabel == "HRV" ? "HRV" : l.yLabel.lowercased()) move together",
                               body: l.sentence, evidence: .scatter(key: l.key), priority: 48 + abs(l.r) * 10))
        }

        // Weekday pattern in recovery: the weakest morning against the rest.
        let means = EffectModel.weekdayMeans(.recovery, days: Array(days.suffix(84)), calendar: calendar)
        if means.count == 7, means.values.allSatisfy({ $0.n >= 4 }),
           let low = means.min(by: { $0.value.mean < $1.value.mean }), let overall = LStat.mean(means.values.map { $0.mean }),
           overall - low.value.mean >= 8 {
            out.append(Insight(id: "weekday", topic: .habits, tone: .neutral, title: "\(weekdayNames[low.key - 1]) are your lowest mornings",
                               body: "Recovery averages \(LNum.int(low.value.mean.rounded()))% on \(weekdayNames[low.key - 1]) against \(LNum.int(overall.rounded()))% across the week. Look at what the day before usually holds.",
                               evidence: .weekdays((1...7).map { means[$0]?.mean }, metric: .recovery), priority: 52))
        }

        if let change = fitness.efficiencyChangePct, abs(change) >= 3 {
            out.append(Insight(id: "economy", topic: .fitness, tone: change > 0 ? .good : .caution,
                               title: change > 0 ? "You are running faster at the same heart rate" : "Running is costing more heartbeats",
                               body: String(format: "Pace per heartbeat has changed by %+.0f%% across your runs in the last eight weeks.", change),
                               evidence: .none, priority: 58))
        }

        if baselines.nights < LBaseline.established {
            out.append(Insight(id: "building", topic: .body, tone: .neutral, title: "Luma is still learning you",
                               body: "\(baselines.nights) of \(LBaseline.established) nights recorded. Baselines, warning signs and most insights switch on once two weeks of nights are in.",
                               evidence: .none, priority: 95))
        }

        return out.sorted { $0.priority > $1.priority }
    }
}
