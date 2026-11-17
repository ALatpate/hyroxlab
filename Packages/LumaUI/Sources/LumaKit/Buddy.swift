import SwiftUI

// MARK: - The companion, drawn

/// The states the companion is drawn in. The raw values are the ones the app's rules give
/// (`BuddyMood` in LumaCore); this target has no dependencies, so it carries its own copy of the names.
public enum BuddyKind: String, CaseIterable, Sendable {
    case waiting, training, sleeping, celebrating, worked, unwell, sleepy, thirsty, hungry, drained, steady, charged
}

/// The companion's build: how far each part has grown, 0 (the plain build) to 1.
public struct BuddyShape: Equatable, Sendable {
    public var shoulders: Double
    public var chest: Double
    public var back: Double
    public var arms: Double
    public var core: Double
    public var legs: Double

    public static let plain = BuddyShape(levels: [])

    /// Strength levels 0…5 in the order shoulders, chest, back, arms, core, legs. A negative or missing
    /// level is a part no lift measures: it is drawn at the plain build.
    public init(levels: [Double]) {
        func part(_ i: Int) -> Double { i < levels.count && levels[i] >= 0 ? min(1, levels[i] / 5) : 0 }
        shoulders = part(0); chest = part(1); back = part(2); arms = part(3); core = part(4); legs = part(5)
    }
}

public enum BuddyStyle: Equatable {
    /// Full colour, with the light on its head in the given colour.
    case color(spark: Color)
    /// White on the Lock Screen's material, where only light and dark carry.
    case vibrant
}

enum BuddyEyes { case open, up, happy, closed, half, wince }
enum BuddyMouth { case smile, grin, flat, o, yawn, wavy, tongue }
enum BuddyProp { case none, sparkle, stars, zzz, sweat, drop, thermo, rumble, question }

/// Joint angles and face. Shoulders, elbows, hips and knees are degrees from straight down, opening
/// outwards; an elbow or a knee adds to the joint above it. `bob` lifts (negative) or sinks the hips.
struct BuddyPose {
    var shL = 14.0, shR = 14.0, elL = 10.0, elR = 10.0
    var hipL = 5.0, hipR = 5.0, knL = 0.0, knR = 0.0
    var bob = 0.0, lean = 0.0, headTilt = 0.0, headDX = 0.0, headDY = 0.0
    var droop = 0.0, spark = 1.0, sparkSway = 0.0, look = 0.0, propLift = 0.0
    var eyes = BuddyEyes.open
    var mouth = BuddyMouth.smile
    var prop = BuddyProp.none

    static func base(_ kind: BuddyKind) -> BuddyPose {
        var p = BuddyPose()
        switch kind {
        case .steady:
            break
        case .charged:
            p.shL = 92; p.shR = 92; p.elL = 86; p.elR = 86; p.hipL = 9; p.hipR = 9
            p.eyes = .happy; p.mouth = .grin; p.bob = -1.5; p.spark = 1.25; p.prop = .sparkle
        case .drained:
            p.shL = 5; p.shR = 5; p.elL = 4; p.elR = 4; p.hipL = 3; p.hipR = 3
            p.eyes = .half; p.mouth = .flat; p.lean = 5; p.headTilt = 9; p.headDY = 2.5; p.droop = 1; p.bob = 1.5
        case .sleeping:
            p.shL = 20; p.shR = 20; p.elL = -34; p.elR = -34; p.hipL = 74; p.hipR = 74; p.knL = -152; p.knR = -152
            p.eyes = .closed; p.mouth = .o; p.headTilt = 12; p.headDY = 4; p.droop = 1; p.bob = 17; p.prop = .zzz
        case .sleepy:
            p.shL = 10; p.shR = 50; p.elL = 6; p.elR = 152; p.hipL = 4; p.hipR = 4
            p.eyes = .half; p.mouth = .yawn; p.headTilt = -6; p.droop = 0.6
        case .training:
            p.shL = -28; p.shR = 42; p.elL = 95; p.elR = 95; p.hipL = -24; p.hipR = 30; p.knL = -8; p.knR = -62
            p.mouth = .o; p.lean = 6; p.bob = -3; p.prop = .sweat
        case .worked:
            p.shL = 46; p.shR = 46; p.elL = -92; p.elR = -92; p.hipL = 8; p.hipR = 8
            p.eyes = .happy; p.mouth = .grin; p.prop = .sweat
        case .celebrating:
            p.shL = 146; p.shR = 146; p.elL = 10; p.elR = 10; p.hipL = 22; p.hipR = 22
            p.eyes = .happy; p.mouth = .grin; p.bob = -7; p.spark = 1.3; p.prop = .stars
        case .unwell:
            p.shL = 22; p.shR = 22; p.elL = -98; p.elR = -98; p.hipL = 3; p.hipR = 3
            p.eyes = .wince; p.mouth = .wavy; p.lean = 4; p.headTilt = 7; p.headDY = 2; p.droop = 0.9; p.prop = .thermo
        case .thirsty:
            p.shL = 8; p.shR = 64; p.elL = 6; p.elR = 78; p.hipL = 4; p.hipR = 4
            p.eyes = .half; p.mouth = .tongue; p.droop = 0.5; p.prop = .drop
        case .hungry:
            p.shL = 24; p.shR = 24; p.elL = -104; p.elR = -104; p.hipL = 4; p.hipR = 4
            p.eyes = .up; p.mouth = .o; p.droop = 0.4; p.prop = .rumble
        case .waiting:
            p.shL = 10; p.shR = 118; p.elL = 6; p.elR = 62; p.hipL = 4; p.hipR = 4
            p.look = 1; p.mouth = .flat; p.headTilt = -7; p.prop = .question
        }
        return p
    }

