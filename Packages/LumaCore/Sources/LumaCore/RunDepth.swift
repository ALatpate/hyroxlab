import Foundation

// MARK: - Heart rate at the easy pace

/// A steady stretch inside a run: its pace, and the heart rate over its last minute.
public struct SteadyStretch: Equatable, Sendable {
    public let paceSPerKm: Double
    public let hr: Double
    public let seconds: Double
}

public struct EasyPacePoint: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let hr: Double
    public let paceSPerKm: Double
}

/// Heart rate at the athlete's own easy pace, run by run. The same pace at a lower heart rate means
/// fitter. Of the heart-rate measures used to follow training, this one stands out most clearly from
/// its day-to-day noise, so it is read from every run that holds a steady stretch at that pace.
public struct EasyPaceRead: Equatable, Sendable {
    public enum Direction: String, Sendable { case falling, steady, rising }

    public let paceSPerKm: Double
    /// One point a day, oldest first.
    public let points: [EasyPacePoint]
    public let direction: Direction
    /// Change from the first third of the points to the last third, in beats a minute.
    public let changeBpm: Double
    public let headline: String
    public let detail: String
}

public enum EasyPace {
    public static let stretchS: Double = 240
    public static let tailS: Double = 60
    /// How far each minute's pace may sit from the stretch's own pace.
    public static let steadiness = 0.05
    /// How far a stretch's pace may sit from the reference pace and still be compared.
    public static let band = 0.05
    public static let minPoints = 3
    /// The share of the average heart rate a change must reach to count: about one beat in a hundred.
    public static let meaningful = 0.01

    /// Steady stretches of four minutes in a run, one after another without overlap.
    public static func stretches(_ samples: [RunSample]) -> [SteadyStretch] {
        guard samples.count >= 4, let last = samples.last else { return [] }
        func distance(at t: Double) -> Double? {
            guard let first = samples.first, t >= first.tS, t <= last.tS else { return nil }
            var lo = 0, hi = samples.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if samples[mid].tS <= t { lo = mid } else { hi = mid }
            }
            let a = samples[lo], b = samples[hi]
            guard b.tS > a.tS else { return a.distanceM }
            return a.distanceM + (b.distanceM - a.distanceM) * (t - a.tS) / (b.tS - a.tS)
        }
        var out: [SteadyStretch] = []
        var start = samples[0].tS
        while start + stretchS <= last.tS {
            let end = start + stretchS
            guard let d0 = distance(at: start), let d1 = distance(at: end), d1 - d0 > 100 else {
                start += 30
                continue
            }
            let pace = stretchS / ((d1 - d0) / 1000)
            // Every minute inside the stretch, taken half a minute apart, must sit near the stretch's own
            // pace: a minute fast and a minute slow averages out over four, and is not steady running.
            var steady = true
            var t = start
            while t + 60 <= end + 1e-6 {
                if let a = distance(at: t), let b = distance(at: min(t + 60, end)), b - a > 20 {
                    let minutePace = 60 / ((b - a) / 1000)
                    if abs(minutePace - pace) > steadiness * pace { steady = false }
                } else {
                    steady = false
                }
                t += 30
            }
            let tail = samples.filter { $0.tS > end - tailS && $0.tS <= end }.compactMap { $0.hr }.filter { $0 > 0 }
            if steady, tail.count >= 3, let hr = LStat.mean(tail) {
                out.append(SteadyStretch(paceSPerKm: pace, hr: hr, seconds: stretchS))
                start = end
            } else {
                start += 30
            }
        }
        return out
    }

    /// `runs` are the runs to read, each with its day. The reference pace is the middle pace of all
    /// their steady stretches; only stretches near it are compared, so every point is at the same pace.
    public static func read(runs: [(day: String, samples: [RunSample])]) -> EasyPaceRead? {
        let found = runs.map { (day: $0.day, stretches: stretches($0.samples)) }.filter { !$0.stretches.isEmpty }
        guard let pace = LStat.median(found.flatMap { $0.stretches.map { $0.paceSPerKm } }) else { return nil }
        var byDay: [String: [Double]] = [:]
        for run in found {
            for s in run.stretches where abs(s.paceSPerKm - pace) <= band * pace { byDay[run.day, default: []].append(s.hr) }
        }
        let points = byDay.keys.sorted().compactMap { day in LStat.mean(byDay[day] ?? []).map { EasyPacePoint(day: day, hr: $0, paceSPerKm: pace) } }
        guard points.count >= minPoints, let mean = LStat.mean(points.map { $0.hr }), mean > 0 else { return nil }
        let third = max(1, points.count / 3)
        let early = LStat.mean(points.prefix(third).map { $0.hr }) ?? mean
        let late = LStat.mean(points.suffix(third).map { $0.hr }) ?? mean
        let change = late - early
        let direction: EasyPaceRead.Direction = abs(change) < meaningful * mean ? .steady : (change < 0 ? .falling : .rising)
        let at = "at \(HXFormat.pace(pace)) per km"
        let beats = String(format: "%.0f", abs(change).rounded())
        let headline: String, detail: String
        switch direction {
        case .falling:
            headline = "Heart rate at your easy pace is falling"
            detail = "About \(beats) bpm lower \(at) than when these runs began. The same pace is costing you less."
        case .rising:
            headline = "Heart rate at your easy pace is rising"
            detail = "About \(beats) bpm higher \(at) than when these runs began. Heat, short sleep and tiredness all do this, so read it over several runs."
        case .steady:
            headline = "Heart rate at your easy pace is steady"
            detail = "It has held within a beat or two \(at) across these runs."
        }
        return EasyPaceRead(paceSPerKm: pace, points: points, direction: direction, changeBpm: change, headline: headline, detail: detail)
    }
}

