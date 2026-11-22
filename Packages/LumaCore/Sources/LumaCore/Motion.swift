import Foundation

// MARK: - Counting from wrist motion
//
// With motion recording switched on, a session keeps the strap's raw wrist motion: a hundred readings a
// second of acceleration on three axes. This file reads that recording and counts what repeats in it:
// steps in a run, strokes on a machine, reps at a station.
//
// It is an experiment and is labelled one wherever it shows. The method has been checked only against
// made-up motion, where it recovers several different rates that were put in. It has not been checked
// against a real class, so a count from it is shown beside the session, changes nothing in the record
// and feeds nothing else. The athlete can enter the real number against a count, and what those
// checks add up to is the evidence the method still lacks.
//
// One trap is guarded against by name. The strap sends motion a second at a time, a fixed hundred
// readings in each. If the readings do not join up across the seconds, every join is a small jump, and
// a method that looks for what repeats will find one repeat a second: sixty a minute, which is a
// believable stroke rate. A recording with such joins is not counted from at all (`MotionTrack.hasSeams`).
//
// What it cannot tell apart is said where it shows: walking about between sets repeats too, and is
// counted with them.

/// One second of wrist motion as the strap sends it: a hundred readings on each of six axes, kept as
/// the whole numbers they arrive as.
public struct MotionSecond: Equatable, Sendable {
    /// The strap's own clock at the start of this second, in whole seconds.
    public var ts: Int
    /// The phone's clock when the second arrived, in milliseconds.
    public var receivedMs: Int
    /// Acceleration x, y and z, then rotation x, y and z: a hundred readings of each, one after another.
    public var columns: [Int16]

    public init(ts: Int, receivedMs: Int, columns: [Int16]) {
        self.ts = ts; self.receivedMs = receivedMs; self.columns = columns
    }
}

/// The strap layer's file of a motion recording, read. The layout is that layer's own
/// (`ImuSessionFileStore`): a short heading, then blocks of up to thirty seconds, each packed.
public enum MotionFile {
    /// Readings a second, and axes, as the file's heading must state them.
    public static let rate = 100
    public static let axes = 6
    /// What one count of acceleration is worth, in g.
    public static let gPerCount = 1.0 / 4096.0
    static let magic = Array("NOOPIMU2".utf8)
    static let payload = rate * axes * 2
    static let blockLimit = 30

    /// The seconds held in one file. `inflate` unpacks one block to the size the file says it has; it
    /// is handed in because unpacking is the phone's job and is not part of this package. A file that
    /// is not of this kind gives nothing, and a block that does not unpack ends the reading there:
    /// what came before it is kept.
    public static func seconds(from data: Data, inflate: (Data, Int) -> Data?) -> [MotionSecond] {
        let bytes = [UInt8](data)
        guard bytes.count >= 24, Array(bytes[0..<8]) == magic else { return [] }
        guard int32(bytes, 16) == rate, int32(bytes, 20) == axes else { return [] }
        var at = 24
        var out: [MotionSecond] = []
        while at + 12 <= bytes.count {
            let count = int32(bytes, at), rawSize = int32(bytes, at + 4), packed = int32(bytes, at + 8)
            at += 12
            guard count > 0, count <= blockLimit, rawSize > 0, packed > 0, at + packed <= bytes.count,
                  let raw = inflate(Data(bytes[at..<(at + packed)]), rawSize) else { break }
            at += packed
            let r = [UInt8](raw)
            var o = 0
            for _ in 0..<count {
                guard o + 20 + payload <= r.count else { break }
                let ts = int64(r, o), received = int64(r, o + 8), length = int32(r, o + 16)
                o += 20
                guard length == payload else { break }
                var columns = [Int16](repeating: 0, count: rate * axes)
                for i in 0..<(rate * axes) {
                    let low = UInt16(r[o + 2 * i]), high = UInt16(r[o + 2 * i + 1])
                    columns[i] = Int16(bitPattern: low | (high << 8))
                }
                o += length
                out.append(MotionSecond(ts: ts, receivedMs: received, columns: columns))
            }
        }
        return out
    }

    static func int32(_ b: [UInt8], _ o: Int) -> Int {
        (Int(b[o]) << 24) | (Int(b[o + 1]) << 16) | (Int(b[o + 2]) << 8) | Int(b[o + 3])
    }

    static func int64(_ b: [UInt8], _ o: Int) -> Int {
        var value: UInt64 = 0
        for i in 0..<8 { value = (value << 8) | UInt64(b[o + i]) }
        return Int(Int64(bitPattern: value))
    }
}

/// A stretch of motion with no second missing: acceleration in g on three axes, a hundred readings a second.
public struct MotionStretch: Sendable {
    /// When its first reading was taken, by the phone's clock, in seconds.
    public var start: Double
    public var x: [Float]
    public var y: [Float]
    public var z: [Float]

