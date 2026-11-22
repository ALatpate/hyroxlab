import SwiftUI
import Speech
import AVFoundation
import LumaCore
import LumaKit

// MARK: - Glimm's day
//
// Once a day Glimm's lines are written afresh from what the day holds, on the athlete's own key, and
// it may add a note or two to its own notebook. Both are switches. Without them, without a key or
// without a connection, it speaks from its fixed lines as before.

extension LumaEnv {
    /// The line written for today that fits the state Glimm is in, when there is one: the
    /// after-training line once a session is done, the evening line from six, the morning line before.
    /// Any other state (asleep, thirsty, a new best) keeps its own fixed lines, which say why.
    func glimmDayLine(for look: BuddyLook, now: Date = Date()) -> GlimmSaying? {
        guard !glimm.quiet, extras.glimmFresh, let lines = glimm.lines, lines.day == LDate.key(now) else { return nil }
        let hour = LDate.calendar.component(.hour, from: now)
        switch look.mood {
        case .worked: return lines.afterTraining
        case .drained, .steady, .charged: return hour >= 18 ? lines.evening : lines.morning
        default: return nil
        }
    }

    /// Has Glimm's lines for the day written, once a day, and lets it add to its notebook. Called after
    /// each reload; it does nothing until the night is in (or the morning is over), and nothing again
    /// once today's lines are there.
    func glimmWriteDay(now: Date = Date()) {
        guard !isDemo, storesReady, loaded, extras.glimmFresh, glimmCanTalk, !glimm.quiet else { return }
        let day = LDate.key(now)
        let hour = LDate.calendar.component(.hour, from: now)
        guard glimm.lines?.day != day, hour >= 4, analysis.lastNight?.day == day || hour >= 11 else { return }
        // A request that failed is tried again, at most every two hours.
        let stamp = now.timeIntervalSince1970
        guard stamp - glimmDayTriedAt >= 7200 else { return }
        glimmDayTriedAt = stamp
        let share = profile.shareHealthWithCoach
        let look = buddyLook(now: now)
        var facts = GlimmBrief.facts(analysis: analysis, planned: planned, workouts: workouts, today: today, shareHealth: share)
        if share { facts.insert("How the day looks: \(look.title). \(look.line)", at: 0) }
        let clock = now.formatted(.dateTime.weekday(.wide)) + ", " + now.formatted(date: .omitted, time: .shortened)
        // Its own notes came from the athlete's records: they go, and are added to or crossed out, only
        // with leave to share those. What it learns from, the last two weeks a line a day and what the
        // app's own analysis has found, goes only while it is learning.
        let learning = glimm.learns && share
        let sent = share ? Array(glimm.notebook.suffix(GlimmState.noticedLimit)) : []
        let ask = GlimmDaily.request(day: day, clock: clock, name: profile.name, facts: facts,
                                     diary: learning ? GlimmBrief.diary(days: days, sleeps: sleeps, workouts: workouts, today: today, shareHealth: share) : [],
                                     patterns: learning ? GlimmBrief.patterns(analysis.insights, shareHealth: share) : [],
                                     notebook: sent.map { $0.text }, takenOut: learning ? glimm.takenOut : [],
                                     wearing: glimmOutfit(for: look.mood, at: now).name, learns: learning)
        Task { [weak self] in
            guard let self else { return }
            guard let raw = try? await self.coach.glimmDay(ask), let parsed = GlimmDaily.parse(raw, day: day) else { return }
            guard self.storesReady else { return }
            var g = self.glimm
            g.lines = parsed.lines
            g.linesAsked = day
            if learning {
                // The answer names notes by their number in the list it was sent; they are crossed out
                // by name, so a notebook changed in the meantime cannot lose the wrong line.
                let outdated = parsed.outdated.compactMap { $0 <= sent.count ? sent[$0 - 1].id : nil }
                g.learn(noticed: parsed.noticed, crossingOut: outdated)
            }
            self.glimm = g
        }
    }

    /// Its notebook has been looked at: what is in it now is no longer new.
    func glimmNotebookSeen(now: Date = Date()) {
        guard storesReady, !glimm.unseenNotes.isEmpty else { return }
        var g = glimm
        g.notebookSeen = now
        glimm = g
    }

    /// Something it suggested remembering was turned down: it is not suggested again.
    func glimmDeclineProposal(_ text: String) {
        glimmStage.proposal = nil
        guard storesReady else { return }
        var g = glimm
        g.decline(text)
        glimm = g
    }

    // MARK: Its notebook

    func glimmLearns(_ on: Bool) {
        guard storesReady else { return }
        var g = glimm
        g.learns = on
        glimm = g
    }

    func glimmClearNotebook() {
        guard storesReady else { return }
        var g = glimm
        g.clearNotebook()
        glimm = g
    }

    // MARK: Small jobs

    /// Does the small job Glimm offered, now that it has been tapped. Nothing is done before the tap.
    func glimmPerform(_ action: GlimmAction) {
        glimmStage.offer = nil
        switch action {
        case .logWater(let ml):
            logWater(Double(ml))
            glimmStage.line = GlimmLine(id: "did-water", text: "Logged \(ml) ml of water.")
            LumaHaptics.success()
        case .open(let place):
            LumaHaptics.select()
            switch place {
            case .breathing: router.push(.breathing)
            case .sleep: router.push(.sleep)
            case .run, .session: router.sheet = .go
            case .coach: router.tab = .coach
            case .plan: router.tab = .train
            }
        }
    }
}