    /// The pose for a state. `beat` picks one of the small still variations a widget moves between (1 is
    /// a blink, 2 a glance aside, 3 a tilt; 10 and 11 are the two steps of a tap reaction). `time`, in
    /// seconds, moves it continuously for the app, and `poke` (0…1) is how far through a tap reaction it is.
    static func make(_ kind: BuddyKind, beat: Int = 0, time: Double? = nil, energy: Double = 0.6, poke: Double? = nil) -> BuddyPose {
        var p = base(kind)
        let awake = p.eyes == .open || p.eyes == .up
        switch beat {
        case 1: if awake { p.eyes = .closed }
        case 2: p.headDX -= 1.6; p.look = p.look == 0 ? -1 : -p.look
        case 3: p.headTilt += 4; p.shL += 7; p.spark *= 1.06
        case 10: p.react(0.5, kind)
        case 11: p.react(0.82, kind)
        default: break
        }
        if let t = time { p.move(kind, t, energy: energy, awake: awake) }
        if let poke { p.react(poke, kind) }
        return p
    }

    private mutating func move(_ kind: BuddyKind, _ t: Double, energy: Double, awake: Bool) {
        let tau = 2 * Double.pi
        let live = 0.45 + 0.55 * energy
        let breathe = sin(t * tau * 0.24)
        bob += 0.7 * breathe
        shL += 1.5 * breathe; shR += 1.5 * breathe
        spark *= 1 + 0.05 * sin(t * tau * 0.9)
        sparkSway = 5 * sin(t * tau * 0.45) * live
        if awake, t.truncatingRemainder(dividingBy: 4.2) < 0.13 { eyes = .closed }
        switch kind {
        case .charged:
            let hop = abs(sin(t * tau * 0.9))
            bob -= 3.2 * hop * live
            let pump = sin(t * tau * 0.9)
            elL += 9 * pump; elR += 9 * pump
        case .celebrating:
            let hop = abs(sin(t * tau * 1.25))
            bob -= 6.5 * hop
            hipL += 8 * hop; hipR += 8 * hop
            let wave = sin(t * tau * 2.5)
            shL += 9 * wave; shR -= 9 * wave
        case .training:
            let s = sin(t * tau * 2.3)
            shL = 7 - 35 * s; shR = 7 + 35 * s
            hipL = 3 + 27 * s; hipR = 3 - 27 * s
            knL = -35 - 27 * s; knR = -35 + 27 * s
            bob -= 2.2 * abs(cos(t * tau * 2.3))
        case .sleeping:
            let slow = sin(t * tau * 0.14)
            bob += 0.9 * slow; headDY += 0.8 * slow
            propLift = (t * 0.32).truncatingRemainder(dividingBy: 1)
        case .sleepy:
            let cycle = t.truncatingRemainder(dividingBy: 5) / 5
            let yawn = cycle < 0.45 ? sin(min(1, cycle / 0.45) * Double.pi) : 0
            mouth = yawn > 0.35 ? .yawn : .flat
            elR = 20 + 132 * yawn; shR = 12 + 38 * yawn
            headTilt += 3 * sin(t * tau * 0.2)
        case .drained:
            lean += 1.6 * sin(t * tau * 0.16)
            headDY += 0.8 * sin(t * tau * 0.16 + 1)
        case .worked:
            bob += 0.9 * sin(t * tau * 0.55)
            propLift = (t * 0.5).truncatingRemainder(dividingBy: 1)
        case .unwell:
            if t.truncatingRemainder(dividingBy: 3) < 0.9 { headDX += 0.35 * sin(t * tau * 7) }
        case .thirsty:
            elR += 6 * sin(t * tau * 0.5)
        case .hungry:
            let rub = sin(t * tau * 0.7)
            elL += 5 * rub; elR -= 5 * rub
        case .waiting:
            let side = sin(t * tau * 0.18)
            headDX += 1.8 * side; look = side > 0 ? 1 : -1
        case .steady:
            headTilt += 2.2 * sin(t * tau * 0.13)
        }
    }

