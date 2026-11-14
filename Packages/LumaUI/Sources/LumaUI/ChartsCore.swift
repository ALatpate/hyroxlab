import SwiftUI
import LumaCore
import LumaKit

// MARK: - Scale and paths

/// A vertical value range with helpers to place values and pick tidy axis ticks.
struct ChartScale: Equatable {
    var lo: Double
    var hi: Double

    init(lo: Double, hi: Double) {
        self.lo = lo
        self.hi = hi > lo ? hi : lo + 1
    }

    /// A range that fits the values (plus anything in `include`) with breathing room, snapped to tidy steps.
    static func fitting(_ values: [Double], include: [Double] = [], pad: Double = 0.14, zeroBased: Bool = false) -> ChartScale {
        let all = values + include
        guard var lo = all.min(), var hi = all.max() else { return ChartScale(lo: 0, hi: 1) }
        if zeroBased { lo = min(0, lo) }
        if hi - lo < 1e-9 { hi = lo + max(1, abs(lo) * 0.1) }
        let span = hi - lo
        let step = niceStep(span / 3)
        let loPadded = zeroBased ? lo : lo - span * pad
        let hiPadded = hi + span * pad
        let snappedLo = zeroBased ? 0 : (loPadded / step).rounded(.down) * step
        let snappedHi = (hiPadded / step).rounded(.up) * step
        return ChartScale(lo: lo >= 0 ? max(0, snappedLo) : snappedLo, hi: snappedHi)
    }

    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let mag = pow(10, floor(log10(raw)))
        let norm = raw / mag
        let nice: Double = norm < 1.5 ? 1 : (norm < 3.5 ? 2 : (norm < 7.5 ? 5 : 10))
        return nice * mag
    }

    func unit(_ v: Double) -> CGFloat { CGFloat((v - lo) / (hi - lo)) }
    func y(_ v: Double, in rect: CGRect) -> CGFloat { rect.maxY - unit(v) * rect.height }

    var ticks: [Double] {
        let step = ChartScale.niceStep((hi - lo) / 3)
        var out: [Double] = []
        var t = (lo / step).rounded(.up) * step
        while t <= hi + step * 0.001 { out.append(t); t += step }
        return out
    }
}

enum ChartPath {
    /// A smooth curve through the points that never overshoots them (monotone cubic, Fritsch–Carlson).
    static func smooth(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        let n = pts.count
        guard n > 2 else {
            if n == 2 { path.addLine(to: pts[1]) }
            return path
        }
        var d = [CGFloat](repeating: 0, count: n - 1)
        var m = [CGFloat](repeating: 0, count: n)
        for i in 0..<(n - 1) {
            let dx = pts[i + 1].x - pts[i].x
            d[i] = dx != 0 ? (pts[i + 1].y - pts[i].y) / dx : 0
        }
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<(n - 1) {
            if d[i] == 0 {
                m[i] = 0; m[i + 1] = 0
            } else {
                let a = m[i] / d[i], b = m[i + 1] / d[i]
                let s = a * a + b * b
                if s > 9 {
                    let t = 3 / s.squareRoot()
                    m[i] = t * a * d[i]; m[i + 1] = t * b * d[i]
                }
            }
        }
        for i in 0..<(n - 1) {
            let dx = (pts[i + 1].x - pts[i].x) / 3
            path.addCurve(to: pts[i + 1],
                          control1: CGPoint(x: pts[i].x + dx, y: pts[i].y + m[i] * dx),
                          control2: CGPoint(x: pts[i + 1].x - dx, y: pts[i + 1].y - m[i + 1] * dx))
        }
        return path
    }

    static func straight(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}

/// A line (or the area under it) through points given in unit space: x and y in 0…1, y up.
struct LineShape: Shape {
    var points: [CGPoint]
    var smooth: Bool = true
    var area: Bool = false

    func path(in rect: CGRect) -> Path {
        let pts = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.maxY - $0.y * rect.height) }
        var path = smooth ? ChartPath.smooth(pts) : ChartPath.straight(pts)
        if area, let first = pts.first, let last = pts.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Shared chart chrome

/// The floating read-out shown while scrubbing a chart.
struct ChartCallout: View {
    let title: String
    let lines: [(color: Color, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(LumaFont.label(10)).foregroundStyle(Luma.mist)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    Circle().fill(line.color).frame(width: 6, height: 6)
                    Text(line.text).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Luma.raised))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Luma.lineStrong, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .fixedSize()
    }
}

