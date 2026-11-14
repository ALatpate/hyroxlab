import Foundation

// MARK: - Race format

/// The HYROX formats a single athlete can prepare for. Loads differ by format; distances do not.
public enum RaceFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case openSingles, proSingles, doubles, relay
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openSingles: return "Open Singles"
        case .proSingles: return "Pro Singles"
        case .doubles: return "Doubles"
        case .relay: return "Relay"
        }
    }
    /// Doubles and relay share the Open loads; only Pro raises them.
    public var usesProLoads: Bool { self == .proSingles }
}

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
}

// MARK: - Stations

/// The eight stations in race order.
public enum Station: Int, Codable, CaseIterable, Identifiable, Sendable {
    case skiErg = 1, sledPush, sledPull, burpeeBroadJump, rowing, farmersCarry, sandbagLunges, wallBalls
    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .skiErg: return "SkiErg"
        case .sledPush: return "Sled Push"
        case .sledPull: return "Sled Pull"
        case .burpeeBroadJump: return "Burpee Broad Jump"
        case .rowing: return "Rowing"
        case .farmersCarry: return "Farmers Carry"
        case .sandbagLunges: return "Sandbag Lunges"
        case .wallBalls: return "Wall Balls"
        }
    }
    public var shortTitle: String {
        switch self {
        case .skiErg: return "Ski"
        case .sledPush: return "Push"
        case .sledPull: return "Pull"
        case .burpeeBroadJump: return "BBJ"
        case .rowing: return "Row"
        case .farmersCarry: return "Carry"
        case .sandbagLunges: return "Lunge"
        case .wallBalls: return "WB"
        }
    }
    /// SF Symbol name used by the UI.
    public var symbol: String {
        switch self {
        case .skiErg: return "figure.skiing.crosscountry"
        case .sledPush: return "figure.strengthtraining.functional"
        case .sledPull: return "figure.rower"
        case .burpeeBroadJump: return "figure.jumprope"
        case .rowing: return "figure.rower"
        case .farmersCarry: return "figure.walk"
        case .sandbagLunges: return "figure.step.training"
        case .wallBalls: return "figure.handball"
        }
    }

    /// What the station is measured in.
    public var measure: StationMeasure {
        switch self {
        case .skiErg, .rowing: return .metres(1000)
        case .sledPush, .sledPull: return .metres(50)
        case .burpeeBroadJump: return .metres(80)
        case .farmersCarry: return .metres(200)
        case .sandbagLunges: return .metres(100)
        case .wallBalls: return .reps(100)
        }
    }

    /// Official load preset (kg) for a format and sex. Sled loads include the sled. Zero means
    /// bodyweight. These are presets: the athlete can override them per session for gym kit.
    /// A typical in-race time for a recreational open-division athlete, in seconds. A reference
    /// point for charts and a starting target until the athlete has times of their own.
    public var typicalSeconds: Double {
        switch self {
        case .skiErg: return 262
        case .sledPush: return 198
        case .sledPull: return 244
        case .burpeeBroadJump: return 302
        case .rowing: return 271
        case .farmersCarry: return 122
        case .sandbagLunges: return 296
        case .wallBalls: return 418
        }
    }

    public func loadKg(format: RaceFormat, sex: Sex) -> Double {
        let pro = format.usesProLoads
        switch (self, sex, pro) {
        case (.sledPush, .male, false): return 152
        case (.sledPush, .female, false): return 102
        case (.sledPush, .male, true): return 202
        case (.sledPush, .female, true): return 152
        case (.sledPull, .male, false): return 103
        case (.sledPull, .female, false): return 78
        case (.sledPull, .male, true): return 153
        case (.sledPull, .female, true): return 103
        case (.farmersCarry, .male, false): return 2 * 24
        case (.farmersCarry, .female, false): return 2 * 16
        case (.farmersCarry, .male, true): return 2 * 32
        case (.farmersCarry, .female, true): return 2 * 24
        case (.sandbagLunges, .male, false): return 20
        case (.sandbagLunges, .female, false): return 10
        case (.sandbagLunges, .male, true): return 30
        case (.sandbagLunges, .female, true): return 20
        case (.wallBalls, .male, false): return 6
        case (.wallBalls, .female, false): return 4
        case (.wallBalls, .male, true): return 9
        case (.wallBalls, .female, true): return 6
        default: return 0
        }
    }

    /// Wall-ball target height in metres; nil for other stations.
    public func targetHeightM(sex: Sex) -> Double? {
        guard self == .wallBalls else { return nil }
        return sex == .male ? 3.0 : 2.7
    }
}