// MARK: - Critical speed from the fastest efforts

/// Critical speed worked out from the fastest efforts found inside recent runs, the way it was done
/// for marathon runners from their training logs: the fastest 400 m, 800 m and 5,000 m, with the
/// distances between them used when they are there too.
public enum CriticalSpeedEfforts {
    public static let distances: [Double] = [400, 800, 1000, 1500, 3000, 5000]
    /// The three the published best fit used.
    public static let preferred: [Double] = [400, 800, 5000]
    public static let weeks = 16

    /// The fastest time over each distance across the runs given.
    public static func fastest(in runs: [[RunSample]]) -> [PersonalBest] {
        distances.compactMap { d in
            let times = runs.compactMap { RunAnalytics.fastest($0, distanceM: d) }
            return times.min().map { PersonalBest(distanceM: d, seconds: $0) }
        }
    }

    /// Critical speed in metres a second and the reserve above it in metres, from those efforts. The
    /// preferred three are used when all are present, otherwise whatever there is, with at least two.
    public static func fit(_ efforts: [PersonalBest]) -> (cs: Double, dPrime: Double)? {
        let chosen = efforts.filter { e in preferred.contains { abs($0 - e.distanceM) < 1 } }
        let use = chosen.count == preferred.count ? chosen : efforts
        let sorted = use.sorted { $0.seconds < $1.seconds }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last, last.seconds - first.seconds >= 60 else { return nil }
        let t = sorted.map { $0.seconds }, d = sorted.map { $0.distanceM }
        let slope: Double, intercept: Double
        if sorted.count == 2 {
            slope = (d[1] - d[0]) / (t[1] - t[0])
            intercept = d[0] - slope * t[0]
        } else {
            guard let line = LStat.linearFit(t, d) else { return nil }
            slope = line.slope
            intercept = line.intercept
        }
        guard slope > 1.5, slope < 7.5 else { return nil }
        return (slope, LStat.clamp(intercept, 0, 600))
    }

    /// Pace in seconds a kilometre at a share of critical speed: 0.85 is a steady long effort, 0.95 hard.
    public static func pace(cs: Double, share: Double) -> Double? {
        let speed = cs * share
        return speed > 0 ? 1000 / speed : nil
    }
}

// MARK: - Durability across a simulation

/// How much heart rate rises for the same speed late in a HYROX session against early in it. In
/// marathon runners the same ratio separated those who held their speed from those who faded, and
/// where it first rose mattered as well as how far.
public struct DurabilityRead: Equatable, Sendable {
    public enum Band: String, Sendable { case low, moderate, high }

    /// Late runs against early runs: 1 is no drift, 1.2 is a fifth more heart rate for the same speed.
    public let ratio: Double
    public let band: Band
    /// Each run's heart rate for its speed against the early runs, in order.
    public let perRun: [Double]
    /// The first run, counted from 1, from which the ratio stays above the onset line. Nil when it never does.
    public let onsetRun: Int?
    public let headline: String
    public let detail: String
}

