import SwiftUI

/// A progress arc with a rounded cap and a soft glow, starting at 12 o'clock.
public struct LumaRing: View {
    var progress: Double
    var lineWidth: CGFloat
    var colors: [Color]
    var track: Color
    var glow: Bool

    public init(progress: Double, lineWidth: CGFloat = 10, colors: [Color], track: Color = Color.white.opacity(0.08), glow: Bool = true) {
        self.progress = progress; self.lineWidth = lineWidth; self.colors = colors; self.track = track; self.glow = glow
    }

    public var body: some View {
        let p = min(1, max(0, progress))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if p > 0 {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(max(1, 360 * p))),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (colors.last ?? .white).opacity(glow ? 0.55 : 0), radius: glow ? lineWidth * 0.8 : 0)
            }
        }
        .padding(lineWidth / 2)
    }
}

/// The Lumen: Luma's signature. A sphere of light whose colour is the recovery band and whose
/// brightness and ring follow the score. Content (the number) is layered on top by the caller.
public struct LumaOrb: View {
    var progress: Double
    var color: Color
    var partner: Color
    var breathing: Bool
    @State private var pulse = false

    public init(progress: Double, color: Color, partner: Color? = nil, breathing: Bool = true) {
        self.progress = progress; self.color = color; self.partner = partner ?? color; self.breathing = breathing
    }

    public var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let p = min(1, max(0, progress))
            ZStack {
                // Halo
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.34 + 0.2 * p), color.opacity(0.0)], center: .center,
                                         startRadius: d * 0.22, endRadius: d * 0.62))
                    .scaleEffect(pulse ? 1.06 : 0.97)
                    .blur(radius: d * 0.04)
                // Sphere
                Circle()
                    .fill(RadialGradient(colors: [color.opacity(0.42), partner.opacity(0.14), Color.black.opacity(0.0)],
                                         center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: d * 0.46))
                    .background(Circle().fill(Luma.deep))
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: d * 0.74, height: d * 0.74)
                // Score ring
                LumaRing(progress: p, lineWidth: d * 0.035, colors: [partner, color])
                    .frame(width: d * 0.9, height: d * 0.9)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard breathing else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A line through evenly spaced values, scaled to its bounds. nil values are skipped.
public struct SparklineShape: Shape {
    var values: [Double]
    var closed: Bool

    public init(values: [Double], closed: Bool = false) { self.values = values; self.closed = closed }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return path }
        let span = hi - lo > 0 ? hi - lo : 1
        let step = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.minX + CGFloat(i) * step, y: rect.maxY - CGFloat((v - lo) / span) * rect.height)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

public struct LumaSparkline: View {
    var values: [Double]
    var color: Color
    var fill: Bool

    public init(values: [Double], color: Color, fill: Bool = true) { self.values = values; self.color = color; self.fill = fill }

    public var body: some View {
        ZStack {
            if fill {
                SparklineShape(values: values, closed: true)
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            }
            SparklineShape(values: values)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
