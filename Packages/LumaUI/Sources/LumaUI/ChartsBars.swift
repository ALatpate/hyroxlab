import SwiftUI
import LumaCore
import LumaKit

// MARK: - Bar chart

/// Animated bars: each grows from the baseline in sequence. Bars can be single-colour, stacked
/// segments, or floating ranges (low…high with a marker), and scrub like the line chart.
struct LumaBarChart: View {
    struct Bar: Identifiable {
        let id: Int
        var value: Double?
        var color: Color
        var label: String = ""
        /// Stacked segments from the bottom up; when set, `value` is their sum.
        var segments: [(value: Double, color: Color)] = []
        /// Floating range: the bar spans low…value and a marker sits at `mark`.
        var low: Double? = nil
        var mark: Double? = nil
        var dimmed: Bool = false
    }

    var bars: [Bar]
    var goal: Double? = nil
    var average: Double? = nil
    var yRange: ClosedRange<Double>? = nil
    var height: CGFloat = 180
    var showAxis: Bool = true
    var widthRatio: CGFloat = 0.64
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var replay: AnyHashable = 0
    var onSelect: ((Int?) -> Void)? = nil
    /// Explicit axis ticks and their labels, for scales that are not plain numbers (clock times, bands).
    var ticks: [Double]? = nil
    var tickFormat: ((Double) -> String)? = nil
    var axisWidth: CGFloat = 34

    @State private var grown = false
    @State private var selected: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: ChartScale {
        if let r = yRange { return ChartScale(lo: r.lowerBound, hi: r.upperBound) }
        let highs = bars.compactMap { $0.value }
        let lows = bars.compactMap { $0.low }
        var include: [Double] = []
        if let g = goal { include.append(g) }
        if let a = average { include.append(a) }
        return ChartScale.fitting(highs + lows, include: include, pad: 0.08, zeroBased: lows.isEmpty)
    }

    var body: some View {
        GeometryReader { geo in
            let axisW: CGFloat = showAxis ? axisWidth : 0
            let hasLabels = bars.contains { !$0.label.isEmpty }
            let plot = CGRect(x: 0, y: 12, width: max(10, geo.size.width - axisW), height: max(10, geo.size.height - 12 - (hasLabels ? 26 : 6)))
            let scale = self.scale
            let slot = plot.width / CGFloat(max(1, bars.count))
            let barW = max(2, min(26, slot * widthRatio))
            ZStack(alignment: .topLeading) {
                if showAxis { ChartGrid(scale: scale, plot: plot, width: geo.size.width, ticks: ticks, format: tickFormat ?? format) }
                ForEach(Array(bars.enumerated()), id: \.element.id) { i, bar in
                    barView(bar, index: i, scale: scale, plot: plot, barW: barW)
                        .position(x: plot.minX + slot * (CGFloat(i) + 0.5), y: plot.midY)
                }
                if let g = goal { rule(at: g, scale: scale, plot: plot, color: Luma.frost.opacity(0.6)) }
                if let a = average { rule(at: a, scale: scale, plot: plot, color: Luma.mist.opacity(0.5)) }
                if hasLabels {
                    ChartXLabels(labels: bars.map { $0.label }, plot: plot, count: min(bars.count, bars.count <= 8 ? 8 : 5),
                                 position: { (CGFloat($0) + 0.5) / CGFloat(max(1, bars.count)) })
                }
                if let i = selected, i < bars.count, let v = bars[i].value {
                    let x = plot.minX + slot * (CGFloat(i) + 0.5)
                    let text = bars[i].low.map { "\(format($0))–\(format(v))" } ?? format(v)
                    ChartCallout(title: bars[i].label, lines: [(bars[i].color, text)])
                        .position(x: min(geo.size.width - 62, max(62, x)), y: 14)
                }
            }
            .modifier(ChartScrub { location in
                guard let location, !bars.isEmpty else { setSelection(nil); return }
                let i = Int(((location.x - plot.minX) / slot).rounded(.down))
                setSelection(min(bars.count - 1, max(0, i)))
            })
        }
        .frame(height: height)
        .onAppear { start() }
        .onChange(of: replay) { _, _ in start() }
    }

