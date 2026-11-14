import Foundation

// MARK: - Race analytics

public struct RunSplitRow: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int            // 1-based run number
    public let seconds: Double
    public let paceSPerKm: Double?
    public let avgHR: Double?
    /// Pace change versus run 1, in seconds per km (+ slower).
    public let driftVsFirstS: Double?
    /// This run's pace divided by the fresh reference pace. 1.00 = no slowdown.
    public let compromisedIndex: Double?
    /// Which station preceded this run (nil for run 1).
    public let afterStation: Station?
}

public struct StationRow: Equatable, Sendable, Identifiable {
    public var id: Int { station.rawValue }
    public let station: Station
    public let seconds: Double
    public let loadKg: Double?
    public let peakHR: Double?
    /// Seconds slower than the athlete's best for this station at this load class; nil without a benchmark.
    public let lostVsBestS: Double?
    /// Heart-rate recovery in the roxzone that follows (peak − HR at the end of roxzone), when known.
    public let hrrAfterS: Double?
}

public struct RaceReport: Equatable, Sendable {
    public let totalS: Double?
    public let runTotalS: Double
    public let stationTotalS: Double
    public let roxzoneTotalS: Double
    public let runs: [RunSplitRow]
    public let stations: [StationRow]
    /// Coefficient of variation of the run paces, as a fraction.
    public let pacingCV: Double?
    /// Average HR of the last run minus the first run, bpm.
    public let hrDriftBpm: Double?
    /// Mean compromised index over runs 2…n.
    public let compromisedIndexMean: Double?
    /// Where time went versus a target: positive = slower than target. Empty without a target.
    public let bridge: [BridgeStep]
}

public struct BridgeStep: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let deltaS: Double
}

public enum RaceAnalytics {
    /// Builds the full report for a HYROX-shaped session. `benchmarks` supplies per-station bests.
    /// `freshPaceSPerKm` is the athlete's unfatigued 1 km race pace; defaults to run 1.
    public static func report(_ s: HXSession, benchmarks: Benchmarks? = nil, freshPaceSPerKm: Double? = nil,
                              targetSplits: [String: Double]? = nil) -> RaceReport {
        let runs = s.runs.filter { $0.endMs != nil }
        let stations = s.stations.filter { $0.endMs != nil }
        let rox = s.roxzones.filter { $0.endMs != nil }

        let firstPace = runs.first?.paceSPerKm
        let reference = freshPaceSPerKm ?? firstPace

        var runRows: [RunSplitRow] = []
        var prevStation: Station? = nil
        var runIdx = 0
        for seg in s.segments where seg.endMs != nil {
            if seg.kind == .station { prevStation = seg.station }
            guard seg.kind == .run, let sec = seg.durationS else { continue }
            runIdx += 1
            let pace = seg.paceSPerKm
            let drift: Double? = (pace != nil && firstPace != nil) ? pace! - firstPace! : nil
            let ci: Double? = (pace != nil && reference != nil && reference! > 0) ? pace! / reference! : nil
            runRows.append(RunSplitRow(index: runIdx, seconds: sec, paceSPerKm: pace, avgHR: seg.hr?.avg,
                                       driftVsFirstS: drift, compromisedIndex: ci, afterStation: prevStation))
            prevStation = nil
        }

        var stationRows: [StationRow] = []
        for (i, seg) in s.segments.enumerated() where seg.kind == .station && seg.endMs != nil {
            guard let st = seg.station, let sec = seg.durationS else { continue }
            let best = benchmarks?.bestStationS(st, loadKg: seg.loadKg)
            var hrr: Double? = nil
            if i + 1 < s.segments.count, s.segments[i + 1].kind == .roxzone,
               let peak = seg.hr?.max, let after = s.segments[i + 1].hr?.min, peak > after {
                hrr = peak - after
            }
            stationRows.append(StationRow(station: st, seconds: sec, loadKg: seg.loadKg, peakHR: seg.hr?.max,
                                          lostVsBestS: best.map { sec - $0 }, hrrAfterS: hrr))
        }

        let paces = runRows.compactMap { $0.paceSPerKm }
        let cv = HXStats.cv(paces)
        let hrDrift: Double? = {
            guard let a = runRows.first?.avgHR, let b = runRows.last?.avgHR, runRows.count >= 2 else { return nil }
            return b - a
        }()
        let ciMean = HXStats.mean(runRows.dropFirst().compactMap { $0.compromisedIndex })

        var bridge: [BridgeStep] = []
        if let targets = targetSplits {
            for seg in s.segments where seg.endMs != nil {
                if let t = targets[seg.label], let d = seg.durationS { bridge.append(BridgeStep(label: seg.label, deltaS: d - t)) }
            }
        }

        return RaceReport(totalS: s.totalS,
                          runTotalS: runs.compactMap(\.durationS).reduce(0, +),
                          stationTotalS: stations.compactMap(\.durationS).reduce(0, +),
                          roxzoneTotalS: rox.compactMap(\.durationS).reduce(0, +),
                          runs: runRows, stations: stationRows, pacingCV: cv, hrDriftBpm: hrDrift,
                          compromisedIndexMean: ciMean, bridge: bridge)
    }
}