    /// A tap: a hop with a wave. Asleep, it opens an eye and settles again.
    private mutating func react(_ poke: Double, _ kind: BuddyKind) {
        let through = min(1, max(0, poke))
        guard kind != .sleeping else {
            eyes = through < 0.7 ? .half : .closed
            headTilt -= 6 * sin(through * Double.pi)
            return
        }
        let up = sin(through * Double.pi)
        bob -= 7 * up
        eyes = .happy; mouth = .grin
        shR += (150 - shR) * up
        elR += (20 - elR) * up + 16 * sin(through * Double.pi * 6) * up
    }
}

/// One simple shape of the figure, in a 100 by 120 box.
struct BuddyPart: Identifiable {
    enum Kind { case capsule, rrect, ellipse, torso, spark, eye, mouth, prop }
    enum Role { case body, line, ink, blush, spark, prop }
    enum Group { case legs, torso, marks, arms, head, face, prop }

    let id: String
    let group: Group
    let kind: Kind
    var cx: Double
    var cy: Double
    var w: Double
    var h: Double
    var rot: Double = 0
    var role: Role = .body
    var radius: Double = 0
    var top: Double = 0
    var waist: Double = 0
    var side: Double = 1
}

enum BuddyRig {
    static let width = 100.0
    static let height = 120.0

    private static func direction(_ degrees: Double, _ side: Double) -> (x: Double, y: Double) {
        let r = degrees * Double.pi / 180
        return (side * sin(r), cos(r))
    }