/// Horizontal grid lines with value labels on the right edge.
struct ChartGrid: View {
    let scale: ChartScale
    let plot: CGRect
    let width: CGFloat
    var ticks: [Double]? = nil
    var format: (Double) -> String

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks ?? scale.ticks, id: \.self) { t in
                let y = scale.y(t, in: plot)
                Path { p in
                    p.move(to: CGPoint(x: plot.minX, y: y))
                    p.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                Text(format(t))
                    .font(LumaFont.label(9.5))
                    .foregroundStyle(Luma.smoke)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: width - plot.maxX - 4, alignment: .trailing)
                    .position(x: plot.maxX + (width - plot.maxX) / 2 + 2, y: y)
            }
        }
    }
}

/// X-axis labels spread evenly; `labels` is one per data index, drawn at `count` positions.
struct ChartXLabels: View {
    let labels: [String]
    let plot: CGRect
    var count: Int = 4
    /// Position of index i along the plot, 0…1.
    var position: (Int) -> CGFloat

    private func x(_ i: Int) -> CGFloat {
        min(plot.maxX - 14, max(plot.minX + 14, plot.minX + position(i) * plot.width))
    }

    /// The labels to draw: evenly picked, then thinned so that none runs into the one before it.
    private var visible: [Int] {
        let n = labels.count
        guard n > 0 else { return [] }
        let picks: [Int] = n <= count || count < 2 ? Array(0..<n) : (0..<count).map { Int((Double($0) / Double(count - 1) * Double(n - 1)).rounded()) }
        var shown: [Int] = []
        var edge: CGFloat = -.greatestFiniteMagnitude
        for i in picks where !labels[i].isEmpty && !shown.contains(i) {
            let width = CGFloat(labels[i].count) * 6.2 + 6
            let centre = x(i)
            if centre - width / 2 >= edge {
                shown.append(i)
                edge = centre + width / 2
            }
        }
        return shown
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visible, id: \.self) { i in
                Text(labels[i])
                    .font(LumaFont.label(9.5))
                    .foregroundStyle(Luma.smoke)
                    .fixedSize()
                    .position(x: x(i), y: plot.maxY + 12)
            }
        }
    }
}

/// Touch-and-hold to scrub, tap to pin: keeps vertical scrolling free for quick swipes.
struct ChartScrub: ViewModifier {
    let onLocation: (CGPoint?) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.12)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        if case .second(true, let drag?) = value { onLocation(drag.location) }
                    }
                    .onEnded { _ in onLocation(nil) }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { tap in
                    onLocation(tap.location)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { onLocation(nil) }
                }
            )
    }
}

// MARK: - Line chart

/// Animated line chart: lines draw in from the left, the area fades up behind them, and
/// touch-and-hold scrubs through the points. Up to a few series over a shared x index.
struct LumaLineChart: View {
    struct Series: Identifiable {
        let id: String
        var values: [Double?]
        var color: Color
        var fill: Bool = false
        var dashed: Bool = false
        var width: CGFloat = 2.6
    }

    var series: [Series]
    var labels: [String] = []
    /// A shaded "normal" band.
    var band: ClosedRange<Double>? = nil
    var bandColor: Color = Luma.frost
    /// A dashed reference line.
    var goal: Double? = nil
    var yRange: ClosedRange<Double>? = nil
    var zeroBased: Bool = false
    var height: CGFloat = 190
    var smooth: Bool = true
    var showAxis: Bool = true
    var format: (Double) -> String = { String(format: "%.0f", $0) }
    var replay: AnyHashable = 0
    var onSelect: ((Int?) -> Void)? = nil
    /// Explicit axis ticks and their labels, for scales that are not plain numbers (clock times, bands).
    var ticks: [Double]? = nil
    var tickFormat: ((Double) -> String)? = nil
    var axisWidth: CGFloat = 34

    @State private var progress: CGFloat = 0
    @State private var selected: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var count: Int { series.map { $0.values.count }.max() ?? 0 }

    private var scale: ChartScale {
        if let r = yRange { return ChartScale(lo: r.lowerBound, hi: r.upperBound) }
        let values = series.flatMap { $0.values.compactMap { $0 } }
        var include: [Double] = []
        if let b = band { include += [b.lowerBound, b.upperBound] }
        if let g = goal { include.append(g) }
        return ChartScale.fitting(values, include: include, zeroBased: zeroBased)
    }

    private func xUnit(_ i: Int) -> CGFloat { count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0.5 }

    private func unitPoints(_ s: Series, _ scale: ChartScale) -> [CGPoint] {
        s.values.enumerated().compactMap { i, v in v.map { CGPoint(x: xUnit(i), y: scale.unit($0)) } }
    }

