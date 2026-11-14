import SwiftUI
import LumaCore
import LumaKit

extension LStageKind {
    var color: Color {
        switch self {
        case .awake: return Color(hex: 0xFFB45C)
        case .rem: return Luma.sky
        case .light: return Luma.dusk
        case .deep: return Color(hex: 0x5B48F0)
        }
    }
    /// Row in the hypnogram, top to bottom.
    var row: Int {
        switch self {
        case .awake: return 0
        case .rem: return 1
        case .light: return 2
        case .deep: return 3
        }
    }
}

// MARK: - Hypnogram

/// The night as four lanes (awake, REM, light, deep). Blocks sweep in from the left; touch-and-hold
/// reads the stage and clock time under the finger.
struct LumaHypnogram: View {
    var stages: [LStage]
    var height: CGFloat = 168
    @State private var progress: CGFloat = 0
    @State private var scrubT: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let start = stages.first?.start ?? 0
            let end = max(start + 60, stages.last?.end ?? 1)
            let labelW: CGFloat = 44
            let plot = CGRect(x: labelW, y: 6, width: max(10, geo.size.width - labelW), height: max(10, geo.size.height - 30))
            let lane = plot.height / 4
            ZStack(alignment: .topLeading) {
                ForEach(LStageKind.allCases.sorted { $0.row < $1.row }, id: \.self) { kind in
                    let y = plot.minY + lane * (CGFloat(kind.row) + 0.5)
                    Text(kind.title).font(LumaFont.label(9.5)).foregroundStyle(Luma.smoke)
                        .frame(width: labelW - 6, alignment: .leading)
                        .position(x: (labelW - 6) / 2, y: y)
                    Path { p in p.move(to: CGPoint(x: plot.minX, y: y)); p.addLine(to: CGPoint(x: plot.maxX, y: y)) }
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
                Canvas { ctx, _ in
                    var previous: CGPoint? = nil
                    for s in stages {
                        let x0 = plot.minX + CGFloat((s.start - start) / (end - start)) * plot.width
                        let x1 = plot.minX + CGFloat((s.end - start) / (end - start)) * plot.width
                        let y = plot.minY + lane * (CGFloat(s.kind.row) + 0.5)
                        if let p = previous {
                            var link = Path()
                            link.move(to: p)
                            link.addLine(to: CGPoint(x: x0, y: y))
                            ctx.stroke(link, with: .color(Color.white.opacity(0.18)), lineWidth: 1)
                        }
                        let rect = CGRect(x: x0, y: y - lane * 0.32, width: max(1.5, x1 - x0), height: lane * 0.64)
                        let block = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 2))
                        ctx.fill(block, with: .linearGradient(Gradient(colors: [s.kind.color, s.kind.color.opacity(0.7)]),
                                                              startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                              endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                        previous = CGPoint(x: x1, y: y)
                    }
                }
                .mask(alignment: .leading) { Rectangle().frame(width: labelW + plot.width * progress) }
                ForEach(0..<4, id: \.self) { i in
                    let f = Double(i) / 3
                    Text(LumaText.time(start + (end - start) * f))
                        .font(LumaFont.label(9.5)).foregroundStyle(Luma.smoke).fixedSize()
                        .position(x: min(plot.maxX - 16, max(plot.minX + 16, plot.minX + plot.width * CGFloat(f))), y: plot.maxY + 13)
                }
                if let t = scrubT, let s = stages.first(where: { t >= $0.start && t <= $0.end }) {
                    let x = plot.minX + CGFloat((t - start) / (end - start)) * plot.width
                    Path { p in p.move(to: CGPoint(x: x, y: plot.minY)); p.addLine(to: CGPoint(x: x, y: plot.maxY)) }
                        .stroke(Luma.frost.opacity(0.4), lineWidth: 1)
                    ChartCallout(title: LumaText.time(t), lines: [(s.kind.color, s.kind.title)])
                        .position(x: min(geo.size.width - 50, max(50 + labelW, x)), y: 12)
                }
            }
            .modifier(ChartScrub { location in
                guard let location else { scrubT = nil; return }
                let f = min(1, max(0, (location.x - plot.minX) / plot.width))
                scrubT = start + (end - start) * Double(f)
            })
        }
        .frame(height: height)
        .onAppear {
            if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: 1.1).delay(0.1)) { progress = 1 } }
        }
    }
}

// MARK: - Calendar heat map

/// A month of days as a grid; each cell is lit by its value. Used for recovery and training history.
struct LumaHeatCalendar: View {
    /// Day keys for the cells, oldest first, in whole weeks starting Monday.
    var days: [String]
    var value: (String) -> Double?
    var color: (Double) -> Color
    var selected: String? = nil
    var today: String
    var onTap: ((String) -> Void)? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(LumaFont.label(9.5)).foregroundStyle(Luma.smoke).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days, id: \.self) { key in
                    let v = value(key)
                    let future = key > today
                    Button {
                        onTap?(key)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(v.map { color($0).opacity(0.85) } ?? Color.white.opacity(future ? 0.02 : 0.05))
                            Text(String(Int(key.suffix(2)) ?? 0))
                                .font(LumaFont.numeral(13, .semibold))
                                .foregroundStyle(v == nil ? Luma.smoke : Luma.ink)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(key == selected ? Luma.frost : (key == today ? Luma.frost.opacity(0.45) : Color.clear), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(onTap == nil)
                }
            }
        }
    }
}

// MARK: - Scatter