public enum StationMeasure: Equatable, Sendable {
    case metres(Int)
    case reps(Int)
    public var label: String {
        switch self {
        case .metres(let m): return "\(m) m"
        case .reps(let r): return "\(r) reps"
        }
    }
}

// MARK: - Segments

/// One timed piece of a HYROX session.
public enum SegmentKind: String, Codable, Sendable, Equatable {
    case warmup, run, roxzone, station, rest, cooldown
}

/// A planned segment, before it is timed.
public struct PlannedSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: SegmentKind
    public var station: Station?
    /// Target distance in metres for runs and distance stations; nil for reps-based or untimed.
    public var distanceM: Double?
    public var reps: Int?
    public var loadKg: Double?
    public var label: String

    public init(id: Int, kind: SegmentKind, station: Station? = nil, distanceM: Double? = nil,
                reps: Int? = nil, loadKg: Double? = nil, label: String) {
        self.id = id; self.kind = kind; self.station = station; self.distanceM = distanceM
        self.reps = reps; self.loadKg = loadKg; self.label = label
    }
}

/// Builds the planned segment list for the standard HYROX shapes.
public enum RacePlanBuilder {
    /// Full race: run → roxzone → station ×8. Roxzones are explicit so transition time is measured.
    public static func fullRace(format: RaceFormat, sex: Sex) -> [PlannedSegment] {
        stations(Array(Station.allCases), format: format, sex: sex)
    }

    /// Half simulation: stations 1–4 or 5–8 with their runs.
    public static func halfRace(secondHalf: Bool, format: RaceFormat, sex: Sex) -> [PlannedSegment] {
        let all = Station.allCases
        let half = secondHalf ? Array(all[4...]) : Array(all[..<4])
        return stations(half, format: format, sex: sex)
    }

    /// Compromised running: station → 1 km run, repeated.
    public static func compromised(station: Station, rounds: Int, format: RaceFormat, sex: Sex) -> [PlannedSegment] {
        var out: [PlannedSegment] = []
        var id = 0
        for _ in 0..<max(1, rounds) {
            out.append(stationSegment(id: &id, station: station, format: format, sex: sex))
            out.append(PlannedSegment(id: id, kind: .run, distanceM: 1000, label: "Run 1 km")); id += 1
        }
        return out
    }

    /// Station practice: `sets` timed efforts with rests between.
    public static func stationPractice(station: Station, sets: Int, format: RaceFormat, sex: Sex) -> [PlannedSegment] {
        var out: [PlannedSegment] = []
        var id = 0
        for i in 0..<max(1, sets) {
            out.append(stationSegment(id: &id, station: station, format: format, sex: sex))
            if i < sets - 1 { out.append(PlannedSegment(id: id, kind: .rest, label: "Rest")); id += 1 }
        }
        return out
    }

    private static func stations(_ list: [Station], format: RaceFormat, sex: Sex) -> [PlannedSegment] {
        var out: [PlannedSegment] = []
        var id = 0
        for (i, s) in list.enumerated() {
            out.append(PlannedSegment(id: id, kind: .run, distanceM: 1000, label: "Run \(i + 1)")); id += 1
            out.append(PlannedSegment(id: id, kind: .roxzone, label: "Roxzone")); id += 1
            out.append(stationSegment(id: &id, station: s, format: format, sex: sex))
            if i < list.count - 1 {
                out.append(PlannedSegment(id: id, kind: .roxzone, label: "Roxzone")); id += 1
            }
        }
        return out
    }

    private static func stationSegment(id: inout Int, station: Station, format: RaceFormat, sex: Sex) -> PlannedSegment {
        defer { id += 1 }
        switch station.measure {
        case .metres(let m):
            return PlannedSegment(id: id, kind: .station, station: station, distanceM: Double(m),
                                  loadKg: station.loadKg(format: format, sex: sex), label: station.title)
        case .reps(let r):
            return PlannedSegment(id: id, kind: .station, station: station, reps: r,
                                  loadKg: station.loadKg(format: format, sex: sex), label: station.title)
        }
    }
}