    public var end: Double { start + Double(x.count) / Double(MotionFile.rate) }
}

/// A recording's motion, laid out in time: the stretches that have no second missing, in order.
public struct MotionTrack: Sendable {
    public var stretches: [MotionStretch] = []
    /// How much larger the step from one second's last reading to the next second's first is than the
    /// steps on either side of it, at the middle join of them all. About one when the seconds join up.
    /// It is the middle one and not the average, so that a footfall landing on a join does not count
    /// against a recording.
    public var seamRatio = 1.0

    /// Above this the seconds do not join up, and nothing is counted from the recording.
    public static let seamLimit = 2.0

    public init() {}

    public var isEmpty: Bool { stretches.isEmpty }
    public var hasSeams: Bool { seamRatio > MotionTrack.seamLimit }
    /// Seconds of motion held.
    public var seconds: Double { stretches.reduce(0.0) { $0 + Double($1.x.count) / Double(MotionFile.rate) } }

    /// Lays the seconds out in time. A second sent twice is taken once, and a missing second ends one
    /// stretch and starts the next: readings are never joined across a gap. The strap stamps each
    /// second with its own clock; the phone's clock is what the session's parts are timed by, so the
    /// stretches are placed by the phone's, using the seconds that arrived with the least delay.
    public static func build(_ seconds: [MotionSecond]) -> MotionTrack {
        let rate = MotionFile.rate
        var seen = Set<Int>()
        var whole: [MotionSecond] = []
        for second in seconds where second.columns.count == rate * MotionFile.axes {
            if seen.insert(second.ts).inserted { whole.append(second) }
        }
        whole.sort { $0.ts < $1.ts }
        var track = MotionTrack()
        guard !whole.isEmpty else { return track }
        // A second is sent once it is over, so it arrives a little after its end. The smallest delays
        // seen are the nearest to the true difference between the two clocks.
        var delays: [Double] = []
        for second in whole where second.receivedMs > 0 {
            delays.append(Double(second.receivedMs) / 1000 - Double(second.ts) - 1)
        }
        delays.sort()
        let shift = delays.isEmpty ? 0.0 : delays[delays.count / 10]

        let scale = Float(MotionFile.gPerCount)
        var open = false
        var start = 0.0
        var x: [Float] = [], y: [Float] = [], z: [Float] = []
        var last = 0
        var ratios: [Double] = []
        // One count on each of three axes, so that readings that do not change at all compare as equal.
        let quantum = 3 * MotionFile.gPerCount
        for second in whole {
            if !open || second.ts != last + 1 {
                if open { track.stretches.append(MotionStretch(start: start, x: x, y: y, z: z)) }
                start = Double(second.ts) + shift
                x = []; y = []; z = []
                open = true
            }
            let c = second.columns
            let n = x.count
            if n >= 2 {
                // The step across the join, against the step just before it and the step just after.
                let x0 = Float(c[0]) * scale, y0 = Float(c[rate]) * scale, z0 = Float(c[2 * rate]) * scale
                let x1 = Float(c[1]) * scale, y1 = Float(c[rate + 1]) * scale, z1 = Float(c[2 * rate + 1]) * scale
                let across = abs(x0 - x[n - 1]) + abs(y0 - y[n - 1]) + abs(z0 - z[n - 1])
                let before = abs(x[n - 1] - x[n - 2]) + abs(y[n - 1] - y[n - 2]) + abs(z[n - 1] - z[n - 2])
                let after = abs(x1 - x0) + abs(y1 - y0) + abs(z1 - z0)
                ratios.append((Double(across) + quantum) / (Double(before + after) / 2 + quantum))
            }
            for i in 0..<rate {
                x.append(Float(c[i]) * scale)
                y.append(Float(c[rate + i]) * scale)
                z.append(Float(c[2 * rate + i]) * scale)
            }
            last = second.ts
        }
        if open { track.stretches.append(MotionStretch(start: start, x: x, y: y, z: z)) }
        if ratios.count >= 10 {
            ratios.sort()
            track.seamRatio = ratios[ratios.count / 2]
        }
        return track
    }
}

// MARK: - What is being counted

/// The kind of movement in a part of a session, which sets what one repeat is called and how fast it
/// can sensibly come.
public enum MotionKind: String, Codable, Sendable, CaseIterable {
    case run, walk, skiErg, row, wallBalls, burpees, lunges, sledPull, sledPush, work, rest

    /// What one repeat is called, in the plural. Empty where nothing is counted.
    public var unit: String {
        switch self {
        case .run, .walk, .lunges: return "steps"
        case .skiErg, .row: return "strokes"
        case .sledPull: return "pulls"
        case .wallBalls, .burpees: return "reps"
        case .work: return "repeats"
        case .sledPush, .rest: return ""
        }
    }