// MARK: - Its ears

/// Turns what is said to Glimm into words, on the phone. Speech is never sent anywhere to be
/// recognised: where the phone cannot do it by itself for the language in use, this says so and the
/// keyboard is used instead.
@MainActor
final class GlimmEars: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var heard = ""
    @Published private(set) var problem: String?

    /// Made when first listened with, so opening Glimm's screen does not touch the phone's audio.
    private lazy var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    private var running = false

    func toggle() {
        if listening { stop() } else { Task { await start() } }
    }

    private func start() async {
        problem = nil
        guard !listening else { return }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = "Speech cannot be turned into words on this phone right now. Use the keyboard's microphone instead."
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            problem = "This phone cannot turn speech into words by itself for your language, and Luma does not send speech anywhere to be read. Use the keyboard's microphone instead."
            return
        }
        guard await GlimmEars.leave() == .authorized else {
            problem = "Allow Speech Recognition for Luma in the phone's Settings to talk to it aloud."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = "Allow the microphone for Luma in the phone's Settings to talk to it aloud."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // A format with no sample rate means no microphone is to be had; a tap on it would stop the app.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                problem = "The microphone is in use by something else."
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            if tapped { input.removeTap(onBus: 0) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: GlimmEars.feed(request))
            tapped = true
            engine.prepare()
            try engine.start()
            running = true
            self.request = request
            heard = ""
            listening = true
            task = recognizer.recognitionTask(with: request, resultHandler: GlimmEars.report { [weak self] text, done in
                Task { @MainActor [weak self] in
                    guard let self, self.listening else { return }
                    if let text { self.heard = text }
                    if done { self.stop() }
                }
            })
        } catch {
            problem = "The microphone could not be started."
            stop()
        }
    }

    func stop() {
        if running {
            engine.stop()
            running = false
        }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        if listening {
            listening = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // The two blocks below are called on the audio and recognition queues, not on the main one, so
    // they are made outside the main actor and touch nothing of this object.

    private nonisolated static func leave() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
    }

    private nonisolated static func feed(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func report(_ tell: @escaping @Sendable (String?, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in tell(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil) }
    }
}

// MARK: - On its screen

/// The small job Glimm has offered, as a button. Nothing happens until it is tapped.
struct GlimmOfferCard: View {
    let action: GlimmAction
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        LumaCard(tint: Luma.volt.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("\(env.extras.name) can do this for you")
                HStack(spacing: 10) {
                    Button(action.label) { env.glimmPerform(action) }.buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    Button("Not now") { env.glimmStage.offer = nil }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }
}

/// What Glimm has worked out by itself, a little each day: every line can be read and taken out, the
/// whole notebook can be emptied, and the learning can be switched off.
struct GlimmNotebook: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let notes = env.glimm.notebook
        // What was new when the screen opened stays marked until it is left.
        let fresh = Set(env.glimm.unseenNotes.map { $0.id })
        LumaSection(title: "What it has worked out")
        LumaGroup {
            Toggle(isOn: Binding(get: { env.glimm.learns }, set: { env.glimmLearns($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let \(env.extras.name) learn by itself").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                    Text("Each day it reads your last two weeks and may write down one or two things it has noticed, cross out a note that no longer holds, and use what it knows in what it says.")
                        .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Luma.volt)
            .padding(.vertical, 10).padding(.horizontal, 16)
            if env.glimm.daysLearned > 0 {
                Text(learnt(notes.count))
                    .font(LumaFont.body(13, .medium)).foregroundStyle(Luma.volt).fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6).padding(.horizontal, 16)
            }
            ForEach(notes.reversed()) { note in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(note.at.formatted(date: .abbreviated, time: .omitted)).font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                            if fresh.contains(note.id) { LumaPill(text: "New", color: Luma.volt) }
                        }
                    }
                    Spacer(minLength: 6)
                    Button { env.glimmForget(note.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Luma.smoke)
                            .frame(width: 34, height: 34).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Take this out")
                }
                .padding(.vertical, 6).padding(.horizontal, 16)
            }
            if notes.isEmpty {
                Text(env.glimm.learns ? "Nothing yet. Its first notes come with the first day's lines." : "Nothing here, and nothing is being added.")
                    .font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    .padding(.vertical, 12).padding(.horizontal, 16)
            }
        }
        if !notes.isEmpty {
            Button("Empty the notebook") { env.glimmClearNotebook() }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
        }
        LumaNote("These are its own notes, written with the day's lines on your Anthropic key and kept on this phone. To learn, that one request a day carries your last two weeks, a line a day: sleep, recovery and sessions. Notes are written, and sent back with a chat, only while sharing health data with the coach is on. Take one out and it is not written again. At most \(GlimmState.noticedLimit) are kept; the oldest give way.")
    }

    /// How much it has had to learn from, in plain counts: the days it has read, the notes it holds,
    /// and the ones it has crossed out itself.
    private func learnt(_ held: Int) -> String {
        let g = env.glimm
        var line = "Learning from \(g.daysLearned) day\(g.daysLearned == 1 ? "" : "s") so far: \(held) note\(held == 1 ? "" : "s") kept"
        if g.crossedOut > 0 { line += ", \(g.crossedOut) crossed out as your days changed" }
        return line + "."
    }
}
