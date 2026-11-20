import SwiftUI

// MARK: - Glimm, drawn

/// How Glimm is inked: in colour, or in light and dark only for the Lock Screen's material.
public enum GlimmInk: Equatable, Sendable {
    case color, mono
}

public enum GlimmLook {
    /// The everyday look: a coral zip hoodie, teal joggers, lilac trainers and a lilac bag.
    public static let signature = "zip:FF766B:plain|joggers:36BFB0:plain|chunky:B5A0EF:plain|-|bag:B5A0EF:plain"

    /// The moods Glimm can be drawn in.
    public static let moods = ["joyful", "steady", "tired", "asleep", "sleepy", "focused", "proud", "celebrating", "resting", "thirsty", "hungry",
                               "curious", "cheeky", "surprised"]

    /// The mood each state of the day is drawn in.
    public static func mood(_ kind: BuddyKind) -> String {
        switch kind {
        case .waiting: return "curious"
        case .training: return "focused"
        case .sleeping: return "asleep"
        case .celebrating: return "celebrating"
        case .worked: return "proud"
        case .unwell: return "resting"
        case .sleepy: return "sleepy"
        case .thirsty: return "thirsty"
        case .hungry: return "hungry"
        case .drained: return "tired"
        case .steady: return "steady"
        case .charged: return "joyful"
        }
    }

    /// Which part of Glimm a touch lands on ("leaf", "head", "cheek", "belly", "hand", "feet"), for a
    /// figure drawn to fit `size`; nil for the air about it.
    public static func zone(at point: CGPoint, in size: CGSize) -> String? {
        let s = min(size.width / CGFloat(GlimmRig.width), size.height / CGFloat(GlimmRig.height))
        guard s > 0 else { return nil }
        let left = (size.width - CGFloat(GlimmRig.width) * s) / 2, top = (size.height - CGFloat(GlimmRig.height) * s) / 2
        return GlimmRig.zone(x: Double((point.x - left) / s), y: Double((point.y - top) / s))
    }

    /// How long a gesture, or the answer to a touch, takes to play, in seconds.
    public static func duration(gesture name: String) -> Double { GlimmRig.duration(gesture: name) }
    public static func duration(tap name: String) -> Double { GlimmRig.duration(tap: name) }
}

extension GColor {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Glimm, drawn to fit its frame.
///
/// With `time` it is drawn afresh for that moment, on a canvas: the app moves it this way. Without,
/// it stands still as a stack of shapes, each at its place and angle, and the system animates the
/// change from one pose to the next: that is how a widget moves it. `flat` draws a still one on a
/// canvas too, as one view, for a screen that shows many at once.
public struct GlimmFigure: View {
    let mood: String
    let outfit: String
    let ink: GlimmInk
    let beat: Int
    let time: Double?
    let energy: Double
    let tap: GlimmAct?
    let play: GlimmAct?
    let flat: Bool

    public init(mood: String, outfit: String? = nil, ink: GlimmInk = .color, beat: Int = 0, time: Double? = nil, energy: Double = 0.6,
                tap: GlimmAct? = nil, play: GlimmAct? = nil, flat: Bool = false) {
        self.mood = mood
        self.outfit = (outfit ?? "").isEmpty ? GlimmLook.signature : (outfit ?? "")
        self.ink = ink; self.beat = beat; self.time = time; self.energy = energy; self.tap = tap; self.play = play; self.flat = flat
    }

    public init(kind: BuddyKind, outfit: String? = nil, ink: GlimmInk = .color, beat: Int = 0, time: Double? = nil, energy: Double = 0.6,
                tap: GlimmAct? = nil, play: GlimmAct? = nil, flat: Bool = false) {
        self.init(mood: GlimmLook.mood(kind), outfit: outfit, ink: ink, beat: beat, time: time, energy: energy, tap: tap, play: play, flat: flat)
    }

