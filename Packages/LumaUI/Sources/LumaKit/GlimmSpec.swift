import Foundation
import CoreGraphics

// MARK: - Glimm's description, read
//
// Glimm is drawn from one description (Tools/glimm/spec.js, carried into GlimmArt.swift): a small
// skeleton, the shapes that hang off each bone, the clothes, and the poses and gestures of each
// mood. This file reads that description into types; GlimmRig.swift turns it into a picture. The
// reference renderer in Tools/glimm/render.js does the same in JavaScript, function for function, so
// the art and the motion can be looked at there before they are built into the app.

/// A value of the description: a number, a word, a list or a table.
enum GV {
    case n(Double), s(String), a([GV]), o([String: GV]), null

    init(_ any: Any) {
        if let v = any as? [String: Any] { self = .o(v.mapValues { GV($0) }) }
        else if let v = any as? [Any] { self = .a(v.map { GV($0) }) }
        else if let v = any as? String { self = .s(v) }
        else if let v = any as? NSNumber { self = .n(v.doubleValue) }
        else { self = .null }
    }

    static func parse(_ json: String) -> GV {
        guard let data = json.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) else { return .o([:]) }
        return GV(any)
    }

    subscript(key: String) -> GV? { if case .o(let d) = self { return d[key] } else { return nil } }
    subscript(i: Int) -> GV? { if case .a(let l) = self, i >= 0, i < l.count { return l[i] } else { return nil } }
    var num: Double? { if case .n(let v) = self { return v } else { return nil } }
    var str: String? { if case .s(let v) = self { return v } else { return nil } }
    var arr: [GV] { if case .a(let v) = self { return v } else { return [] } }
    var obj: [String: GV] { if case .o(let v) = self { return v } else { return [:] } }
}

struct GRGB: Equatable {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    /// "#RRGGBB" or "RRGGBB"; magenta when it is neither, so a slip shows.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self.init(255, 0, 255); return }
        self.init(Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// Lighter by `pct` percent of the way to white, or darker when it is negative.
    func shaded(_ pct: Double) -> GRGB {
        func one(_ v: Double) -> Double {
            let moved = pct >= 0 ? v + (255 - v) * pct / 100 : v * (1 + pct / 100)
            return min(255, max(0, moved.rounded()))
        }
        return GRGB(one(r), one(g), one(b))
    }
}

/// A colour as drawn, 0…1.
struct GColor: Equatable {
    var r: Double, g: Double, b: Double, a: Double
}

/// A colour token: a name from the palette in force or "#RRGGBB", then an optional shade ("+12"
/// lighter, "-20" darker, in percent) and an optional opacity ("@55", in percent).
struct GToken: Equatable {
    var name: String = ""
    var rgb: GRGB?
    var shade: Double = 0
    var alpha: Double = 1

    init(_ text: String) {
        var rest = Substring(text)
        if rest.hasPrefix("#"), rest.count >= 7 {
            rgb = GRGB(hex: String(rest.prefix(7)))
            rest = rest.dropFirst(7)
        } else {
            let end = rest.firstIndex { $0 == "+" || $0 == "-" || $0 == "@" } ?? rest.endIndex
            name = String(rest[..<end])
            rest = rest[end...]
        }
        if let at = rest.firstIndex(of: "@") {
            alpha = (Double(rest[rest.index(after: at)...]) ?? 100) / 100
            rest = rest[..<at]
        }
        if !rest.isEmpty { shade = Double(rest) ?? 0 }
    }

    init(name: String, shade: Double = 0, alpha: Double = 1) { self.name = name; self.shade = shade; self.alpha = alpha }
}

/// A paint as described: one token, or a blend of two along a line or out from a point.
enum GPaintSpec: Equatable {
    case solid(GToken)
    /// 0 degrees runs left to right, 90 top to bottom.
    case lin(GToken, GToken, Double)
    /// The centre in the shape's own box (0…1), the radius as a share of its longer side.
    case rad(GToken, GToken, Double, Double, Double)

