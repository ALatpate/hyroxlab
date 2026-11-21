import Foundation

// MARK: - Breathing paces

/// One part of a breath.
public enum BreathPart: String, Codable, Sendable {
    case breatheIn, holdFull, breatheOut, holdEmpty

    public var title: String {
        switch self {
        case .breatheIn: return "Breathe in"
        case .holdFull, .holdEmpty: return "Hold"
        case .breatheOut: return "Breathe out"
        }
    }

    /// What the strap does as this part begins: one buzz in, two out, nothing for a hold.
    public var cue: StrapCue? {
        switch self {
        case .breatheIn: return .one
        case .breatheOut: return .two
        case .holdFull, .holdEmpty: return nil
        }
    }
}

/// A breathing pace: seconds in, held, out and held again.
public struct BreathPace: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var note: String
    public var inS: Double
    public var holdFullS: Double
    public var outS: Double
    public var holdEmptyS: Double

    public init(id: String, title: String, note: String, inS: Double, holdFullS: Double = 0, outS: Double, holdEmptyS: Double = 0) {
        self.id = id; self.title = title; self.note = note
        self.inS = inS; self.holdFullS = holdFullS; self.outS = outS; self.holdEmptyS = holdEmptyS
    }

    public var cycleS: Double { inS + holdFullS + outS + holdEmptyS }
    public var breathsPerMinute: Double { cycleS > 0 ? 60 / cycleS : 0 }

    public static let calm = BreathPace(id: "calm", title: "Calm", note: "4 in, 6 out. A longer breath out settles the body.", inS: 4, outS: 6)
    public static let even = BreathPace(id: "even", title: "Even", note: "5.5 in, 5.5 out. About five and a half breaths a minute.", inS: 5.5, outS: 5.5)
    public static let box = BreathPace(id: "box", title: "Box", note: "4 in, hold 4, 4 out, hold 4. Steadying before an effort.",
                                       inS: 4, holdFullS: 4, outS: 4, holdEmptyS: 4)
    public static let all: [BreathPace] = [.calm, .even, .box]

    /// The parts of one breath in order, with their lengths. Parts of no length are left out.
    public var parts: [(part: BreathPart, seconds: Double)] {
        let all: [(part: BreathPart, seconds: Double)] = [(part: .breatheIn, seconds: inS), (part: .holdFull, seconds: holdFullS),
                                                          (part: .breatheOut, seconds: outS), (part: .holdEmpty, seconds: holdEmptyS)]
        return all.filter { $0.seconds > 0 }
    }

    /// Where a session is `t` seconds after it started.
    public func moment(at t: Double) -> BreathMoment {
        let cycle = cycleS
        guard cycle > 0, t >= 0 else { return BreathMoment(part: .breatheIn, progress: 0, remainingS: inS, breath: 0, fill: 0) }
        let breath = LNum.int((t / cycle).rounded(.down))
        var into = t - Double(breath) * cycle
        for (part, seconds) in parts {
            if into < seconds {
                let progress = into / seconds
                let fill: Double
                switch part {
                case .breatheIn: fill = progress
                case .holdFull: fill = 1
                case .breatheOut: fill = 1 - progress
                case .holdEmpty: fill = 0
                }
                return BreathMoment(part: part, progress: progress, remainingS: seconds - into, breath: breath, fill: fill)
            }
            into -= seconds
        }
        return BreathMoment(part: .breatheIn, progress: 0, remainingS: inS, breath: breath + 1, fill: 0)
    }
}

public struct BreathMoment: Equatable, Sendable {
    public var part: BreathPart
    /// 0 at the start of the part, 1 at its end.
    public var progress: Double
    public var remainingS: Double
    /// Breaths completed before this one.
    public var breath: Int
    /// How full the lungs are drawn: 0 empty, 1 full.
    public var fill: Double
}

// MARK: - Beat-to-beat variation, live

