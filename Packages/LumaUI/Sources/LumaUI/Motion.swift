import SwiftUI
import LumaCore
import LumaKit

// The moving parts that are Luma's own: a tick that draws itself, a heart that beats at the real rate,
// rows that shimmer while photos are read, a banner for a new best, and a tile that opens into its
// screen. The timings come from `LumaMotion`; with Reduce Motion on, each of these stands still.

// MARK: - A tick that draws itself

struct TickShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.18))
        return p
    }
}

/// A round checkbox. Ticked, it fills, the tick is drawn stroke by stroke and the whole mark lands
/// with a small bounce.
struct LumaTick: View {
    let on: Bool
    var size: CGFloat = 22
    var color: Color = Luma.mint

    var body: some View {
        ZStack {
            Circle().strokeBorder(Luma.smoke, lineWidth: 1.6).opacity(on ? 0 : 1)
            Circle().fill(color).scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
            TickShape()
                .trim(from: 0, to: on ? 1 : 0)
                .stroke(Luma.ink, style: StrokeStyle(lineWidth: max(1.8, size * 0.11), lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .animation(LumaMotion.pop, value: on)
        .accessibilityHidden(true)
    }
}

// MARK: - A heart at the real rate

/// A heart that beats at the heart rate it is given, to the nearest five beats a minute. With no live
/// reading it does not beat: a heart moving at a made-up pace would be showing a rate nobody measured.
struct BeatingHeart: View {
    let bpm: Int?
    var size: CGFloat = 11
    var color: Color = Luma.coral

    private var pace: Int? {
        guard let bpm, bpm >= 30, bpm <= 230, !LumaMotion.reduced else { return nil }
        return (bpm + 2) / 5 * 5
    }

    var body: some View {
        if let pace {
            Beat(pace: pace, size: size, color: color).id(pace)
        } else {
            Image(systemName: "heart.fill").font(.system(size: size, weight: .bold)).foregroundStyle(color)
        }
    }

    private struct Beat: View {
        let pace: Int
        let size: CGFloat
        let color: Color
        @State private var full = false

        var body: some View {
            Image(systemName: "heart.fill").font(.system(size: size, weight: .bold)).foregroundStyle(color)
                .scaleEffect(full ? 1.26 : 1)
                .onAppear {
                    // Out and back is one beat, so each half takes half the time between beats.
                    withAnimation(.easeOut(duration: 30.0 / Double(pace)).repeatForever(autoreverses: true)) { full = true }
                }
        }
    }
}

/// The large heart on the heart-rate screen: a halo and a heart that swell once a beat.
struct PulsingHeart: View {
    let bpm: Int?

    private var pace: Int? {
        guard let bpm, bpm >= 30, bpm <= 230, !LumaMotion.reduced else { return nil }
        return (bpm + 2) / 5 * 5
    }

    var body: some View {
        if let pace {
            Pulse(pace: pace).id(pace)
        } else {
            PulsingHeart.mark(full: false)
        }
    }

    fileprivate static func mark(full: Bool) -> some View {
        ZStack {
            Circle().fill(Luma.coral.opacity(0.16)).frame(width: 112, height: 112).scaleEffect(full ? 1.14 : 0.94)
            Circle().fill(Luma.coral.opacity(0.24)).frame(width: 78, height: 78)
            Image(systemName: "heart.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(Luma.coral)
                .scaleEffect(full ? 1.08 : 1)
        }
        .frame(width: 120, height: 120)
        .accessibilityHidden(true)
    }

    private struct Pulse: View {
        let pace: Int
        @State private var full = false

        var body: some View {
            PulsingHeart.mark(full: full)
                .onAppear {
                    withAnimation(.easeOut(duration: 30.0 / Double(pace)).repeatForever(autoreverses: true)) { full = true }
                }
        }
    }
}

// MARK: - Shimmer

/// A band of light that crosses a placeholder while what it stands for is being worked out.
struct LumaShimmer: ViewModifier {
    @State private var phase: CGFloat = -0.7

    func body(content: Content) -> some View {
        content
            .overlay {
                if !LumaMotion.reduced {
                    GeometryReader { geo in
                        LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.26), Color.white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !LumaMotion.reduced else { return }
                withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) { phase = 1.1 }
            }
    }
}

extension View {
    func lumaShimmer() -> some View { modifier(LumaShimmer()) }
}

/// Stand-in rows shown while photos are being read: the shape of what is coming, shimmering.
struct ReadingRows: View {
    let caption: String
    var rows: Int = 4

    private static let titles: [CGFloat] = [150, 118, 172, 134, 160]
    private static let details: [CGFloat] = [96, 132, 84, 110, 124]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Luma.mist)
                Text(caption).font(LumaFont.body(13.5, .medium)).foregroundStyle(Luma.mist)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<rows, id: \.self) { i in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.10)).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 7) {
                            Capsule().fill(Color.white.opacity(0.13)).frame(width: ReadingRows.titles[i % 5], height: 10)
                            Capsule().fill(Color.white.opacity(0.08)).frame(width: ReadingRows.details[i % 5], height: 8)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .lumaShimmer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumaPanel(radius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
    }
}

// MARK: - A new best

/// A lift's estimated max passing its previous best.
struct LumaBest: Equatable, Identifiable {
    let id = UUID()
    let lift: String
    let kg: Double
    let previous: Double