    /// The fewest and the most repeats a minute taken for this movement. Nil where nothing is counted:
    /// at rest, and pushing a sled, where the hands hold still on the handles.
    var band: ClosedRange<Double>? {
        switch self {
        case .run: return 130.0...220.0
        case .walk: return 70.0...150.0
        case .lunges: return 20.0...70.0
        case .skiErg: return 25.0...70.0
        case .row: return 16.0...42.0
        case .sledPull: return 15.0...70.0
        case .wallBalls: return 12.0...45.0
        case .burpees: return 6.0...30.0
        case .work: return 10.0...70.0
        case .sledPush, .rest: return nil
        }
    }

    /// Steps show as a jolt at each footfall whichever way the arm is pointing, so they are counted
    /// from the size of the acceleration. Everything else is counted along the line the wrist moves
    /// most on, where one stroke or rep is one swing out and back.
    var byFootfall: Bool {
        switch self {
        case .run, .walk, .lunges: return true
        default: return false
        }
    }

    /// Running and walking are known by their pace, steps a minute, and the rest by their count.
    public var byPace: Bool { self == .run || self == .walk }

    public var counts: Bool { band != nil }

    /// A plain name for the kind.
    public var title: String {
        switch self {
        case .run: return "Run"
        case .walk: return "Carry"
        case .skiErg: return "SkiErg"
        case .row: return "Row"
        case .wallBalls: return "Wall balls"
        case .burpees: return "Burpees"
        case .lunges: return "Lunges"
        case .sledPull: return "Sled pull"
        case .sledPush: return "Sled push"
        case .work: return "Work"
        case .rest: return "Rest"
        }
    }

    /// The kind a part's name points to, when it points to one.
    public static func named(_ label: String) -> MotionKind? {
        let words = label.lowercased().split { !$0.isLetter }.map { String($0) }
        func has(_ start: String) -> Bool { words.contains { $0.hasPrefix(start) } }
        if has("rest") || has("recover") || has("roxzone") || has("transition") || has("break") { return .rest }
        if has("ski") { return .skiErg }
        if has("wall") { return .wallBalls }
        if has("burpee") { return .burpees }
        if has("lunge") { return .lunges }
        if has("farmer") || has("carry") { return .walk }
        if has("sled") { return has("pull") ? .sledPull : .sledPush }
        if has("row") { return .row }
        if has("run") || has("jog") || has("treadmill") || has("sprint") { return .run }
        if has("walk") { return .walk }
        return nil
    }

    /// The kind a part's name points to. `other` is what an unrecognised name is taken for: a run in a
    /// running session, work elsewhere.
    public static func infer(_ label: String, other: MotionKind = .work) -> MotionKind {
        named(label) ?? other
    }
}

/// What was counted in one part.
public struct MotionCount: Equatable, Sendable {
    /// Whole repeats counted.
    public var count: Int
    /// Their usual pace, a minute. Nil when nothing repeated steadily enough to give one.
    public var perMinute: Double?
    /// The share of the moving time in which the movement kept a beat that could be followed.
    public var steady: Double
    /// Seconds of the part with motion recorded.
    public var coveredS: Double

    public init(count: Int, perMinute: Double?, steady: Double, coveredS: Double) {
        self.count = count; self.perMinute = perMinute; self.steady = steady; self.coveredS = coveredS
    }
}

// MARK: - Counting

public enum MotionCounter {
    /// Readings a second after halving: enough for the fastest footfalls, and a quarter of the sums.
    static let fs = 50.0
    /// Movement smaller than this, in g, is taken for holding still.
    static let stillBelow = 0.05
    /// How well a window must match itself one repeat later for a beat to be read from it.
    static let beatAtLeast = 0.5
    /// How well a step along the part must match itself, one repeat either side, to be counted.
    static let hereAtLeast = 0.35
    /// How well a window must also match itself at half the delay for the half to be one footstep.
    static let halfAtLeast = 0.5
    /// The least of a part that must have motion recorded for a count to be given.
    static let coverAtLeast = 0.5

    /// The repeats in one part of a recording, between two moments by the phone's clock. Nil when
    /// nothing is counted for the kind, when the recording's seconds do not join up, or when too
    /// little of the part was recorded to say.
    public static func count(_ track: MotionTrack, from: Double, to: Double, kind: MotionKind) -> MotionCount? {
        guard !track.hasSeams else { return nil }
        return unguarded(track, from: from, to: to, kind: kind)
    }