/// Beat-to-beat variation from the strap's own intervals as they arrive. The figure is RMSSD over the
/// most recent window, the same measure the nightly HRV uses, taken over a much shorter stretch, so it
/// moves more and is only compared with itself inside one sitting.
public struct LiveHRV: Equatable, Sendable {
    /// Seconds of beats the figure is worked out over.
    public var windowS: Double
    /// Fewest beats before a figure is given.
    public var minBeats: Int

    private var beats: [(t: Double, ms: Double)] = []

    public init(windowS: Double = 60, minBeats: Int = 20) {
        self.windowS = windowS; self.minBeats = minBeats
    }

    public static func == (a: LiveHRV, b: LiveHRV) -> Bool {
        a.windowS == b.windowS && a.minBeats == b.minBeats && a.beats.count == b.beats.count
            && zip(a.beats, b.beats).allSatisfy { $0.t == $1.t && $0.ms == $1.ms }
    }

    /// An interval a heart can produce at rest or in light work. Anything else is a missed or doubled beat.
    public static func plausible(_ ms: Double) -> Bool { ms >= 300 && ms <= 2000 }

    /// Intervals in milliseconds that arrived `t` seconds into the sitting.
    public mutating func add(_ intervals: [Double], at t: Double) {
        for ms in intervals where LiveHRV.plausible(ms) { beats.append((t, ms)) }
        beats.removeAll { t - $0.t > windowS }
    }

    public var beatCount: Int { beats.count }

    /// RMSSD in milliseconds, or nil with too few beats. A jump of more than a fifth between neighbours
    /// is taken for a missed beat and that pair is left out.
    public var rmssd: Double? { LiveHRV.rmssd(beats.map { $0.ms }, minBeats: minBeats) }

    /// Mean heart rate over the window, from the same intervals.
    public var heartRate: Double? {
        guard beats.count >= 3, let mean = LStat.mean(beats.map { $0.ms }), mean > 0 else { return nil }
        return 60_000 / mean
    }

    public static func rmssd(_ intervals: [Double], minBeats: Int = 20) -> Double? {
        let clean = intervals.filter(plausible)
        guard clean.count >= max(2, minBeats) else { return nil }
        var squares: [Double] = []
        for i in 1..<clean.count {
            let a = clean[i - 1], b = clean[i]
            guard abs(b - a) <= 0.2 * a else { continue }
            squares.append((b - a) * (b - a))
        }
        guard squares.count >= max(1, minBeats / 2), let mean = LStat.mean(squares) else { return nil }
        return mean.squareRoot()
    }
}

/// What a breathing sitting came to: the variation at its start against its end.
public struct BreathOutcome: Codable, Equatable, Sendable, Identifiable {
    public var id: Double { endedAt }
    public var endedAt: Double
    public var paceID: String
    public var seconds: Double
    public var hrvBefore: Double?
    public var hrvAfter: Double?
    public var heartRateBefore: Double?
    public var heartRateAfter: Double?

    public init(endedAt: Double, paceID: String, seconds: Double, hrvBefore: Double?, hrvAfter: Double?,
                heartRateBefore: Double?, heartRateAfter: Double?) {
        self.endedAt = endedAt; self.paceID = paceID; self.seconds = seconds
        self.hrvBefore = hrvBefore; self.hrvAfter = hrvAfter
        self.heartRateBefore = heartRateBefore; self.heartRateAfter = heartRateAfter
    }

    /// One plain line on what changed, or nil when either end has no figure.
    public var line: String? {
        guard let a = hrvBefore, let b = hrvAfter, a > 0 else { return nil }
        let change = (b - a) / a
        if change >= 0.1 { return "Beat-to-beat variation rose from \(LNum.int(a.rounded())) to \(LNum.int(b.rounded())) ms." }
        if change <= -0.1 { return "Beat-to-beat variation fell from \(LNum.int(a.rounded())) to \(LNum.int(b.rounded())) ms." }
        return "Beat-to-beat variation held near \(LNum.int(b.rounded())) ms."
    }
}
