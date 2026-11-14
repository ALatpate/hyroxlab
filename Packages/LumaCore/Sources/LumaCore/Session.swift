import Foundation

// MARK: - HXSession model

/// What kind of session was recorded. Stored as a string so new kinds never break old rows.
public enum HXSessionKind: Codable, Equatable, Sendable, Hashable {
    case fullSimulation
    case halfSimulation(secondHalf: Bool)
    case stationPractice(Station)
    case compromisedRunning(Station)
    case runOutdoor
    case runTreadmill
    case runIntervals
    case strength
    case other

    public var title: String {
        switch self {
        case .fullSimulation: return "Full simulation"
        case .halfSimulation(let second): return second ? "Half simulation · 5–8" : "Half simulation · 1–4"
        case .stationPractice(let s): return "\(s.title) practice"
        case .compromisedRunning(let s): return "Compromised running · \(s.shortTitle)"
        case .runOutdoor: return "Outdoor run"
        case .runTreadmill: return "Treadmill run"
        case .runIntervals: return "Run intervals"
        case .strength: return "Strength"
        case .other: return "HXSession"
        }
    }

    public var isRun: Bool {
        switch self {
        case .runOutdoor, .runTreadmill, .runIntervals: return true
        default: return false
        }
    }

    public var isHyrox: Bool {
        switch self {
        case .fullSimulation, .halfSimulation, .stationPractice, .compromisedRunning: return true
        default: return false
        }
    }
}

/// Summary of heart rate over a segment. `quality` is the fraction of expected 1 Hz samples that
/// arrived; wrist optical HR at stations is usually marked `wristOptical` so analytics can discount it.
public struct HRSummary: Codable, Equatable, Sendable {
    public var avg: Double
    public var max: Double
    public var min: Double
    public var sampleCount: Int
    public var expectedCount: Int
    public var source: HRSource

    public init(avg: Double, max: Double, min: Double, sampleCount: Int, expectedCount: Int, source: HRSource) {
        self.avg = avg; self.max = max; self.min = min
        self.sampleCount = sampleCount; self.expectedCount = expectedCount; self.source = source
    }

    public var quality: Double { expectedCount > 0 ? Double(sampleCount) / Double(expectedCount) : 0 }

    public static func from(samples: [Double], durationS: Double, source: HRSource) -> HRSummary? {
        guard !samples.isEmpty else { return nil }
        return HRSummary(avg: samples.reduce(0, +) / Double(samples.count), max: samples.max() ?? 0,
                         min: samples.min() ?? 0, sampleCount: samples.count,
                         expectedCount: Swift.max(1, Int(durationS.rounded())), source: source)
    }
}

public enum HRSource: String, Codable, Sendable {
    case wristOptical, chestStrap, unknown
}

/// A timed segment of a completed (or in-progress) session. Times are milliseconds on a monotonic
/// clock relative to session start, plus the wall-clock start for display.
public struct HXSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var kind: SegmentKind
    public var station: Station?
    public var label: String
    public var startMs: Int64
    public var endMs: Int64?
    public var distanceM: Double?
    public var reps: Int?
    public var loadKg: Double?
    public var hr: HRSummary?
    /// Free text the athlete adds afterwards ("broke the lunges at 60 m").
    public var note: String?

    public init(id: Int, kind: SegmentKind, station: Station? = nil, label: String, startMs: Int64,
                endMs: Int64? = nil, distanceM: Double? = nil, reps: Int? = nil, loadKg: Double? = nil,
                hr: HRSummary? = nil, note: String? = nil) {
        self.id = id; self.kind = kind; self.station = station; self.label = label
        self.startMs = startMs; self.endMs = endMs; self.distanceM = distanceM; self.reps = reps
        self.loadKg = loadKg; self.hr = hr; self.note = note
    }

    public var durationMs: Int64? { endMs.map { $0 - startMs } }
    public var durationS: Double? { durationMs.map { Double($0) / 1000 } }

    /// Seconds per kilometre, for runs with a distance.
    public var paceSPerKm: Double? {
        guard let d = distanceM, d > 0, let s = durationS else { return nil }
        return s / (d / 1000)
    }
}

/// A recorded session. `segments` is appended as the session runs so a crash loses at most the
/// segment in flight.
public struct HXSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: HXSessionKind
    public var format: RaceFormat
    public var sex: Sex
    public var startedAt: Date
    public var endedAt: Date?
    public var segments: [HXSegment]
    public var targetFinishS: Double?
    public var rpe: Int?
    public var note: String?

    public init(id: UUID = UUID(), kind: HXSessionKind, format: RaceFormat, sex: Sex, startedAt: Date,
                endedAt: Date? = nil, segments: [HXSegment] = [], targetFinishS: Double? = nil,
                rpe: Int? = nil, note: String? = nil) {
        self.id = id; self.kind = kind; self.format = format; self.sex = sex; self.startedAt = startedAt
        self.endedAt = endedAt; self.segments = segments; self.targetFinishS = targetFinishS
        self.rpe = rpe; self.note = note
    }

    public var totalMs: Int64? {
        guard let last = segments.last?.endMs else { return nil }
        return last - (segments.first?.startMs ?? 0)
    }
    public var totalS: Double? { totalMs.map { Double($0) / 1000 } }
    public var runs: [HXSegment] { segments.filter { $0.kind == .run } }
    public var stations: [HXSegment] { segments.filter { $0.kind == .station } }
    public var roxzones: [HXSegment] { segments.filter { $0.kind == .roxzone } }
    public var isComplete: Bool { endedAt != nil }
}

