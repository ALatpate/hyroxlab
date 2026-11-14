import SwiftUI
import Combine
import AVFoundation
import LumaCore
import LumaKit

// MARK: - Voice

/// Spoken cues over whatever is playing: music ducks while Luma speaks.
@MainActor
final class SessionVoice {
    private let speech = AVSpeechSynthesizer()
    var enabled = true

    func say(_ text: String) {
        guard enabled, !text.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5
        speech.speak(u)
    }

    static func pace(_ p: Double?) -> String {
        guard let p, p.isFinite, p > 0 else { return "unknown" }
        let s = Int(p.rounded())
        return "\(s / 60) \(s % 60) per kilometre"
    }
}

// MARK: - Demo recorder

/// A stand-in recorder for the gallery: time passes and distance accumulates at a steady pace.
@MainActor
final class DemoRecorder: LumaRecorder {
    private(set) var isRunning = false
    private(set) var isPaused = false
    private var startedAt = Date()
    private var banked: TimeInterval = 0
    private var sport = "Running"
    private var gps = true
    var onStrapDoubleTap: (() -> Void)?
    /// Seconds already "run" when a demo session opens mid-way.
    var headStart: TimeInterval = 0

    var elapsed: TimeInterval { banked + headStart + (isRunning && !isPaused ? Date().timeIntervalSince(startedAt) : 0) }
    var distanceM: Double { gps ? elapsed / 308 * 1000 : 0 }

    func start(sport: String, gps: Bool) -> Bool {
        guard !isRunning else { return false }
        self.sport = sport; self.gps = gps
        isRunning = true; isPaused = false; banked = 0; startedAt = Date()
        return true
    }

    func setPaused(_ paused: Bool) {
        guard isRunning, paused != isPaused else { return }
        if paused { banked += Date().timeIntervalSince(startedAt) } else { startedAt = Date() }
        isPaused = paused
    }

    func route() -> [LumaRoutePoint] {
        guard gps else { return [] }
        let loop = LumaDemoSource.loop(distanceM: 9200, salt: 3)
        let n = min(loop.count, max(2, Int(distanceM / 9200 * Double(loop.count))))
        return loop.prefix(n).enumerated().map { LumaRoutePoint(lat: $0.element.lat, lon: $0.element.lon, t: Double($0.offset) * 13) }
    }

    func finish() async -> LWorkout? {
        let end = Date().timeIntervalSince1970
        let w = LWorkout(start: end - elapsed, end: end, sport: sport, source: "demo", kcal: elapsed / 60 * 12, avgHR: 152, maxHR: 171,
                         strain: 62, distanceM: gps ? distanceM : nil)
        isRunning = false
        return w
    }

    func discard() { isRunning = false }
}

// MARK: - Run controller

struct RunResult: Equatable {
    var workout: LWorkout?
    var title: String
    var seconds: Double
    var distanceM: Double
    var laps: [RunLap]
    var samples: [RunSample]
    var route: [LCoord]
    var newBests: [PersonalBest]
    var avgHR: Double?
    var maxHR: Double?
}

/// Drives a run (outdoor, intervals, treadmill) or any timed session on top of the strap recorder:
/// the recorder owns heart rate, strain, GPS and the stored session; this adds the one-second
/// timeline, auto-laps, smoothed pace, voice cues, auto-pause and structured intervals.
@MainActor
final class RunController: ObservableObject {
    struct Phase: Equatable {
        let label: String
        let targetPace: Double?
        let metres: Double?
        let seconds: Double?
        var isWork: Bool { label.hasPrefix("Work") }
    }

    let plan: RunPlan
    private unowned let env: LumaEnv
    private let recorder: LumaRecorder
    private let voice = SessionVoice()

    @Published private(set) var started = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var distanceM: Double = 0
    @Published private(set) var pace: Double?
    @Published private(set) var avgPace: Double?
    @Published private(set) var hr: Int?
    @Published private(set) var laps: [RunLap] = []
    @Published private(set) var lapFlash: RunLap?
    @Published private(set) var route: [LCoord] = []
    @Published private(set) var paused = false
    @Published private(set) var autoPaused = false
    @Published private(set) var phase: Phase?
    @Published private(set) var phaseIndex = 0
    @Published private(set) var phaseCount = 0
    @Published private(set) var result: RunResult?
    @Published private(set) var failed: String?
    @Published private(set) var samples: [RunSample] = []

