import SwiftUI
import LumaCore
import LumaKit

// MARK: - Trends

struct TrendsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var metric: LMetric = .recovery
    @State private var other: LMetric? = .strain

    private let metrics: [LMetric] = [.recovery, .strain, .sleepHours, .hrv, .restingHR, .respRate, .skinTempDev, .deepMin, .remMin,
                                      .sleepEfficiency, .steps, .activeKcal]

    private func isSignal(_ m: LMetric) -> Bool { [.hrv, .restingHR, .respRate, .skinTempDev, .sleepEfficiency].contains(m) }

    var body: some View {
        let a = env.analysis
        LumaDetailScreen(title: "Trends", tone: metric.tone) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(metrics) { m in
                        LumaChip(title: m.title, isOn: m == metric, tint: m.tone.color) { metric = m }
                    }
                }
                .padding(.horizontal, Luma.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Luma.gutter)

            MetricHistoryCard(metric: metric, style: isSignal(metric) ? .line : .bars,
                              barColor: metric == .recovery ? { Luma.recovery($0) } : nil, initial: .quarter)
                .id(metric)
            if let t = a.trend(metric) { TrendNote(trend: t) }
            MonthHeatCard(metric: metric)
            CompareCard(metric: metric, other: $other, options: metrics.filter { $0 != metric })

            LumaSection(title: "Insights", action: "See all") { router.push(.insights) }
            ForEach(a.insights.prefix(2)) { InsightCard(insight: $0) }

            LumaSection(title: "Aerobic fitness")
            FitnessCard(fitness: a.fitness)
            RunDepthCards()
        }
    }
}

/// Five weeks of a metric as a calendar, lit by how each day compares with the rest.
struct MonthHeatCard: View {
    let metric: LMetric
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let start = LDate.adding(-28, to: LDate.weekStart(env.today))
        let keys = (0..<35).map { LDate.adding($0, to: start) }
        let byDay = Dictionary(env.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let values = keys.compactMap { byDay[$0].flatMap { metric.value($0) } }
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("\(metric.title) · last five weeks")
                LumaHeatCalendar(days: keys, value: { key in byDay[key].flatMap { metric.value($0) } },
                                 color: { v in
                                     if metric == .recovery { return Luma.recovery(v) }
                                     let f = hi > lo ? (v - lo) / (hi - lo) : 0.5
                                     return metric.tone.color.opacity(0.35 + 0.65 * f)
                                 }, today: env.today)
            }
        }
    }
}

/// Two metrics over 90 days on a shared, standardised scale, with how strongly they move together.
struct CompareCard: View {
    let metric: LMetric
    @Binding var other: LMetric?
    let options: [LMetric]
    @EnvironmentObject private var env: LumaEnv

    private func standardised(_ values: [Double?]) -> [Double?] {
        let real = values.compactMap { $0 }
        guard let m = LStat.mean(real), let s = LStat.sd(real), s > 0 else { return values.map { _ in nil } }
        return LStat.rollingMean(values.map { $0.map { ($0 - m) / s } }, window: 7, minCount: 3)
    }

    var body: some View {
        let second = other.flatMap { options.contains($0) ? $0 : nil } ?? options.first ?? .strain
        let a = env.series(metric, count: 90), b = env.series(second, count: 90)
        let pairs = zip(a.values, b.values).compactMap { x, y -> (Double, Double)? in
            guard let x, let y else { return nil }
            return (x, y)
        }
        let corr = LStat.spearman(pairs.map { $0.0 }, pairs.map { $0.1 })
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LumaLabel("Compare with")
                    Spacer()
                    Menu {
                        ForEach(options) { m in Button(m.title) { other = m } }
                    } label: {
                        HStack(spacing: 5) {
                            Text(second.title).font(LumaFont.body(14, .semibold))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Luma.frost)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                if pairs.count >= 10 {
                    LumaLineChart(series: [
                        LumaLineChart.Series(id: "a", values: standardised(a.values), color: metric.tone.color),
                        LumaLineChart.Series(id: "b", values: standardised(b.values), color: Luma.frost.opacity(0.75), dashed: true, width: 2),
                    ], labels: a.keys.map { LumaText.shortDay($0) }, height: 170, showAxis: false, replay: "\(metric.rawValue)-\(second.rawValue)")
                    if let c = corr {
                        let strength = abs(c.r) >= 0.5 ? "move together strongly" : (abs(c.r) >= 0.3 ? "move together" : (abs(c.r) >= 0.15 ? "are loosely linked" : "show no real link"))
                        LumaNote(String(format: "Over %d days, %@ and %@ %@%@ (rank correlation %+.2f). Lines are 7-day averages on a common scale.",
                                        c.n, metric.title.lowercased(), second.title.lowercased(), strength,
                                        abs(c.r) >= 0.15 ? (c.r > 0 ? ", rising and falling in step" : ", in opposite directions") : "", c.r))
                    }
                } else {
                    LumaNote("Needs at least ten days where both were measured.")
                }
            }
        }
    }
}