    /// The count without the check that the seconds join up. It is here so that a test can show what
    /// that check is for; nothing else calls it.
    static func unguarded(_ track: MotionTrack, from: Double, to: Double, kind: MotionKind) -> MotionCount? {
        guard let band = kind.band, to > from else { return nil }
        var total = Tally()
        for stretch in track.stretches {
            guard let piece = Piece(stretch, from: from, to: to, longest: 60 / band.lowerBound) else { continue }
            total.add(tally(piece, band: band, byFootfall: kind.byFootfall))
        }
        guard total.covered >= coverAtLeast * (to - from) * fs, total.covered >= 8 * fs else { return nil }
        let rates = total.rates.sorted()
        return MotionCount(count: LNum.int(total.count.rounded()),
                           perMinute: rates.isEmpty ? nil : rates[rates.count / 2],
                           steady: total.moving > 0 ? min(1, total.beating / total.moving) : 0,
                           coveredS: total.covered / fs)
    }

    // MARK: The working

    /// A part of one stretch, halved to fifty readings a second, with what does not change taken out:
    /// gravity, and anything slower than the slowest repeat looked for.
    struct Piece {
        var x: [Double]
        var y: [Double]
        var z: [Double]
        /// The size of the acceleration, treated the same way: where footfalls show.
        var size: [Double]
        /// When its first reading was taken, by the phone's clock.
        var start: Double

        init?(_ s: MotionStretch, from: Double, to: Double, longest: Double) {
            let rate = Double(MotionFile.rate)
            let i0 = max(0, LNum.int(((from - s.start) * rate).rounded()))
            let i1 = min(s.x.count, LNum.int(((to - s.start) * rate).rounded()))
            guard i1 - i0 >= 2 * LNum.int(MotionCounter.fs) else { return nil }
            let n = (i1 - i0) / 2
            var x = [Double](repeating: 0, count: n)
            var y = [Double](repeating: 0, count: n)
            var z = [Double](repeating: 0, count: n)
            var size = [Double](repeating: 0, count: n)
            for j in 0..<n {
                let a = i0 + 2 * j
                let vx = Double(s.x[a] + s.x[a + 1]) / 2
                let vy = Double(s.y[a] + s.y[a + 1]) / 2
                let vz = Double(s.z[a] + s.z[a + 1]) / 2
                x[j] = vx; y[j] = vy; z[j] = vz
                size[j] = (vx * vx + vy * vy + vz * vz).squareRoot()
            }
            let span = max(3, LNum.int((1.25 * longest * MotionCounter.fs).rounded()))
            self.x = MotionCounter.withoutSlow(x, span: span)
            self.y = MotionCounter.withoutSlow(y, span: span)
            self.z = MotionCounter.withoutSlow(z, span: span)
            self.size = MotionCounter.withoutSlow(size, span: span)
            self.start = s.start + Double(i0) / rate
        }

        var count: Int { x.count }
    }

    struct Tally {
        var count = 0.0
        var covered = 0.0
        var moving = 0.0
        var beating = 0.0
        var rates: [Double] = []

        mutating func add(_ other: Tally) {
            count += other.count; covered += other.covered; moving += other.moving; beating += other.beating
            rates += other.rates
        }
    }

    /// What one window of movement shows: whether there is movement at all, and the length of one
    /// repeat when it keeps a beat.
    struct Beat {
        var moving = false
        /// Seconds for one repeat, when the window keeps a beat.
        var period: Double?
        /// How well the window matched itself.
        var strength = 0.0
        /// The delay, in readings, at which it matched: two steps where the feet land unevenly.
        var every = 0
        /// What the beat was read from.
        var signal: [Double] = []
    }

    /// Counts a piece by walking along it in short steps. Each step is read from a window around it,
    /// long enough to hold four of the slowest repeats, and adds as many repeats as fit into the part
    /// of the step in which the wrist was moving, at the pace that window keeps. A window that keeps
    /// no beat adds nothing, and neither does a step that does not itself match the beat: a pause
    /// between two sets is not counted for the sets either side of it.
    static func tally(_ p: Piece, band: ClosedRange<Double>, byFootfall: Bool) -> Tally {
        var out = Tally()
        let n = p.count
        let shortest = 60 / band.upperBound, longest = 60 / band.lowerBound
        var window = LNum.int(min(max(4 * longest, 8), 32) * fs)
        if n < window {
            guard Double(n) >= max(8, 2.2 * longest) * fs else { return out }
            window = n
        }
        let hop = max(1, window / 4)
        let second = LNum.int(fs)
        var k = 0
        while k < n {
            let end = min(k + hop, n)
            let w0 = min(max(0, k + hop / 2 - window / 2), n - window)
            let beat = read(p, at: w0, length: window, shortest: shortest, longest: longest, byFootfall: byFootfall)
            out.covered += Double(end - k)
            if let period = beat.period {
                let live = Double(movedIn(p, from: k, to: end, block: max(second, beat.every)))
                out.moving += live
                if live > 0, keeps(beat.signal, from: k - w0, to: end - w0, every: beat.every) {
                    out.beating += live
                    out.count += live / (period * fs)
                    out.rates.append(60 / period)
                }
            } else if beat.moving {
                out.moving += Double(movedIn(p, from: k, to: end, block: second))
            }
            k = end
        }
        return out
    }