public enum Durability {
    public static let onsetLine = 1.025
    public static let lowUnder = 1.1
    public static let highFrom = 1.2

    public static func band(_ ratio: Double) -> DurabilityRead.Band {
        ratio < lowUnder ? .low : (ratio < highFrom ? .moderate : .high)
    }

    /// From the runs of a session that have a time, a distance and a heart rate. At least four are needed.
    /// With six or more, the first and last runs are left out of the two ends, as the opening and the
    /// finish are not typical.
    public static func read(_ session: HXSession) -> DurabilityRead? {
        let costs: [Double] = session.runs.compactMap { run in
            guard let s = run.durationS, s > 0, let hr = run.hr?.avg, hr > 0 else { return nil }
            let metres = run.distanceM ?? 1000
            guard metres > 0 else { return nil }
            return hr / (metres / s)
        }
        return read(costs: costs)
    }

    /// `costs` is heart rate divided by speed for each run, in order.
    public static func read(costs: [Double]) -> DurabilityRead? {
        let n = costs.count
        guard n >= 4 else { return nil }
        let earlyRange = n >= 6 ? 1...2 : 0...1
        let lateRange = n >= 6 ? (n - 3)...(n - 2) : (n - 2)...(n - 1)
        guard let early = LStat.mean(Array(costs[earlyRange])), early > 0, let late = LStat.mean(Array(costs[lateRange])) else { return nil }
        let perRun = costs.map { $0 / early }
        let ratio = late / early
        var onset: Int?
        for i in (earlyRange.upperBound + 1)..<n where perRun[i...].allSatisfy({ $0 > onsetLine }) {
            onset = i + 1
            break
        }
        let b = band(ratio)
        let figure = String(format: "%.2f", ratio)
        let headline: String
        switch b {
        case .low: headline = "You held your speed for the heart rate"
        case .moderate: headline = "Some drift late in the runs"
        case .high: headline = "Heart rate drifted well up for the same speed"
        }
        var detail = "Late runs cost \(figure) times the heart rate for the same speed as the early ones."
        if let onset { detail += " The drift set in from run \(onset)." }
        if b != .low { detail += " Long easy running and compromised-running sets are what move this." }
        return DurabilityRead(ratio: ratio, band: b, perRun: perRun, onsetRun: onset, headline: headline, detail: detail)
    }
}

// MARK: - Where the minutes go

/// The shares of a full session spent running, on the stations and in the Roxzone, beside the shares
/// in published results.
public struct TimeShares: Equatable, Sendable {
    public let run: Double
    public let stations: Double
    public let roxzone: Double
    public let referenceRun: Double
    public let referenceStations: Double
    public let referenceRoxzone: Double
    /// The part that sits furthest above the reference, in plain words.
    public let line: String

    public static let referenceNote = "Reference: the top 100 Pro results of the 2024/25 season."
}

public enum TimeSharesModel {
    /// Shares of total time for the top 100 Pro athletes in 2024/25: running and Roxzone as published,
    /// the stations as the remainder.
    public static func reference(_ sex: Sex) -> (run: Double, stations: Double, roxzone: Double) {
        sex == .female ? (0.479, 0.449, 0.072) : (0.485, 0.442, 0.073)
    }

    public static func read(_ session: HXSession) -> TimeShares? {
        func total(_ segments: [HXSegment]) -> Double { segments.reduce(0) { $0 + ($1.durationS ?? 0) } }
        let run = total(session.runs), stations = total(session.stations), rox = total(session.roxzones)
        let all = run + stations + rox
        guard case .fullSimulation = session.kind, run > 0, stations > 0, rox > 0, all > 0 else { return nil }
        let ref = reference(session.sex)
        let shares = (run / all, stations / all, rox / all)
        let over = [("running", shares.0 - ref.run), ("the stations", shares.1 - ref.stations), ("the Roxzone", shares.2 - ref.roxzone)]
        let line: String
        if let worst = over.max(by: { $0.1 < $1.1 }), worst.1 >= 0.02 {
            line = "More of your time goes on \(worst.0) than in the reference, by \(LNum.int((worst.1 * 100).rounded())) points."
        } else {
            line = "Your time is split much as in the reference."
        }
        return TimeShares(run: shares.0, stations: shares.1, roxzone: shares.2, referenceRun: ref.run, referenceStations: ref.stations,
                          referenceRoxzone: ref.roxzone, line: line)
    }
}
