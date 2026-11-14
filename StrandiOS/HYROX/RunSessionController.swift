import Foundation
import SwiftUI
import Combine
import AVFoundation
import CoreLocation
import HYROXCore

/// Drives an outdoor, treadmill or interval run on top of NOOP's workout engine: NOOP records HR,
/// GPS route and the WorkoutRow; this controller adds the 1 Hz sample timeline, auto-laps, smoothed
/// pace, voice cues, auto-pause, structured intervals and the HYROX Lab session record.
@MainActor
final class RunSessionController: ObservableObject, Identifiable {
    let id = UUID()
    let kind: HXSessionKind
    let planned: PlannedSession?
    private unowned let model: AppModel
    private unowned let store: HXStore

    @Published private(set) var elapsedS: Double = 0
    @Published private(set) var distanceM: Double = 0
    @Published private(set) var smoothedPace: Double?
    @Published private(set) var avgPace: Double?
    @Published private(set) var hr: Int?
    @Published private(set) var laps: [RunLap] = []
    @Published private(set) var lapFlash: RunLap?
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var isPaused = false
    @Published private(set) var autoPaused = false
    @Published private(set) var phase: IntervalPhase?
    @Published private(set) var finished: HXSession?
    @Published var manualDistanceM: Double = 0      // treadmill: entered at the end
    @Published private(set) var samples: [RunSample] = []
    @Published private(set) var started = false

    struct IntervalPhase: Equatable {
        let label: String
        let index: Int
        let total: Int
        let targetPace: Double?
        let endsAtDistanceM: Double?
        let endsAtS: Double?
    }

    private var timer: AnyCancellable?
    private var smoother = PaceSmoother()
    private var lastLapDistance: Double = 0
    private var lastDistanceChangeS: Double = 0
    private var lastDistanceSeen: Double = 0
    private var lastCueKm = 0
    private var lastCueMinute = 0
    private var intervals: [IntervalPhase] = []
    private var intervalIndex = 0
    private let speech = AVSpeechSynthesizer()
    private var startWall = Date()

    init(model: AppModel, store: HXStore, kind: HXSessionKind, planned: PlannedSession?) {
        self.model = model; self.store = store; self.kind = kind; self.planned = planned
    }

