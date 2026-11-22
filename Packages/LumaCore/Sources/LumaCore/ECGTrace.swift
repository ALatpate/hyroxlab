import Foundation

// MARK: - A trace from the clasp
//
// A WHOOP MG has two electrodes in its clasp, and can send the signal between them: a trace of the
// heart's electrical beat, taken while the clasp is held with the other hand. This file reads such a
// trace for two things only: where its beats are, and so the heart rate and how much the time between
// beats varies.
//
// It is a trial, and it is instrumentation. Luma does not look for rhythm problems, gives no verdict on
// a trace, and never shows what the strap's own software concluded about one: that conclusion is left
// out of everything handed to this file (`ECGPacket`). The amplitude has no known unit and is drawn
// as it arrives.
//
// Three things are measured, not assumed, because none of them has been checked on a strap from here:
//
//  - How fast the trace is read. The strap layer's notes say the pace is not established, so it is
//    taken from this reading's own packets: how many readings came in how many seconds, by the phone's
//    clock, and by the strap's where the two agree. Without it no beat is timed.
//  - That the packets join up. The trace comes about a packet a second. If the packets do not join,
//    every join looks like a beat, and the answer is sixty a minute: a believable heart rate. A trace
//    with such joins is not counted from (`ECGReader.seamLimit`).
//  - That the beats stand clear of what is between them. Where they do not, no figure is given.

/// One packet of the trace, as the strap layer decoded it. What the strap's own software concluded
/// about the trace is not carried here, on purpose: there is no field for it.
public struct ECGPacket: Equatable, Sendable {
    /// The packet's number in the strap's own count.
    public var sequence: Int
    /// The phone's clock when it arrived, in milliseconds.
    public var arrivedMs: Int
    /// The strap's own clock for the packet, in seconds, where it gave one.
    public var strapTime: Double?
    /// The readings, as whole numbers of no known unit.
    public var samples: [Int]
    /// The clasp was being touched.
    public var contact: Bool
    /// The heart rate the strap itself put on the trace at this point, where it gave one.
    public var strapHeartRate: Int?

    public init(sequence: Int, arrivedMs: Int, strapTime: Double? = nil, samples: [Int], contact: Bool = true, strapHeartRate: Int? = nil) {
        self.sequence = sequence; self.arrivedMs = arrivedMs; self.strapTime = strapTime
        self.samples = samples; self.contact = contact; self.strapHeartRate = strapHeartRate
    }
}

/// Why a trace gave no figure. Each is about the reading, never about the heart.
public enum ECGProblem: String, Codable, Sendable, CaseIterable {
    case nothing, flat, timing, joins, few, unclear

    public var text: String {
        switch self {
        case .nothing: return "No trace reached the phone."
        case .flat: return "The strap sent a flat line: it had not settled, or the clasp was not being held."
        case .timing: return "Too little of the trace arrived, or it arrived too unevenly, to tell how fast it was read. Without that, beats cannot be timed."
        case .joins: return "The pieces of this trace do not join up, and each join would be counted as a beat. Nothing is counted from it."
        case .few: return "Too few beats could be picked out of this trace to give a figure."
        case .unclear: return "The beats in this trace could not be followed well enough to give a figure."
        }
    }
}

/// What was read from one trace, and the trace itself.
public struct ECGRead: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var takenAt: Date
    public var packets = 0
    /// Packets missing from the strap's own count.
    public var lost = 0
    public var samples = 0
    /// Readings a second, as measured from this reading.
    public var perSecond: Double?
    /// Whether the strap's own clock gave the same pace as the phone's. Nil where the strap gave no clock.
    public var clocksAgree: Bool?
    public var beats = 0
    /// Beats a minute, from the usual time between beats.
    public var heartRate: Double?
    /// How much the time between one beat and the next changes, in milliseconds (RMSSD).
    public var variationMs: Double?
    /// The times between beats, in milliseconds, in order.
    public var intervalsMs: [Int] = []
    /// The share of the trace taken while the clasp was being touched.
    public var contactShare = 0.0
    /// The heart rate the strap itself put on the trace.
    public var strapHeartRate: Int?
    /// The heart rate from the wrist's light sensor at the time.
    public var wristHeartRate: Int?
    /// How the packets join: about one when they do.
    public var seamRatio = 1.0
    public var problem: ECGProblem?
    /// The trace, for drawing: whole numbers of no known unit.
    public var trace: [Int] = []
    /// Where the beats found are, in readings along `trace`.
    public var beatsAt: [Int] = []

    public init(id: String, takenAt: Date) { self.id = id; self.takenAt = takenAt }

    /// Seconds of trace, where its pace was measured.
    public var seconds: Double? { perSecond.map { Double(samples) / $0 } }

    /// The heart rate as a whole number, for showing.
    public var beatsAMinute: Int? { heartRate.map { LNum.int($0.rounded()) } }
}