    private var timer: AnyCancellable?
    private var smoother = PaceSmoother()
    private var lapStartT = 0.0
    private var lapStartD = 0.0
    private var lastMoveT = 0.0
    private var lastMoveD = 0.0
    private var lastCueKm = 0
    private var lastCueBlock = 0
    private var phases: [Phase] = []
    private var phaseStartT = 0.0
    private var phaseStartD = 0.0

    init(env: LumaEnv, plan: RunPlan) {
        self.env = env
        self.plan = plan
        self.recorder = env.recorder ?? DemoRecorder()
        voice.enabled = env.profile.voiceCues
    }

    var usesGPS: Bool { plan.mode == .free || plan.mode == .intervals }
    var isRun: Bool { plan.mode != .session }
    var zones: HXZones { env.profile.zones() }

    var phaseProgress: Double {
        guard let p = phase else { return 0 }
        if let m = p.metres { return min(1, (distanceM - phaseStartD) / m) }
        if let s = p.seconds { return min(1, (elapsed - phaseStartT) / s) }
        return 0
    }
    var phaseRemaining: String {
        guard let p = phase else { return "" }
        if let m = p.metres { return "\(Int(max(0, m - (distanceM - phaseStartD)))) m to go" }
        if let s = p.seconds { return "\(LumaText.duration(max(0, s - (elapsed - phaseStartT)))) to go" }
        return ""
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        if let demo = recorder as? DemoRecorder, env.isDemo { demo.headStart = usesGPS ? 1423 : 1264 }
        guard recorder.start(sport: plan.sport, gps: usesGPS) else {
            failed = "Another session is already being recorded. Finish it first."
            return
        }
        started = true
        env.device?.setLiveHeartRate(true)
        if plan.mode == .intervals { buildIntervals() }
        if env.isDemo { seedDemo() }
        voice.say(plan.mode == .intervals ? "Intervals. Warm up." : "\(plan.title) started.")
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        tick()
    }

    func togglePause() {
        paused.toggle()
        autoPaused = false
        recorder.setPaused(paused)
        smoother.reset()
        voice.say(paused ? "Paused." : "Resumed.")
    }

    func lap() {
        guard elapsed - lapStartT > 5 else { return }
        closeLap(partial: true, distance: distanceM, time: elapsed)
    }

    /// Ends the session. `treadmillKm` is the distance read off the treadmill, when there is no GPS.
    func finish(treadmillKm: Double? = nil) {
        timer?.cancel()
        env.device?.setLiveHeartRate(false)
        let seconds = elapsed
        var finalSamples = samples
        var distance = distanceM
        if plan.mode == .treadmill, let km = treadmillKm, km > 0, seconds > 0 {
            distance = km * 1000
            let rate = distance / seconds
            finalSamples = samples.map { RunSample(tS: $0.tS, distanceM: $0.tS * rate, hr: $0.hr) }
        }
        let finalLaps = isRun && distance > 0 ? RunAnalytics.laps(finalSamples) : []
        let hrs = finalSamples.compactMap { $0.hr }
        let track = route
        Task {
            var workout = await recorder.finish()
            if var w = workout, plan.mode == .treadmill, distance > 0, w.editable {
                let old = w
                w.distanceM = distance
                env.saveWorkout(w, replacing: old)
                workout = w
            }
            var bests: [PersonalBest] = []
            if usesGPS, distance >= 1000 { bests = env.mergePBs(RunAnalytics.personalBests(finalSamples)) }
            if let w = workout, isRun { env.saveRunSamples(finalSamples, for: w.id) }
            env.reload()
            voice.say(isRun ? "\(plan.title) finished. \(String(format: "%.1f", distance / 1000)) kilometres." : "\(plan.title) finished.")
            result = RunResult(workout: workout, title: plan.title, seconds: seconds, distanceM: distance, laps: finalLaps, samples: finalSamples,
                               route: track, newBests: bests, avgHR: LStat.mean(hrs), maxHR: hrs.max())
        }
    }

    func discard() {
        timer?.cancel()
        recorder.discard()
        env.device?.setLiveHeartRate(false)
    }

    // MARK: Tick