    /// Reads one window. The signal is the size of the acceleration for footfalls, and otherwise the
    /// movement along the one line the wrist moved most on in this window. The window is laid over
    /// itself at every delay a repeat could have; where it matches best, and well enough, is the
    /// length of one repeat. Of matches that are nearly as good as the best, the shortest delay is
    /// taken, because a movement that repeats every second also matches itself every two.
    static func read(_ p: Piece, at w0: Int, length: Int, shortest: Double, longest: Double, byFootfall: Bool) -> Beat {
        var beat = Beat()
        var energy = 0.0
        for i in w0..<(w0 + length) { energy += p.x[i] * p.x[i] + p.y[i] * p.y[i] + p.z[i] * p.z[i] }
        guard (energy / Double(length)).squareRoot() >= stillBelow else { return beat }
        beat.moving = true

        var s: [Double]
        if byFootfall {
            s = Array(p.size[w0..<(w0 + length)])
        } else {
            let line = mainLine(p, from: w0, to: w0 + length)
            s = [Double](repeating: 0, count: length)
            for i in 0..<length { s[i] = p.x[w0 + i] * line.0 + p.y[w0 + i] * line.1 + p.z[w0 + i] * line.2 }
        }
        s = smoothed(s)
        var squares = [Double](repeating: 0, count: length + 1)
        for i in 0..<length { squares[i + 1] = squares[i] + s[i] * s[i] }
        beat.signal = s
        guard (squares[length] / Double(length)).squareRoot() >= stillBelow / 2 else { return beat }

        let first = max(2, LNum.int((shortest * fs).rounded(.down)) - 1)
        // Footfalls are looked for as far as two steps apart: see below.
        let reach = byFootfall ? 2 * longest : longest
        let last = min(length / 2, LNum.int((reach * fs).rounded(.up)) + 1)
        guard last > first + 2 else { return beat }
        var match = [Double](repeating: 0, count: last + 1)
        for lag in first...last {
            var both = 0.0
            for i in 0..<(length - lag) { both += s[i] * s[i + lag] }
            let a = squares[length - lag], b = squares[length] - squares[lag]
            match[lag] = a > 0 && b > 0 ? both / (a * b).squareRoot() : 0
        }
        var peaks: [Int] = []
        for lag in (first + 1)..<last where match[lag] > match[lag - 1] && match[lag] >= match[lag + 1] {
            peaks.append(lag)
        }
        var best = 0.0
        for lag in peaks where match[lag] > best { best = match[lag] }
        beat.strength = best
        guard best >= beatAtLeast, let every = peaks.first(where: { match[$0] >= 0.9 * best }) else { return beat }
        beat.strength = match[every]

        var period = finest(match, every) / fs
        if byFootfall {
            // Left and right seldom land alike, so the wrist can repeat best every two steps. Where it
            // also repeats, well enough, at half that delay, the half is one step; and where it shows
            // no step at all, only the swing of the arm, one step is still half of what repeats.
            let near = max(2, every / 8)
            var step: Int?
            for lag in peaks where abs(2 * lag - every) <= near && match[lag] >= halfAtLeast * match[every] {
                if let held = step, match[held] >= match[lag] { continue }
                step = lag
            }
            if let step {
                period = finest(match, step) / fs
            } else if period > longest * 1.02 {
                period /= 2
            }
        }
        guard period >= shortest * 0.98, period <= longest * 1.02 else { return beat }
        beat.period = period
        beat.every = every
        return beat
    }

    /// The best match usually falls between two readings: the values either side of it say where.
    static func finest(_ match: [Double], _ lag: Int) -> Double {
        let l = match[lag - 1], m = match[lag], r = match[lag + 1]
        let bend = l - 2 * m + r
        return bend < 0 ? Double(lag) + 0.5 * (l - r) / bend : Double(lag)
    }

    /// The readings between two points in which the wrist was moving, judged a block at a time. A
    /// block is at least one repeat long, so that the quiet part of a slow movement is not a pause.
    static func movedIn(_ p: Piece, from a: Int, to b: Int, block: Int) -> Int {
        var total = 0
        var k = a
        while k < b {
            let e = min(k + block, b)
            let s0 = max(0, min(k, e - block))
            var energy = 0.0
            for i in s0..<e { energy += p.x[i] * p.x[i] + p.y[i] * p.y[i] + p.z[i] * p.z[i] }
            if (energy / Double(e - s0)).squareRoot() >= stillBelow { total += e - k }
            k = e
        }
        return total
    }

