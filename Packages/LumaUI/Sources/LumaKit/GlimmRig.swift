import Foundation
import CoreGraphics

// MARK: - Glimm's rig
//
// From a mood and a moment to a flat list of parts (a shape, a place, a paint), back to front. Every
// function here has its twin in Tools/glimm/render.js, which draws the same parts on a canvas.

/// A gesture or a touch under way: which one, and how far through it is (0…1).
public struct GlimmAct: Equatable, Sendable {
    public var name: String
    public var phase: Double

    public init(name: String, phase: Double) { self.name = name; self.phase = phase }
}

struct GStroke: Equatable {
    var color: GColor
    var width: Double
}

/// A paint as drawn. Points are in the shape's own box (0…1).
enum GPaint: Equatable {
    case solid(GColor)
    case lin(GColor, GColor, Double, Double, Double, Double)
    case rad(GColor, GColor, Double, Double, Double)
}

/// One part of the picture: a shape of a size, turned, at a place, in the figure's 100 by 120 box.
struct GlimmPart: Identifiable, Equatable {
    var id: String
    var sh: GShape
    var x: Double, y: Double, w: Double, h: Double, rot: Double
    var r: Double = 0
    var ops: [GOp]?
    var fill: GPaint?
    var stroke: GStroke?
    /// The line about the group of parts this one touches.
    var ol: GStroke?
    var o: Double = 1
    var z: Double = 0
    var flip = false
    var txt: String?
    /// Drawn inside the part and cut to its outline, measured from its middle.
    var kids: [GlimmPart] = []
}

struct GBone {
    var x: Double, y: Double, rot: Double
    var side: Double = 1
}

/// The palette in force, and how what is drawn with it is outlined.
struct GEnv {
    var colors: [String: GRGB]
    var mono = false
    var ol: GToken?
    var olw = 0.5
}

enum GlimmRig {
    static let width = 100.0
    static let height = 120.0

    static func rotv(_ x: Double, _ y: Double, _ deg: Double) -> (Double, Double) {
        let r = deg * Double.pi / 180
        let c = cos(r), s = sin(r)
        return (x * c - y * s, x * s + y * c)
    }