    @ViewBuilder
    private func barView(_ bar: Bar, index i: Int, scale: ChartScale, plot: CGRect, barW: CGFloat) -> some View {
        let isSelected = selected == i
        let fade: Double = (selected != nil && !isSelected) || bar.dimmed ? 0.35 : 1
        ZStack(alignment: .bottom) {
            Color.clear
            if let v = bar.value {
                let top = scale.unit(v) * plot.height
                let bottom = scale.unit(bar.low ?? scale.lo) * plot.height
                let h = max(bar.low == nil ? 3 : 6, top - bottom)
                Group {
                    if bar.segments.isEmpty {
                        RoundedRectangle(cornerRadius: min(barW / 2, 6), style: .continuous)
                            .fill(LinearGradient(colors: [bar.color, bar.color.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: bar.color.opacity(isSelected ? 0.7 : 0.0), radius: 8)
                    } else {
                        let total = max(1e-9, bar.segments.reduce(0) { $0 + $1.value })
                        VStack(spacing: 1.5) {
                            ForEach(Array(bar.segments.enumerated().reversed()), id: \.offset) { _, seg in
                                Rectangle().fill(seg.color).frame(height: max(0, h * CGFloat(seg.value / total) - 1.5))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: min(barW / 2, 6), style: .continuous))
                    }
                }
                .frame(width: barW, height: h)
                .overlay(alignment: .bottom) {
                    if let m = bar.mark {
                        Circle().fill(Luma.frost)
                            .frame(width: min(barW + 2, 9), height: min(barW + 2, 9))
                            .offset(y: -(scale.unit(m) * plot.height - bottom) + min(barW + 2, 9) / 2)
                    }
                }
                .scaleEffect(x: 1, y: grown ? 1 : 0.001, anchor: .bottom)
                .offset(y: -bottom)
                .animation(growAnimation(i), value: grown)
            }
        }
        .frame(width: barW, height: plot.height)
        .opacity(fade)
    }

    private func growAnimation(_ i: Int) -> Animation? {
        if reduceMotion { return nil }
        let stagger: Double = min(0.03, 0.6 / Double(max(1, bars.count)))
        return Animation.spring(response: 0.55, dampingFraction: 0.78).delay(0.08 + Double(i) * stagger)
    }

    private func rule(at v: Double, scale: ChartScale, plot: CGRect, color: Color) -> some View {
        let y = scale.y(v, in: plot)
        return Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }

    private func setSelection(_ i: Int?) {
        guard i != selected else { return }
        selected = i
        if i != nil { LumaHaptics.select() }
        onSelect?(i)
    }

    private func start() {
        if reduceMotion { grown = true; return }
        grown = false
        DispatchQueue.main.async { grown = true }
    }
}

// MARK: - Horizontal composition bars

/// One horizontal bar split into coloured shares (sleep stages, macros, training intensity).
struct LumaShareBar: View {
    struct Share: Identifiable {
        let id: String
        var value: Double
        var color: Color
    }
    var shares: [Share]
    var height: CGFloat = 14
    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            let total = max(1e-9, shares.reduce(0) { $0 + $1.value })
            HStack(spacing: 2) {
                ForEach(shares) { s in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(s.color)
                        .frame(width: max(0, (geo.size.width - CGFloat(shares.count - 1) * 2) * CGFloat(s.value / total)))
                }
            }
            .clipShape(Capsule())
            .mask(alignment: .leading) { Rectangle().frame(width: grown ? geo.size.width : 0) }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.1)) { grown = true } }
    }
}

/// Time in each heart-rate zone, as five rows that fill from the left.
struct LumaZoneBars: View {
    /// Seconds in zones 1…5.
    var seconds: [Double]
    /// Lower bpm bound of each zone, for the labels.
    var bounds: [Double] = []

    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        let peak = max(1, seconds.max() ?? 1)
        VStack(spacing: 10) {
            ForEach((0..<min(5, seconds.count)).reversed(), id: \.self) { i in
                HStack(spacing: 10) {
                    Text("Z\(i + 1)").font(LumaFont.numeral(15, .bold)).foregroundStyle(Luma.zone(i + 1)).frame(width: 22, alignment: .leading)
                    LumaBar(value: seconds[i], total: peak, color: Luma.zone(i + 1), height: 10)
                    Text(LumaText.duration(seconds[i])).font(LumaFont.numeral(15, .semibold)).foregroundStyle(Luma.frost)
                        .frame(width: 52, alignment: .trailing)
                    Text("\(Int((seconds[i] / total * 100).rounded()))%").font(LumaFont.body(12)).foregroundStyle(Luma.mist)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            if bounds.count == 5 {
                Text("Zone 2 from \(Int(bounds[1])) bpm, zone 4 from \(Int(bounds[3])) bpm, zone 5 from \(Int(bounds[4])) bpm")
                    .font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Gauge

/// A 240° dial with coloured ranges and a marker at the current value.
struct LumaGauge: View {
    var value: Double?
    var range: ClosedRange<Double>
    /// Coloured stretches of the dial.
    var bands: [(range: ClosedRange<Double>, color: Color)]
    var lineWidth: CGFloat = 12
    @State private var shown: Double = 0

    private func fraction(_ v: Double) -> Double {
        min(1, max(0, (v - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height * 1.25)
            let span = 240.0
            ZStack {
                ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                    Circle()
                        .trim(from: fraction(band.range.lowerBound) * span / 360 + 0.004, to: fraction(band.range.upperBound) * span / 360 - 0.004)
                        .stroke(band.color.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(150))
                }
                if value != nil {
                    Circle().fill(Luma.frost)
                        .frame(width: lineWidth + 8, height: lineWidth + 8)
                        .overlay(Circle().stroke(Luma.night, lineWidth: 3))
                        .shadow(color: .white.opacity(0.6), radius: 6)
                        .offset(x: (d - lineWidth) / 2)
                        .rotationEffect(.degrees(150 + fraction(shown) * span))
                }
            }
            .frame(width: d - lineWidth, height: d - lineWidth)
            .position(x: geo.size.width / 2, y: d / 2)
        }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.15)) { shown = value ?? range.lowerBound } }
        .onChange(of: value) { _, new in withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = new ?? range.lowerBound } }
    }
}