    /// Whether the signal between two points, and one repeat either side of them, matches itself one
    /// repeat later. Too short a reach to tell is taken on the window's word.
    static func keeps(_ s: [Double], from a: Int, to b: Int, every lag: Int) -> Bool {
        let lo = max(0, a - lag), hi = min(s.count, b + lag)
        let m = hi - lag - lo
        guard m >= max(2, lag / 2) else { return true }
        var both = 0.0, uu = 0.0, vv = 0.0
        for i in lo..<(lo + m) {
            both += s[i] * s[i + lag]
            uu += s[i] * s[i]
            vv += s[i + lag] * s[i + lag]
        }
        guard uu > 0, vv > 0 else { return false }
        return both / (uu * vv).squareRoot() >= hereAtLeast
    }

    /// The one line through a window along which the wrist moved most.
    static func mainLine(_ p: Piece, from a: Int, to b: Int) -> (Double, Double, Double) {
        var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
        for i in a..<b {
            let x = p.x[i], y = p.y[i], z = p.z[i]
            xx += x * x; xy += x * y; xz += x * z; yy += y * y; yz += y * z; zz += z * z
        }
        // Start from the axis that moved most, and turn towards the line a few times over.
        var v: (Double, Double, Double) = (0, 0, 1)
        if xx >= yy, xx >= zz { v = (1, 0, 0) } else if yy >= zz { v = (0, 1, 0) }
        for _ in 0..<24 {
            let nx = xx * v.0 + xy * v.1 + xz * v.2
            let ny = xy * v.0 + yy * v.1 + yz * v.2
            let nz = xz * v.0 + yz * v.1 + zz * v.2
            let size = (nx * nx + ny * ny + nz * nz).squareRoot()
            guard size > 0 else { break }
            v = (nx / size, ny / size, nz / size)
        }
        return v
    }

    /// A signal with its own slow drift taken out: each reading less the mean of those around it.
    static func withoutSlow(_ v: [Double], span: Int) -> [Double] {
        let n = v.count
        guard n > 1 else { return v }
        var sums = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { sums[i + 1] = sums[i] + v[i] }
        let half = span / 2
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = max(0, i - half), b = min(n, i + half + 1)
            out[i] = v[i] - (sums[b] - sums[a]) / Double(b - a)
        }
        return out
    }

    /// Each reading as the mean of itself and its two neighbours, to settle jitter.
    static func smoothed(_ v: [Double]) -> [Double] {
        let n = v.count
        guard n > 2 else { return v }
        var out = v
        for i in 1..<(n - 1) { out[i] = (v[i - 1] + v[i] + v[i + 1]) / 3 }
        return out
    }
}

// MARK: - A session with no marks, split by its motion

/// A stretch of a recording and what the motion in it looks like: running, other work, or rest.
public struct MotionSpan: Equatable, Sendable {
    public var kind: MotionKind
    /// By the phone's clock, in seconds.
    public var start: Double
    public var end: Double

    public init(kind: MotionKind, start: Double, end: Double) { self.kind = kind; self.start = start; self.end = end }
}

/// Splits a recording that was not marked into parts, by the motion alone: running where the wrist
/// shows footfalls at a running pace, rest where it is still, work for everything between. A proposal,
/// shown as one. It does not tell one station from another, or a carry from a station.
public enum MotionSplit {
    /// Seconds in one step along the recording.
    static let step = 4.0
    /// A part shorter than this is folded into what is around it.
    static let shortest = 30.0
    /// The footfalls a minute taken for running, how well they must repeat, and how hard they must land.
    static let runBand = 140.0...215.0
    static let runBeat = 0.55
    static let runSize = 0.2
    /// The slowest movement still taken for movement: one repeat in this many seconds.
    static let slowest = 6.0

    public static func spans(_ track: MotionTrack, from: Double, to: Double) -> [MotionSpan] {
        guard !track.hasSeams, to > from else { return [] }
        var out: [MotionSpan] = []
        for stretch in track.stretches {
            guard let piece = MotionCounter.Piece(stretch, from: from, to: to, longest: slowest) else { continue }
            out += parts(of: piece)
        }
        return out
    }