// MARK: - Benchmarks

/// Personal bests per station (bucketed by load) and per run, with the sessions they came from.
public struct Benchmarks: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var seconds: Double
        public var date: Date
        public var sessionID: UUID
        public var loadKg: Double?
    }

    /// Key: "station.rawValue@loadBucket" — see `loadKey`.
    public var stationBests: [String: Entry]
    public var bestRun1kS: Entry?
    /// Best full-race time, if any complete simulation exists.
    public var bestFullSimS: Entry?
    /// Average roxzone per transition over the last 3 simulations.
    public var typicalRoxzoneS: Double?

    public init() { stationBests = [:] }

    /// Loads are bucketed to the nearest 5 kg so 152 and 153 compare, 152 and 202 do not.
    public static func loadKey(_ station: Station, loadKg: Double?) -> String {
        let bucket = Int(((loadKg ?? 0) / 5).rounded()) * 5
        return "\(station.rawValue)@\(bucket)"
    }

    public func bestStationS(_ station: Station, loadKg: Double?) -> Double? {
        stationBests[Self.loadKey(station, loadKg: loadKg)]?.seconds
    }

    /// Folds a completed session into the bests. Idempotent per session.
    public mutating func ingest(_ s: HXSession) {
        for seg in s.stations where seg.endMs != nil {
            guard let st = seg.station, let sec = seg.durationS, sec > 5 else { continue }
            let k = Self.loadKey(st, loadKg: seg.loadKg)
            if let cur = stationBests[k], cur.seconds <= sec, cur.sessionID != s.id { continue }
            stationBests[k] = Entry(seconds: sec, date: s.startedAt, sessionID: s.id, loadKg: seg.loadKg)
        }
        for seg in s.runs where seg.endMs != nil {
            guard let d = seg.distanceM, d >= 990, let sec = seg.durationS, sec > 120 else { continue }
            if bestRun1kS == nil || sec < bestRun1kS!.seconds {
                bestRun1kS = Entry(seconds: sec, date: s.startedAt, sessionID: s.id, loadKg: nil)
            }
        }
        if case .fullSimulation = s.kind, s.isComplete, let t = s.totalS, s.stations.count == 8 {
            if bestFullSimS == nil || t < bestFullSimS!.seconds {
                bestFullSimS = Entry(seconds: t, date: s.startedAt, sessionID: s.id, loadKg: nil)
            }
        }
    }

    /// Recomputes typical roxzone from the most recent simulations.
    public mutating func updateRoxzone(from sessions: [HXSession]) {
        let sims = sessions.filter { $0.kind == .fullSimulation && $0.isComplete }
            .sorted { $0.startedAt > $1.startedAt }.prefix(3)
        let per = sims.flatMap { $0.roxzones.compactMap(\.durationS) }
        typicalRoxzoneS = HXStats.mean(per)
    }
}

// MARK: - Race readiness

public enum ReadinessVerdict: String, Codable, Sendable {
    case ready, close, notYet
    public var title: String {
        switch self {
        case .ready: return "Ready"
        case .close: return "Close"
        case .notYet: return "Not yet"
        }
    }
}

