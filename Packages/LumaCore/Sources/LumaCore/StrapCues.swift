import Foundation

// MARK: - Cues on the wrist

/// The few buzzes Luma sends during a session, told apart by feel alone.
public enum StrapCue: String, Codable, Sendable, CaseIterable {
    /// One short buzz: a change of interval, breathe in.
    case one
    /// Two short buzzes: back in the zone, go again, breathe out.
    case two
    /// Three buzzes: ease off.
    case three
}

// MARK: - Zone guard

/// What the guard has to say about a heart-rate reading.
public enum ZoneSignal: Equatable, Sendable {
    /// Heart rate has stayed above the zone: ease off.
    case above
    /// Heart rate is back inside the zone after being above it.
    case back

    public var cue: StrapCue { self == .above ? .three : .two }
}

/// Watches heart rate against the top of a target zone during a session. It speaks when the reading
/// has stayed above the zone, and once more when it is back, so a single high beat or a reading that
/// hovers on the line does not set the strap off again and again.
public struct ZoneGuard: Equatable, Sendable {
    /// Top of the target zone, in beats a minute.
    public var ceiling: Double
    /// How long a reading must stay above the ceiling before the guard speaks.
    public var holdS: Double
    /// Beats below the ceiling a reading must fall to before it counts as back.
    public var marginBpm: Double
    /// The shortest gap between two "above" signals while heart rate stays high.
    public var quietS: Double

    private var aboveSince: Double?
    private var warnedAt: Double?
    private var out = false

    public init(ceiling: Double, holdS: Double = 8, marginBpm: Double = 3, quietS: Double = 45) {
        self.ceiling = ceiling; self.holdS = holdS; self.marginBpm = marginBpm; self.quietS = quietS
    }

    /// True between an "above" signal and the "back" that answers it.
    public var isAbove: Bool { out }

    /// One reading taken `t` seconds into the session. A missing reading changes nothing.
    public mutating func feed(hr: Double?, at t: Double) -> ZoneSignal? {
        guard let hr, hr > 0 else { return nil }
        if hr > ceiling {
            if aboveSince == nil { aboveSince = t }
            guard let since = aboveSince, t - since >= holdS else { return nil }
            if !out {
                out = true
                warnedAt = t
                return .above
            }
            if let warned = warnedAt, t - warned >= quietS {
                warnedAt = t
                return .above
            }
            return nil
        }
        aboveSince = nil
        if out, hr <= ceiling - marginBpm {
            out = false
            return .back
        }
        return nil
    }

    /// The top of zone `zone` (1 to 4) in the athlete's own zones. Zone 5 has no top to guard.
    public static func ceiling(of zone: Int, in zones: HXZones) -> Double? {
        guard zone >= 1, zone < zones.bounds.count else { return nil }
        let top = zones.bounds[zone]
        return top > 0 ? top : nil
    }
}

// MARK: - Go again

/// When to start the next effort, judged by heart rate instead of a fixed clock: once it has come down
/// to a target, and never before a shortest rest or after a longest one.
public struct GoAgain: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        /// Heart rate reached the target.
        case recovered
        /// The longest rest ran out first.
        case time
    }

    /// Heart rate to come down to, in beats a minute.
    public var targetBpm: Double
    public var minRestS: Double
    public var maxRestS: Double
    /// How long the reading must stay at or under the target.
    public var holdS: Double

    private var underSince: Double?

    public init(targetBpm: Double, minRestS: Double = 15, maxRestS: Double = 180, holdS: Double = 3) {
        self.targetBpm = targetBpm; self.minRestS = minRestS; self.maxRestS = maxRestS; self.holdS = holdS
    }

    /// The default target: seven tenths of the athlete's highest heart rate.
    public static let defaultShare = 0.7

    public static func target(maxHR: Double, share: Double = defaultShare) -> Double {
        (maxHR * LStat.clamp(share, 0.5, 0.9)).rounded()
    }

    /// One reading taken `t` seconds into the rest. Returns why the rest is over, once it is.
    public mutating func feed(hr: Double?, at t: Double) -> Reason? {
        if t >= maxRestS { return .time }
        guard let hr, hr > 0 else {
            underSince = nil
            return nil
        }
        if hr <= targetBpm {
            if underSince == nil { underSince = t }
            if let since = underSince, t - since >= holdS, t >= minRestS { return .recovered }
        } else {
            underSince = nil
        }
        return nil
    }
}