    init?(_ v: GV?) {
        guard let v else { return nil }
        if let s = v.str { self = .solid(GToken(s)); return }
        let l = v.arr
        guard l.count >= 3, let kind = l[0].str, let a = l[1].str, let b = l[2].str else { return nil }
        if kind == "lin" { self = .lin(GToken(a), GToken(b), l.count > 3 ? l[3].num ?? 90 : 90) }
        else { self = .rad(GToken(a), GToken(b), l.count > 3 ? l[3].num ?? 0.5 : 0.5, l.count > 4 ? l[4].num ?? 0.5 : 0.5, l.count > 5 ? l[5].num ?? 0.5 : 0.5) }
    }
}

enum GShape: String { case el, cap, rr, path, txt }

/// One step of a path, in its shape's own box (0…1).
enum GOp: Equatable {
    case m(Double, Double), l(Double, Double), q(Double, Double, Double, Double), c(Double, Double, Double, Double, Double, Double), z

    /// "M x y L x y Q cx cy x y C ax ay bx by x y Z".
    static func parse(_ d: String) -> [GOp] {
        var ops: [GOp] = []
        let t = d.split { $0 == " " || $0 == "," }.map(String.init)
        var i = 0
        func take(_ n: Int) -> [Double] {
            let v = (0..<n).map { k in i + k < t.count ? Double(t[i + k]) ?? 0 : 0 }
            i += n
            return v
        }
        while i < t.count {
            let c = t[i]
            i += 1
            switch c {
            case "Z": ops.append(.z)
            case "M": let v = take(2); ops.append(.m(v[0], v[1]))
            case "L": let v = take(2); ops.append(.l(v[0], v[1]))
            case "Q": let v = take(4); ops.append(.q(v[0], v[1], v[2], v[3]))
            case "C": let v = take(6); ops.append(.c(v[0], v[1], v[2], v[3], v[4], v[5]))
            default: break
            }
        }
        return ops
    }
}

/// How an element is outlined: as the palette in force says, not at all, or in its own line.
enum GOutline: Equatable { case byEnv, none, own(GToken, Double) }

/// Something drawn inside an element and cut to its outline, measured from the element's middle.
struct GKid: Equatable {
    var sh: GShape
    var x: Double, y: Double, w: Double, h: Double, rot: Double
    var fill: GPaintSpec?
    var r: Double = 0
    var ops: [GOp]?
    var stroke: GToken?
    var strokeWidth: Double = 0
    var o: Double = 1
    var txt: String?

    init(_ sh: GShape, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rot: Double, _ fill: String?, r: Double = 0, ops: [GOp]? = nil,
         stroke: String? = nil, strokeWidth: Double = 0) {
        self.sh = sh; self.x = x; self.y = y; self.w = w; self.h = h; self.rot = rot
        self.fill = fill.map { .solid(GToken($0)) }
        self.r = r; self.ops = ops; self.stroke = stroke.map { GToken($0) }; self.strokeWidth = strokeWidth
    }

    /// [shape, x, y, w, h, turn, fill, options]
    init?(_ v: GV) {
        let l = v.arr
        guard l.count >= 6, let sh = l[0].str.flatMap({ GShape(rawValue: $0) }) else { return nil }
        self.sh = sh
        x = l[1].num ?? 0; y = l[2].num ?? 0; w = l[3].num ?? 0; h = l[4].num ?? 0; rot = l[5].num ?? 0
        fill = l.count > 6 ? GPaintSpec(l[6]) : nil
        let o = l.count > 7 ? l[7] : GV.null
        r = o["r"]?.num ?? 0
        ops = o["d"]?.str.map { GOp.parse($0) }
        if let s = o["s"]?.arr, s.count == 2, let c = s[0].str { stroke = GToken(c); strokeWidth = s[1].num ?? 1 }
        self.o = o["o"]?.num ?? 1
        txt = o["t"]?.str
    }
}

/// An element of the description: [bone, shape, x, y, w, h, turn, fill, options], measured from the
/// bone's joint.
struct GEl {
    var bone: String
    var sh: GShape
    var x: Double, y: Double, w: Double, h: Double, rot: Double
    var fill: GPaintSpec?
    var r: Double = 0
    var ops: [GOp]?
    var stroke: GToken?
    var strokeWidth: Double = 0
    var ol: GOutline = .byEnv
    var o: Double = 1
    var z: Double?
    var dz: Double = 0
    var txt: String?
    var kids: [GKid] = []
    var mir = false