/// Paired values with a fitted line, for "how does X relate to Y" insights.
struct LumaScatter: View {
    var points: [(x: Double, y: Double)]
    var color: Color
    var xLabel: String
    var yLabel: String
    var height: CGFloat = 200
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: 6, y: 8, width: max(10, geo.size.width - 12), height: max(10, geo.size.height - 34))
            let xs = ChartScale.fitting(points.map { $0.x }, pad: 0.08)
            let ys = ChartScale.fitting(points.map { $0.y }, pad: 0.08)
            let fit = LStat.linearFit(points.map { $0.x }, points.map { $0.y })
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)).frame(width: plot.width, height: plot.height).offset(x: plot.minX, y: plot.minY)
                if let fit {
                    let y0 = min(plot.maxY, max(plot.minY, ys.y(fit.intercept + fit.slope * xs.lo, in: plot)))
                    let y1 = min(plot.maxY, max(plot.minY, ys.y(fit.intercept + fit.slope * xs.hi, in: plot)))
                    Path { p in
                        p.move(to: CGPoint(x: plot.minX, y: y0))
                        p.addLine(to: CGPoint(x: plot.maxX, y: y1))
                    }
                    .trim(from: 0, to: shown ? 1 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 5]))
                }
                ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
                    Circle().fill(color.opacity(0.75))
                        .frame(width: 7, height: 7)
                        .position(x: plot.minX + xs.unit(pt.x) * plot.width, y: ys.y(pt.y, in: plot))
                        .scaleEffect(shown ? 1 : 0.01)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(i) * 0.008), value: shown)
                }
                Text(xLabel).font(LumaFont.label(9.5)).foregroundStyle(Luma.smoke).fixedSize()
                    .position(x: plot.midX, y: plot.maxY + 14)
                Text(yLabel).font(LumaFont.label(9.5)).foregroundStyle(Luma.smoke).fixedSize()
                    .position(x: plot.minX + 40, y: plot.minY + 10)
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { shown = true } }
    }
}

// MARK: - Radar

/// A polygon over named spokes, each 0…1. Used for station strengths.
struct LumaRadar: View {
    var spokes: [(label: String, value: Double?)]
    var color: Color
    @State private var grow: CGFloat = 0

    private func point(_ i: Int, _ r: CGFloat, _ centre: CGPoint) -> CGPoint {
        let a = -Double.pi / 2 + Double(i) / Double(max(1, spokes.count)) * 2 * Double.pi
        return CGPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y + r * CGFloat(sin(a)))
    }

    var body: some View {
        GeometryReader { geo in
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 30
            ZStack {
                ForEach(1..<5, id: \.self) { ring in
                    Path { p in
                        for i in 0...spokes.count {
                            let pt = point(i % max(1, spokes.count), radius * CGFloat(ring) / 4, centre)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.white.opacity(ring == 4 ? 0.14 : 0.06), lineWidth: 1)
                }
                Path { p in
                    for i in 0...spokes.count {
                        let idx = i % max(1, spokes.count)
                        let v = CGFloat(min(1, max(0.04, spokes[idx].value ?? 0.04)))
                        let pt = point(idx, radius * v * grow, centre)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                }
                .fill(color.opacity(0.22))
                .overlay(
                    Path { p in
                        for i in 0...spokes.count {
                            let idx = i % max(1, spokes.count)
                            let v = CGFloat(min(1, max(0.04, spokes[idx].value ?? 0.04)))
                            let pt = point(idx, radius * v * grow, centre)
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                        p.closeSubpath()
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .shadow(color: color.opacity(0.7), radius: 6)
                )
                ForEach(Array(spokes.enumerated()), id: \.offset) { i, s in
                    Text(s.label)
                        .font(LumaFont.label(9.5))
                        .foregroundStyle(s.value == nil ? Luma.smoke : Luma.mist)
                        .fixedSize()
                        .position(point(i, radius + 18, centre))
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.1)) { grow = 1 } }
    }
}

// MARK: - Route

/// A GPS track drawn as a line of light on the night field (no map tiles): fits the track to the
/// frame, keeps its aspect, and traces it from start to finish.
struct LumaRouteTrace: View {
    var coords: [LCoord]
    var color: Color = Luma.volt
    var lineWidth: CGFloat = 4
    @State private var progress: CGFloat = 0

    private func unitPoints() -> [CGPoint] {
        guard let minLat = coords.map({ $0.lat }).min(), let maxLat = coords.map({ $0.lat }).max(),
              let minLon = coords.map({ $0.lon }).min(), let maxLon = coords.map({ $0.lon }).max() else { return [] }
        let k = cos((minLat + maxLat) / 2 * Double.pi / 180)
        let w = max(1e-9, (maxLon - minLon) * k), h = max(1e-9, maxLat - minLat)
        let s = max(w, h)
        return coords.map { c in
            CGPoint(x: ((c.lon - minLon) * k + (s - w) / 2) / s, y: ((c.lat - minLat) + (s - h) / 2) / s)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let pts = unitPoints()
            let side = min(geo.size.width, geo.size.height) - 28
            ZStack {
                if pts.count >= 2 {
                    LineShape(points: pts, smooth: false)
                        .trim(from: 0, to: progress)
                        .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round, lineJoin: .round))
                        .blur(radius: 9)
                    LineShape(points: pts, smooth: false)
                        .trim(from: 0, to: progress)
                        .stroke(LinearGradient(colors: [color, Color.white], startPoint: .bottomLeading, endPoint: .topTrailing),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    if let first = pts.first {
                        Circle().fill(Luma.night).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(color, lineWidth: 3))
                            .position(x: first.x * side, y: side - first.y * side)
                    }
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.6).delay(0.15)) { progress = 1 } }
    }
}