    public var body: some View {
        let pose = GlimmRig.pose(mood, t: time, beat: beat, energy: energy, tap: tap, play: play)
        let parts = GlimmRig.parts(pose, outfit: outfit, mono: ink == .mono)
        let turn = pose["turn"]
        GeometryReader { geo in
            let s = min(geo.size.width / CGFloat(GlimmRig.width), geo.size.height / CGFloat(GlimmRig.height))
            Group {
                if time != nil || flat {
                    Canvas { context, _ in
                        var c = context
                        // A spin: the picture narrows to nothing about its middle and opens again.
                        if turn > 0 {
                            let k = max(0.04, abs(cos(turn * Double.pi)))
                            c.translateBy(x: 50 * s, y: 0)
                            c.scaleBy(x: CGFloat(k), y: 1)
                            c.translateBy(x: -50 * s, y: 0)
                        }
                        for p in parts { GlimmDraw.part(c, p, s) }
                    }
                } else {
                    ZStack {
                        ForEach(parts) { GlimmPartView(p: $0, s: s) }
                    }
                    .animation(LumaMotion.reduced ? nil : .spring(response: 0.55, dampingFraction: 0.62), value: "\(mood)|\(beat)|\(outfit)")
                }
            }
            .frame(width: CGFloat(GlimmRig.width) * s, height: CGFloat(GlimmRig.height) * s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

enum GlimmDraw {
    /// A part's outline about (0, 0), at the size it is drawn.
    static func path(_ p: GlimmPart, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> Path {
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        switch p.sh {
        case .el:
            return Path(ellipseIn: rect)
        case .cap:
            return Path(roundedRect: rect, cornerRadius: min(w, h) / 2)
        case .rr:
            return Path(roundedRect: rect, cornerRadius: min(CGFloat(p.r) * s, w / 2, h / 2))
        case .path, .txt:
            var path = Path()
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x - 0.5) * w, y: CGFloat(y - 0.5) * h) }
            for op in p.ops ?? [] {
                switch op {
                case .m(let x, let y): path.move(to: pt(x, y))
                case .l(let x, let y): path.addLine(to: pt(x, y))
                case .q(let a, let b, let x, let y): path.addQuadCurve(to: pt(x, y), control: pt(a, b))
                case .c(let a, let b, let c, let d, let x, let y): path.addCurve(to: pt(x, y), control1: pt(a, b), control2: pt(c, d))
                case .z: path.closeSubpath()
                }
            }
            return path
        }
    }

    static func flat(_ f: GPaint?) -> Color {
        switch f {
        case .solid(let c)?: return c.color
        case .lin(let a, _, _, _, _, _)?: return a.color
        case .rad(let a, _, _, _, _)?: return a.color
        case nil: return .white
        }
    }

    // MARK: On a canvas

    static func shading(_ f: GPaint, _ w: CGFloat, _ h: CGFloat) -> GraphicsContext.Shading {
        switch f {
        case .solid(let c):
            return .color(c.color)
        case .lin(let a, let b, let x0, let y0, let x1, let y1):
            let from = CGPoint(x: CGFloat(x0 - 0.5) * w, y: CGFloat(y0 - 0.5) * h)
            let to = CGPoint(x: CGFloat(x1 - 0.5) * w, y: CGFloat(y1 - 0.5) * h)
            return .linearGradient(Gradient(colors: [a.color, b.color]), startPoint: from, endPoint: to)
        case .rad(let a, let b, let cx, let cy, let r):
            let centre = CGPoint(x: CGFloat(cx - 0.5) * w, y: CGFloat(cy - 0.5) * h)
            return .radialGradient(Gradient(colors: [a.color, b.color]), center: centre, startRadius: 0, endRadius: CGFloat(r) * max(w, h))
        }
    }

    static func part(_ context: GraphicsContext, _ p: GlimmPart, _ s: CGFloat) {
        guard p.o > 0.001 else { return }
        var c = context
        c.translateBy(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s)
        c.rotate(by: .degrees(p.rot))
        if p.flip { c.scaleBy(x: -1, y: 1) }
        c.opacity *= p.o
        let w = CGFloat(p.w) * s, h = CGFloat(p.h) * s
        if p.sh == .txt {
            let text = Text(p.txt ?? "").font(.system(size: h, weight: .heavy, design: .rounded)).foregroundColor(flat(p.fill))
            c.draw(text, at: .zero, anchor: .center)
            return
        }
        let outline = path(p, w, h, s)
        if let f = p.fill { c.fill(outline, with: shading(f, w, h)) }
        if !p.kids.isEmpty {
            var inside = c
            inside.clip(to: outline)
            for kid in p.kids { part(inside, kid, s) }
        }
        if let st = p.stroke {
            c.stroke(outline, with: .color(st.color.color), style: StrokeStyle(lineWidth: CGFloat(st.width) * s, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: As shapes

    static func style(_ f: GPaint, _ w: CGFloat, _ h: CGFloat) -> AnyShapeStyle {
        switch f {
        case .solid(let c):
            return AnyShapeStyle(c.color)
        case .lin(let a, let b, let x0, let y0, let x1, let y1):
            return AnyShapeStyle(LinearGradient(colors: [a.color, b.color], startPoint: UnitPoint(x: x0, y: y0), endPoint: UnitPoint(x: x1, y: y1)))
        case .rad(let a, let b, let cx, let cy, let r):
            return AnyShapeStyle(RadialGradient(colors: [a.color, b.color], center: UnitPoint(x: cx, y: cy), startRadius: 0, endRadius: CGFloat(r) * max(w, h)))
        }
    }
}

/// A part's outline as a shape, filling the frame it is given.
struct GlimmOutline: Shape {
    let p: GlimmPart
    let s: CGFloat

    func path(in rect: CGRect) -> Path {
        GlimmDraw.path(p, rect.width, rect.height, s).offsetBy(dx: rect.midX, dy: rect.midY)
    }
}

/// One part as a view: its place and its turn are what the system animates from one pose to the next.
struct GlimmPartView: View {
    let p: GlimmPart
    let s: CGFloat

    var body: some View {
        let w = CGFloat(p.w) * s, h = CGFloat(p.h) * s
        GlimmPiece(p: p, s: s, w: w, h: h) {
            if !p.kids.isEmpty {
                ZStack {
                    ForEach(p.kids) { kid in
                        let kw = CGFloat(kid.w) * s, kh = CGFloat(kid.h) * s
                        GlimmPiece(p: kid, s: s, w: kw, h: kh) { EmptyView() }
                            .position(x: w / 2 + CGFloat(kid.x) * s, y: h / 2 + CGFloat(kid.y) * s)
                    }
                }
                .frame(width: w, height: h)
                .clipShape(GlimmOutline(p: p, s: s))
            }
        }
        .position(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s)
    }
}

/// A part at its own size and turn, with whatever is drawn inside it.
struct GlimmPiece<Inside: View>: View {
    let p: GlimmPart
    let s: CGFloat
    let w: CGFloat
    let h: CGFloat
    @ViewBuilder var inside: () -> Inside

    var body: some View {
        content
            .frame(width: w, height: h)
            .scaleEffect(x: p.flip ? -1 : 1, y: 1)
            .rotationEffect(.degrees(p.rot))
            .opacity(p.o)
    }

    @ViewBuilder
    private var content: some View {
        if p.sh == .txt {
            Text(p.txt ?? "").font(.system(size: h, weight: .heavy, design: .rounded)).foregroundStyle(GlimmDraw.flat(p.fill)).fixedSize()
        } else {
            let shape = GlimmOutline(p: p, s: s)
            ZStack {
                if let f = p.fill { shape.fill(GlimmDraw.style(f, w, h)) }
                inside()
                if let st = p.stroke {
                    shape.stroke(st.color.color, style: StrokeStyle(lineWidth: CGFloat(st.width) * s, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