    /// The figure's parts, back to front. Limbs are capsules turned about their joints, so a change of
    /// pose is a change of position and angle, which is what a widget can animate between two entries.
    static func parts(_ p: BuddyPose, shape b: BuddyShape) -> [BuddyPart] {
        var parts: [BuddyPart] = []
        let cx = 50.0
        let hipY = 88.0 + p.bob
        let top = 13.0 + 5.5 * b.shoulders + 2.0 * b.chest + 2.0 * b.back
        let waist = 10.0 + 1.6 * b.core + 1.0 * b.legs
        let torsoH = 31.0
        let lr = p.lean * Double.pi / 180
        func body(_ dx: Double, _ dy: Double) -> (x: Double, y: Double) {
            (cx + dx * cos(lr) - dy * sin(lr), hipY + dx * sin(lr) + dy * cos(lr))
        }

        let legW = 8.0 + 6.5 * b.legs
        let thigh = 12.0, shin = 11.0
        let hipX = 5.6 + 1.6 * b.legs
        for (side, name) in [(-1.0, "L"), (1.0, "R")] {
            let a1 = side < 0 ? p.hipL : p.hipR
            let a2 = a1 + (side < 0 ? p.knL : p.knR)
            let jx = cx + side * hipX, jy = hipY - 1.5
            let d1 = direction(a1, side)
            let kx = jx + d1.x * thigh, ky = jy + d1.y * thigh
            let d2 = direction(a2, side)
            let fx = kx + d2.x * shin, fy = ky + d2.y * shin
            parts.append(BuddyPart(id: "thigh" + name, group: .legs, kind: .capsule, cx: (jx + kx) / 2, cy: (jy + ky) / 2, w: legW, h: thigh + legW,
                                   rot: -side * a1))
            parts.append(BuddyPart(id: "shin" + name, group: .legs, kind: .capsule, cx: (kx + fx) / 2, cy: (ky + fy) / 2, w: legW * 0.84,
                                   h: shin + legW * 0.84, rot: -side * a2))
            parts.append(BuddyPart(id: "foot" + name, group: .legs, kind: .rrect, cx: fx + side * 2.2, cy: fy + 1.2, w: 11.0 + 1.5 * b.legs, h: 6.6,
                                   rot: -side * a2 * 0.25, radius: 3.2))
        }

        let t = body(0, -torsoH / 2 + 1)
        parts.append(BuddyPart(id: "torso", group: .torso, kind: .torso, cx: t.x, cy: t.y, w: top * 2, h: torsoH, rot: p.lean, top: top, waist: waist))
        if b.core >= 0.5 {
            for k in 0..<2 {
                let a = body(0, -8.5 - Double(k) * 5.0)
                parts.append(BuddyPart(id: "ab\(k)", group: .marks, kind: .capsule, cx: a.x, cy: a.y, w: waist * 0.72, h: 0.9, rot: p.lean, role: .line))
            }
        }
        if b.chest >= 0.5 {
            for (i, side) in [-1.0, 1.0].enumerated() {
                let c = body(side * top * 0.36, -20.5)
                parts.append(BuddyPart(id: "pec\(i)", group: .marks, kind: .capsule, cx: c.x, cy: c.y, w: top * 0.52, h: 0.9, rot: p.lean, role: .line))
            }
        }

        let armW = 6.2 + 5.2 * b.arms
        let upper = 13.0, fore = 12.0
        for (side, name) in [(-1.0, "L"), (1.0, "R")] {
            let a1 = side < 0 ? p.shL : p.shR
            let a2 = a1 + (side < 0 ? p.elL : p.elR)
            let j = body(side * (top - 1.2), -torsoH + 6.5)
            let d1 = direction(a1, side)
            let ex = j.x + d1.x * upper, ey = j.y + d1.y * upper
            let d2 = direction(a2, side)
            let hx = ex + d2.x * fore, hy = ey + d2.y * fore
            let delt = armW + 3.0 + 4.0 * b.shoulders
            parts.append(BuddyPart(id: "delt" + name, group: .arms, kind: .ellipse, cx: j.x, cy: j.y, w: delt, h: delt))
            parts.append(BuddyPart(id: "arm" + name, group: .arms, kind: .capsule, cx: (j.x + ex) / 2, cy: (j.y + ey) / 2,
                                   w: armW * (1.0 + 0.18 * b.arms), h: upper + armW, rot: -side * a1))
            parts.append(BuddyPart(id: "fore" + name, group: .arms, kind: .capsule, cx: (ex + hx) / 2, cy: (ey + hy) / 2, w: armW * 0.86,
                                   h: fore + armW * 0.86, rot: -side * a2))
            let hand = armW * 0.95 + 2.2
            parts.append(BuddyPart(id: "hand" + name, group: .arms, kind: .ellipse, cx: hx, cy: hy, w: hand, h: hand))
        }

        let turn = p.headTilt + p.lean
        let neck = body(0, -torsoH + 1.0)
        let hx = neck.x + p.headDX, hy = neck.y - 20.5 + p.headDY
        let tr = turn * Double.pi / 180
        func head(_ dx: Double, _ dy: Double) -> (x: Double, y: Double) {
            (hx + dx * cos(tr) - dy * sin(tr), hy + dx * sin(tr) + dy * cos(tr))
        }
        let scale = p.spark * (1.0 - 0.25 * p.droop)
        let crown = head(0, -22.0)
        let lift = 6.2 * scale * (1 - 0.55 * p.droop)
        let sparkTurn = turn + 78.0 * p.droop + p.sparkSway
        let sr = sparkTurn * Double.pi / 180
        parts.append(BuddyPart(id: "spark", group: .head, kind: .spark, cx: crown.x + sin(sr) * lift, cy: crown.y - cos(sr) * lift, w: 10.5 * scale,
                               h: 15.0 * scale, rot: sparkTurn, role: .spark))
        parts.append(BuddyPart(id: "head", group: .head, kind: .rrect, cx: hx, cy: hy, w: 52.0, h: 45.0, rot: turn, radius: 20.5))
        for (side, name) in [(-1.0, "L"), (1.0, "R")] {
            let e = head(side * 10.2, 1.6)
            parts.append(BuddyPart(id: "eye" + name, group: .face, kind: .eye, cx: e.x, cy: e.y, w: 14, h: 14, rot: turn, role: .ink, side: side))
            let c = head(side * 17.2, 9.0)
            parts.append(BuddyPart(id: "cheek" + name, group: .face, kind: .ellipse, cx: c.x, cy: c.y, w: 7.4, h: 4.3, rot: turn, role: .blush))
        }
        let m = head(0, 10.8)
        parts.append(BuddyPart(id: "mouth", group: .face, kind: .mouth, cx: m.x, cy: m.y, w: 16, h: 16, rot: turn, role: .ink))
        if p.prop != .none {
            parts.append(BuddyPart(id: "prop", group: .prop, kind: .prop, cx: hx, cy: hy, w: 100, h: 100, role: .prop))
        }
        return parts
    }
}

