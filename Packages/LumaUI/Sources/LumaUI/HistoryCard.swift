import SwiftUI
import LumaCore
import LumaKit

enum HistoryRange: Int, CaseIterable, Hashable {
    case week = 7, month = 30, quarter = 90, half = 180

    var title: String {
        switch self {
        case .week: return "1W"
        case .month: return "1M"
        case .quarter: return "3M"
        case .half: return "6M"
        }
    }
    var phrase: String {
        switch self {
        case .week: return "7-day"
        case .month: return "30-day"
        case .quarter: return "3-month"
        case .half: return "6-month"
        }
    }
    /// Longer ranges are shown as weekly averages so the marks stay readable.
    var bucket: Int { self == .quarter || self == .half ? 7 : 1 }

    static let options: [(value: HistoryRange, title: String)] = HistoryRange.allCases.map { ($0, $0.title) }
}

/// A metric's history with a range switch: the headline figure is the period average, or the value
/// under the finger while scrubbing. Bars for totals and scores, a line with the personal band for
/// signals that hover around a baseline.
struct MetricHistoryCard: View {
    enum Style { case bars, line }

    let metric: LMetric
    var style: Style = .bars
    var title: String? = nil
    var color: Color? = nil
    /// Colour per value (recovery bands); overrides `color` for bars.
    var barColor: ((Double) -> Color)? = nil
    var goal: Double? = nil
    var initial: HistoryRange = .month

    @EnvironmentObject private var env: LumaEnv
    @State private var range: HistoryRange?
    @State private var selected: Int?

    private var active: HistoryRange { range ?? initial }

    private struct Bucket {
        let label: String
        let value: Double?
    }

    private func buckets() -> [Bucket] {
        let s = env.series(metric, count: active.rawValue)
        let size = active.bucket
        guard size > 1 else {
            return zip(s.keys, s.values).map { Bucket(label: LumaText.shortDay($0.0), value: $0.1) }
        }
        var out: [Bucket] = []
        var i = s.keys.count
        while i > 0 {
            let lo = max(0, i - size)
            let vals = s.values[lo..<i].compactMap { $0 }
            out.append(Bucket(label: "\(LumaText.shortDay(s.keys[lo]))", value: LStat.mean(vals)))
            i = lo
        }
        return out.reversed()
    }

    var body: some View {
        let data = buckets()
        let values = data.compactMap { $0.value }
        let tone = color ?? metric.tone.color
        let avg = LStat.mean(values)
        let prior = priorAverage()
        let shownValue: Double? = selected.flatMap { $0 < data.count ? data[$0].value : nil } ?? avg
        let baseline = env.analysis.baselines.baseline(for: metric)

        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        LumaLabel(title ?? metric.title)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(shownValue.map { metric.format($0) } ?? "–")
                                .font(LumaFont.numeral(40)).foregroundStyle(Luma.frost)
                                .contentTransition(.numericText())
                            Text(metric.unit).font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist)
                        }
                        Text(selected.flatMap { $0 < data.count ? (active.bucket > 1 ? "Week of \(data[$0].label)" : data[$0].label) : nil }
                             ?? "\(active.phrase) average")
                            .font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                    }
                    Spacer(minLength: 8)
                    LumaSegmented(selection: Binding(get: { active }, set: { range = $0; selected = nil }), options: HistoryRange.options)
                        .frame(width: 168)
                }

                if values.count < 2 {
                    LumaEmpty(symbol: "chart.xyaxis.line", title: "Not enough data yet",
                              message: "This fills in as the strap records more days.")
                } else if style == .bars {
                    LumaBarChart(bars: data.enumerated().map { i, b in
                        LumaBarChart.Bar(id: i, value: b.value, color: b.value.flatMap { v in barColor.map { $0(v) } } ?? tone, label: b.label)
                    }, goal: goal, average: selected == nil ? avg : nil, format: { metric.format($0) }, replay: active, onSelect: { selected = $0 })
                } else {
                    LumaLineChart(values: data.map { $0.value }, labels: data.map { $0.label }, color: tone,
                                  band: baseline.map { $0.low...$0.high }, goal: goal, format: { metric.format($0) },
                                  replay: active, onSelect: { selected = $0 })
                }

                HStack(spacing: 0) {
                    stat("Lowest", values.min())
                    stat("Highest", values.max())
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel("vs previous")
                        if let avg, let prior {
                            DeltaBadge(delta: avg - prior, decimals: metric.decimals, higherIsBetter: metric.higherIsBetter, suffix: "")
                        } else {
                            Text("–").font(LumaFont.numeral(18)).foregroundStyle(Luma.smoke)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func stat(_ label: String, _ v: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LumaLabel(label)
            Text(v.map { metric.format($0) } ?? "–").font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Average over the period just before the visible one.
    private func priorAverage() -> Double? {
        let n = active.rawValue
        let s = env.series(metric, count: n * 2)
        return LStat.mean(Array(s.values.prefix(n)).compactMap { $0 })
    }
}

/// A small titled statistic used in grids on the detail screens.
struct StatCell: View {
    let label: String
    let value: String
    var unit: String = ""
    var note: String? = nil
    var color: Color = Luma.frost

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LumaLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(LumaFont.numeral(28)).foregroundStyle(color)
                if !unit.isEmpty { Text(unit).font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist) }
            }
            if let note { Text(note).font(LumaFont.body(12)).foregroundStyle(Luma.smoke).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(LumaPanel(radius: 20))
    }
}

/// A two-column grid for `StatCell`s.
struct StatGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) { content() }
    }
}

/// A paragraph of explanation under a chart.
struct LumaNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
    }
}

/// Day stepper used on screens that show one day or night at a time.
struct DayStepper: View {
    @Binding var day: String
    let earliest: String?
    let today: String

    var body: some View {
        HStack(spacing: 10) {
            Button {
                LumaHaptics.select()
                day = LDate.adding(-1, to: day)
            } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).frame(width: 40, height: 40).contentShape(Rectangle()) }
            .disabled(earliest.map { day <= $0 } ?? true)
            Text(LumaText.dayTitle(day, today: today)).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                .frame(maxWidth: .infinity)
            Button {
                LumaHaptics.select()
                day = LDate.adding(1, to: day)
            } label: { Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).frame(width: 40, height: 40).contentShape(Rectangle()) }
            .disabled(day >= today)
        }
        .foregroundStyle(Luma.frost)
        .padding(.horizontal, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Luma.line, lineWidth: 1))
    }
}