// MARK: - Split recorder

/// Monotonic clock abstraction so the recorder can be tested deterministically.
public protocol MonotonicClock: Sendable {
    /// Milliseconds since an arbitrary fixed point. Never goes backwards, unaffected by wall-clock changes.
    func nowMs() -> Int64
}

public struct SystemMonotonicClock: MonotonicClock {
    public init() {}
    public func nowMs() -> Int64 {
        // ProcessInfo.systemUptime is monotonic on Apple platforms and Linux.
        Int64((ProcessInfo.processInfo.systemUptime * 1000).rounded())
    }
}

/// Drives a session through its planned segments. Every transition is stamped in milliseconds
/// from the monotonic clock. The recorder never writes anywhere itself: it hands back the updated
/// `HXSession` after each call so the caller can persist it immediately.
public struct SplitRecorder: Sendable {
    public private(set) var session: HXSession
    public private(set) var plan: [PlannedSegment]
    public private(set) var currentIndex: Int
    private let clock: MonotonicClock
    private let t0: Int64

    public init(session: HXSession, plan: [PlannedSegment], clock: MonotonicClock = SystemMonotonicClock()) {
        self.session = session
        self.plan = plan
        self.currentIndex = -1
        self.clock = clock
        self.t0 = clock.nowMs()
    }

    public var elapsedMs: Int64 { clock.nowMs() - t0 }
    public var isFinished: Bool { currentIndex >= plan.count }
    public var isStarted: Bool { currentIndex >= 0 }
    public var current: PlannedSegment? { (isStarted && !isFinished) ? plan[currentIndex] : nil }
    public var next: PlannedSegment? { currentIndex + 1 < plan.count ? plan[currentIndex + 1] : nil }
    public var currentSegmentElapsedMs: Int64? {
        guard let open = session.segments.last, open.endMs == nil else { return nil }
        return elapsedMs - open.startMs
    }

    /// Opens the first planned segment.
    public mutating func start() {
        guard !isStarted else { return }
        currentIndex = 0
        open(plan[0], at: 0)
    }

    /// Closes the current segment and opens the next. Returns the segment just closed.
    /// `hr` is the HR summary the caller computed for the closed segment; `distanceM`/`reps` override
    /// the plan when the athlete did something different.
    @discardableResult
    public mutating func advance(hr: HRSummary? = nil, distanceM: Double? = nil, reps: Int? = nil) -> HXSegment? {
        guard isStarted, !isFinished else { return nil }
        let now = elapsedMs
        let closed = close(at: now, hr: hr, distanceM: distanceM, reps: reps)
        currentIndex += 1
        if currentIndex < plan.count { open(plan[currentIndex], at: now) }
        else { session.endedAt = Date() }
        return closed
    }

    /// Ends the session early, closing whatever is open.
    public mutating func finish(hr: HRSummary? = nil) {
        guard isStarted, !isFinished else { return }
        _ = close(at: elapsedMs, hr: hr, distanceM: nil, reps: nil)
        currentIndex = plan.count
        session.endedAt = Date()
    }

    /// Re-opens the last closed segment by merging the open one back into it. Used when a tap
    /// advanced too early. Safe to call once per advance.
    public mutating func undoLastAdvance() {
        guard session.segments.count >= 2, let open = session.segments.last, open.endMs == nil else { return }
        session.segments.removeLast()
        session.segments[session.segments.count - 1].endMs = nil
        currentIndex = max(0, currentIndex - 1)
    }

    private mutating func open(_ p: PlannedSegment, at ms: Int64) {
        session.segments.append(HXSegment(id: p.id, kind: p.kind, station: p.station, label: p.label,
                                        startMs: ms, distanceM: p.distanceM, reps: p.reps, loadKg: p.loadKg))
    }

    private mutating func close(at ms: Int64, hr: HRSummary?, distanceM: Double?, reps: Int?) -> HXSegment? {
        guard var seg = session.segments.last, seg.endMs == nil else { return nil }
        seg.endMs = max(ms, seg.startMs)
        if let hr { seg.hr = hr }
        if let distanceM { seg.distanceM = distanceM }
        if let reps { seg.reps = reps }
        session.segments[session.segments.count - 1] = seg
        return seg
    }
}
