import Foundation

// MARK: - Run samples

/// One sample of a run's progress: cumulative distance and elapsed seconds, optional HR and altitude.
public struct RunSample: Codable, Equatable, Sendable {
    public var tS: Double
    public var distanceM: Double
    public var hr: Double?
    public var altitudeM: Double?
    public var lat: Double?
    public var lon: Double?

    public init(tS: Double, distanceM: Double, hr: Double? = nil, altitudeM: Double? = nil, lat: Double? = nil, lon: Double? = nil) {
        self.tS = tS; self.distanceM = distanceM; self.hr = hr; self.altitudeM = altitudeM; self.lat = lat; self.lon = lon
    }
}

public struct RunLap: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let distanceM: Double
    public let seconds: Double
    public let paceSPerKm: Double
    public let avgHR: Double?
    public let isPartial: Bool

    public init(index: Int, distanceM: Double, seconds: Double, paceSPerKm: Double, avgHR: Double?, isPartial: Bool) {
        self.index = index; self.distanceM = distanceM; self.seconds = seconds
        self.paceSPerKm = paceSPerKm; self.avgHR = avgHR; self.isPartial = isPartial
    }
}

public struct HRZoneShare: Equatable, Sendable, Identifiable {
    public var id: Int { zone }
    public let zone: Int        // 1…5
    public let seconds: Double
    public let fraction: Double
}

public struct PersonalBest: Codable, Equatable, Sendable, Identifiable {
    public var id: Double { distanceM }
    public let distanceM: Double
    public let seconds: Double
    public init(distanceM: Double, seconds: Double) { self.distanceM = distanceM; self.seconds = seconds }
    public var label: String {
        switch distanceM {
        case 1000: return "1 km"
        case 1609: return "1 mile"
        case 5000: return "5 km"
        case 10000: return "10 km"
        case 21097: return "Half marathon"
        default: return "\(Int(distanceM)) m"
        }
    }
}

// MARK: - Pace smoothing

/// Rolling pace over a trailing window of distance samples. Never reports faster than `floorSPerKm`.
public struct PaceSmoother: Sendable {
    public var windowS: Double
    public var floorSPerKm: Double
    private var buffer: [(t: Double, d: Double)] = []

    public init(windowS: Double = 10, floorSPerKm: Double = 150) {
        self.windowS = windowS; self.floorSPerKm = floorSPerKm
    }

    /// Feed cumulative distance at time t; returns smoothed pace in s/km or nil while warming up.
    public mutating func push(tS: Double, distanceM: Double) -> Double? {
        buffer.append((tS, distanceM))
        while let first = buffer.first, tS - first.t > windowS { buffer.removeFirst() }
        guard let first = buffer.first, buffer.count >= 2 else { return nil }
        let dt = tS - first.t, dd = distanceM - first.d
        guard dt >= 3, dd > 1 else { return nil }
        let pace = dt / (dd / 1000)
        return max(pace, floorSPerKm)
    }

    public mutating func reset() { buffer.removeAll() }
}

// MARK: - Zones

public struct HXZones: Codable, Equatable, Sendable {
    /// Lower bounds of zones 1…5 in bpm (zone 1 starts at `bounds[0]`).
    public let bounds: [Double]

    public init(bounds: [Double]) { self.bounds = bounds }

    /// Five zones from max HR: 50/60/70/80/90 %.
    public static func fromMaxHR(_ max: Double) -> HXZones {
        HXZones(bounds: [0.5, 0.6, 0.7, 0.8, 0.9].map { $0 * max })
    }
    /// Five zones from lactate-threshold HR (Friel-style): <85 / 85–89 / 90–94 / 95–99 / ≥100 % of LTHR.
    public static func fromLTHR(_ lthr: Double) -> HXZones {
        HXZones(bounds: [0.0, 0.85, 0.90, 0.95, 1.0].map { $0 * lthr })
    }
    /// Age estimate when nothing better exists.
    public static func fromAge(_ age: Int) -> HXZones { fromMaxHR(Double(208 - Int(Double(age) * 0.7))) }

    public func zone(for hr: Double) -> Int {
        var z = 1
        for (i, b) in bounds.enumerated() where hr >= b { z = i + 1 }
        return min(5, max(1, z))
    }
}

// MARK: - Run analytics

public enum RunAnalytics {
    /// Auto-laps at `lapM` from cumulative samples; the final partial lap is flagged.
    public static func laps(_ samples: [RunSample], lapM: Double = 1000) -> [RunLap] {
        guard samples.count >= 2, lapM > 0 else { return [] }
        var laps: [RunLap] = []
        var lapStartT = samples[0].tS, lapStartD = samples[0].distanceM
        var nextMark = lapStartD + lapM
        var hrAcc: [Double] = []
        var prev = samples[0]
        for s in samples.dropFirst() {
            if let h = s.hr { hrAcc.append(h) }
            while s.distanceM >= nextMark {
                // Interpolate the crossing time.
                let frac = (nextMark - prev.distanceM) / max(1e-6, s.distanceM - prev.distanceM)
                let tCross = prev.tS + frac * (s.tS - prev.tS)
                let secs = tCross - lapStartT
                laps.append(RunLap(index: laps.count + 1, distanceM: lapM, seconds: secs,
                                paceSPerKm: secs / (lapM / 1000), avgHR: HXStats.mean(hrAcc), isPartial: false))
                lapStartT = tCross; lapStartD = nextMark; nextMark += lapM
                hrAcc.removeAll()
            }
            prev = s
        }
        let remD = prev.distanceM - lapStartD
        if remD > 50 {
            let secs = prev.tS - lapStartT
            laps.append(RunLap(index: laps.count + 1, distanceM: remD, seconds: secs,
                            paceSPerKm: secs / (remD / 1000), avgHR: HXStats.mean(hrAcc), isPartial: true))
        }
        return laps
    }