    static func == (a: LumaBest, b: LumaBest) -> Bool { a.id == b.id }
}

/// Shown once, over whatever screen is up, when a saved session holds a new best: the figure counts
/// up from the old best to the new one and a light crosses the banner.
struct NewBestBanner: View {
    let best: LumaBest
    @State private var shown: Double
    @State private var sweep: CGFloat = -0.7

    init(best: LumaBest) {
        self.best = best
        _shown = State(initialValue: LumaMotion.reduced ? best.kg : best.previous)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "trophy.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(Luma.ink)
                .frame(width: 44, height: 44).background(Circle().fill(Luma.volt))
            VStack(alignment: .leading, spacing: 1) {
                Text("New best").font(LumaFont.label(11)).foregroundStyle(Luma.volt)
                Text(best.lift).font(LumaFont.heading(17)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.75)
                Text("Estimated max, up from \(LumaText.kg(best.previous.rounded())) kg").font(LumaFont.body(12)).foregroundStyle(Luma.mist).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                RollingNumber(value: shown) { String(format: "%.0f", $0) }.font(LumaFont.numeral(40, .heavy)).foregroundStyle(Luma.frost)
                Text("kg").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist)
            }
        }
        .padding(14)
        .background(LumaPanel(tint: Luma.volt, radius: 24))
        .overlay {
            GeometryReader { geo in
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.22), Color.white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.45)
                    .offset(x: sweep * geo.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        .onAppear {
            guard !LumaMotion.reduced else { return }
            withAnimation(.easeOut(duration: 1.1).delay(0.25)) { shown = best.kg }
            withAnimation(.easeInOut(duration: 0.9).delay(0.35)) { sweep = 1.2 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New best. \(best.lift): estimated max \(Int(best.kg.rounded())) kilograms, up from \(Int(best.previous.rounded())).")
    }
}

// MARK: - A tile that opens into its screen

/// Where a pushed screen grows from. The tile that was tapped names itself just before the push; the
/// screen takes the name once, as it is made, and keeps it, so it closes back into the same tile.
enum LumaZoom {
    static var pending: String?
}

private struct LumaZoomKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var lumaZoom: Namespace.ID? {
        get { self[LumaZoomKey.self] }
        set { self[LumaZoomKey.self] = newValue }
    }
}

struct LumaZoomSource: ViewModifier {
    let name: String
    @Environment(\.lumaZoom) private var space

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let space, !LumaMotion.reduced {
            content.matchedTransitionSource(id: name, in: space)
        } else {
            content
        }
    }
}

struct LumaZoomTarget: ViewModifier {
    @State private var name: String? = LumaZoom.pending
    @Environment(\.lumaZoom) private var space

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let space, let name, !LumaMotion.reduced {
            content.navigationTransition(.zoom(sourceID: name, in: space))
        } else {
            content
        }
    }
}

extension View {
    /// Marks a tile as the place its screen opens from. Push with `router.push(_:from:)` and the same name.
    func lumaZoomSource(_ name: String) -> some View { modifier(LumaZoomSource(name: name)) }
}