// MARK: - Shapes

/// The body: wide at the shoulders, narrower at the hips, every corner rounded.
struct BuddyTorso: Shape {
    let top: Double
    let waist: Double

    func path(in rect: CGRect) -> Path {
        let u = top > 0 ? rect.width / CGFloat(top * 2) : 1
        let t = CGFloat(top) * u, w = CGFloat(waist) * u, h = rect.height
        let x = rect.midX, y = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x - t + 5 * u, y: y))
        p.addLine(to: CGPoint(x: x + t - 5 * u, y: y))
        p.addQuadCurve(to: CGPoint(x: x + t - 0.6 * u, y: y + 5 * u), control: CGPoint(x: x + t, y: y))
        p.addLine(to: CGPoint(x: x + w + 0.4 * u, y: y + h - 6 * u))
        p.addQuadCurve(to: CGPoint(x: x + w - 5 * u, y: y + h), control: CGPoint(x: x + w, y: y + h))
        p.addLine(to: CGPoint(x: x - w + 5 * u, y: y + h))
        p.addQuadCurve(to: CGPoint(x: x - w - 0.4 * u, y: y + h - 6 * u), control: CGPoint(x: x - w, y: y + h))
        p.addLine(to: CGPoint(x: x - t + 0.6 * u, y: y + 5 * u))
        p.addQuadCurve(to: CGPoint(x: x - t + 5 * u, y: y), control: CGPoint(x: x - t, y: y))
        p.closeSubpath()
        return p
    }
}

/// The light on its head: a small flame.
struct BuddySpark: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let x = rect.midX, y = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: x, y: y - h / 2))
        p.addCurve(to: CGPoint(x: x, y: y + h / 2), control1: CGPoint(x: x + w * 0.62, y: y - h * 0.05), control2: CGPoint(x: x + w * 0.5, y: y + h / 2))
        p.addCurve(to: CGPoint(x: x, y: y - h / 2), control1: CGPoint(x: x - w * 0.5, y: y + h / 2), control2: CGPoint(x: x - w * 0.62, y: y - h * 0.05))
        p.closeSubpath()
        return p
    }
}

/// The small strokes and fills of the face and the things around it, each drawn about the middle of
/// its box. `unit` is the box's width in figure units, so one path serves every size.
struct BuddyGlyph: Shape {
    enum Kind { case arcUp, arcDown, lid, chevron, smile, smallSmile, flat, wavy, grin, star, drop, rumble }

    let kind: Kind
    var unit: Double = 14
    var side: Double = 1