    var isTreadmill: Bool { kind == .runTreadmill }
    var zones: HXZones { store.zones }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        startWall = Date()
        model.startWorkout(sport: isTreadmill ? "Treadmill run" : "Running")
        model.startRealtimeHR()
        if kind == .runIntervals { buildIntervals() }
        say(kind == .runIntervals ? "Intervals. Warm up." : "Run started.")
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }

    func togglePause() {
        model.toggleWorkoutPause()
        isPaused = model.activeWorkout?.isPaused ?? !isPaused
        autoPaused = false
        say(isPaused ? "Paused." : "Resumed.")
        smoother.reset()
    }

    func lap() {
        guard !samples.isEmpty else { return }
        closeLap(partial: true, atDistance: distanceM, atTime: elapsedS)
    }

    func finish() {
        timer?.cancel()
        if isTreadmill, manualDistanceM > 0 { rewriteSamplesForManualDistance() }
        let secs = elapsedS
        let dist = isTreadmill ? manualDistanceM : distanceM
        let hrs = samples.compactMap(\.hr)
        let summary = HRSummary.from(samples: hrs, durationS: secs, source: .wristOptical)
        var session = HXSession(kind: kind, format: store.profile.format, sex: store.sex, startedAt: startWall, endedAt: Date())
        session.segments = [HXSegment(id: 0, kind: .run, label: kind.title, startMs: 0, endMs: Int64(secs * 1000),
                                      distanceM: dist > 0 ? dist : nil, hr: summary)]
        store.upsert(session)
        store.saveRunSamples(samples, for: session.id)
        if let p = planned { store.markPlanned(p, completedBy: session) }
        // Let NOOP close its own record (route, Effort, Health write-back). We mirror nothing extra for
        // runs: NOOP's manual workout IS the record; the HYROX Lab session links to it by start time.
        if model.activeWorkout != nil {
            if secs < AppModel.minimumWorkoutSeconds { model.discardWorkout() } else { model.endWorkout() }
        }
        model.stopRealtimeHR()
        say("Run finished. \(HXFormat.km(dist, decimals: 1)) kilometres.")
        finished = session
    }

    func discard() {
        timer?.cancel()
        if model.activeWorkout != nil { model.discardWorkout() }
        model.stopRealtimeHR()
    }

    // MARK: Tick

    private func tick() {
        guard let w = model.activeWorkout else { return }
        elapsedS = w.elapsed()
        hr = model.bpm
        if !isTreadmill { distanceM = model.gpsRecorder.distanceM }
        if w.isPaused { return }

        samples.append(RunSample(tS: elapsedS, distanceM: distanceM, hr: hr.map { Double($0) }))
        smoothedPace = isTreadmill ? nil : smoother.push(tS: elapsedS, distanceM: distanceM)
        avgPace = distanceM > 50 ? elapsedS / (distanceM / 1000) : nil

        // Auto-lap each kilometre.
        if distanceM - lastLapDistance >= 1000 {
            closeLap(partial: false, atDistance: lastLapDistance + 1000, atTime: elapsedS)
        }
        // Route polyline for the map, every 5 s.
        if Int(elapsedS) % 5 == 0, !isTreadmill, let pts = ActiveRouteStore.load() {
            route = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        }
        // Voice cues.
        if store.profile.voiceCues {
            let km = Int(distanceM / 1000)
            if store.profile.cueEveryKm, km > lastCueKm {
                lastCueKm = km
                let lapPace = laps.last?.paceSPerKm
                say("\(km) kilometre\(km == 1 ? "" : "s"). Last split \(spoken(pace: lapPace)).\(hr.map { " Heart rate \($0)." } ?? "")")
            } else if !store.profile.cueEveryKm || isTreadmill {
                let m = Int(elapsedS / 300)
                if m > lastCueMinute { lastCueMinute = m; say("\(m * 5) minutes.\(hr.map { " Heart rate \($0)." } ?? "")") }
            }
        }
        // Intervals.
        if kind == .runIntervals { advanceIntervalsIfNeeded() }
        // Auto-pause: no movement for 6 s outdoors.
        if store.profile.autoPause, !isTreadmill {
            if distanceM - lastDistanceSeen > 3 { lastDistanceSeen = distanceM; lastDistanceChangeS = elapsedS
                if autoPaused { autoPaused = false }
            } else if elapsedS - lastDistanceChangeS > 6, !isPaused, elapsedS > 15 {
                model.toggleWorkoutPause(); isPaused = true; autoPaused = true; say("Auto paused.")
            }
        }
        if autoPaused, model.gpsRecorder.distanceM - lastDistanceSeen > 8 {
            model.toggleWorkoutPause(); isPaused = false; autoPaused = false; say("Resumed.")
            lastDistanceSeen = model.gpsRecorder.distanceM; lastDistanceChangeS = elapsedS
        }
    }

    private func closeLap(partial: Bool, atDistance d: Double, atTime t: Double) {
        let lapStartT = lapStartTime
        let secs = t - lapStartT
        let dist = d - lastLapDistance
        guard dist > 20, secs > 5 else { return }
        let lapHR = HXStats.mean(samples.filter { $0.tS > lapStartT && $0.tS <= t }.compactMap(\.hr))
        let lap = RunLap(index: laps.count + 1, distanceM: dist, seconds: secs, paceSPerKm: secs / (dist / 1000), avgHR: lapHR, isPartial: partial)
        laps.append(lap)
        lapStartTime = t
        lastLapDistance = d
        lapFlash = lap
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if lapFlash == lap { lapFlash = nil } }
    }
    private var lapStartTime: Double = 0

    // MARK: Intervals

    private func buildIntervals() {
        let p = store.paces
        var list: [IntervalPhase] = [IntervalPhase(label: "Warm up", index: 0, total: 0, targetPace: p.easy, endsAtDistanceM: nil, endsAtS: 600)]
        let reps = 6
        for i in 1...reps {
            list.append(IntervalPhase(label: "Work \(i) of \(reps)", index: i, total: reps, targetPace: p.interval, endsAtDistanceM: 1000, endsAtS: nil))
            if i < reps { list.append(IntervalPhase(label: "Recover", index: i, total: reps, targetPace: p.easy, endsAtDistanceM: nil, endsAtS: 90)) }
        }
        list.append(IntervalPhase(label: "Cool down", index: 0, total: 0, targetPace: p.easy, endsAtDistanceM: nil, endsAtS: 600))
        intervals = list
        intervalIndex = 0
        phase = list.first
        phaseStartS = 0; phaseStartD = 0
    }
    private var phaseStartS: Double = 0
    private var phaseStartD: Double = 0

    private func advanceIntervalsIfNeeded() {
        guard let cur = phase else { return }
        var done = false
        if let d = cur.endsAtDistanceM, distanceM - phaseStartD >= d { done = true }
        if let s = cur.endsAtS, elapsedS - phaseStartS >= s { done = true }
        guard done else { return }
        intervalIndex += 1
        phaseStartS = elapsedS; phaseStartD = distanceM
        if intervalIndex < intervals.count {
            phase = intervals[intervalIndex]
            model.buzz(loops: phase!.label.hasPrefix("Work") ? 3 : 1, gate: HapticPrefs.intervals)
            say("\(phase!.label).\(phase!.targetPace.map { " Target \(spoken(pace: $0))." } ?? "")")
        } else {
            phase = nil
            say("Session complete.")
        }
    }

    /// Progress through the current interval phase, 0…1.
    var phaseProgress: Double {
        guard let cur = phase else { return 0 }
        if let d = cur.endsAtDistanceM { return min(1, (distanceM - phaseStartD) / d) }
        if let s = cur.endsAtS { return min(1, (elapsedS - phaseStartS) / s) }
        return 0
    }

    // MARK: Treadmill

    private func rewriteSamplesForManualDistance() {
        guard let last = samples.last, last.tS > 0 else { return }
        let rate = manualDistanceM / last.tS
        samples = samples.map { RunSample(tS: $0.tS, distanceM: $0.tS * rate, hr: $0.hr, altitudeM: nil) }
        laps = RunAnalytics.laps(samples)
        distanceM = manualDistanceM
    }

    // MARK: Speech

    private func say(_ text: String) {
        guard store.profile.voiceCues else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speech.speak(u)
    }

    private func spoken(pace: Double?) -> String {
        guard let p = pace, p.isFinite, p > 0 else { return "unknown" }
        let s = Int(p.rounded())
        return "\(s / 60) \(s % 60) per kilometre"
    }
}