    init(_ bone: String, _ sh: GShape, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rot: Double, _ fill: GPaintSpec?) {
        self.bone = bone; self.sh = sh; self.x = x; self.y = y; self.w = w; self.h = h; self.rot = rot; self.fill = fill
    }

    init?(_ v: GV) {
        let l = v.arr
        guard l.count >= 7, let bone = l[0].str, let sh = l[1].str.flatMap({ GShape(rawValue: $0) }) else { return nil }
        self.bone = bone; self.sh = sh
        x = l[2].num ?? 0; y = l[3].num ?? 0; w = l[4].num ?? 0; h = l[5].num ?? 0; rot = l[6].num ?? 0
        fill = l.count > 7 ? GPaintSpec(l[7]) : nil
        let o = l.count > 8 ? l[8] : GV.null
        r = o["r"]?.num ?? 0
        ops = o["d"]?.str.map { GOp.parse($0) }
        if let s = o["s"]?.arr, s.count == 2, let c = s[0].str { stroke = GToken(c); strokeWidth = s[1].num ?? 1 }
        if let line = o["ol"] {
            // A pair is the element's own line; anything else (0) is no line at all.
            let pair = line.arr
            if pair.count == 2, let c = pair[0].str { ol = .own(GToken(c), pair[1].num ?? 0.5) } else { ol = .none }
        }
        self.o = o["o"]?.num ?? 1
        z = o["z"]?.num
        dz = o["dz"]?.num ?? 0
        txt = o["t"]?.str
        kids = (o["kids"]?.arr ?? []).compactMap { GKid($0) }
        mir = (o["mir"]?.num ?? 0) != 0
    }
}

/// A pose: the numbers and the words (a mouth shape, a thing held) that the rig is set by.
struct GlimmPose: Equatable {
    var n: [String: Double] = [:]
    var w: [String: String] = [:]

    subscript(_ key: String) -> Double { n[key] ?? 0 }
    func word(_ key: String) -> String { w[key] ?? "none" }

    mutating func merge(_ other: GlimmPose) {
        for (k, v) in other.n { n[k] = v }
        for (k, v) in other.w { w[k] = v }
    }

    init() {}

    init(_ v: GV?) {
        for (k, value) in v?.obj ?? [:] {
            if let x = value.num { n[k] = x } else if let s = value.str { w[k] = s }
        }
    }
}

struct GGesture {
    var dur: Double
    var keys: [(at: Double, set: GlimmPose)]

    init(_ v: GV) {
        dur = v["dur"]?.num ?? 1
        keys = (v["keys"]?.arr ?? []).map { (at: $0[0]?.num ?? 0, set: GlimmPose($0[1])) }
    }
}

struct GOsc {
    var ch: String, amp: Double, hz: Double, ph: Double, mode: String

    init?(_ v: GV) {
        let l = v.arr
        guard l.count >= 3, let ch = l[0].str else { return nil }
        self.ch = ch; amp = l[1].num ?? 0; hz = l[2].num ?? 0
        ph = l.count > 3 ? l[3].num ?? 0 : 0
        mode = l.count > 4 ? l[4].str ?? "sin" : "sin"
    }
}

struct GMood {
    var base = GlimmPose()
    var live = GlimmPose()
    var osc: [GOsc] = []
    var gestures: [String] = []
    var every = 7.0
    var stills: [(g: String?, at: Double, set: GlimmPose)] = []

    init() {}

    init(_ v: GV) {
        base = GlimmPose(v["base"])
        live = GlimmPose(v["live"])
        osc = (v["osc"]?.arr ?? []).compactMap { GOsc($0) }
        gestures = (v["gestures"]?.arr ?? []).compactMap { $0.str }
        every = v["every"]?.num ?? 7
        stills = (v["stills"]?.arr ?? []).map { (g: $0["g"]?.str, at: $0["at"]?.num ?? 0.5, set: GlimmPose($0["set"])) }
    }
}

struct GTop {
    var sil = "trunk"
    var sleeve = "none"
    var cuff: GToken?
    var kids: [GKid] = []
    var over: [GEl] = []
    var inner: String?
    var sc: GToken?
    var pattern: String?
    var c2: String?
    var hood = false