    /// Fastest contiguous window covering `distanceM`, via two pointers over cumulative samples.
    public static func fastest(_ samples: [RunSample], distanceM: Double) -> Double? {
        guard samples.count >= 2, let last = samples.last, last.distanceM >= distanceM else { return nil }
        var best = Double.infinity
        var j = 0
        for i in 0..<samples.count {
            while j < samples.count, samples[j].distanceM - samples[i].distanceM < distanceM { j += 1 }
            guard j < samples.count else { break }
            // Interpolate exact crossing between j-1 and j.
            let a = samples[j - 1], b = samples[j]
            let need = samples[i].distanceM + distanceM
            let frac = (need - a.distanceM) / max(1e-6, b.distanceM - a.distanceM)
            let tCross = a.tS + frac * (b.tS - a.tS)
            best = min(best, tCross - samples[i].tS)
        }
        return best.isFinite ? best : nil
    }

    public static let pbDistances: [Double] = [1000, 1609, 5000, 10000, 21097]

    public static func personalBests(_ samples: [RunSample]) -> [PersonalBest] {
        pbDistances.compactMap { d in fastest(samples, distanceM: d).map { PersonalBest(distanceM: d, seconds: $0) } }
    }

    /// Time in each HR zone from 1 Hz-ish samples.
    public static func zoneShares(_ samples: [RunSample], zones: HXZones) -> [HRZoneShare] {
        var secs = [Double](repeating: 0, count: 5)
        var prev: RunSample? = nil
        for s in samples {
            if let p = prev, let h = s.hr { secs[zones.zone(for: h) - 1] += max(0, s.tS - p.tS) }
            prev = s
        }
        let total = secs.reduce(0, +)
        return (0..<5).map { HRZoneShare(zone: $0 + 1, seconds: secs[$0], fraction: total > 0 ? secs[$0] / total : 0) }
    }

    /// Aerobic decoupling: (pace/HR efficiency first half) vs second half, as a percent. >5 % suggests
    /// the run was beyond current aerobic fitness or conditions were hard. nil when HR is missing.
    public static func decouplingPercent(_ samples: [RunSample]) -> Double? {
        guard let last = samples.last, last.distanceM > 1000 else { return nil }
        let half = last.distanceM / 2
        let a = samples.filter { $0.distanceM <= half }, b = samples.filter { $0.distanceM > half }
        guard let ea = efficiency(a), let eb = efficiency(b), ea > 0 else { return nil }
        return (ea - eb) / ea * 100
    }

    /// Speed per heartbeat (m/s ÷ bpm) over a stretch.
    private static func efficiency(_ s: [RunSample]) -> Double? {
        guard let f = s.first, let l = s.last, l.tS > f.tS + 60 else { return nil }
        let hrs = s.compactMap(\.hr)
        guard let hr = HXStats.mean(hrs), hr > 60 else { return nil }
        let speed = (l.distanceM - f.distanceM) / (l.tS - f.tS)
        return speed / hr
    }

    /// Elevation gain from altitude samples with a 3 m hysteresis to ignore GPS jitter.
    public static func elevationGainM(_ samples: [RunSample]) -> Double {
        var gain = 0.0
        var ref: Double? = nil
        for s in samples {
            guard let a = s.altitudeM else { continue }
            guard let r = ref else { ref = a; continue }
            if a - r >= 3 { gain += a - r; ref = a } else if r - a >= 3 { ref = a }
        }
        return gain
    }
}

// MARK: - Race prediction (running)

public enum RunPredictor {
    /// Riegel: t2 = t1 × (d2/d1)^k. k defaults to 1.06; `fitExponent` personalises it from ≥2 PBs.
    public static func predict(fromDistanceM d1: Double, timeS t1: Double, toDistanceM d2: Double, exponent k: Double = 1.06) -> Double {
        t1 * pow(d2 / d1, k)
    }

    /// Fits k from personal bests (log-log least squares); clamped to a plausible 1.02…1.15.
    public static func fitExponent(_ pbs: [PersonalBest]) -> Double? {
        guard pbs.count >= 2 else { return nil }
        let xs = pbs.map { log($0.distanceM) }, ys = pbs.map { log($0.seconds) }
        guard let fit = HXStats.linearFit(xs, ys) else { return nil }
        return HXStats.clamp(fit.slope, 1.02, 1.15)
    }

    /// Predicted time range for `targetM` from the best available PB; ±3 % band.
    public static func range(for targetM: Double, pbs: [PersonalBest]) -> (low: Double, high: Double)? {
        guard let anchor = pbs.filter({ $0.distanceM >= 3000 }).max(by: { $0.distanceM < $1.distanceM }) ?? pbs.last else { return nil }
        let k = fitExponent(pbs) ?? 1.06
        let t = predict(fromDistanceM: anchor.distanceM, timeS: anchor.seconds, toDistanceM: targetM, exponent: k)
        return (t * 0.97, t * 1.03)
    }
}