public struct FormatReadiness: Equatable, Sendable, Identifiable {
    public var id: String { format.rawValue }
    public let format: RaceFormat
    public let verdict: ReadinessVerdict
    /// Predicted finish range, seconds. nil when there is not enough data to predict.
    public let predictedLowS: Double?
    public let predictedHighS: Double?
    /// Plain sentences on what is missing or weakest.
    public let gaps: [String]
    /// 0–1 coverage of the data the prediction needs.
    public let confidence: Double
}

public enum RaceReadiness {
    /// Fatigue multipliers applied to fresh station bests when summing a race; from the gap between
    /// typical practice bests and in-race times. Calibrated per athlete once simulations exist.
    static let defaultStationFatigue = 1.12
    static let defaultRunFatigue = 1.08

    public static func assess(benchmarks b: Benchmarks, sessions: [HXSession], sex: Sex,
                              fresh1kS: Double?, formats: [RaceFormat] = RaceFormat.allCases) -> [FormatReadiness] {
        formats.map { assess(format: $0, benchmarks: b, sessions: sessions, sex: sex, fresh1kS: fresh1kS) }
    }

    public static func assess(format: RaceFormat, benchmarks b: Benchmarks, sessions: [HXSession], sex: Sex,
                              fresh1kS: Double?) -> FormatReadiness {
        var gaps: [String] = []
        var covered = 0
        var stationSum = 0.0
        for st in Station.allCases {
            let load = st.loadKg(format: format, sex: sex)
            if let best = b.bestStationS(st, loadKg: load) {
                stationSum += best; covered += 1
            } else {
                gaps.append("No timed \(st.title) at \(load > 0 ? "\(Int(load)) kg" : "bodyweight") yet")
            }
        }
        let run1k = b.bestRun1kS?.seconds ?? fresh1kS
        if run1k == nil { gaps.append("No 1 km run time yet") }

        // Calibrate fatigue from real simulations when available.
        var stationFatigue = defaultStationFatigue
        var runFatigue = defaultRunFatigue
        let sims = sessions.filter { $0.kind == .fullSimulation && $0.isComplete && $0.stations.count == 8 }
        if let sim = sims.sorted(by: { $0.startedAt > $1.startedAt }).first {
            let simStations = sim.stations.compactMap(\.durationS).reduce(0, +)
            let simBest = sim.stations.compactMap { seg -> Double? in
                guard let st = seg.station else { return nil }
                return b.bestStationS(st, loadKg: seg.loadKg)
            }.reduce(0, +)
            if simBest > 0 { stationFatigue = HXStats.clamp(simStations / simBest, 1.0, 1.5) }
            if let r1 = run1k, r1 > 0 {
                let runMean = HXStats.mean(sim.runs.compactMap(\.durationS)) ?? r1
                runFatigue = HXStats.clamp(runMean / r1, 1.0, 1.6)
            }
        }

        let coverage = Double(covered) / 8 * 0.7 + (run1k != nil ? 0.3 : 0)
        var low: Double? = nil, high: Double? = nil
        if let r1 = run1k, covered >= 6 {
            // Estimate missing stations at the median of covered ones so a range still forms.
            let perStation = stationSum / Double(covered)
            let fullStations = stationSum + perStation * Double(8 - covered)
            let rox = (b.typicalRoxzoneS ?? 40) * 8
            let runs = r1 * runFatigue * 8
            let mid = fullStations * stationFatigue + runs + rox
            let band = mid * (0.05 + 0.10 * (1 - coverage))
            low = mid - band; high = mid + band
        }

        let verdict: ReadinessVerdict
        if covered == 8, run1k != nil, !sims.isEmpty {
            verdict = .ready
        } else if covered >= 5, run1k != nil {
            verdict = .close
            if sims.isEmpty { gaps.insert("No full simulation yet — do one before entering", at: 0) }
        } else {
            verdict = .notYet
        }
        if format == .proSingles, covered < 8 {
            gaps.append("Pro loads not yet proven at every station")
        }
        return FormatReadiness(format: format, verdict: verdict, predictedLowS: low, predictedHighS: high,
                               gaps: Array(gaps.prefix(4)), confidence: coverage)
    }
}