    private func tick() {
        elapsed = recorder.elapsed
        hr = env.live.strap.liveHeartRate()
        if usesGPS { distanceM = recorder.distanceM }
        if paused && !autoPaused { return }

        if !paused {
            samples.append(RunSample(tS: elapsed, distanceM: distanceM, hr: hr.map(Double.init)))
            pace = usesGPS ? smoother.push(tS: elapsed, distanceM: distanceM) : nil
            avgPace = distanceM > 50 ? elapsed / (distanceM / 1000) : nil
            if usesGPS, distanceM - lapStartD >= 1000 { closeLap(partial: false, distance: lapStartD + 1000, time: elapsed) }
            if Int(elapsed) % 5 == 0, usesGPS { route = recorder.route().map { LCoord(lat: $0.lat, lon: $0.lon) } }
            cues()
            if plan.mode == .intervals { advancePhase() }
        }
        guard env.profile.autoPause, usesGPS else { return }
        let d = recorder.distanceM
        if d - lastMoveD > 3 {
            lastMoveD = d; lastMoveT = elapsed
            if autoPaused {
                autoPaused = false; paused = false
                recorder.setPaused(false)
                voice.say("Resumed.")
            }
        } else if !paused, elapsed - lastMoveT > 8, elapsed > 20 {
            paused = true; autoPaused = true
            recorder.setPaused(true)
            voice.say("Auto paused.")
        }
    }

    private func cues() {
        let km = Int(distanceM / 1000)
        let heart = hr.map { " Heart rate \($0)." } ?? ""
        if usesGPS, env.profile.cueEveryKm, km > lastCueKm {
            lastCueKm = km
            voice.say("\(km) kilometre\(km == 1 ? "" : "s"). Last split \(SessionVoice.pace(laps.last?.paceSPerKm)).\(heart)")
        } else if !usesGPS || !env.profile.cueEveryKm {
            let block = Int(elapsed / 300)
            if block > lastCueBlock { lastCueBlock = block; voice.say("\(block * 5) minutes.\(heart)") }
        }
    }

    private func closeLap(partial: Bool, distance d: Double, time t: Double) {
        let seconds = t - lapStartT, metres = d - lapStartD
        guard metres > 20, seconds > 5 else { return }
        let lapHR = LStat.mean(samples.filter { $0.tS > lapStartT && $0.tS <= t }.compactMap { $0.hr })
        let lap = RunLap(index: laps.count + 1, distanceM: metres, seconds: seconds, paceSPerKm: seconds / (metres / 1000), avgHR: lapHR, isPartial: partial)
        laps.append(lap)
        lapStartT = t; lapStartD = d
        lapFlash = lap
        LumaHaptics.thud()
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if lapFlash == lap { lapFlash = nil }
        }
    }

    // MARK: Intervals

    private func buildIntervals() {
        let paces = env.profile.fiveKSeconds.map { TrainingPaces(fiveKSeconds: $0) }
        var list = [Phase(label: "Warm up", targetPace: paces?.easy, metres: nil, seconds: 600)]
        for i in 1...max(1, plan.intervalCount) {
            list.append(Phase(label: "Work \(i) of \(plan.intervalCount)", targetPace: plan.targetPaceSPerKm ?? paces?.interval, metres: plan.intervalMeters, seconds: nil))
            if i < plan.intervalCount { list.append(Phase(label: "Recover", targetPace: paces?.easy, metres: nil, seconds: plan.restSeconds)) }
        }
        list.append(Phase(label: "Cool down", targetPace: paces?.easy, metres: nil, seconds: 600))
        phases = list
        phaseCount = list.count
        phaseIndex = 0
        phase = list.first
    }

    private func advancePhase() {
        guard let p = phase else { return }
        var done = false
        if let m = p.metres, distanceM - phaseStartD >= m { done = true }
        if let s = p.seconds, elapsed - phaseStartT >= s { done = true }
        guard done else { return }
        phaseIndex += 1
        phaseStartT = elapsed; phaseStartD = distanceM
        if phaseIndex < phases.count {
            let next = phases[phaseIndex]
            phase = next
            env.device?.cue()
            let target = next.targetPace.map { " Target " + SessionVoice.pace($0) + "." } ?? ""
            voice.say(next.label + "." + target)
        } else {
            phase = nil
            voice.say("Session complete. Finish when you are ready.")
        }
    }

    /// Fills in the minutes "already run" so the gallery shows a session in full flow.
    private func seedDemo() {
        let total = recorder.elapsed
        var d = 0.0
        var out: [RunSample] = []
        for t in stride(from: 0.0, to: total, by: 1) {
            let speed = usesGPS ? 1000 / (308 + 14 * sin(t / 140) + 6 * sin(t / 37)) : 0
            d += speed
            out.append(RunSample(tS: t, distanceM: d, hr: 138 + 16 * min(1, t / 400) + 5 * sin(t / 90)))
        }
        samples = out
        if usesGPS {
            laps = RunAnalytics.laps(out).filter { !$0.isPartial }
            lapStartD = Double(laps.count) * 1000
            lapStartT = laps.reduce(0) { $0 + $1.seconds }
            lastCueKm = laps.count
            route = recorder.route().map { LCoord(lat: $0.lat, lon: $0.lon) }
        }
        lastCueBlock = Int(total / 300)
        lastMoveD = recorder.distanceM; lastMoveT = total
        if plan.mode == .intervals, phases.count > 3 {
            phaseIndex = 3; phase = phases[3]
            phaseStartT = total - 150; phaseStartD = recorder.distanceM - 520
        }
    }
}