public enum ECGReader {
    /// Above this the packets do not join up, and nothing is counted from the trace.
    static let seamLimit = 2.0
    /// How near the strap's clock and the phone's must be on the pace of the readings.
    static let clocksWithin = 0.03
    /// How far the beats must stand above what is between them.
    static let standAtLeast = 6.0
    /// Beats sitting on packet joins, as a share of all found, at which the joins are taken for the beats.
    static let onJoinsLimit = 0.6
    /// The most readings of a trace that are kept.
    static let traceLimit = 6000

    /// Reads a trace from its packets.
    public static func read(id: String, takenAt: Date, packets: [ECGPacket], wristHeartRate: Int? = nil) -> ECGRead {
        work(id: id, takenAt: takenAt, packets: packets, wristHeartRate: wristHeartRate, guarded: true)
    }

    /// The reading with the checks on packet joins left out. It is here so that a test can show what
    /// those checks are for; nothing else calls it.
    static func unguarded(id: String, takenAt: Date, packets: [ECGPacket]) -> ECGRead {
        work(id: id, takenAt: takenAt, packets: packets, wristHeartRate: nil, guarded: false)
    }

    static func work(id: String, takenAt: Date, packets: [ECGPacket], wristHeartRate: Int?, guarded: Bool) -> ECGRead {
        var out = ECGRead(id: id, takenAt: takenAt)
        out.wristHeartRate = wristHeartRate
        var seen = Set<Int>()
        var ps: [ECGPacket] = []
        for p in packets.sorted(by: { $0.sequence < $1.sequence }) {
            if seen.insert(p.sequence).inserted { ps.append(p) }
        }
        out.packets = ps.count
        var total = 0
        var touched = 0
        var rates: [Double] = []
        for p in ps {
            total += p.samples.count
            if p.contact { touched += p.samples.count }
            if let hr = p.strapHeartRate, hr > 0 { rates.append(Double(hr)) }
        }
        out.samples = total
        guard let first = ps.first, let last = ps.last, total > 0 else { out.problem = .nothing; return out }
        out.lost = max(0, last.sequence - first.sequence + 1 - ps.count)
        out.contactShare = Double(touched) / Double(total)
        out.strapHeartRate = median(rates).map { LNum.int($0) }

        // Packets in unbroken sequence make a run. Nothing is measured or joined across a lost packet.
        var runs: [[Int]] = []
        var joins: [(run: Int, at: Int)] = []
        var ratios: [Double] = []
        var phone: [[(count: Int, at: Double)]] = []
        var strap: [[(count: Int, at: Double)]] = []
        let strapClock = ps.allSatisfy { $0.strapTime != nil }
        var position = 0
        for (k, p) in ps.enumerated() {
            if k == 0 || p.sequence != ps[k - 1].sequence + 1 {
                runs.append([]); phone.append([]); strap.append([])
            } else {
                let run = runs[runs.count - 1]
                let s = p.samples
                if run.count >= 2, s.count >= 2 {
                    // The step across the join, against the step just before it and the step just after.
                    let across = Double(abs(s[0] - run[run.count - 1]))
                    let beside = Double(abs(run[run.count - 1] - run[run.count - 2]) + abs(s[1] - s[0])) / 2
                    ratios.append((across + 1) / (beside + 1))
                    joins.append((run: runs.count - 1, at: run.count))
                }
            }
            phone[phone.count - 1].append((count: position, at: Double(p.arrivedMs) / 1000))
            if strapClock, let t = p.strapTime { strap[strap.count - 1].append((count: position, at: t)) }
            runs[runs.count - 1].append(contentsOf: p.samples)
            position += p.samples.count
        }
        if ratios.count >= 10, let middle = median(ratios) { out.seamRatio = middle }

        var all: [Int] = []
        for run in runs { all.append(contentsOf: run) }
        let dropped = max(0, all.count - traceLimit)
        out.trace = Array(all[dropped...])

        // The pace: by the phone's clock, and by the strap's where the strap gave one and it agrees.
        let byPhone = perSecond(phone)
        let byStrap = strapClock ? perSecond(strap) : nil
        var pace = byPhone
        if let a = byPhone, let b = byStrap {
            let agree = abs(a - b) <= clocksWithin * b
            out.clocksAgree = agree
            pace = agree ? b : nil
        }
        guard let fs = pace, fs >= 40, fs <= 1200 else { out.problem = .timing; return out }
        out.perSecond = fs
        if guarded, out.seamRatio > seamLimit { out.problem = .joins; return out }

        // Beats, a stretch of trace at a time.
        var series: [[Double]] = []
        var stands: [Double] = []
        var marks: [Int] = []
        var found = 0, near = 0, usable = 0, offset = 0
        let zeroRun = max(2, LNum.int(0.3 * fs))
        for (ri, run) in runs.enumerated() {
            for span in stretches(of: run, zeroRun: zeroRun) {
                usable += span.count
                var piece = [Double](repeating: 0, count: span.count)
                for i in 0..<span.count { piece[i] = Double(run[span.lowerBound + i]) }
                let got = beats(in: piece, perSecond: fs)
                if got.at.count >= 3 { stands.append(got.stand) }
                found += got.at.count
                for f in got.at {
                    let at = Double(span.lowerBound) + f
                    marks.append(offset + LNum.int(at.rounded()))
                    if joins.contains(where: { $0.run == ri && abs(at - Double($0.at)) <= 2 }) { near += 1 }
                }
                var between: [Double] = []
                if got.at.count >= 2 {
                    for i in 1..<got.at.count { between.append((got.at[i] - got.at[i - 1]) / fs) }
                }
                series.append(between)
            }
            offset += run.count
        }
        out.beats = found
        out.beatsAt = marks.map { $0 - dropped }.filter { $0 >= 0 }
        guard Double(usable) >= 2 * fs else { out.problem = .flat; return out }
        var every: [Double] = []
        for s in series { every.append(contentsOf: s) }
        let good = every.filter { $0 >= 0.3 && $0 <= 2.0 }
        guard found >= 8, good.count >= 6, let mid = median(good) else { out.problem = .few; return out }
        guard let stand = median(stands), stand >= standAtLeast else { out.problem = .unclear; return out }
        if guarded, Double(near) >= onJoinsLimit * Double(found) { out.problem = .joins; return out }

        // A time between beats far from the usual one is a beat missed, or one too many: it is left out.
        func usual(_ v: Double) -> Bool { v >= 0.3 && v <= 2.0 && abs(v - mid) <= 0.3 * mid }
        let kept = every.filter { usual($0) }
        guard Double(kept.count) >= 0.6 * Double(every.count) else { out.problem = .unclear; return out }
        out.heartRate = 60 / mid
        out.intervalsMs = kept.prefix(300).map { LNum.int(($0 * 1000).rounded()) }
        var squares = 0.0
        var pairs = 0
        for s in series where s.count >= 2 {
            for i in 1..<s.count where usual(s[i - 1]) && usual(s[i]) {
                let d = s[i] - s[i - 1]
                squares += d * d
                pairs += 1
            }
        }
        if pairs >= 10 { out.variationMs = 1000 * (squares / Double(pairs)).squareRoot() }
        return out
    }

