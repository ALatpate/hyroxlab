import Foundation
import SwiftUI
import Combine
import AVFoundation
import LumaCore

/// Race mode: drives a HYROX-shaped session through its planned segments with millisecond splits,
/// autosaves after every transition, takes the strap's double-tap as "next", buzzes the strap and
/// speaks the cues. HR comes from NOOP's live stream; the session is mirrored into NOOP on finish.
@MainActor
final class RaceSessionController: ObservableObject, Identifiable {
    let id = UUID()
    let kind: HXSessionKind
    let planned: PlannedSession?
    private unowned let model: AppModel
    private unowned let store: HXStore

    @Published private(set) var recorder: SplitRecorder
    @Published private(set) var elapsedS: Double = 0
    @Published private(set) var segmentS: Double = 0
    @Published private(set) var hr: Int?
    @Published private(set) var finished: HXSession?
    @Published private(set) var started = false
    @Published var wallBallReps = 0
    @Published private(set) var aheadBehindS: Double?

    private var timer: AnyCancellable?
    private var segmentHR: [Double] = []
    private let speech = AVSpeechSynthesizer()
    private var targets: [String: Double] = [:]
    private var cumulativeTarget: Double = 0
    private var halfwaySpoken = false
    private var previousTapHandler: (@MainActor () -> Void)?
    private var tickCount = 0

    init(model: AppModel, store: HXStore, kind: HXSessionKind, planned: PlannedSession?) {
        self.model = model; self.store = store; self.kind = kind; self.planned = planned
        let format = store.profile.format, sex = store.sex
        let plan: [PlannedSegment]
        switch kind {
        case .fullSimulation: plan = RacePlanBuilder.fullRace(format: format, sex: sex)
        case .halfSimulation(let second): plan = RacePlanBuilder.halfRace(secondHalf: second, format: format, sex: sex)
        case .compromisedRunning(let st): plan = RacePlanBuilder.compromised(station: st, rounds: 4, format: format, sex: sex)
        case .stationPractice(let st): plan = RacePlanBuilder.stationPractice(station: st, sets: 4, format: format, sex: sex)
        default: plan = RacePlanBuilder.fullRace(format: format, sex: sex)
        }
        let session = HXSession(kind: kind, format: format, sex: sex, startedAt: Date())
        recorder = SplitRecorder(session: session, plan: plan)
        buildTargets(plan: plan)
    }