// MARK: - Race controller

/// The system monotonic clock plus an offset, so a demo can open part-way through a race.
final class RaceClock: MonotonicClock, @unchecked Sendable {
    private let base = SystemMonotonicClock()
    var offsetMs: Int64 = 0
    func nowMs() -> Int64 { base.nowMs() + offsetMs }
}

/// Race mode: steps a HYROX-shaped session through its planned segments with millisecond splits,
/// saves after every transition, takes the strap's double-tap as "next", and speaks each cue.
@MainActor
final class RaceController: ObservableObject {
    let kind: HXSessionKind
    private unowned let env: LumaEnv
    private let strap: LumaRecorder
    private let voice = SessionVoice()
    private let clock: RaceClock

    @Published private(set) var recorder: SplitRecorder
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var segment: Double = 0
    @Published private(set) var hr: Int?
    @Published private(set) var started = false
    @Published private(set) var finished: HXSession?
    @Published private(set) var aheadBehind: Double?
    @Published var wallBallReps = 0

    private var timer: AnyCancellable?
    private var segmentHR: [Double] = []
    private var targets: [Int: Double] = [:]
    private var cumulativeTarget = 0.0
    private var halfwaySpoken = false
    private var ticks = 0

    init(env: LumaEnv, kind: HXSessionKind) {
        self.env = env
        self.kind = kind
        self.strap = env.recorder ?? DemoRecorder()
        let format = env.profile.format, sex = env.profile.sex
        let plan: [PlannedSegment]
        switch kind {
        case .halfSimulation(let second): plan = RacePlanBuilder.halfRace(secondHalf: second, format: format, sex: sex)
        case .compromisedRunning(let st): plan = RacePlanBuilder.compromised(station: st, rounds: 4, format: format, sex: sex)
        case .stationPractice(let st): plan = RacePlanBuilder.stationPractice(station: st, sets: 4, format: format, sex: sex)
        default: plan = RacePlanBuilder.fullRace(format: format, sex: sex)
        }
        let clock = RaceClock()
        self.clock = clock
        recorder = SplitRecorder(session: HXSession(kind: kind, format: format, sex: sex, startedAt: Date()), plan: plan, clock: clock)
        voice.enabled = env.profile.voiceCues
        buildTargets(plan)
    }

    var plan: [PlannedSegment] { recorder.plan }
    var current: PlannedSegment? { recorder.current }
    var next: PlannedSegment? { recorder.next }
    var index: Int { max(0, recorder.currentIndex) }
    var progress: Double { plan.isEmpty ? 0 : Double(index) / Double(plan.count) }
    var currentTarget: Double? { current.flatMap { targets[$0.id] } }
    var canUseStrapTap: Bool { env.live.strap.secure }

    func start() {
        guard !started else { return }
        started = true
        recorder.start()
        env.upsert(recorder.session)
        _ = strap.start(sport: "HYROX", gps: false)
        strap.onStrapDoubleTap = { [weak self] in self?.advance() }
        env.device?.setLiveHeartRate(true)
        env.device?.cue()
        if env.isDemo { seedDemo() }
        voice.say("Go. \(current?.label ?? "")")
        timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        tick()
    }