    static func parts(of p: MotionCounter.Piece) -> [MotionSpan] {
        let fs = MotionCounter.fs
        let n = p.count
        let hop = LNum.int(step * fs), window = 2 * hop
        guard n >= window else { return [] }
        var kinds: [MotionKind] = []
        var k = 0
        while k + hop <= n {
            let w0 = min(max(0, k + hop / 2 - window / 2), n - window)
            var energy = 0.0, size = 0.0
            for i in w0..<(w0 + window) {
                energy += p.x[i] * p.x[i] + p.y[i] * p.y[i] + p.z[i] * p.z[i]
                size += p.size[i] * p.size[i]
            }
            let moving = (energy / Double(window)).squareRoot() >= MotionCounter.stillBelow
            let landing = (size / Double(window)).squareRoot() >= runSize
            var kind: MotionKind = moving ? .work : .rest
            if moving, landing {
                let beat = MotionCounter.read(p, at: w0, length: window, shortest: 60 / runBand.upperBound,
                                              longest: 60 / runBand.lowerBound, byFootfall: true)
                if beat.period != nil, beat.strength >= runBeat { kind = .run }
            }
            kinds.append(kind)
            k += hop
        }
        // One odd step inside a run is not a station: each step takes the kind most of its neighbours have.
        let reach = 3
        let order: [MotionKind] = [.run, .work, .rest]
        var settled = kinds
        for i in kinds.indices {
            var votes: [MotionKind: Int] = [:]
            for j in max(0, i - reach)...min(kinds.count - 1, i + reach) { votes[kinds[j], default: 0] += 1 }
            let top = votes.values.max() ?? 0
            if (votes[kinds[i]] ?? 0) < top, let winner = order.first(where: { (votes[$0] ?? 0) == top }) {
                settled[i] = winner
            }
        }
        var spans: [MotionSpan] = []
        for (i, kind) in settled.enumerated() {
            let start = p.start + Double(i) * step
            let end = i == settled.count - 1 ? p.start + Double(n) / fs : start + step
            if let last = spans.last, last.kind == kind {
                spans[spans.count - 1].end = end
            } else {
                spans.append(MotionSpan(kind: kind, start: start, end: end))
            }
        }
        // The shortest part is folded into its longer neighbour until none is too short to mean anything.
        while spans.count > 1 {
            var i = 0
            for j in spans.indices where spans[j].end - spans[j].start < spans[i].end - spans[i].start { i = j }
            guard spans[i].end - spans[i].start < shortest else { break }
            let before = i > 0 ? spans[i - 1].end - spans[i - 1].start : -1
            let after = i < spans.count - 1 ? spans[i + 1].end - spans[i + 1].start : -1
            if before >= after {
                spans[i - 1].end = spans[i].end
            } else {
                spans[i + 1].start = spans[i].start
            }
            spans.remove(at: i)
            // Two parts of a kind that now touch are one part.
            var joined: [MotionSpan] = []
            for span in spans {
                if let last = joined.last, last.kind == span.kind {
                    joined[joined.count - 1].end = span.end
                } else {
                    joined.append(span)
                }
            }
            spans = joined
        }
        return spans
    }
}

// MARK: - What is kept of a reading

/// A moment marked during a session: the start of a part, by its name.
public struct MotionMark: Equatable, Sendable {
    /// By the phone's clock, in seconds.
    public var at: Double
    public var text: String

    public init(at: Double, text: String) { self.at = at; self.text = text }
}

/// One part of a recording and what was counted in it.
public struct MotionPart: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var label: String
    public var kind: MotionKind
    /// Seconds from the start of the recording.
    public var startS: Double
    public var durationS: Double
    public var count: Int?
    public var perMinute: Double?
    public var steady: Double?
    /// The real number, entered by the athlete afterwards: steps a minute for running and walking,
    /// the count for the rest.
    public var actual: Int?

    public init(id: Int, label: String, kind: MotionKind, startS: Double, durationS: Double, count: Int? = nil,
                perMinute: Double? = nil, steady: Double? = nil, actual: Int? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.startS = startS; self.durationS = durationS
        self.count = count; self.perMinute = perMinute; self.steady = steady; self.actual = actual
    }

    /// The one number a part is known by: steps a minute for running and walking, the count for the rest.
    public var figure: Int? {
        guard let counted = count else { return nil }
        if kind.byPace { return perMinute.map { LNum.int($0.rounded()) } }
        return counted
    }

    /// What that number is a number of.
    public var figureUnit: String { kind.byPace ? "steps a minute" : kind.unit }

    /// The count as it is said. Nil when nothing was counted.
    public var said: String? {
        guard let counted = count else { return nil }
        if kind.byPace {
            guard let pace = figure else { return "no steady step" }
            return "\(pace) steps a minute"
        }
        guard counted > 0 else { return "no steady \(kind.unit)" }
        if let rate = perMinute { return "\(counted) \(kind.unit), \(LNum.int(rate.rounded())) a minute" }
        return "\(counted) \(kind.unit)"
    }

    /// The movement kept a beat for less than half of the time the wrist was moving.
    public var uneven: Bool { (steady ?? 1) < 0.5 && (count ?? 0) > 0 }
}