    var plan: [PlannedSegment] { recorder.plan }
    var current: PlannedSegment? { recorder.current }
    var next: PlannedSegment? { recorder.next }
    var session: HXSession { recorder.session }
    var progress: Double { plan.isEmpty ? 0 : Double(max(0, recorder.currentIndex)) / Double(plan.count) }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        recorder.start()
        store.upsert(recorder.session)
        model.startRealtimeHR()
        model.startWorkout(sport: "HYROX")
        previousTapHandler = model.strapDoubleTapOverride
        model.strapDoubleTapOverride = { [weak self] in self?.advance() }
        model.buzz(loops: 3, gate: HapticPrefs.workout)
        say("Go. \(current?.label ?? "")")
        timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
    }

    /// Next segment. Bound to the big button and to the strap double-tap.
    func advance() {
        guard recorder.isStarted, !recorder.isFinished else { return }
        let closedLabel = current?.label
        let summary = HRSummary.from(samples: segmentHR, durationS: Double(recorder.currentSegmentElapsedMs ?? 0) / 1000, source: .wristOptical)
        let reps: Int? = (current?.station == .wallBalls && wallBallReps > 0) ? wallBallReps : nil
        recorder.advance(hr: summary, reps: reps)
        segmentHR.removeAll(); wallBallReps = 0; halfwaySpoken = false
        store.upsert(recorder.session)
        if let l = closedLabel, let t = targets[l] { cumulativeTarget += t }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if recorder.isFinished {
            complete()
        } else {
            model.buzz(loops: current?.kind == .run ? 2 : 1, gate: HapticPrefs.workout)
            say(cue(for: current))
        }
    }

    func undo() {
        recorder.undoLastAdvance()
        store.upsert(recorder.session)
        say("Undone. Back to \(current?.label ?? "").")
    }

    func finishEarly() {
        let summary = HRSummary.from(samples: segmentHR, durationS: Double(recorder.currentSegmentElapsedMs ?? 0) / 1000, source: .wristOptical)
        recorder.finish(hr: summary)
        complete()
    }

    func discard() {
        timer?.cancel()
        restoreTap()
        if model.activeWorkout != nil { model.discardWorkout() }
        model.stopRealtimeHR()
        store.delete(recorder.session)
    }

    private func complete() {
        timer?.cancel()
        restoreTap()
        var s = recorder.session
        s.endedAt = Date()
        store.upsert(s)
        if let p = planned { store.markPlanned(p, completedBy: s) }
        let allHR = s.segments.compactMap(\.hr)
        let avg = allHR.isEmpty ? nil : Int(allHR.map(\.avg).reduce(0, +) / Double(allHR.count))
        let mx = allHR.map(\.max).max().map { Int($0) }
        let dist = s.segments.filter { $0.kind == .run }.compactMap(\.distanceM).reduce(0, +)
        if model.activeWorkout != nil {
            // NOOP's own record carries HR and Effort; we discard its auto row and write ours with the
            // right sport, duration and distance so nothing is counted twice.
            model.discardWorkout()
        }
        Task { await store.mirrorToNOOP(s, distanceM: dist > 0 ? dist : nil, avgHr: avg, maxHr: mx, kcal: nil) }
        model.stopRealtimeHR()
        model.buzz(loops: 5, gate: HapticPrefs.workout)
        say("Finished. \(HXFormat.duration(s.totalS ?? 0)).")
        finished = s
    }

    private func restoreTap() {
        model.strapDoubleTapOverride = previousTapHandler
        previousTapHandler = nil
    }

    // MARK: Tick

    private func tick() {
        elapsedS = Double(recorder.elapsedMs) / 1000
        segmentS = Double(recorder.currentSegmentElapsedMs ?? 0) / 1000
        tickCount += 1
        if tickCount % 5 == 0 {           // once a second
            hr = model.bpm
            if let h = hr { segmentHR.append(Double(h)) }
        }
        if let cur = current, let target = targets[cur.label] {
            aheadBehindS = (cumulativeTarget + min(segmentS, target)) - elapsedS
            if cur.kind == .run, !halfwaySpoken, segmentS >= target * 0.5 {
                halfwaySpoken = true
                say("Halfway. \(HXFormat.signedSeconds(aheadBehindS ?? 0)).")
            }
        }
    }

    // MARK: Targets

    /// Per-segment targets from the athlete's own benchmarks (fallback: race pace and 30 s roxzones).
    private func buildTargets(plan: [PlannedSegment]) {
        let b = store.benchmarks
        let runT = (b.bestRun1kS?.seconds ?? store.paces.hyroxRace) * 1.08
        let rox = b.typicalRoxzoneS ?? 35
        var t: [String: Double] = [:]
        for p in plan {
            switch p.kind {
            case .run: t[p.label] = runT
            case .roxzone: t[p.label] = rox
            case .station: if let st = p.station { t[p.label] = (b.bestStationS(st, loadKg: p.loadKg) ?? defaultStationS(st)) * 1.1 }
            case .rest: t[p.label] = 180
            default: break
            }
        }
        targets = t
    }

    private func defaultStationS(_ st: Station) -> Double {
        switch st {
        case .skiErg: return 260; case .sledPush: return 200; case .sledPull: return 240; case .burpeeBroadJump: return 300
        case .rowing: return 270; case .farmersCarry: return 120; case .sandbagLunges: return 300; case .wallBalls: return 420
        }
    }

    var currentTargetS: Double? { current.flatMap { targets[$0.label] } }

    private func cue(for p: PlannedSegment?) -> String {
        guard let p else { return "" }
        switch p.kind {
        case .run: return "Run. Target \(HXFormat.duration(targets[p.label] ?? 0))."
        case .roxzone: return "Roxzone. Move."
        case .station:
            let load = p.loadKg.map { $0 > 0 ? " at \(Int($0)) kilos" : "" } ?? ""
            return "\(p.label)\(load)."
        case .rest: return "Rest."
        default: return p.label
        }
    }

    private func say(_ text: String) {
        guard store.profile.voiceCues, !text.isEmpty else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? s.setActive(true)
        let u = AVSpeechUtterance(string: text); u.rate = 0.5
        speech.speak(u)
    }
}