    /// Moves to the next segment. Bound to the big button and to the strap's double-tap.
    func advance() {
        guard recorder.isStarted, !recorder.isFinished else { return }
        let closed = current
        let summary = HRSummary.from(samples: segmentHR, durationS: Double(recorder.currentSegmentElapsedMs ?? 0) / 1000, source: .wristOptical)
        let reps: Int? = (closed?.station == .wallBalls && wallBallReps > 0) ? wallBallReps : nil
        recorder.advance(hr: summary, reps: reps)
        segmentHR.removeAll(); wallBallReps = 0; halfwaySpoken = false
        env.upsert(recorder.session)
        if let c = closed, let t = targets[c.id] { cumulativeTarget += t }
        LumaHaptics.success()
        if recorder.isFinished {
            complete()
        } else {
            env.device?.cue()
            voice.say(cue(current))
        }
    }

    func undo() {
        recorder.undoLastAdvance()
        env.upsert(recorder.session)
        voice.say("Undone. Back to \(current?.label ?? "").")
    }

    func finishEarly() {
        let summary = HRSummary.from(samples: segmentHR, durationS: Double(recorder.currentSegmentElapsedMs ?? 0) / 1000, source: .wristOptical)
        recorder.finish(hr: summary)
        complete()
    }

    func discard() {
        timer?.cancel()
        strap.onStrapDoubleTap = nil
        strap.discard()
        env.device?.setLiveHeartRate(false)
        env.delete(recorder.session)
    }

    private func complete() {
        timer?.cancel()
        strap.onStrapDoubleTap = nil
        var s = recorder.session
        if s.endedAt == nil { s.endedAt = Date() }
        env.upsert(s)
        env.device?.setLiveHeartRate(false)
        env.device?.cue()
        voice.say("Finished. \(LumaText.duration(s.totalS ?? 0)).")
        let distance = s.runs.compactMap { $0.distanceM }.reduce(0, +)
        Task {
            if var w = await strap.finish(), distance > 0, w.editable {
                let old = w
                w.distanceM = distance
                env.saveWorkout(w, replacing: old)
            }
            env.reload()
        }
        finished = s
    }

    private func tick() {
        elapsed = Double(recorder.elapsedMs) / 1000
        segment = Double(recorder.currentSegmentElapsedMs ?? 0) / 1000
        ticks += 1
        if ticks % 5 == 1 {
            hr = env.live.strap.liveHeartRate()
            if let h = hr { segmentHR.append(Double(h)) }
        }
        if let cur = current, let target = targets[cur.id] {
            aheadBehind = (cumulativeTarget + min(segment, target)) - elapsed
            if cur.kind == .run, !halfwaySpoken, segment >= target * 0.5 {
                halfwaySpoken = true
                let delta = aheadBehind ?? 0
                voice.say("Halfway. \(Int(abs(delta))) seconds \(delta >= 0 ? "ahead" : "behind").")
            }
        }
    }

    /// Per-segment targets: the athlete's own bests with their measured race fatigue, the same
    /// numbers the finish prediction is built from.
    private func buildTargets(_ plan: [PlannedSegment]) {
        var practice = false
        if case .stationPractice = kind { practice = true }
        targets = RaceReadiness.targets(for: plan, benchmarks: env.benchmarks, sessions: env.sessions,
                                        fresh1kS: env.runPBs.first { $0.distanceM == 1000 }?.seconds,
                                        fallbackRun1kS: env.profile.fiveKSeconds.map { $0 / 5 * 1.12 } ?? 330, raceEffort: !practice)
    }

    private func cue(_ p: PlannedSegment?) -> String {
        guard let p else { return "" }
        switch p.kind {
        case .run: return "Run. Target \(LumaText.duration(targets[p.id] ?? 0))."
        case .roxzone: return "Roxzone. Keep moving."
        case .station:
            if let kg = p.loadKg, kg > 0 { return "\(p.label) at \(Int(kg)) kilos." }
            return "\(p.label)."
        case .rest: return "Rest."
        default: return p.label
        }
    }

    /// Opens the gallery part-way through a race, with believable splits behind it.
    private func seedDemo() {
        var rng = SeededRNG(seed: 12)
        for _ in 0..<max(0, min(9, plan.count - 2)) {
            guard let cur = current else { break }
            let t = (targets[cur.id] ?? 60) * rng.range(0.9, 1.04)
            clock.offsetMs += Int64(t * 1000)
            recorder.advance(hr: HRSummary(avg: 161, max: 170, min: 150, sampleCount: Int(t), expectedCount: Int(t), source: .wristOptical))
            cumulativeTarget += targets[cur.id] ?? 0
        }
        clock.offsetMs += 96_000
        env.upsert(recorder.session)
    }
}