    func path(in rect: CGRect) -> Path {
        let u = rect.width / CGFloat(unit)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: c.x + CGFloat(x) * u, y: c.y + CGFloat(y) * u) }
        var p = Path()
        switch kind {
        case .arcUp:
            p.move(to: at(-4.2, 1.6)); p.addQuadCurve(to: at(4.2, 1.6), control: at(0, -5.2))
        case .arcDown:
            p.move(to: at(-4.2, 0)); p.addQuadCurve(to: at(4.2, 0), control: at(0, 4.4))
        case .lid:
            p.move(to: at(-4.6, -0.2)); p.addLine(to: at(4.6, -0.2))
        case .chevron:
            p.move(to: at(-3.4 * side, -3)); p.addLine(to: at(3.0 * side, 0)); p.addLine(to: at(-3.4 * side, 3))
        case .smile:
            p.move(to: at(-4.2, -1)); p.addQuadCurve(to: at(4.2, -1), control: at(0, 3.8))
        case .smallSmile:
            p.move(to: at(-4, -0.6)); p.addQuadCurve(to: at(4, -0.6), control: at(0, 2.6))
        case .flat:
            p.move(to: at(-3.4, 0.6)); p.addLine(to: at(3.4, 0.6))
        case .wavy:
            p.move(to: at(-4.6, 1)); p.addQuadCurve(to: at(0, 1), control: at(-2.3, -2)); p.addQuadCurve(to: at(4.6, 1), control: at(2.3, 4))
        case .grin:
            p.move(to: at(-5, -1.6)); p.addQuadCurve(to: at(5, -1.6), control: at(0, 7.4)); p.closeSubpath()
        case .star:
            let r = unit / 2, k = r * 0.28
            p.move(to: at(0, -r))
            for q in [(k, -k), (r, 0), (k, k), (0, r), (-k, k), (-r, 0), (-k, -k)] { p.addLine(to: at(q.0, q.1)) }
            p.closeSubpath()
        case .drop:
            let h = unit / 2
            p.move(to: at(0, -h)); p.addQuadCurve(to: at(0, h), control: at(h * 0.9, h * 0.32))
            p.addQuadCurve(to: at(0, -h), control: at(-h * 0.9, h * 0.32)); p.closeSubpath()
        case .rumble:
            p.move(to: at(-2.2, -3.5)); p.addQuadCurve(to: at(-2.2, 1.5), control: at(0.8, -1.5))
            p.move(to: at(2.3, -5.5)); p.addQuadCurve(to: at(2.3, 3.5), control: at(6.7, -1.1))
        }
        return p
    }
}

// MARK: - The figure

struct BuddyPalette {
    let body: Color
    let line: Color
    let ink: Color
    let blush: Color
    let spark: Color
    let prop: Color
    let water: Color
    /// The colour of the outline that separates a limb from what it crosses.
    let ground: Color
    let highlight: Bool

    static func of(_ style: BuddyStyle) -> BuddyPalette {
        switch style {
        case .color(let spark):
            return BuddyPalette(body: Luma.frost, line: Color(hex: 0xB9C3D6), ink: Color(hex: 0x0A0D12), blush: Color(hex: 0xFF7A93), spark: spark,
                                prop: Luma.mist, water: Luma.sky, ground: Luma.night, highlight: true)
        case .vibrant:
            return BuddyPalette(body: .white, line: Color(white: 0.55), ink: .black, blush: Color(white: 0.74), spark: Color(white: 0.86),
                                prop: Color(white: 0.82), water: Color(white: 0.82), ground: .black, highlight: false)
        }
    }

    func color(_ role: BuddyPart.Role) -> Color {
        switch role {
        case .body: return body
        case .line: return line
        case .ink: return ink
        case .blush: return blush
        case .spark: return spark
        case .prop: return prop
        }
    }
}

/// The companion, drawn to fit its frame. The same view serves the app, where `time` moves it, and the
/// widgets, where it stands still and the system animates the change from one entry's pose to the next.
public struct BuddyFigure: View {
    let kind: BuddyKind
    let shape: BuddyShape
    let style: BuddyStyle
    let beat: Int
    let time: Double?
    let energy: Double
    let poke: Double?

    public init(kind: BuddyKind, shape: BuddyShape = .plain, style: BuddyStyle = .color(spark: Luma.volt), beat: Int = 0, time: Double? = nil,
                energy: Double = 0.6, poke: Double? = nil) {
        self.kind = kind; self.shape = shape; self.style = style; self.beat = beat; self.time = time; self.energy = energy; self.poke = poke
    }

    private struct Layer: Identifiable {
        let id: String
        let part: BuddyPart
        let halo: Bool
    }