    static func clamp(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, v)) }

    static func smooth(_ x: Double) -> Double {
        let t = clamp(x)
        return t * t * (3 - 2 * t)
    }

    /// A repeatable number in 0..<1 for a whole number: the same slot of time always gives the same choice.
    static func hash(_ n: Double) -> Double {
        let v = sin(n * 12.9898 + 4.1414) * 43758.5453
        return v - v.rounded(.down)
    }

    // MARK: Colour

    private static let skinLike: Set<String> = ["skin", "skinHi", "skinLo", "white", "sole"]

    static func color(_ t: GToken, _ env: GEnv) -> GColor {
        var rgb = t.rgb ?? env.colors[t.name] ?? GRGB(255, 0, 255)
        if t.shade != 0 { rgb = rgb.shaded(t.shade) }
        if env.mono {
            // The Lock Screen keeps only light and dark: skin is the light, everything else keeps its
            // own lightness, pulled apart a little so clothes still read against skin.
            let l = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255
            let g = (255 * clamp(skinLike.contains(t.name) ? 0.97 : 0.1 + 0.72 * l)).rounded()
            rgb = GRGB(g, g, g)
        }
        return GColor(r: rgb.r / 255, g: rgb.g / 255, b: rgb.b / 255, a: t.alpha)
    }

    static func paint(_ spec: GPaintSpec?, _ env: GEnv) -> GPaint? {
        guard let spec else { return nil }
        switch spec {
        case .solid(let t):
            return .solid(color(t, env))
        case .lin(let a, let b, let deg):
            let r = deg * Double.pi / 180
            let dx = cos(r) / 2, dy = sin(r) / 2
            return .lin(color(a, env), color(b, env), 0.5 - dx, 0.5 - dy, 0.5 + dx, 0.5 + dy)
        case .rad(let a, let b, let cx, let cy, let radius):
            return .rad(color(a, env), color(b, env), cx, cy, radius)
        }
    }

    // MARK: Channels: the pose at one moment

    /// One gesture laid over a pose. A gesture is a list of keys (when 0…1, what to set); a channel
    /// starts and ends at the pose's own value unless the gesture keys it there. Numbers ease from key
    /// to key; words (a mouth shape, a prop) switch at their key.
    static func apply(_ g: GGesture, _ ch: inout GlimmPose, _ phase: Double) {
        let base = ch
        var numbers: [String] = []
        var words: [String] = []
        for key in g.keys {
            for k in key.set.n.keys where !numbers.contains(k) { numbers.append(k) }
            for k in key.set.w.keys where !words.contains(k) { words.append(k) }
        }
        for name in numbers {
            var keys: [(Double, Double)] = []
            for key in g.keys { if let v = key.set.n[name] { keys.append((key.at, v)) } }
            guard !keys.isEmpty else { continue }
            if keys[0].0 > 0 { keys.insert((0, base[name]), at: 0) }
            if keys[keys.count - 1].0 < 1 { keys.append((1, base[name])) }
            var v = keys[keys.count - 1].1
            for i in 0..<(keys.count - 1) {
                let a = keys[i].0, va = keys[i].1, b = keys[i + 1].0, vb = keys[i + 1].1
                if phase >= a && phase <= b {
                    v = va + (vb - va) * smooth(b > a ? (phase - a) / (b - a) : 1)
                    break
                }
            }
            ch.n[name] = v
        }
        for name in words {
            var v = base.w[name]
            for key in g.keys { if let value = key.set.w[name], phase >= key.at, phase < 1 { v = value } }
            ch.w[name] = v
        }
    }

    /// The pose of a mood. `beat` picks one of the mood's stills, which a widget moves between; `t`,
    /// in seconds, moves it continuously for the app; `tap` is a touch being answered and `play` a
    /// gesture asked for.
    static func pose(_ mood: String, t: Double? = nil, beat: Int = 0, energy: Double = 0.6, tap: GlimmAct? = nil, play: GlimmAct? = nil) -> GlimmPose {
        let S = GlimmSpec.shared
        let M = S.moods[mood] ?? S.moods["steady"] ?? GMood()
        var ch = S.defaults
        ch.merge(M.base)
        if beat >= 10 {
            if let g = S.taps[beat >= 20 ? "leaf" : "head"] { apply(g, &ch, beat % 10 == 0 ? 0.3 : 0.62) }
        } else if beat > 0, !M.stills.isEmpty {
            let still = M.stills[(beat - 1) % M.stills.count]
            if let name = still.g, let g = S.gestures[name] { apply(g, &ch, still.at) }
            ch.merge(still.set)
        }
        if let t {
            let live = 0.5 + 0.5 * energy
            // What the mood holds differently while it moves, and the marks about it drifting on.
            ch.merge(M.live)
            ch.n["propPhase"] = t * 0.45
            for o in S.breath + M.osc {
                var v = sin(2 * Double.pi * (o.hz * t + o.ph))
                if o.mode == "abs" { v = abs(v) }
                if o.mode == "pos" { v = max(0, v) }
                ch.n[o.ch] = ch[o.ch] + o.amp * v * (o.mode == "calm" ? 1 : live)
            }
            // Blinks: uneven, now and then two together, and none while the eyes are shut or smiling.
            if ch["eyeOpen"] > 0.5, ch["eyeSmile"] < 0.5 {
                let slot = (t / 3.7).rounded(.down)
                let dt = t - (slot * 3.7 + hash(slot) * 2.2)
                if (dt >= 0 && dt < 0.13) || (hash(slot + 91) < 0.28 && dt >= 0.3 && dt < 0.42) { ch.n["eyeOpen"] = 0.04 }
            }
            // A small thing done of its own accord, every few seconds.
            if !M.gestures.isEmpty, tap == nil, play == nil {
                let slot = (t / M.every).rounded(.down)
                let pick = whole((hash(slot * 7 + 3) * Double(M.gestures.count)).rounded(.down)) % M.gestures.count
                if let g = S.gestures[M.gestures[pick]] {
                    let start = slot * M.every + 0.6 + hash(slot * 13 + 5) * max(0, M.every - g.dur - 1.2)
                    if t >= start, t < start + g.dur { apply(g, &ch, (t - start) / g.dur) }
                }
            }
        }
        if let play, let g = S.gestures[play.name] { apply(g, &ch, clamp(play.phase)) }
        if let tap, let g = S.taps[tap.name] { apply(g, &ch, clamp(tap.phase)) }
        return ch
    }

    /// How long a gesture or the answer to a touch lasts, in seconds.
    static func duration(gesture name: String) -> Double { GlimmSpec.shared.gestures[name]?.dur ?? 1 }
    static func duration(tap name: String) -> Double { GlimmSpec.shared.taps[name]?.dur ?? 1 }

    // MARK: Bones

    /// Where each bone is: its joint, and the turn of everything hung from it. A limb at rest points
    /// straight down; angles open outwards, and an elbow or a knee adds to the joint above it. A
    /// planted foot stays where it stands and the knee bends to suit, so a bob or a shift of weight
    /// flexes the legs.
    static func bones(_ ch: GlimmPose) -> [String: GBone] {
        let R = GlimmSpec.shared.rig
        var B: [String: GBone] = [:]
        let rootX = R.rootX + ch["sway"], rootY = R.rootY + ch["bob"] - ch["lift"]
        let lean = ch["lean"]
        B["ground"] = GBone(x: R.rootX, y: R.ground, rot: 0)
        B["torso"] = GBone(x: rootX, y: rootY, rot: lean)
        func T(_ x: Double, _ y: Double) -> (Double, Double) {
            let d = rotv(x, y, lean)
            return (rootX + d.0, rootY + d.1)
        }
        let neck = T(0, -R.torsoLen)
        let hrot = lean * 0.6 + ch["headTilt"]
        let up = rotv(0, -R.neckUp, hrot)
        let head = GBone(x: neck.0 + up.0 + ch["headDX"], y: neck.1 + up.1 + ch["headDY"], rot: hrot)
        B["head"] = head
        let lf = rotv(R.leafX, R.leafY, hrot)
        B["leaf"] = GBone(x: head.x + lf.0, y: head.y + lf.1, rot: hrot + ch["leaf"] + ch["leafDroop"] * R.leafDroop)
        let rad = Double.pi / 180
        for (s, n) in [(-1.0, "L"), (1.0, "R")] {
            let j = T(s * R.shoulderX, R.shoulderY)
            let sh = ch["sh" + n], el = ch["el" + n]
            let r1 = lean - s * sh, r2 = lean - s * (sh + el)
            B["upper" + n] = GBone(x: j.0, y: j.1, rot: r1, side: s)
            let e = rotv(0, R.upper, r1)
            let ex = j.0 + e.0, ey = j.1 + e.1
            B["fore" + n] = GBone(x: ex, y: ey, rot: r2, side: s)
            let h = rotv(0, R.fore, r2)
            B["hand" + n] = GBone(x: ex + h.0, y: ey + h.1, rot: r2, side: s)

            let jx = rootX + s * R.hipX, jy = rootY + R.hipY
            let planted = ch["plant" + n] >= 0.5
            // Degrees from straight down, towards the right of the picture.
            var phi1 = s * ch["hip" + n]
            var phi2 = s * (ch["hip" + n] + ch["kn" + n])
            if planted {
                let ax = R.rootX + s * ch["stance"] + ch["step" + n], ay = R.ankle - ch["raise" + n]
                let dx = ax - jx, dy = ay - jy
                let d = (dx * dx + dy * dy).squareRoot()
                let a = clamp(d, abs(R.thigh - R.shin) + 0.01, R.thigh + R.shin - 0.001)
                let theta = atan2(dx, dy)
                let cosine = (R.thigh * R.thigh + a * a - R.shin * R.shin) / (2 * R.thigh * a)
                let alpha = acos(clamp(cosine, -1, 1))
                phi1 = (theta + s * alpha) / rad
                let kx = jx + R.thigh * sin(phi1 * rad), ky = jy + R.thigh * cos(phi1 * rad)
                phi2 = atan2(jx + sin(theta) * a - kx, jy + cos(theta) * a - ky) / rad
            }
            B["thigh" + n] = GBone(x: jx, y: jy, rot: -phi1, side: s)
            let kx = jx + R.thigh * sin(phi1 * rad), ky = jy + R.thigh * cos(phi1 * rad)
            B["shin" + n] = GBone(x: kx, y: ky, rot: -phi2, side: s)
            let fx = kx + R.shin * sin(phi2 * rad), fy = ky + R.shin * cos(phi2 * rad)
            let follow = planted ? 0 : -phi2 * R.footFollow
            B["foot" + n] = GBone(x: fx, y: fy, rot: follow - s * ch["foot" + n], side: s)
        }
        return B
    }

    // MARK: Parts

    private static let limbs: Set<String> = ["upper", "fore", "hand", "thigh", "shin", "foot"]

    /// An element of the description, placed in the picture. "upper", "fore", "hand", "thigh", "shin"
    /// and "foot" stand for both sides, mirrored; an element marked `mir` is drawn on both sides of
    /// its bone's own axis.
    static func place(_ el: GEl, _ B: [String: GBone], _ env: GEnv, _ z: Double, _ id: String, _ out: inout [GlimmPart]) {
        let both = B[el.bone] == nil
        let names = both ? [el.bone + "L", el.bone + "R"] : [el.bone]
        for name in names {
            guard let b = B[name] else { continue }
            let mirrors: [Double] = el.mir ? [1, -1] : [1]
            for m in mirrors {
                let s = (both ? b.side : 1) * m
                let d = rotv(s * el.x, el.y, b.rot)
                var tag = ""
                if let last = name.last, last == "L" || last == "R", limbs.contains(String(name.dropLast())) {
                    tag = String(last)
                } else if el.mir {
                    tag = m > 0 ? "a" : "b"
                }
                var part = GlimmPart(id: id + tag, sh: el.sh, x: b.x + d.0, y: b.y + d.1, w: el.w, h: el.h, rot: b.rot + s * el.rot)
                part.flip = s < 0 && el.sh == .path
                part.r = el.r
                part.ops = el.ops
                part.fill = paint(el.fill, env)
                if let stroke = el.stroke { part.stroke = GStroke(color: color(stroke, env), width: el.strokeWidth) }
                if el.fill != nil {
                    switch el.ol {
                    case .none: part.ol = nil
                    case .own(let t, let width): part.ol = GStroke(color: color(t, env), width: width)
                    case .byEnv: if let t = env.ol { part.ol = GStroke(color: color(t, env), width: env.olw) }
                    }
                }
                part.o = el.o
                part.z = (el.z ?? z) + el.dz
                part.txt = el.txt
                let kidSide: Double = (s < 0 && el.sh != .path) ? -1 : 1
                var kids: [GlimmPart] = []
                for (i, k) in el.kids.enumerated() { kids.append(kid(k, env, id + tag + ".\(i)", kidSide)) }
                part.kids = kids
                out.append(part)
            }
        }
    }

    /// Something drawn inside a part and cut to its outline. `side` mirrors it for the left of a pair.
    static func kid(_ k: GKid, _ env: GEnv, _ id: String, _ side: Double = 1) -> GlimmPart {
        var p = GlimmPart(id: id, sh: k.sh, x: side * k.x, y: k.y, w: k.w, h: k.h, rot: side * k.rot)
        p.r = k.r
        p.ops = k.ops
        p.fill = paint(k.fill, env)
        if let stroke = k.stroke { p.stroke = GStroke(color: color(stroke, env), width: k.strokeWidth) }
        p.o = k.o
        p.txt = k.txt
        return p
    }

    /// The colours an item of clothing is drawn in: its own colour as "c", a companion as "c2".
    static func clothEnv(_ env: GEnv, _ hex: String, _ companion: String?) -> GEnv {
        var e = env
        let c = GRGB(hex: hex)
        e.colors["c"] = c
        e.colors["c2"] = c.shaded(55)
        e.ol = GToken("c-38")
        e.olw = env.mono ? 0.9 : 0.5
        if let companion {
            if companion.hasPrefix("#") {
                e.colors["c2"] = GRGB(hex: companion)
            } else {
                let got = color(GToken(companion), e)
                e.colors["c2"] = GRGB((got.r * 255).rounded(), (got.g * 255).rounded(), (got.b * 255).rounded())
            }
        }
        return e
    }

    struct Item: Equatable {
        var shape: String
        var hex: String
        var pattern: String
    }

    /// "top|bottom|feet|head|accessory", each "shape:RRGGBB:pattern" or "-".
    static func parseOutfit(_ code: String) -> [Item?] {
        let slots = code.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        var out: [Item?] = []
        for i in 0..<5 {
            guard i < slots.count else { out.append(nil); continue }
            let p = slots[i].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if p.count >= 2, p[0] != "-", !p[0].isEmpty {
                out.append(Item(shape: p[0], hex: p[1], pattern: p.count > 2 && !p[2].isEmpty ? p[2] : "plain"))
            } else {
                out.append(nil)
            }
        }
        return out
    }

    private static let starOps = GOp.parse("M 0.5 0 L 0.62 0.36 L 1 0.38 L 0.7 0.61 L 0.81 0.98 L 0.5 0.76 L 0.19 0.98 L 0.3 0.61 L 0 0.38 L 0.38 0.36 Z")
    private static let skirtOps = GOp.parse("M 0.14 0 L 0.86 0 L 1 0.86 Q 0.5 1.08 0 0.86 Z")

    /// Marks of a pattern over a box w by h: kids of the garment's body, so its outline cuts them.
    static func patternKids(_ pattern: String, _ w: Double, _ h: Double, _ seedText: String) -> [GKid] {
        var out: [GKid] = []
        var seedInt = 0
        for c in seedText.unicodeScalars { seedInt = (seedInt * 31 + whole(c.value)) % 9973 }
        let seed = Double(seedInt)
        switch pattern {
        case "stripes":
            var y = -h / 2 + 4.2
            while y < h / 2 {
                out.append(GKid(.rr, 0, y, w + 4, 2.6, 0, "c2"))
                y += 6.4
            }
        case "dots":
            var row = 0
            var y = -h / 2 + 4
            while y < h / 2 - 1 {
                var x = -w / 2 + 3 + Double(row % 2) * 2.8
                while x < w / 2 {
                    out.append(GKid(.el, x, y, 2.1, 2.1, 0, "c2"))
                    x += 5.6
                }
                y += 5.6
                row += 1
            }
        case "checks":
            var y = -h / 2 + 3.5
            while y < h / 2 {
                out.append(GKid(.rr, 0, y, w + 4, 2.7, 0, "c2@55"))
                y += 6.6
            }
            var x = -w / 2 + 3.3
            while x < w / 2 {
                out.append(GKid(.rr, x, 0, 2.7, h + 4, 0, "c2@55"))
                x += 6.6
            }
        case "stars":
            for i in 0..<6 {
                let k = Double(i)
                let x = (hash(seed + k * 3) - 0.5) * (w - 6)
                let y = (hash(seed + k * 3 + 1) - 0.5) * (h - 7)
                out.append(GKid(.path, x, y, 4.4, 4.4, hash(seed + k) * 40 - 20, "c2", ops: starOps))
            }
        case "flowers":
            for i in 0..<7 {
                let k = Double(i)
                let x = (hash(seed + k * 7) - 0.5) * (w - 5)
                let y = (hash(seed + k * 7 + 1) - 0.5) * (h - 6)
                for petal in 0..<5 {
                    let a = (Double(petal) * 72 + k * 20) * Double.pi / 180
                    out.append(GKid(.el, x + cos(a) * 1.5, y + sin(a) * 1.5, 2, 2, 0, "#FFFFFF@92"))
                }
                out.append(GKid(.el, x, y, 1.5, 1.5, 0, "gold"))
            }
        case "sprinkles":
            let tints = ["c2", "#FFFFFF", "c-30", "c2-25"]
            for i in 0..<13 {
                let k = Double(i)
                let x = (hash(seed + k * 5) - 0.5) * (w - 4)
                let y = (hash(seed + k * 5 + 2) - 0.5) * (h - 5)
                out.append(GKid(.cap, x, y, 1.1, 3.4, hash(seed + k * 5 + 3) * 180, tints[i % tints.count]))
            }
        default:
            break
        }
        return out
    }

    /// Every part of the picture, back to front.
    static func parts(_ ch: GlimmPose, outfit code: String, mono: Bool = false) -> [GlimmPart] {
        let S = GlimmSpec.shared
        let R = S.rig
        let B = bones(ch)
        let env = GEnv(colors: S.colors, mono: mono)
        var skin = env
        skin.ol = GToken("skinLine")
        skin.olw = mono ? 0.9 : 0.5
        var out: [GlimmPart] = []
        let outfit = parseOutfit(code)
        let zArm = S.z("arm"), zNeck = S.z("neck")
        let frontL = ch["frontL"] >= 0.5 ? S.z("front") : 0
        let frontR = ch["frontR"] >= 0.5 ? S.z("front") : 0
        // An arm's parts move in front of the head when it is raised across it.
        func lift(_ from: Int) {
            guard frontL != 0 || frontR != 0, from < out.count else { return }
            for i in from..<out.count where out[i].z >= zArm && out[i].z < zNeck {
                if frontL != 0, out[i].id.hasSuffix("L") { out[i].z += frontL }
                if frontR != 0, out[i].id.hasSuffix("R") { out[i].z += frontR }
            }
        }

        // The ground under it, smaller as it leaves the ground.
        if !mono {
            var ground = GlimmPart(id: "ground", sh: .el, x: R.rootX + ch["sway"] * 0.5, y: R.ground, w: max(12, 33 - ch["lift"] * 1.3), h: 5.2, rot: 0)
            let alpha = clamp(30 - ch["lift"], 8, 30).rounded() / 100
            ground.fill = .solid(GColor(r: 0, g: 0, b: 0, a: alpha))
            ground.z = S.z("ground")
            out.append(ground)
        }

        // Skin.
        for (i, el) in S.body.enumerated() { place(el, B, skin, 0, "b\(i)", &out) }
        lift(0)

        // Clothes.
        if let item = outfit[1], let G = S.bottoms[item.shape] ?? S.bottoms[S.fallback["bottom"] ?? ""] {
            let e = clothEnv(env, item.hex, G.c2)
            let from = out.count
            let lw = R.legW + 2 + G.wide
            let legFill = GPaintSpec.lin(GToken("c+5"), GToken("c-8"), 0)
            var hip = GEl("torso", .rr, 0, -2.6, 35 + G.wide * 0.6, 10.6, 0, .lin(GToken("c+5"), GToken("c-8"), 90))
            hip.z = S.z("hip")
            hip.r = 5
            place(hip, B, e, 0, "ph", &out)
            if G.skirt {
                var skirt = GEl("torso", .path, 0, 1.2, 39, 12.5, 0, .lin(GToken("c+5"), GToken("c-10"), 90))
                skirt.z = S.z("hip") + 0.6
                skirt.ops = skirtOps
                skirt.kids = G.kids
                place(skirt, B, e, 0, "ps", &out)
            } else {
                let tl = G.leg == "short" ? R.thigh * 0.74 + lw : R.thigh + lw
                var thigh = GEl("thigh", .cap, 0, tl / 2 - lw / 2, lw, tl, 0, legFill)
                thigh.z = S.z("pant")
                thigh.kids = G.thighKids
                place(thigh, B, e, 0, "pt", &out)
                if G.leg != "short" {
                    let sl = R.shin + lw * 0.5 - 0.6
                    var shin = GEl("shin", .cap, 0, sl / 2 - lw / 2 + 0.2, lw - 0.2 + G.flare, sl, 0, legFill)
                    shin.z = S.z("pant") + 0.01
                    shin.kids = G.shinKids
                    place(shin, B, e, 0, "pl", &out)
                    if let cuff = G.cuff {
                        var band = GEl("shin", .rr, 0, R.shin - 1.5, lw + 0.5, 2.6, 0, .solid(cuff))
                        band.z = S.z("pant") + 0.6
                        band.r = 1.2
                        place(band, B, e, 0, "pc", &out)
                    }
                }
            }
            for (i, el) in G.over.enumerated() { place(el, B, e, S.z("hip") + 1, "po\(i)", &out) }
            lift(from)
        }
        func wear(_ item: Item?, _ table: [String: GWear], _ slot: String, _ z: Double) {
            guard let item, let G = table[item.shape] ?? table[S.fallback[slot] ?? ""] else { return }
            let e = clothEnv(env, item.hex, G.c2)
            let from = out.count
            for (i, el) in G.parts.enumerated() { place(el, B, e, z, "\(slot.prefix(1))x\(i)", &out) }
            lift(from)
        }
        wear(outfit[2], S.feet, "feet", S.z("shoe"))
        var hooded = false
        if let item = outfit[0], let G = S.tops[item.shape] ?? S.tops[S.fallback["top"] ?? ""],
           let sil = S.sil[G.sil] ?? S.sil["trunk"], sil.box.count == 4 {
            hooded = G.hood
            let e = clothEnv(env, item.hex, G.c2)
            let from = out.count
            // A cut with a pattern of its own (a rugby shirt's stripes) wears it when it is plain.
            let pattern = item.pattern != "plain" ? item.pattern : (G.pattern ?? "plain")
            var kids = patternKids(pattern, sil.box[2], sil.box[3], item.shape + item.hex)
            kids += G.kids
            if let inner = G.inner, let trunk = S.sil["trunk"], trunk.box.count == 4 {
                var under = GEl("torso", .path, trunk.box[0], trunk.box[1], trunk.box[2], trunk.box[3], 0, .lin(GToken(inner), GToken(inner + "-10"), 90))
                under.ops = trunk.ops
                under.z = S.z("top") - 0.6
                under.ol = .own(GToken(inner + "-38"), 0.5)
                place(under, B, e, 0, "ti", &out)
            }
            var trunkEl = GEl("torso", .path, sil.box[0], sil.box[1], sil.box[2], sil.box[3], 0, .lin(GToken("c+7"), GToken("c-9"), 90))
            trunkEl.ops = sil.ops
            trunkEl.z = S.z("top")
            trunkEl.kids = kids
            place(trunkEl, B, e, 0, "tb", &out)
            for (i, el) in G.over.enumerated() { place(el, B, e, S.z("top") + 2, "to\(i)", &out) }
            var sc = e
            if let t = G.sc {
                let got = color(t, e)
                sc.colors["c2"] = e.colors["c"]
                sc.colors["c"] = GRGB((got.r * 255).rounded(), (got.g * 255).rounded(), (got.b * 255).rounded())
            }
            let aw = R.armW + 2.6
            let band: [GKid] = pattern == "stripes" ? [GKid(.rr, 0, 0.6, aw + 2, 2.2, 0, "c2")] : []
            let sleeveFill = GPaintSpec.lin(GToken("c+7"), GToken("c-7"), 0)
            if G.sleeve == "long" || G.sleeve == "short" {
                let len = G.sleeve == "long" ? R.upper + aw : R.upper * 0.62 + aw
                var sleeve = GEl("upper", .cap, 0, len / 2 - aw / 2, aw, len, 0, sleeveFill)
                sleeve.z = S.z("sleeve")
                sleeve.kids = band
                place(sleeve, B, sc, 0, "su", &out)
            }
            if G.sleeve == "long" {
                let len = R.fore + aw * 0.5
                var sleeve = GEl("fore", .cap, 0, len / 2 - aw / 2 + 0.3, aw - 0.3, len, 0, sleeveFill)
                sleeve.z = S.z("sleeve") + 0.01
                sleeve.kids = band
                place(sleeve, B, sc, 0, "sf", &out)
                if let cuff = G.cuff {
                    var bandEl = GEl("fore", .rr, 0, R.fore - 1.3, aw + 0.4, 2.6, 0, .solid(cuff))
                    bandEl.z = S.z("sleeve") + 0.6
                    bandEl.r = 1.2
                    place(bandEl, B, sc, 0, "sc", &out)
                }
            }
            lift(from)
        }
        wear(outfit[4], S.accs, "acc", S.z("acc"))
        // A hood worn up takes the place of a hat.
        if !hooded { wear(outfit[3], S.heads, "head", S.z("hat")) }

        // The leaf, the face, and whatever it is holding or whatever floats about it.
        var leafEnv = env
        leafEnv.ol = GToken("leafLine")
        leafEnv.olw = mono ? 0.9 : 0.5
        for (i, el) in S.leaf.enumerated() { place(el, B, leafEnv, S.z("leaf"), "lf\(i)", &out) }
        face(ch, B, env, &out)
        let from = out.count
        if let held = S.held[ch.word("hold")] {
            for (i, el) in held.enumerated() { place(el, B, env, S.z("held"), "h\(i)", &out) }
        }
        lift(from)
        if let marks = S.props[ch.word("prop")] { props(marks, ch, B, env, &out) }

        // One outline about each group of parts that touch: every part is first drawn wide in the line
        // colour, just beneath itself, so joints inside a limb show no seam.
        var all: [GlimmPart] = []
        all.reserveCapacity(out.count * 2)
        for p in out {
            if let ol = p.ol, p.fill != nil {
                var halo = p
                halo.id = "o-" + p.id
                halo.fill = .solid(ol.color)
                halo.stroke = GStroke(color: ol.color, width: ol.width * 2)
                halo.kids = []
                halo.z = p.z - 0.4
                halo.ol = nil
                all.append(halo)
            }
            all.append(p)
        }
        let ordered = all.enumerated().sorted { a, b in
            a.element.z != b.element.z ? a.element.z < b.element.z : a.offset < b.offset
        }
        return ordered.map { $0.element }
    }

    /// Points given about a middle, turned into the shape's own box.
    private static func unit(_ ops: [GOp], _ w: Double, _ h: Double) -> [GOp] {
        func ux(_ v: Double) -> Double { v / w + 0.5 }
        func uy(_ v: Double) -> Double { v / h + 0.5 }
        return ops.map { op in
            switch op {
            case .m(let x, let y): return .m(ux(x), uy(y))
            case .l(let x, let y): return .l(ux(x), uy(y))
            case .q(let a, let b, let x, let y): return .q(ux(a), uy(b), ux(x), uy(y))
            case .c(let a, let b, let c, let d, let x, let y): return .c(ux(a), uy(b), ux(c), uy(d), ux(x), uy(y))
            case .z: return .z
            }
        }
    }

    /// A part made here, from points measured in figure units about its own middle.
    private static func made(_ id: String, _ b: GBone, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rot: Double, _ z: Double,
                             _ sh: GShape, _ fill: GPaintSpec?, _ env: GEnv, ops: [GOp]? = nil, stroke: String? = nil, width: Double = 0,
                             kids: [GKid] = []) -> GlimmPart {
        let d = rotv(x, y, b.rot)
        var p = GlimmPart(id: id, sh: sh, x: b.x + d.0, y: b.y + d.1, w: w, h: h, rot: b.rot + rot)
        if let ops { p.ops = unit(ops, w, h) }
        p.fill = paint(fill, env)
        if let stroke { p.stroke = GStroke(color: color(GToken(stroke), env), width: width) }
        p.z = z
        var inner: [GlimmPart] = []
        for (i, k) in kids.enumerated() { inner.append(kid(k, env, id + ".\(i)")) }
        p.kids = inner
        return p
    }

    /// The face: brows, eyes with their lids and lights, cheeks, freckles and the mouth, from the pose.
    private static func face(_ ch: GlimmPose, _ B: [String: GBone], _ env: GEnv, _ out: inout [GlimmPart]) {
        let S = GlimmSpec.shared
        guard let b = B["head"] else { return }
        let z = S.z("face")
        let wide = ch["eyeWide"]
        let eyeX = S.face("eyeX"), eyeY = S.face("eyeY"), cheekX = S.face("cheekX"), cheekY = S.face("cheekY")
        for s in [-1.0, 1.0] {
            let n = s < 0 ? "L" : "R"
            let ex = s * eyeX + ch["lookX"] * 1.3
            let ey = eyeY + ch["lookY"] * 1.1
            let closedSmile = ch["eyeSmile"] >= 0.5 || (ch["wink"] >= 0.5 && s > 0)
            let open = ch["eyeOpen"]
            if closedSmile {
                out.append(made("eye" + n, b, ex, ey + 0.6, 11, 7, 0, z, .path, nil, env, ops: [.m(-4.9, 2.2), .q(0, -5.6, 4.9, 2.2)], stroke: "eye", width: 2.1))
            } else if open < 0.12 {
                out.append(made("eye" + n, b, ex, ey + 1.6, 11, 6, 0, z, .path, nil, env, ops: [.m(-4.7, -1.2), .q(0, 3.6, 4.7, -1.2)], stroke: "eye", width: 1.9))
            } else {
                let w = S.face("eyeW") * (1 + 0.16 * wide)
                let h = S.face("eyeH") * (1 + 0.16 * wide)
                let lx = ch["lookX"] * 0.5, ly = ch["lookY"] * 0.4
                var kids: [GKid] = [
                    GKid(.el, 0, h * 0.36, w * 0.8, h * 0.42, 0, "eyeRing@70"),
                    GKid(.el, -w * 0.2 + lx, -h * 0.23 + ly, w * 0.42, w * 0.42, 0, "white"),
                    GKid(.el, w * 0.2 + lx, h * 0.22 + ly, w * 0.19, w * 0.19, 0, "white@92"),
                ]
                if open < 0.97 {
                    let cover = (1 - open) * h
                    let tilt = -s * ch["lid"]
                    kids.append(GKid(.rr, 0, -h / 2 + cover / 2 - 3, w * 2, cover + 6, tilt, "skin"))
                    kids.append(GKid(.rr, 0, -h / 2 + cover, w * 2, 1.5, tilt, "eye"))
                }
                out.append(made("eye" + n, b, ex, ey, w, h, 0, z, .el, .solid(GToken("eye")), env, kids: kids))
            }
            // Brows: the inner end down is intent, the inner end up is worry; one raised is a question.
            let asym = s > 0 ? ch["browAsym"] * 1.8 : -ch["browAsym"] * 0.7
            let by = S.face("browY") - ch["browY"] - asym - 1.2 * wide
            out.append(made("brow" + n, b, s * eyeX, by, 6.4, 1.7, -s * ch["brow"], z + 0.2, .cap, .solid(GToken("brow")), env))
            let blush = clamp(52 * ch["blush"], 0, 100).rounded() / 100
            out.append(made("cheek" + n, b, s * cheekX, cheekY, 11, 7.2, 0, z - 0.3, .el,
                            .rad(GToken(name: "blush", alpha: blush), GToken(name: "blush", alpha: 0), 0.5, 0.5, 0.5), env))
            let spots: [(Double, Double)] = [(-3.6, -1.9), (0, -3.2), (2.7, -0.7)]
            for (i, f) in spots.enumerated() {
                out.append(made("fr" + n + "\(i)", b, s * (cheekX + f.0), cheekY + f.1, 1.5, 1.5, 0, z - 0.2, .el, .solid(GToken("freckle@90")), env))
            }
        }
        let mx = ch["mouthX"], my = S.face("mouthY") + ch["mouthY"]
        let mo = clamp(ch["mouthOpen"], 0.2, 1.4), mw = ch["mouthW"]
        let zm = z + 0.4
        func line(_ w: Double, _ h: Double, _ ops: [GOp]) {
            out.append(made("mouth", b, mx, my, w, h, 0, zm, .path, nil, env, ops: ops, stroke: "mouthLine", width: 1.8))
        }
        let smile: [GOp] = [.m(-4.6 * mw, -1.2), .q(0, 3.6, 4.6 * mw, -1.2)]
        switch ch.word("mouth") {
        case "grin":
            let hw = 6.3 * mw, d = 6.6 * mo
            let ops: [GOp] = [.m(-hw, -2.3), .q(0, -0.4, hw, -2.3), .c(hw - 0.4, d * 0.75, hw * 0.45, d, 0, d), .c(-hw * 0.45, d, -hw + 0.4, d * 0.75, -hw, -2.3), .z]
            out.append(made("mouth", b, mx, my, 14, 12, 0, zm, .path, .solid(GToken("mouthIn")), env, ops: ops, stroke: "mouthLine", width: 0.9,
                            kids: [GKid(.el, 0, d + 0.4, hw * 1.5, d * 0.95, 0, "tongue")]))
        case "teeth":
            let hw = 6 * mw, d = 4.6 * mo
            let ops: [GOp] = [.m(-hw, -1.9), .q(0, -0.9, hw, -1.9), .c(hw - 0.3, d * 0.8, hw * 0.5, d, 0, d), .c(-hw * 0.5, d, -hw + 0.3, d * 0.8, -hw, -1.9), .z]
            out.append(made("mouth", b, mx, my, 14, 10, 0, zm, .path, .solid(GToken("mouthIn")), env, ops: ops, stroke: "mouthLine", width: 0.9,
                            kids: [GKid(.rr, 0, -1.7, hw * 2, 2.9, 0, "tooth", r: 0.8)]))
        case "open":
            out.append(made("mouth", b, mx, my + 0.6, 4.6 * mw, 5.4 * mo, 0, zm, .el, .solid(GToken("mouthIn")), env, stroke: "mouthLine", width: 0.7))
        case "yawn":
            out.append(made("mouth", b, mx, my + 1.4, 8.6 * mw, 10.8 * mo, 0, zm, .el, .solid(GToken("mouthIn")), env, stroke: "mouthLine", width: 0.8,
                            kids: [GKid(.el, 0, 10.8 * mo * 0.42, 7, 5.5, 0, "tongue")]))
        case "flat":
            line(9, 3, [.m(-3.1 * mw, 0.4), .l(3.1 * mw, 0.4)])
        case "smirk":
            line(11, 6, [.m(-4.1 * mw, 0.9), .q(0.8, 2.9, 4.5 * mw, -1.9)])
        case "wavy":
            line(11, 6, [.m(-4.6, 0.8), .q(-2.3, -2, 0, 0.8), .q(2.3, 3.6, 4.6, 0.8)])
        case "pout":
            line(8, 5, [.m(-2.9, 1.5), .q(0, -1.5, 2.9, 1.5)])
        case "tongue":
            line(11, 7, smile)
            out.append(made("tongue", b, mx + 1.5, my + 3.1, 4.4, 5, 0, z + 0.5, .el, .solid(GToken("tongue")), env, stroke: "mouthLine", width: 0.6))
        default:
            line(11, 7, smile)
        }
    }

    /// What floats about it, from the head's middle. A mark that rises or falls drifts and fades over
    /// the loop; one that twinkles comes and goes.
    private static func props(_ marks: [GMark], _ ch: GlimmPose, _ B: [String: GBone], _ env: GEnv, _ out: inout [GlimmPart]) {
        guard let head = B["head"] else { return }
        let raw = ch["propPhase"]
        let ph = raw - raw.rounded(.down)
        for (i, mk) in marks.enumerated() {
            let q = ph + mk.off
            let p = q - q.rounded(.down)
            var dy = 0.0, alpha = 1.0, k = 1.0
            if mk.rise != 0 {
                dy = -mk.rise * p
                alpha = p < 0.15 ? p / 0.15 : 1 - smooth((p - 0.55) / 0.45)
                k = 0.8 + 0.3 * p
            }
            if mk.fall != 0 {
                dy = mk.fall * p
                alpha = p < 0.1 ? p / 0.1 : 1 - smooth((p - 0.6) / 0.4)
            }
            if mk.tw { k = 0.75 + 0.35 * abs(sin(Double.pi * (p + mk.off))) }
            var part = GlimmPart(id: "p\(i)", sh: mk.sh, x: head.x + mk.x, y: head.y + mk.y + dy, w: mk.size * k, h: (mk.h ?? mk.size) * k, rot: mk.rot)
            part.r = mk.r
            part.ops = mk.ops
            part.fill = paint(mk.fill, env)
            if let stroke = mk.stroke { part.stroke = GStroke(color: color(stroke, env), width: mk.strokeWidth) }
            part.o = alpha * mk.o
            part.z = 90 + Double(i) * 0.01
            part.txt = mk.txt
            out.append(part)
        }
    }

    // MARK: Touch

    /// Which part of Glimm a touch at a point of the figure's box lands on, or nil for the air about it.
    static func zone(x: Double, y: Double) -> String? {
        if y < 24, x > 38, x < 82 { return "leaf" }
        if y < 70 {
            guard x > 19, x < 81 else { return nil }
            return y > 50 && abs(x - 50) > 13 ? "cheek" : "head"
        }
        if y > 99 { return x > 28 && x < 72 ? "feet" : nil }
        if x < 33 || x > 67 { return x > 20 && x < 80 ? "hand" : nil }
        return "belly"
    }
}
