import SwiftUI
import Combine
import LumaCore
import LumaKit

// MARK: - Reading a workout to be led through

extension LumaEnv {
    /// Keeps a workout that was read, newest first, so it can be started again without reading it again.
    func keep(_ workout: GuidedWorkout) {
        let rest = guided.filter { $0.id != workout.id && $0.title.lowercased() != workout.title.lowercased() }
        guided = Array(([workout] + rest).prefix(12))
    }

    func forget(_ workout: GuidedWorkout) {
        guided.removeAll { $0.id == workout.id }
    }
}

/// A workout typed as a sentence or shown in a picture of the board is read into blocks of steps,
/// checked by the athlete, and then led through one effort or rest at a time.
struct GuidedSetupSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [PickedPhoto] = []
    @State private var text = ""
    @State private var workout: GuidedWorkout?
    @State private var busy = false
    @State private var error: String?

    /// The gallery's workout, as a class board might have it.
    static let demoWorkout = GuidedWorkout(title: "Tuesday class", sport: "Class", blocks: [
        GuidedBlock(name: "Warm-up", steps: [GuidedStep(name: "Row", measure: .time(300))]),
        GuidedBlock(name: "Part A", rounds: 4, steps: [
            GuidedStep(name: "Wall balls", measure: .reps(20), load: "6 kg"),
            GuidedStep(name: "Run", measure: .distance(400)),
            GuidedStep(name: "Farmers carry", measure: .distance(50), load: "2 x 16 kg", restS: 60),
        ]),
        GuidedBlock(name: "Finisher", rounds: 8, steps: [GuidedStep(name: "Burpees", measure: .time(20), restS: 10)]),
    ], note: "Scale the wall ball to 4 kg if needed")

    var body: some View {
        LumaSheet(title: workout == nil ? "Lead me through a workout" : "Check and start", tone: .run) {
            if workout != nil { review } else { pick }
        }
        .onAppear {
            // The gallery has no coach to read with, so it opens on a read made up for it.
            if env.isDemo, LumaLaunch.page == 1, workout == nil { workout = GuidedSetupSheet.demoWorkout }
        }
    }

    // MARK: Pick

    @ViewBuilder
    private var pick: some View {
        if env.coach.hasKey {
            LumaLabel("A picture of the board (up to 2)")
            PhotoStrip(photos: $photos, limit: 2, size: 76)
            LumaField(title: photos.isEmpty ? "Or type it: “EMOM 12: 15 wall balls, 12 burpees”" : "Add detail (optional)", text: $text, axis: .vertical)
            LumaNote("Luma reads it into blocks of steps and shows you what it read before anything starts. Then it leads you through: a buzz on the strap and a spoken cue at every change, a countdown for anything timed, and a double-tap on the strap to move on.")
            if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
            Button {
                Task { await read() }
            } label: {
                if busy { HStack(spacing: 10) { ProgressView().tint(Luma.ink); Text("Reading") } } else { Label("Read it", systemImage: "sparkles") }
            }
            .buttonStyle(LumaPrimaryButtonStyle())
            .disabled(busy || (photos.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        } else {
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reading a workout needs the coach").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    LumaNote("Luma reads the sentence or the picture with your own Anthropic key. Connect one and this is ready.")
                    Button("Connect a key") { router.sheet = .coachSetup }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
        if !env.guided.isEmpty {
            LumaSection(title: "Read before")
            LumaGroup {
                ForEach(env.guided) { saved in
                    Button { workout = saved } label: {
                        LumaRow(symbol: "list.bullet.rectangle.portrait.fill", symbolColor: Luma.aqua, title: saved.title, subtitle: saved.summary, chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func read() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            workout = try await env.coach.readGuided(text: text, photos: photos.map { $0.data })
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "That could not be read. Try again, or type the workout."
        }
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        if let w = workout {
            VStack(alignment: .leading, spacing: 4) {
                Text(w.title).font(LumaFont.title(26)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                Text(w.plannedS.map { "\(w.summary) · \(LumaText.duration($0))" } ?? w.summary).font(LumaFont.body(14)).foregroundStyle(Luma.mist)
            }
            ForEach(Array(w.blocks.enumerated()), id: \.offset) { i, block in
                LumaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(block.name).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                            Spacer()
                            Stepper(value: rounds(i), in: 1...GuidedWorkout.maxRounds) {
                                Text(block.rounds == 1 ? "Once" : "\(block.rounds) rounds").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                            }
                            .fixedSize()
                        }
                        ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Luma.volt).frame(width: 6, height: 6)
                                Text(step.name).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                Spacer(minLength: 6)
                                Text(line(step)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).multilineTextAlignment(.trailing)
                            }
                        }
                        if block.restBetweenRoundsS > 0 {
                            Text("Rest \(GuidedWorkout.lengthText(block.restBetweenRoundsS)) between rounds").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                        }
                    }
                }
            }
            if let note = w.note { LumaNote("Also on the board: \(note)") }
            ForEach(w.problems, id: \.self) { problem in
                Text(problem).font(LumaFont.body(13.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true)
            }
            LumaNote("Check it against the board. A step with a time counts down and moves on by itself; anything else waits for you to tap Next or double-tap the strap.")
            Button("Start") {
                LumaHaptics.thud()
                env.keep(w)
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.cover = .guided(w) }
            }
            .buttonStyle(LumaPrimaryButtonStyle())
            .disabled(!w.isReady)
            Button("Read another") { workout = nil }.buttonStyle(LumaSecondaryButtonStyle())
            if env.guided.contains(where: { $0.id == w.id }) {
                Button("Forget this workout") {
                    env.forget(w)
                    workout = nil
                }
                .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
    }

    private func rounds(_ block: Int) -> Binding<Int> {
        Binding(get: { workout?.blocks[safe: block]?.rounds ?? 1 },
                set: { value in
                    guard var w = workout, block < w.blocks.count else { return }
                    w.blocks[block].rounds = value
                    workout = w
                })
    }

    private func line(_ step: GuidedStep) -> String {
        var parts: [String] = []
        switch step.measure {
        case .time(let t): parts.append(GuidedWorkout.lengthText(t))
        case .reps(let n): parts.append(n == 1 ? "1 rep" : "\(n) reps")
        case .distance(let m): parts.append(m >= 1000 ? "\(LumaText.km(m, decimals: 1)) km" : "\(LNum.int(m.rounded())) m")
        case .open: parts.append("until done")
        }
        if let load = step.load, !load.isEmpty { parts.append(load) }
        if step.restS > 0 { parts.append("rest \(GuidedWorkout.lengthText(step.restS))") }
        return parts.joined(separator: " · ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Being led through it

/// Leads the athlete through a workout: one effort or rest at a time, on top of the strap recorder,
/// which owns heart rate, strain and the stored session. A stretch with a set time counts down and
/// moves on by itself; any other waits for a tap or a double-tap on the strap.
@MainActor
final class GuidedController: ObservableObject {
    let workout: GuidedWorkout
    let segments: [GuidedSegment]
    private unowned let env: LumaEnv
    private let strap: LumaRecorder
    private let voice = SessionVoice()

    @Published private(set) var index = 0
    @Published private(set) var started = false
    @Published private(set) var paused = false
    @Published private(set) var elapsed: Double = 0
    /// Seconds into the stretch under way.
    @Published private(set) var within: Double = 0
    @Published private(set) var hr: Int?
    @Published private(set) var failed: String?
    /// The session is over. `stored` is what the strap layer kept of it, when it kept anything.
    @Published private(set) var ended = false
    @Published private(set) var stored: LWorkout?

    private var timer: AnyCancellable?
    private var stretchStart: Double = 0
    private var counted = 0
    private var recordingMotion = false
    private var heartRates: [Double] = []

    init(env: LumaEnv, workout: GuidedWorkout) {
        self.env = env
        self.workout = workout
        segments = workout.segments
        strap = env.recorder ?? DemoRecorder()
        voice.enabled = env.profile.voiceCues
    }

    var current: GuidedSegment? { index < segments.count ? segments[index] : nil }
    var next: GuidedSegment? { index + 1 < segments.count ? segments[index + 1] : nil }
    /// Seconds left in a stretch with a set time.
    var remaining: Double? { current?.seconds.map { max(0, $0 - within) } }
    var progress: Double { segments.isEmpty ? 0 : Double(min(index, segments.count)) / Double(segments.count) }
    var averageHR: Double? { LStat.mean(heartRates) }
    var canUseStrapTap: Bool { env.live.strap.secure }

    /// The sport a led workout is stored under, in the strap layer's own names.
    private var sport: String {
        switch workout.sport {
        case "Strength": return "Strength"
        case "Run": return "Running"
        case "HYROX": return "HYROX"
        default: return "Conditioning"
        }
    }

    func start() {
        guard !started else { return }
        if let demo = strap as? DemoRecorder, env.isDemo { demo.headStart = 612 }
        guard strap.start(sport: sport, gps: false) else {
            failed = "Another session is already being recorded. Finish it first."
            return
        }
        started = true
        strap.onStrapDoubleTap = { [weak self] in self?.advance() }
        env.device?.setLiveHeartRate(true)
        env.device?.cue()
        if env.extras.motion, env.device?.startMotion(note: workout.title) == true {
            recordingMotion = true
            if let first = current { env.device?.markMotion(first.title) }
        }
        // The gallery opens a few stretches in, part-way through a timed one when there is one.
        if env.isDemo {
            index = min(5, max(0, segments.count - 1))
            stretchStart = strap.elapsed - 7
        } else {
            stretchStart = strap.elapsed
        }
        voice.say("\(workout.title). " + words(current))
        timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        elapsed = strap.elapsed
        within = max(0, elapsed - stretchStart)
        let reading = env.live.strap.liveHeartRate()
        if reading != hr { hr = reading }
        guard !paused, let now = current else { return }
        if let h = reading, LNum.int(elapsed * 4) % 4 == 0 { heartRates.append(Double(h)) }
        guard let length = now.seconds else { return }
        let left = length - within
        // A tap for each of the last three seconds of a timed stretch.
        let whole = LNum.int(left.rounded(.up))
        if whole >= 1, whole <= 3, whole != counted {
            counted = whole
            LumaHaptics.tap()
        }
        if left <= 0 { advance() }
    }

    /// Moves to the next stretch. Bound to the big button, to the strap's double-tap, and to the end of
    /// a timed stretch.
    func advance() {
        guard started, !ended, index < segments.count else { return }
        index += 1
        stretchStart = strap.elapsed
        within = 0
        counted = 0
        guard let now = current else {
            finish()
            return
        }
        env.device?.cue()
        LumaHaptics.success()
        if recordingMotion { env.device?.markMotion(now.title) }
        voice.say(words(now))
    }

    /// Back to the start of the stretch before, for a tap that came too soon.
    func back() {
        guard started, !ended, index > 0 else { return }
        index -= 1
        stretchStart = strap.elapsed
        within = 0
        counted = 0
        if recordingMotion, let now = current { env.device?.markMotion(now.title) }
        voice.say("Back to \(current?.title ?? "the start").")
    }

    func togglePause() {
        guard started, !ended else { return }
        paused.toggle()
        strap.setPaused(paused)
        voice.say(paused ? "Paused." : "Resumed.")
    }

    func finish() {
        guard started, !ended else { return }
        timer?.cancel()
        strap.onStrapDoubleTap = nil
        env.device?.setLiveHeartRate(false)
        env.device?.cue()
        stopMotion()
        elapsed = strap.elapsed
        voice.say("Workout finished.")
        let note = "\(workout.title): \(workout.summary)"
        Task {
            if var w = await strap.finish() {
                if w.editable, !env.isDemo {
                    let old = w
                    w.notes = note
                    env.saveWorkout(w, replacing: old)
                }
                stored = w
            }
            env.reload()
            ended = true
        }
    }

    func discard() {
        timer?.cancel()
        strap.onStrapDoubleTap = nil
        strap.discard()
        env.device?.setLiveHeartRate(false)
        stopMotion()
    }

    private func stopMotion() {
        guard recordingMotion else { return }
        recordingMotion = false
        env.device?.stopMotion()
    }

    /// A stretch as it is said aloud.
    private func words(_ s: GuidedSegment?) -> String {
        guard let s else { return "" }
        if s.isRest {
            return "Rest. " + GuidedController.spoken(s.seconds ?? 0) + "." + (next.map { " Then \($0.title)." } ?? "")
        }
        var out = s.title + "."
        if let length = s.seconds {
            out += " " + GuidedController.spoken(length) + "."
        } else if !s.detail.isEmpty {
            out += " " + s.detail.replacingOccurrences(of: " · ", with: ", ") + "."
        }
        if s.rounds > 1 { out += " Round \(s.round) of \(s.rounds)." }
        return out
    }

    /// "45 seconds", "1 minute 30".
    static func spoken(_ seconds: Double) -> String {
        let s = LNum.int(seconds.rounded())
        if s < 60 { return "\(s) seconds" }
        let m = s / 60, r = s % 60
        return "\(m) minute\(m == 1 ? "" : "s")" + (r > 0 ? " \(r)" : "")
    }
}

struct GuidedLiveScreen: View {
    let workout: GuidedWorkout
    @EnvironmentObject private var env: LumaEnv

    var body: some View { GuidedLiveBody(env: env, workout: workout) }
}

private struct GuidedLiveBody: View {
    @StateObject private var c: GuidedController
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false

    init(env: LumaEnv, workout: GuidedWorkout) {
        _c = StateObject(wrappedValue: GuidedController(env: env, workout: workout))
    }

    var body: some View {
        ZStack {
            LumaBackdrop(tone: c.current?.isRest == true ? .sleep : .run, strength: 1.2)
            if c.ended {
                summary
            } else if !c.started {
                ready
            } else {
                running
            }
        }
        .onAppear { if env.isDemo { c.start() } }
        .confirmationDialog("End this workout?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Finish and save") { c.finish() }
            Button("Discard", role: .destructive) { c.discard(); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                LumaIconButton(symbol: "xmark") { dismiss() }
            }
            Spacer()
            Image(systemName: "list.bullet.rectangle.portrait.fill").font(.system(size: 50, weight: .semibold)).foregroundStyle(Luma.volt)
            Text(c.workout.title).font(LumaFont.title(34)).foregroundStyle(Luma.frost).multilineTextAlignment(.center)
            Text("\(c.workout.summary). A buzz and a spoken cue at every change. Time, heart rate and strain are recorded for the whole session.")
                .font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center).padding(.horizontal, 30)
            if let f = c.failed { Text(f).font(LumaFont.body(14)).foregroundStyle(Luma.coral).multilineTextAlignment(.center).padding(.horizontal, 30) }
            Spacer()
            Button("Start") { c.start() }.buttonStyle(LumaPrimaryButtonStyle()).padding(.horizontal, 24)
            Text(c.canUseStrapTap ? "Double-tap the strap to move on without the phone." : "Tap Next to move on.")
                .font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
        }
        .padding(.vertical, 18).padding(.horizontal, Luma.gutter)
    }

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.workout.title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost).lineLimit(1)
                    Text(c.paused ? "Paused" : LumaText.duration(c.elapsed)).font(LumaFont.label(11)).foregroundStyle(c.paused ? Luma.amber : Luma.volt)
                }
                Spacer()
                if let hr = c.hr {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.coral)
                        Text("\(hr)").font(LumaFont.numeral(26)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, Luma.gutter).padding(.top, 10)
            LumaBar(value: c.progress, total: 1, color: Luma.volt, height: 6)
                .padding(.horizontal, Luma.gutter).padding(.top, 12)

            Spacer(minLength: 8)
            if let now = c.current {
                VStack(spacing: 6) {
                    Text(now.rounds > 1 ? "\(now.block) · round \(now.round) of \(now.rounds)" : now.block)
                        .font(LumaFont.label(12)).foregroundStyle(Luma.mist)
                    Text(now.title).font(LumaFont.title(44)).foregroundStyle(now.isRest ? Luma.sky : Luma.frost)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
                    if !now.isRest, !now.detail.isEmpty, now.seconds == nil {
                        Text(now.detail).font(LumaFont.heading(22)).foregroundStyle(Luma.volt).multilineTextAlignment(.center)
                    }
                    Text(LumaText.duration(c.remaining ?? c.within))
                        .font(LumaFont.numeral(104, .heavy)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text(now.seconds == nil ? "Tap Next when it is done" : "Moves on by itself").font(LumaFont.body(13)).foregroundStyle(Luma.smoke)
                }
                .padding(.horizontal, Luma.gutter)
            }
            Spacer(minLength: 8)
            if let next = c.next {
                HStack {
                    LumaLabel("Next")
                    Spacer()
                    Text(next.detail.isEmpty || next.isRest ? next.title + (next.isRest ? " " + next.detail : "") : "\(next.title) · \(next.detail)")
                        .font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(LumaPanel(radius: 18))
                .padding(.horizontal, Luma.gutter)
            }
            HStack(spacing: 18) {
                roundButton("backward.end.fill", "Back", Luma.frost) { c.back() }
                Button {
                    LumaHaptics.thud()
                    c.advance()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "forward.end.fill").font(.system(size: 26, weight: .bold))
                        Text("Next").font(LumaFont.label(10))
                    }
                    .foregroundStyle(Luma.ink)
                    .frame(width: 96, height: 96).background(Circle().fill(Luma.volt)).shadow(color: Luma.volt.opacity(0.45), radius: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
                roundButton(c.paused ? "play.fill" : "pause.fill", c.paused ? "Resume" : "Pause", Luma.frost) { c.togglePause() }
                roundButton("stop.fill", "Finish", Luma.coral) { confirmStop = true }
            }
            .padding(.top, 16).padding(.bottom, 26)
        }
    }

    private var summary: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 54, weight: .semibold)).foregroundStyle(Luma.volt)
            Text(c.workout.title).font(LumaFont.title(32)).foregroundStyle(Luma.frost).multilineTextAlignment(.center)
            Text(LumaText.duration(c.stored?.durationS ?? c.elapsed)).font(LumaFont.numeral(88, .heavy)).foregroundStyle(Luma.frost)
                .minimumScaleFactor(0.6).lineLimit(1)
            StatGrid {
                StatCell(label: "Efforts", value: "\(c.segments.filter { !$0.isRest }.count)")
                StatCell(label: "Average heart rate", value: (c.stored?.avgHR ?? c.averageHR).map { "\(LNum.int($0.rounded()))" } ?? "–", unit: "bpm")
                if let strain = c.stored?.strain { StatCell(label: "Strain", value: LScale.text(strain, on21: env.profile.strainOn21)) }
                if let kcal = c.stored?.kcal { StatCell(label: "Energy", value: LFormat.grouped(kcal), unit: "kcal") }
            }
            .padding(.horizontal, Luma.gutter)
            Text(c.stored == nil ? "It was too short to keep as a session." : "Saved to your training log.")
                .font(LumaFont.body(14)).foregroundStyle(Luma.mist)
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(LumaPrimaryButtonStyle()).padding(.horizontal, 24).padding(.bottom, 18)
        }
    }

    private func roundButton(_ symbol: String, _ label: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 56, height: 56).background(Circle().fill(Luma.raised)).overlay(Circle().strokeBorder(Luma.line, lineWidth: 1))
                Text(label).font(LumaFont.label(10)).foregroundStyle(Luma.mist)
            }
        }
        .buttonStyle(.plain)
    }
}