    private func layers(_ parts: [BuddyPart]) -> [Layer] {
        var out: [Layer] = []
        var i = 0
        while i < parts.count {
            let group = parts[i].group
            var j = i
            while j < parts.count, parts[j].group == group { j += 1 }
            let run = parts[i..<j]
            // A limb is drawn twice: first wide in the ground colour, then filled. Its pieces then read
            // as one shape with one outline, and stand clear of whatever they cross.
            if group == .legs || group == .torso || group == .arms || group == .head {
                for p in run { out.append(Layer(id: "o-" + p.id, part: p, halo: true)) }
            }
            for p in run { out.append(Layer(id: p.id, part: p, halo: false)) }
            i = j
        }
        return out
    }

    public var body: some View {
        let pose = BuddyPose.make(kind, beat: beat, time: time, energy: energy, poke: poke)
        let all = layers(BuddyRig.parts(pose, shape: shape))
        let palette = BuddyPalette.of(style)
        GeometryReader { geo in
            let s = min(geo.size.width / CGFloat(BuddyRig.width), geo.size.height / CGFloat(BuddyRig.height))
            ZStack {
                ForEach(all) { layer in
                    BuddyPartView(part: layer.part, halo: layer.halo, pose: pose, palette: palette, s: s)
                }
            }
            .frame(width: CGFloat(BuddyRig.width) * s, height: CGFloat(BuddyRig.height) * s)
            // Standing still, a change of pose is animated; moved by the clock, every frame is already drawn.
            .animation(time == nil && !LumaMotion.reduced ? .spring(response: 0.55, dampingFraction: 0.62) : nil, value: kind.rawValue + "|\(beat)")
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct BuddyPartView: View {
    let part: BuddyPart
    let halo: Bool
    let pose: BuddyPose
    let palette: BuddyPalette
    let s: CGFloat

    private var outline: StrokeStyle { StrokeStyle(lineWidth: 3.2 * s, lineJoin: .round) }

    var body: some View {
        content
            .frame(width: CGFloat(part.w) * s, height: CGFloat(part.h) * s)
            .rotationEffect(.degrees(part.rot))
            .position(x: CGFloat(part.cx) * s, y: CGFloat(part.cy) * s)
    }

    @ViewBuilder
    private var content: some View {
        let color = halo ? palette.ground : palette.color(part.role)
        switch part.kind {
        case .capsule:
            solid(Capsule(), color)
        case .ellipse:
            solid(Ellipse(), color).opacity(part.role == .blush ? 0.55 : 1)
        case .rrect:
            solid(RoundedRectangle(cornerRadius: CGFloat(part.radius) * s, style: .continuous), color)
        case .torso:
            solid(BuddyTorso(top: part.top, waist: part.waist), color)
        case .spark:
            solid(BuddySpark(), color)
        case .eye:
            BuddyEye(eyes: pose.eyes, side: part.side, look: pose.look, palette: palette, s: s)
        case .mouth:
            BuddyMouthView(mouth: pose.mouth, palette: palette, s: s)
        case .prop:
            BuddyPropView(prop: pose.prop, lift: pose.propLift, palette: palette, s: s)
        }
    }

    @ViewBuilder
    private func solid<S: Shape>(_ shape: S, _ color: Color) -> some View {
        if halo {
            shape.fill(color).overlay(shape.stroke(color, style: outline))
        } else {
            shape.fill(color)
        }
    }
}

private struct BuddyEye: View {
    let eyes: BuddyEyes
    let side: Double
    let look: Double
    let palette: BuddyPalette
    let s: CGFloat

    private func line(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round) }

    var body: some View {
        ZStack {
            switch eyes {
            case .open, .up:
                let dx = CGFloat(1.5 * look) * s
                let dy: CGFloat = eyes == .up ? -1.6 * s : 0
                Ellipse().fill(palette.ink).frame(width: 7.4 * s, height: 10 * s).offset(x: dx, y: dy)
                if palette.highlight {
                    Circle().fill(Color.white).frame(width: 3 * s, height: 3 * s).offset(x: dx - 1.4 * s, y: dy - 2.4 * s)
                }
            case .happy:
                BuddyGlyph(kind: .arcUp).stroke(palette.ink, style: line(2.3))
            case .closed:
                BuddyGlyph(kind: .arcDown).stroke(palette.ink, style: line(2.3))
            case .half:
                Ellipse().fill(palette.ink).frame(width: 7.4 * s, height: 6.2 * s).offset(y: 1.2 * s)
                Rectangle().fill(palette.body).frame(width: 10.4 * s, height: 5.2 * s).offset(y: -2.8 * s)
                BuddyGlyph(kind: .lid).stroke(palette.ink, style: line(1.8))
            case .wince:
                BuddyGlyph(kind: .chevron, side: side).stroke(palette.ink, style: line(2.2))
            }
        }
    }
}

private struct BuddyMouthView: View {
    let mouth: BuddyMouth
    let palette: BuddyPalette
    let s: CGFloat

    private func line(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round) }

    var body: some View {
        ZStack {
            switch mouth {
            case .smile:
                BuddyGlyph(kind: .smile, unit: 16).stroke(palette.ink, style: line(2.1))
            case .grin:
                BuddyGlyph(kind: .grin, unit: 16).fill(palette.ink)
            case .flat:
                BuddyGlyph(kind: .flat, unit: 16).stroke(palette.ink, style: line(2.1))
            case .o:
                Ellipse().fill(palette.ink).frame(width: 4.6 * s, height: 5.4 * s).offset(y: 0.8 * s)
            case .yawn:
                Ellipse().fill(palette.ink).frame(width: 8 * s, height: 10 * s).offset(y: 1.6 * s)
            case .wavy:
                BuddyGlyph(kind: .wavy, unit: 16).stroke(palette.ink, style: line(2))
            case .tongue:
                BuddyGlyph(kind: .smallSmile, unit: 16).stroke(palette.ink, style: line(2))
                Capsule().fill(palette.blush).frame(width: 3.8 * s, height: 4.4 * s).offset(y: 3.1 * s)
            }
        }
    }
}

/// What floats beside the head: a sparkle, a bead of sweat, a question mark. Placed from the head's centre.
private struct BuddyPropView: View {
    let prop: BuddyProp
    let lift: Double
    let palette: BuddyPalette
    let s: CGFloat