    init(_ v: GV) {
        sil = v["sil"]?.str ?? "trunk"
        sleeve = v["sleeve"]?.str ?? "none"
        cuff = GTop.cuff(v["cuff"])
        kids = (v["kids"]?.arr ?? []).compactMap { GKid($0) }
        over = (v["over"]?.arr ?? []).compactMap { GEl($0) }
        inner = v["inner"]?.str
        sc = v["sc"]?.str.map { GToken($0) }
        pattern = v["pattern"]?.str
        c2 = v["c2"]?.str
        hood = (v["hood"]?.num ?? 0) != 0
    }

    /// 1 is the item's own colour a little darker; a word is that colour.
    static func cuff(_ v: GV?) -> GToken? {
        guard let v else { return nil }
        if let s = v.str { return GToken(s) }
        return (v.num ?? 0) != 0 ? GToken("c-14") : nil
    }
}

struct GBottom {
    var leg = "long"
    var wide = 0.0
    var flare = 0.0
    var cuff: GToken?
    var skirt = false
    var kids: [GKid] = []
    var thighKids: [GKid] = []
    var shinKids: [GKid] = []
    var over: [GEl] = []
    var c2: String?

    init(_ v: GV) {
        leg = v["leg"]?.str ?? "long"
        wide = v["wide"]?.num ?? 0
        flare = v["flare"]?.num ?? 0
        cuff = GTop.cuff(v["cuff"])
        skirt = (v["skirt"]?.num ?? 0) != 0
        kids = (v["kids"]?.arr ?? []).compactMap { GKid($0) }
        thighKids = (v["thighKids"]?.arr ?? []).compactMap { GKid($0) }
        shinKids = (v["shinKids"]?.arr ?? []).compactMap { GKid($0) }
        over = (v["over"]?.arr ?? []).compactMap { GEl($0) }
        c2 = v["c2"]?.str
    }
}

struct GWear {
    var parts: [GEl] = []
    var c2: String?

    init(_ v: GV) {
        parts = (v["parts"]?.arr ?? []).compactMap { GEl($0) }
        c2 = v["c2"]?.str
    }
}

/// A mark that floats about the head: [shape, x, y, size, fill, options].
struct GMark {
    var sh: GShape
    var x: Double, y: Double, size: Double
    var fill: GPaintSpec?
    var h: Double?
    var rot = 0.0, r = 0.0, o = 1.0, off = 0.0
    var rise = 0.0, fall = 0.0
    var tw = false
    var ops: [GOp]?
    var stroke: GToken?
    var strokeWidth = 0.0
    var txt: String?

    init?(_ v: GV) {
        let l = v.arr
        guard l.count >= 4, let sh = l[0].str.flatMap({ GShape(rawValue: $0) }) else { return nil }
        self.sh = sh
        x = l[1].num ?? 0; y = l[2].num ?? 0; size = l[3].num ?? 0
        fill = l.count > 4 ? GPaintSpec(l[4]) : nil
        let o = l.count > 5 ? l[5] : GV.null
        h = o["h"]?.num
        rot = o["rot"]?.num ?? 0; r = o["r"]?.num ?? 0; self.o = o["o"]?.num ?? 1; off = o["off"]?.num ?? 0
        rise = o["rise"]?.num ?? 0; fall = o["fall"]?.num ?? 0
        tw = (o["tw"]?.num ?? 0) != 0
        ops = o["d"]?.str.map { GOp.parse($0) }
        if let s = o["s"]?.arr, s.count == 2, let c = s[0].str { stroke = GToken(c); strokeWidth = s[1].num ?? 1 }
        txt = o["t"]?.str
    }
}

struct GRig {
    var rootX = 50.0, rootY = 92.0, ground = 113.2, ankle = 106.6, torsoLen = 25.0, neckUp = 23.5
    var leafX = 2.5, leafY = -22.2, leafDroop = 78.0
    var shoulderX = 15.4, shoulderY = -21.5, upper = 9.6, fore = 8.8, armW = 8.0
    var hipX = 7.6, hipY = 1.2, thigh = 7.0, shin = 6.6, legW = 11.0, footFollow = 0.3