    var body: some View {
        GeometryReader { geo in
            let axisW: CGFloat = showAxis ? axisWidth : 0
            let plot = CGRect(x: 0, y: 12, width: max(10, geo.size.width - axisW), height: max(10, geo.size.height - 12 - (labels.isEmpty ? 6 : 26)))
            let scale = self.scale
            ZStack(alignment: .topLeading) {
                if showAxis { ChartGrid(scale: scale, plot: plot, width: geo.size.width, ticks: ticks, format: tickFormat ?? format) }
                if let b = band {
                    let top = scale.y(b.upperBound, in: plot), bottom = scale.y(b.lowerBound, in: plot)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(bandColor.opacity(0.07))
                        .frame(width: plot.width, height: max(1, bottom - top))
                        .offset(x: plot.minX, y: top)
                }
                if let g = goal {
                    let y = scale.y(g, in: plot)
                    Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                        .stroke(Luma.mist.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
                ForEach(series) { s in
                    let pts = unitPoints(s, scale)
                    ZStack {
                        if s.fill {
                            LineShape(points: pts, smooth: smooth, area: true)
                                .fill(LinearGradient(colors: [s.color.opacity(0.32), s.color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                                .mask(alignment: .leading) { Rectangle().frame(width: plot.width * progress) }
                        }
                        LineShape(points: pts, smooth: smooth)
                            .trim(from: 0, to: progress)
                            .stroke(s.color.opacity(0.55), style: StrokeStyle(lineWidth: s.width + 5, lineCap: .round, lineJoin: .round))
                            .blur(radius: 6)
                            .opacity(s.dashed ? 0 : 1)
                        LineShape(points: pts, smooth: smooth)
                            .trim(from: 0, to: progress)
                            .stroke(s.color, style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round, dash: s.dashed ? [5, 5] : []))
                        if let last = pts.last, !s.dashed {
                            Circle().fill(s.color)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Luma.night, lineWidth: 2))
                                .shadow(color: s.color.opacity(0.8), radius: 6)
                                .position(x: last.x * plot.width, y: plot.height - last.y * plot.height)
                                .opacity(progress >= 1 ? 1 : 0)
                        }
                    }
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                }
                if !labels.isEmpty {
                    ChartXLabels(labels: labels, plot: plot, position: { xUnit($0) })
                }
                if let i = selected, i < count { selection(i, plot: plot, scale: scale, width: geo.size.width) }
            }
            .modifier(ChartScrub { location in
                guard let location, count > 0 else { setSelection(nil); return }
                let f = min(1, max(0, (location.x - plot.minX) / plot.width))
                setSelection(Int((f * CGFloat(count - 1)).rounded()))
            })
        }
        .frame(height: height)
        .onAppear { start() }
        .onChange(of: replay) { _, _ in start() }
    }

    @ViewBuilder
    private func selection(_ i: Int, plot: CGRect, scale: ChartScale, width: CGFloat) -> some View {
        let x = plot.minX + xUnit(i) * plot.width
        let lines: [(color: Color, text: String)] = series.compactMap { s in
            guard i < s.values.count, let v = s.values[i] else { return nil }
            return (s.color, format(v))
        }
        Path { p in p.move(to: CGPoint(x: x, y: plot.minY)); p.addLine(to: CGPoint(x: x, y: plot.maxY)) }
            .stroke(Luma.frost.opacity(0.35), lineWidth: 1)
        ForEach(series) { s in
            if i < s.values.count, let v = s.values[i] {
                Circle().fill(Luma.night)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(s.color, lineWidth: 3))
                    .position(x: x, y: scale.y(v, in: plot))
            }
        }
        if !lines.isEmpty {
            ChartCallout(title: i < labels.count ? labels[i] : "", lines: lines)
                .position(x: min(width - 62, max(62, x)), y: 14)
        }
    }

    private func setSelection(_ i: Int?) {
        guard i != selected else { return }
        selected = i
        if i != nil { LumaHaptics.select() }
        onSelect?(i)
    }

    private func start() {
        if reduceMotion { progress = 1; return }
        progress = 0
        withAnimation(.easeOut(duration: 1.0).delay(0.1)) { progress = 1 }
    }
}

extension LumaLineChart {
    /// One series, the common case.
    init(values: [Double?], labels: [String] = [], color: Color, fill: Bool = true, band: ClosedRange<Double>? = nil,
         goal: Double? = nil, yRange: ClosedRange<Double>? = nil, height: CGFloat = 190,
         format: @escaping (Double) -> String = { String(format: "%.0f", $0) }, replay: AnyHashable = 0,
         onSelect: ((Int?) -> Void)? = nil, ticks: [Double]? = nil, axisWidth: CGFloat = 34) {
        self.init(series: [Series(id: "main", values: values, color: color, fill: fill)], labels: labels, band: band,
                  bandColor: color, goal: goal, yRange: yRange, height: height, format: format, replay: replay, onSelect: onSelect,
                  ticks: ticks, axisWidth: axisWidth)
    }
}