/// What was read from one recording: its parts, each with its count. Kept so that it does not have to
/// be worked out again, and so that it outlasts the recording.
public struct MotionRead: Codable, Equatable, Sendable, Identifiable {
    /// The recording's own name.
    public var id: String
    public var startedAt: Date
    public var seconds: Double
    public var parts: [MotionPart]
    /// The parts were worked out from the motion itself, because the session marked none.
    public var fromMotion: Bool
    /// Why nothing was counted, when nothing was.
    public var problem: String?
    /// How the recording's seconds joined: about one when they do (`MotionTrack.seamRatio`).
    public var seamRatio: Double?

    public init(id: String, startedAt: Date, seconds: Double, parts: [MotionPart] = [], fromMotion: Bool = false, problem: String? = nil) {
        self.id = id; self.startedAt = startedAt; self.seconds = seconds; self.parts = parts
        self.fromMotion = fromMotion; self.problem = problem
    }

    public var endedAt: Date { startedAt.addingTimeInterval(seconds) }

    public static let noMotion = "No motion reached the phone for this recording."
    public static let seams = "The seconds of this recording do not join up, and each join would be counted as a movement. Nothing is counted from it."

    /// A part shorter than this is not listed.
    static let shortestPart = 3.0

    /// Reads a recording. Where the session marked its parts, each is counted as what its name says it
    /// is. Where it marked none, the parts are worked out from the motion: running, work and rest.
    /// `other` is what a part with an unrecognised name is taken for.
    public static func make(id: String, startedAt: Date, seconds: Double, marks: [MotionMark], track: MotionTrack,
                            other: MotionKind = .work) -> MotionRead {
        var read = MotionRead(id: id, startedAt: startedAt, seconds: seconds)
        guard !track.isEmpty else { read.problem = noMotion; return read }
        read.seamRatio = track.seamRatio
        guard !track.hasSeams else { read.problem = seams; return read }
        let start = startedAt.timeIntervalSince1970, end = start + seconds
        let named = marks.filter { $0.at >= start - 5 && $0.at < end }.sorted { $0.at < $1.at }
        // One mark is a whole session under one name, which is worth keeping only when the name says
        // what the movement was.
        let marked = named.count >= 2 || (named.count == 1 && MotionKind.named(named[0].text) != nil)
        if marked {
            if let first = named.first, first.at - start >= 20 {
                read.parts.append(part(0, "Start", other, start, first.at, start, track))
            }
            for (i, mark) in named.enumerated() {
                let from = max(start, mark.at), to = i + 1 < named.count ? named[i + 1].at : end
                guard to - from >= shortestPart else { continue }
                let kind = MotionKind.infer(mark.text, other: other)
                read.parts.append(part(read.parts.count, mark.text, kind, from, to, start, track))
            }
        } else {
            read.fromMotion = true
            for span in MotionSplit.spans(track, from: start, to: end) {
                read.parts.append(part(read.parts.count, span.kind.title, span.kind, span.start, span.end, start, track))
            }
        }
        if read.parts.isEmpty { read.problem = noMotion }
        return read
    }

    private static func part(_ id: Int, _ label: String, _ kind: MotionKind, _ from: Double, _ to: Double,
                             _ start: Double, _ track: MotionTrack) -> MotionPart {
        var p = MotionPart(id: id, label: label, kind: kind, startS: from - start, durationS: to - from)
        if let c = MotionCounter.count(track, from: from, to: to, kind: kind) {
            p.count = c.count
            p.perMinute = c.perMinute
            p.steady = c.steady
        }
        return p
    }
}

/// What the athlete's own numbers say about the counting so far.
public struct MotionChecks: Equatable, Sendable {
    /// Parts with both a count and the real number.
    public var checked: Int
    /// How far off a count typically was, as a share of the real number.
    public var typicalError: Double

    public init(checked: Int, typicalError: Double) { self.checked = checked; self.typicalError = typicalError }

    public static func summary(_ reads: [MotionRead]) -> MotionChecks? {
        var errors: [Double] = []
        for read in reads {
            for part in read.parts {
                guard let figure = part.figure, let actual = part.actual, actual > 0 else { continue }
                errors.append(abs(Double(figure - actual)) / Double(actual))
            }
        }
        guard !errors.isEmpty else { return nil }
        errors.sort()
        return MotionChecks(checked: errors.count, typicalError: errors[errors.count / 2])
    }

    public var line: String {
        let percent = LNum.int((typicalError * 100).rounded())
        let times = checked == 1 ? "once" : "\(checked) times"
        return "Checked against your own numbers \(times): typically off by \(percent)%."
    }
}