    init() {}

    init(_ v: GV?) {
        guard let v else { return }
        func n(_ k: String, _ d: Double) -> Double { v[k]?.num ?? d }
        func pair(_ k: String, _ i: Int, _ d: Double) -> Double { v[k]?[i]?.num ?? d }
        rootX = pair("root", 0, rootX); rootY = pair("root", 1, rootY)
        ground = n("ground", ground); ankle = n("ankle", ankle); torsoLen = n("torsoLen", torsoLen); neckUp = n("neckUp", neckUp)
        leafX = pair("leaf", 0, leafX); leafY = pair("leaf", 1, leafY); leafDroop = n("leafDroop", leafDroop)
        shoulderX = pair("shoulder", 0, shoulderX); shoulderY = pair("shoulder", 1, shoulderY)
        upper = n("upper", upper); fore = n("fore", fore); armW = n("armW", armW)
        hipX = pair("hip", 0, hipX); hipY = pair("hip", 1, hipY)
        thigh = n("thigh", thigh); shin = n("shin", shin); legW = n("legW", legW); footFollow = n("footFollow", footFollow)
    }
}

/// The description, read once.
final class GlimmSpec {
    static let shared = GlimmSpec()

    let rig: GRig
    let z: [String: Double]
    let colors: [String: GRGB]
    let face: [String: Double]
    let fallback: [String: String]
    let body: [GEl]
    let leaf: [GEl]
    let sil: [String: (box: [Double], ops: [GOp])]
    let tops: [String: GTop]
    let bottoms: [String: GBottom]
    let feet: [String: GWear]
    let heads: [String: GWear]
    let accs: [String: GWear]
    let held: [String: [GEl]]
    let props: [String: [GMark]]
    let defaults: GlimmPose
    let breath: [GOsc]
    let moods: [String: GMood]
    let gestures: [String: GGesture]
    let taps: [String: GGesture]

    private init() {
        let v = GV.parse(GlimmArt.json)
        rig = GRig(v["rig"])
        z = (v["z"]?.obj ?? [:]).compactMapValues { $0.num }
        colors = (v["colors"]?.obj ?? [:]).compactMapValues { $0.str.map { GRGB(hex: $0) } }
        face = (v["face"]?.obj ?? [:]).compactMapValues { $0.num }
        fallback = (v["fallback"]?.obj ?? [:]).compactMapValues { $0.str }
        body = (v["body"]?.arr ?? []).compactMap { GEl($0) }
        leaf = (v["leaf"]?.arr ?? []).compactMap { GEl($0) }
        sil = (v["sil"]?.obj ?? [:]).mapValues { s in (box: (s["box"]?.arr ?? []).map { $0.num ?? 0 }, ops: GOp.parse(s["d"]?.str ?? "")) }
        tops = (v["tops"]?.obj ?? [:]).mapValues { GTop($0) }
        bottoms = (v["bottoms"]?.obj ?? [:]).mapValues { GBottom($0) }
        feet = (v["feet"]?.obj ?? [:]).mapValues { GWear($0) }
        heads = (v["heads"]?.obj ?? [:]).mapValues { GWear($0) }
        accs = (v["accs"]?.obj ?? [:]).mapValues { GWear($0) }
        held = (v["held"]?.obj ?? [:]).mapValues { $0.arr.compactMap { GEl($0) } }
        props = (v["props"]?.obj ?? [:]).mapValues { $0.arr.compactMap { GMark($0) } }
        defaults = GlimmPose(v["defaults"])
        breath = (v["breath"]?.arr ?? []).compactMap { GOsc($0) }
        moods = (v["moods"]?.obj ?? [:]).mapValues { GMood($0) }
        gestures = (v["gestures"]?.obj ?? [:]).mapValues { GGesture($0) }
        taps = (v["taps"]?.obj ?? [:]).mapValues { GGesture($0) }
    }

    func z(_ key: String) -> Double { z[key] ?? 0 }
    func face(_ key: String) -> Double { face[key] ?? 0 }
}