    // MARK: The working

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        return v.sorted()[v.count / 2]
    }

    /// Readings a second, from where each packet starts in the count and when it came. The pace is
    /// taken between each packet and the one half its run later, and the middle one of all is kept,
    /// so that packets which arrived in a bunch do not bend it.
    static func perSecond(_ runs: [[(count: Int, at: Double)]]) -> Double? {
        var slopes: [Double] = []
        for run in runs where run.count >= 8 {
            let half = run.count / 2
            for i in 0..<(run.count - half) {
                let dt = run[i + half].at - run[i].at
                if dt > 0 { slopes.append(Double(run[i + half].count - run[i].count) / dt) }
            }
        }
        guard slopes.count >= 4 else { return nil }
        return median(slopes)
    }

    /// The stretches of a run that are trace. The zeros a run opens with while the strap settles, and
    /// any later stretch of zeros, are not.
    static func stretches(of run: [Int], zeroRun: Int) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        let n = run.count
        var j = 0
        while j < n {
            if run[j] == 0 {
                var k = j
                while k < n, run[k] == 0 { k += 1 }
                if k - j >= zeroRun || j == 0 {
                    if let s = start, j > s { out.append(s..<j) }
                    start = nil
                    j = k
                    continue
                }
            }
            if start == nil { start = j }
            j += 1
        }
        if let s = start, n > s { out.append(s..<n) }
        return out
    }

    /// Each reading as the mean of those within a span around it.
    static func movingMean(_ v: [Double], span: Int) -> [Double] {
        let n = v.count
        var sums = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { sums[i + 1] = sums[i] + v[i] }
        let half = span / 2
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let a = max(0, i - half), b = min(n, i + half + 1)
            out[i] = (sums[b] - sums[a]) / Double(b - a)
        }
        return out
    }

    /// The beats in one unbroken stretch of trace: where each is, in readings and parts of a reading,
    /// and how far the beats stand above what is between them.
    ///
    /// The slow drift is taken out, and what is left is turned into how sharply the trace is changing,
    /// which is where a beat stands out whichever way up the trace is. A beat is a place where that
    /// stands highest for a quarter of a second around; its exact moment is the tip of the trace there.
    static func beats(in x: [Double], perSecond fs: Double) -> (at: [Double], stand: Double) {
        let n = x.count
        guard n >= LNum.int(2 * fs), n > 2 else { return ([], 0) }
        let base = movingMean(x, span: max(3, LNum.int((0.2 * fs).rounded())))
        var flat = [Double](repeating: 0, count: n)
        for i in 0..<n { flat[i] = x[i] - base[i] }
        var change = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let d = flat[i + 1] - flat[i - 1]
            change[i] = d * d
        }
        let sharp = movingMean(change, span: max(3, LNum.int((0.12 * fs).rounded())))
        let reach = max(1, LNum.int((0.25 * fs).rounded()) / 2)
        var candidates: [Int] = []
        for i in 1..<(n - 1) {
            guard sharp[i] > 0, sharp[i] > sharp[i - 1] else { continue }
            var highest = true
            for j in max(0, i - reach)..<min(n, i + reach + 1) where sharp[j] > sharp[i] {
                highest = false
                break
            }
            if highest { candidates.append(i) }
        }
        guard candidates.count >= 3 else { return ([], 0) }
        // Beats are the tall ones: a rise counts when it is at least a third as tall as the tall ones are.
        let heights = candidates.map { sharp[$0] }.sorted()
        let tall = heights[min(heights.count - 1, LNum.int(0.9 * Double(heights.count)))]
        let kept = candidates.filter { sharp[$0] >= 0.3 * tall }
        let floor = median(sharp) ?? 0
        let level = median(kept.map { sharp[$0] }) ?? 0
        let stand = floor > 0 ? min(1_000_000, level / floor) : 1_000_000

        // Which way up the beats point: the way most of them do.
        let window = max(1, LNum.int((0.06 * fs).rounded()))
        var ups = 0
        for i in kept {
            var j = max(0, i - window)
            for k in max(0, i - window)..<min(n, i + window + 1) where abs(flat[k]) > abs(flat[j]) { j = k }
            if flat[j] > 0 { ups += 1 }
        }
        let way: Double = ups * 2 >= kept.count ? 1 : -1
        var at: [Double] = []
        for i in kept {
            let a = max(1, i - window), b = min(n - 1, i + window + 1)
            guard a < b else { continue }
            var j = a
            for k in a..<b where way * flat[k] > way * flat[j] { j = k }
            // The tip usually falls between two readings: the readings either side of it say where.
            let l = way * flat[j - 1], m = way * flat[j], r = way * flat[j + 1]
            let bend = l - 2 * m + r
            let fine = Double(j) + (bend < 0 ? 0.5 * (l - r) / bend : 0)
            // Two rises can belong to one beat: it is one beat.
            if let last = at.last, fine - last < 0.2 * fs { continue }
            at.append(fine)
        }
        return (at, stand)
    }
}