struct FitnessCard: View {
    let fitness: FitnessState
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel("VO₂max estimate")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(fitness.vo2max.map { String(format: "%.0f", $0) } ?? "–").font(LumaFont.numeral(44)).foregroundStyle(Luma.frost)
                            Text("ml/kg/min").font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist)
                        }
                    }
                    Spacer()
                    if let v = fitness.vo2max {
                        LumaPill(text: FitnessModel.category(vo2max: v, age: env.profile.age(), sex: env.profile.sex), color: Luma.aqua)
                    }
                }
                if fitness.vo2maxHistory.count >= 3 {
                    LumaLineChart(values: fitness.vo2maxHistory.map { $0.value }, labels: fitness.vo2maxHistory.map { LumaText.shortDay($0.day) },
                                  color: Luma.aqua, height: 130, format: { String(format: "%.0f", $0) })
                }
                LumaNote(fitness.vo2maxFromRuns
                         ? "Estimated from your steady runs: the oxygen cost of your pace against how much of your heart-rate reserve it used. Good to within a few points; a lab test is the only exact measure."
                         : "A coarse estimate from resting and maximum heart rate. It sharpens once Luma has a few steady outdoor runs with heart rate.")
                if let change = fitness.efficiencyChangePct {
                    LumaDivider()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            LumaLabel("Running economy · 8 weeks")
                            Text(String(format: "%+.1f%%", change)).font(LumaFont.numeral(30)).foregroundStyle(change >= 0 ? Luma.mint : Luma.amber)
                        }
                        Spacer()
                        if fitness.efficiency.count >= 4 {
                            LumaSparkline(values: fitness.efficiency.suffix(20).map { $0.value }, color: Luma.mint).frame(width: 130, height: 44)
                        }
                    }
                    LumaNote("Speed per heartbeat across your runs. Rising means the same effort carries you faster.")
                }
            }
        }
    }
}

// MARK: - Insights

struct InsightsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var topic: Insight.Topic?

    var body: some View {
        let all = env.analysis.insights
        let shown = topic.map { t in all.filter { $0.topic == t } } ?? all
        LumaDetailScreen(title: "Insights", tone: .hrv) {
            Text("What your data says").font(LumaFont.title(26)).foregroundStyle(Luma.frost)
            LumaNote("Patterns Luma has found in your own numbers. Each one is tested against chance and labelled when the evidence is still thin.")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    LumaChip(title: "All", isOn: topic == nil) { topic = nil }
                    ForEach([Insight.Topic.body, .sleep, .training, .habits, .fitness], id: \.self) { t in
                        LumaChip(title: t.rawValue.capitalized, isOn: topic == t) { topic = t }
                    }
                }
                .padding(.horizontal, Luma.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Luma.gutter)
            if shown.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "sparkles", title: "Nothing to report here yet",
                              message: "Insights appear as nights, sessions and daily check-ins accumulate.")
                }
            }
            ForEach(shown) { InsightCard(insight: $0) }
        }
    }
}

struct InsightCard: View {
    let insight: Insight
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    private var color: Color {
        switch insight.tone {
        case .good: return Luma.mint
        case .neutral: return Luma.sky
        case .caution: return Luma.amber
        }
    }
    private var symbol: String {
        switch insight.topic {
        case .body: return "heart.text.square.fill"
        case .sleep: return "moon.stars.fill"
        case .training: return "figure.strengthtraining.traditional"
        case .habits: return "checklist"
        case .fitness: return "lungs.fill"
        }
    }

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
                        .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.14)))
                    Text(insight.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                }
                evidence
                LumaNote(insight.body)
                Button {
                    router.askCoach("Tell me more about this and what I should do: \(insight.title). \(insight.body)")
                } label: {
                    Label("Ask the coach", systemImage: "sparkles").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.volt)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var evidence: some View {
        switch insight.evidence {
        case .none:
            EmptyView()
        case .series(let metric):
            let s = env.series(metric, count: 30)
            if s.values.compactMap({ $0 }).count >= 4 {
                LumaLineChart(values: s.values, labels: s.keys.map { LumaText.shortDay($0) }, color: color,
                              band: env.analysis.baselines.baseline(for: metric).map { $0.low...$0.high }, height: 120,
                              format: { metric.format($0) })
            }
        case .compare(let aLabel, let a, let bLabel, let b, let metric):
            CompareBars(aLabel: aLabel, a: a, bLabel: bLabel, b: b, metric: metric, color: color)
        case .scatter(let key):
            if let link = env.analysis.links.first(where: { $0.key == key }) {
                LumaScatter(points: zip(link.xs, link.ys).map { (x: $0.0, y: $0.1) }, color: color, xLabel: link.xLabel, yLabel: link.yLabel, height: 170)
            }
        case .weekdays(let values, let metric):
            LumaBarChart(bars: values.enumerated().map { i, v in
                LumaBarChart.Bar(id: i, value: v, color: metric == .recovery ? Luma.recovery(v) : color, label: ["M", "T", "W", "T", "F", "S", "S"][i])
            }, height: 120, showAxis: false, format: { metric.format($0) })
        }
    }
}