    private func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> some View {
        BuddyGlyph(kind: .star, unit: 2).fill(palette.spark).frame(width: 2 * r * s, height: 2 * r * s).offset(x: x * s, y: y * s)
    }

    private func letter(_ text: String, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Text(text).font(.system(size: size * s, weight: .heavy, design: .rounded)).foregroundStyle(palette.prop).offset(x: x * s, y: y * s)
    }

    var body: some View {
        ZStack {
            switch prop {
            case .none:
                EmptyView()
            case .sparkle:
                star(33, -20, 4.4)
                star(-34, -14, 3.2)
            case .stars:
                star(33, -20, 4.4)
                star(-34, -14, 3.2)
                star(39, 2, 2.6)
                star(-39, 6, 2.2)
            case .zzz:
                let up = CGFloat(lift) * 6
                letter("z", 11, 30, -21 - up)
                letter("z", 8, 36.5, -29.5 - up)
            case .question:
                letter("?", 15, 32, -22)
            case .sweat:
                BuddyGlyph(kind: .drop, unit: 2).fill(palette.water).frame(width: 7.6 * s, height: 7.6 * s)
                    .offset(x: 30 * s, y: (-12.2 + CGFloat(lift) * 5) * s)
            case .drop:
                BuddyGlyph(kind: .drop, unit: 2).stroke(palette.water, style: StrokeStyle(lineWidth: 1.6 * s, lineJoin: .round))
                    .frame(width: 11.6 * s, height: 11.6 * s).offset(x: 33 * s, y: 19.8 * s)
            case .thermo:
                ZStack {
                    Capsule().fill(palette.prop).frame(width: 15 * s, height: 2.8 * s)
                    Circle().fill(palette.blush).frame(width: 5.2 * s, height: 5.2 * s).offset(x: 8 * s)
                }
                .rotationEffect(.degrees(-38)).offset(x: 14 * s, y: 8 * s)
            case .rumble:
                BuddyGlyph(kind: .rumble, unit: 14).stroke(palette.prop, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                    .frame(width: 14 * s, height: 14 * s).offset(x: 24.2 * s, y: 41.5 * s)
            }
        }
    }
}
