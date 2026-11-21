import SwiftUI
import LumaCore
import LumaKit

extension BuddyMood {
    var kind: BuddyKind { BuddyKind(rawValue: rawValue) ?? .steady }

    /// The rule behind a state, in a sentence.
    var why: String {
        switch self {
        case .waiting: return "There is no recovery score for today yet, so there is nothing to go by."
        case .training: return "A session is being recorded."
        case .sleeping: return "It is inside your usual night, taken from your last two weeks of bed and wake times."
        case .celebrating: return "A lift's estimated max passed its old best in the last three hours."
        case .worked: return "A session ended in the last 75 minutes."
        case .unwell: return "Your overnight signals have moved away from your normal together. The same read raises the warning on Today."
        case .sleepy: return "It is within 45 minutes of the lights-out that covers tonight's sleep need."
        case .thirsty: return "Water is more than a quarter of the day's target behind where the hour says it should be."
        case .hungry: return "It is past 13:00 and no food has been logged today."
        case .drained: return "Today's recovery is under 34%."
        case .steady: return "Today's recovery is between 34% and 66%."
        case .charged: return "Today's recovery is 67% or more."
        }
    }
}

// MARK: - The moving figure

/// Glimm in the app: breathing, blinking, shifting its weight and doing small things of its own
/// accord, as its mood has it. A touch is answered where it lands: a boop of the leaf, a pat, a
/// tickle, a high five. With Reduce Motion on it stands still in the same pose.
struct LiveGlimm: View {
    let mood: String
    let outfit: String
    var energy: Double = 0.6
    var cue: GlimmCue? = nil
    var label: String = ""
    var onTouch: ((String) -> Void)? = nil

    private struct Touch: Equatable {
        var zone: String
        var at: Date
    }

    @State private var touch: Touch?
    @State private var visible = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if LumaMotion.reduced {
                    GlimmFigure(mood: mood, outfit: outfit, energy: energy)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                        let play = playing(at: context.date)
                        GlimmFigure(mood: mood, outfit: worn(play), time: t, energy: energy, tap: touching(at: context.date), play: play)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // A tap only: a press-and-hold here would take the scroll away from the page under it.
            .gesture(SpatialTapGesture().onEnded { value in
                touched(GlimmLook.zone(at: value.location, in: geo.size) ?? "head")
            })
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    private func touched(_ zone: String) {
        touch = Touch(zone: zone, at: Date())
        LumaHaptics.tap()
        onTouch?(zone)
    }

    /// The answer to a touch, while it lasts.
    private func touching(at date: Date) -> GlimmAct? {
        guard let touch else { return nil }
        let through = date.timeIntervalSince(touch.at) / GlimmLook.duration(tap: touch.zone)
        return through >= 0 && through <= 1 ? GlimmAct(name: touch.zone, phase: through) : nil
    }

    /// A gesture asked for, while it lasts.
    private func playing(at date: Date) -> GlimmAct? {
        guard let cue else { return nil }
        let through = date.timeIntervalSince(cue.at) / GlimmLook.duration(gesture: cue.name)
        return through >= 0 && through <= 1 ? GlimmAct(name: cue.name, phase: through) : nil
    }

    /// A change of clothes happens halfway through its twirl, when it is edge on.
    private func worn(_ play: GlimmAct?) -> String {
        if let play, let cue, let from = cue.from, play.name == cue.name, play.phase < 0.5 { return from }
        return outfit
    }
}

/// What Glimm is saying.
struct GlimmBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LumaFont.body(15, .medium)).foregroundStyle(Luma.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Luma.frost))
            .background(alignment: .bottom) {
                Rectangle().fill(Luma.frost).frame(width: 13, height: 13).rotationEffect(.degrees(45)).offset(y: 5)
            }
            .padding(.horizontal, 22)
            .accessibilityLabel(text)
    }
}

// MARK: - On Today

/// Glimm on Today: the figure, its name, the state and a line of its own. The recovery figure and the
/// day's call are already on this screen, so the line is Glimm's words, not the figure again.
struct BuddyStrip: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    /// What it said to a touch, shown for a few seconds in place of its line.
    @State private var said: String?

    var body: some View {
        if env.extras.buddyOnToday {
            // Looked at again each minute: its state can change with the clock alone.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                strip(env.buddyLook(now: context.date), now: context.date)
            }
        }
    }

    private func strip(_ look: BuddyLook, now: Date) -> some View {
        let outfit = env.glimmOutfit(for: look.mood, at: now)
        return Button { router.push(.buddy, from: "buddy") } label: {
            HStack(spacing: 14) {
                LiveGlimm(mood: look.mood.glimm.rawValue, outfit: outfit.code, energy: look.energy ?? 0.6,
                          label: "\(env.extras.name). \(look.title). \(look.line)") { zone in answer(zone) }
                    .frame(width: 78, height: 94)
                VStack(alignment: .leading, spacing: 3) {
                    LumaLabel(env.extras.name)
                    Text(look.title).font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                    Text(said ?? env.glimmAside(look, now: now))
                        .font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
        .lumaZoomSource("buddy")
    }

    private func answer(_ zone: String) {
        guard !env.glimm.quiet else { return }
        let line = GlimmVoice.line(.tap(zone), seed: UInt64(max(0, LNum.int(Date().timeIntervalSince1970)))).text
        said = line
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if said == line { said = nil }
        }
    }
}

// MARK: - Its own screen

struct BuddyScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View { BuddyStage(stage: env.glimmStage) }
}

private struct BuddyStage: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @ObservedObject var stage: GlimmStage
    @StateObject private var ears = GlimmEars()
    @State private var name = ""
    @State private var draft = ""
    @State private var note = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(env.buddyLook(now: context.date), now: context.date)
        }
        .onAppear {
            name = env.extras.buddyName
            env.glimmGreet(env.buddyLook())
        }
        .onChange(of: env.loaded) { _, _ in env.glimmGreet(env.buddyLook()) }
        .onChange(of: env.buddyLook().mood) { _, _ in env.glimmGreet(env.buddyLook()) }
        .onDisappear {
            rename()
            ears.stop()
            // The next time its screen opens it says how the day stands again.
            stage.greeted = nil
        }
        // What is heard is put in the box as it is heard, to be looked at and sent.
        .onChange(of: ears.heard) { _, text in if ears.listening || !text.isEmpty { draft = text } }
    }

    private func screen(_ look: BuddyLook, now: Date) -> some View {
        let outfit = env.glimmOutfit(for: look.mood, at: now)
        let mood = stage.mood(or: look.mood.glimm.rawValue, at: now)
        return LumaDetailScreen(title: env.extras.name, tone: .recovery) {
            VStack(spacing: 4) {
                ZStack(alignment: .bottom) {
                    Color.clear.frame(height: 66)
                    if stage.thinking {
                        GlimmBubble(text: "…")
                    } else if let line = stage.line {
                        GlimmBubble(text: line.text)
                            .id(line.id + line.text)
                            .transition(.scale(scale: 0.86, anchor: .bottom).combined(with: .opacity))
                    }
                }
                .animation(LumaMotion.reduced ? nil : .spring(response: 0.35, dampingFraction: 0.72), value: stage.line?.text)
                LiveGlimm(mood: mood, outfit: outfit.code, energy: look.energy ?? 0.6, cue: stage.cue,
                          label: "\(env.extras.name). \(look.title). \(look.line)") { zone in env.glimmSay(.tap(zone)) }
                    .frame(height: 290)
                    .frame(maxWidth: .infinity)
                Text(look.title).font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                Text(look.line).font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            talk(look)
            if let offer = stage.offer { GlimmOfferCard(action: offer) }
            if let proposal = stage.proposal { proposalCard(proposal) }
            wearing(look, outfit, now: now)

            LumaCard {
                VStack(alignment: .leading, spacing: 8) {
                    LumaLabel("Why it looks like this")
                    Text(look.mood.why).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    LumaNote("Its state only ever shows what Luma already knows. What is happening now comes first, then how your body is, then what the logs are missing. Its words are its own; the figures are yours.")
                }
            }

            BuddyDayCard(now: now)
            memories
            GlimmNotebook()
            taste

            LumaSection(title: "On your Lock Screen")
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        lockPreview(.circular).frame(width: 76, height: 76)
                        lockPreview(.rectangular).frame(height: 76).frame(maxWidth: .infinity)
                    }
                    LumaNote("It is on the heart-rate card whenever that shows. For a widget of its own, touch and hold the Lock Screen, tap Customise, then the widget row, and pick Luma, then Companion. It shifts a little every few minutes; with the phone unlocked, tap it for a wave.")
                }
            }

            LumaSection(title: "Settings")
            LumaGroup {
                HStack(spacing: 12) {
                    Text("Name").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                    Spacer()
                    TextField("Glimm", text: $name)
                        .font(LumaFont.body(15)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .frame(maxWidth: 170)
                        .onSubmit { rename() }
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { env.extras.buddyOnToday }, set: { on in
                    var e = env.extras
                    e.buddyOnToday = on
                    env.extras = e
                })) {
                    Text("Show on Today").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                }
                .tint(Luma.volt)
                .padding(.vertical, 8).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { env.glimm.quiet }, set: { env.glimmQuiet($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quiet company").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("It keeps its remarks to itself. It still moves, and still answers when you talk to it.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Luma.volt)
                .padding(.vertical, 8).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { env.extras.glimmFresh }, set: { on in
                    var e = env.extras
                    e.glimmFresh = on
                    env.extras = e
                    if on { env.glimmWriteDay() }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fresh lines each day").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("Once a day its lines are written from how your day stands, on your Anthropic key: one small request. Off, it speaks from its own fixed lines.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Luma.volt)
                .padding(.vertical, 8).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { env.extras.glimmAloud }, set: { on in
                    var e = env.extras
                    e.glimmAloud = on
                    env.extras = e
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Say replies aloud").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("Its answers in a chat are spoken as well as shown.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Luma.volt)
                .padding(.vertical, 8).padding(.horizontal, 16)
            }

            LumaSection(title: "Every state")
            BuddyMoodGrid(outfit: { env.glimmOutfit(for: $0, at: now).code })
        }
        // The day moved on while its screen was open and it changed for it: it turns into the new clothes.
        .onChange(of: outfit.code) { before, _ in env.glimmNoticeChange(from: before) }
    }

    // MARK: Talking

    @ViewBuilder
    private func talk(_ look: BuddyLook) -> some View {
        if env.glimmCanTalk {
            let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(spacing: 10) {
                TextField("Say something to \(env.extras.name)", text: $draft)
                    .font(LumaFont.body(15)).foregroundStyle(Luma.frost)
                    .submitLabel(.send)
                    .onSubmit { send(look) }
                if !env.isDemo {
                    Button {
                        LumaHaptics.select()
                        ears.toggle()
                    } label: {
                        Image(systemName: ears.listening ? "waveform" : "mic.fill").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ears.listening ? Luma.ink : Luma.frost)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(ears.listening ? Luma.coral : Color.white.opacity(0.1)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(ears.listening ? "Stop listening" : "Say it aloud")
                }
                Button { send(look) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(empty || stage.thinking ? Luma.smoke : Luma.volt))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(empty || stage.thinking)
                .accessibilityLabel("Send")
            }
            .padding(.vertical, 8).padding(.leading, 16).padding(.trailing, 8)
            .background(LumaPanel(radius: 24))
            if ears.listening {
                Text("Listening. Tap the microphone again when you have finished, then send.").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
            } else if let problem = ears.problem {
                Text(problem).font(LumaFont.body(12.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true)
            }
            if !env.glimm.chat.isEmpty { lately }
            LumaNote(env.profile.shareHealthWithCoach
                     ? "Its replies come from your own Anthropic key, on the model the coach is set to. It is told why it looks the way it does, how today stands (the night, the plan, the last session), what it chose to wear, what you asked it to remember and what it has worked out. Speech is turned into words on this phone."
                     : "Its replies come from your own Anthropic key, on the model the coach is set to. It is told what it chose to wear and what you asked it to remember, and none of your numbers: sharing health data with the coach is off. Speech is turned into words on this phone.")
        } else {
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    LumaLabel("Talk with \(env.extras.name)")
                    Text("For now it speaks from its own lines. Connect your Anthropic key and you can talk with it: it answers in its own voice, may change its clothes if it likes an idea of yours, and can offer to remember what you tell it.")
                        .font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    Button("Connect a key") { router.sheet = .coachSetup }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    /// The last few lines of the chat.
    private var lately: some View {
        LumaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LumaLabel("Lately")
                    Spacer()
                    Button("Clear") { env.glimmClearChat() }.font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist).buttonStyle(.plain)
                }
                ForEach(Array(env.glimm.chat.suffix(6).enumerated()), id: \.offset) { _, turn in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(turn.mine ? "You" : env.extras.name).font(LumaFont.label(10)).foregroundStyle(turn.mine ? Luma.mist : Luma.volt)
                            .frame(width: 52, alignment: .leading)
                        Text(turn.text).font(LumaFont.body(13.5)).foregroundStyle(turn.mine ? Luma.mist : Luma.frost)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func send(_ look: BuddyLook) {
        ears.stop()
        let text = draft
        draft = ""
        LumaKeyboard.dismiss()
        env.glimmSend(text, look: look)
    }

    private func proposalCard(_ proposal: String) -> some View {
        LumaCard(tint: Luma.volt.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("\(env.extras.name) would like to remember")
                Text(proposal).font(LumaFont.body(15)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Remember it") {
                        env.glimmRemember(proposal, source: "chat")
                        stage.proposal = nil
                    }
                    .buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    Button("Not this") { stage.proposal = nil }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    // MARK: Clothes

    /// What it has on and why, in its own words. Nothing here changes its clothes: it picks them.
    private func wearing(_ look: BuddyLook, _ outfit: GlimmOutfit, now: Date) -> some View {
        let why = GlimmVoice.worn(env.glimmWhy(for: look.mood, at: now), outfit: outfit, day: LDate.key(now))
        return Group {
            LumaSection(title: "What it picked")
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(outfit.name).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    if !env.glimm.quiet {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "quote.opening").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.volt)
                            Text(why).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LumaNote("\(env.extras.name) dresses itself. It picks for what the day is and how the day feels, from a wardrobe and a taste that are its own, and changes when it decides to.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: What it keeps

    @ViewBuilder
    private var memories: some View {
        LumaSection(title: "What it remembers")
        LumaGroup {
            ForEach(env.glimm.memories.filter { $0.source != GlimmState.noticed }.reversed()) { memory in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(memory.text).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button { env.glimmForget(memory.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Luma.smoke)
                            .frame(width: 34, height: 34).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Forget")
                }
                .padding(.vertical, 6).padding(.horizontal, 16)
            }
            HStack(spacing: 10) {
                TextField("Something for it to remember", text: $note)
                    .font(LumaFont.body(15)).foregroundStyle(Luma.frost)
                    .submitLabel(.done)
                    .onSubmit { keepNote() }
                Button("Add") { keepNote() }
                    .font(LumaFont.body(14, .semibold)).foregroundStyle(note.trimmingCharacters(in: .whitespaces).isEmpty ? Luma.smoke : Luma.volt)
                    .buttonStyle(.plain)
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.vertical, 12).padding(.horizontal, 16)
        }
        LumaNote("Only what you write here, or agree to when it asks in a chat. Nothing is kept without a yes, and anything can be taken out. It stays on this phone, and goes to the model only as part of a chat you start.")
    }

    private func keepNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        env.glimmRemember(text, source: "told")
        note = ""
        LumaKeyboard.dismiss()
    }

    /// What it likes to wear: the colour it is into for now, what it has always liked, what it has
    /// grown fond of, and its lucky top. None of it is set by anyone.
    @ViewBuilder
    private var taste: some View {
        let fond = env.glimm.taste.fondOf
        let lucky = env.glimm.lucky.flatMap { GlimmItem(id: $0)?.name }.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        LumaSection(title: "Its taste")
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                tasteLine("Into right now", [env.glimmPhase()])
                tasteLine("Always liked", GlimmNature.favourites.colours + GlimmNature.favourites.cuts)
                if !fond.isEmpty { tasteLine("Grown fond of", fond) }
                if let lucky { tasteLine("Lucky top", [lucky]) }
                LumaNote("Its taste is its own. It came with favourites, it goes through phases with a colour, it grows fond of what it had on when you said something kind, and the top it trained in on the day of a new best becomes its lucky one.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tasteLine(_ title: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LumaLabel(title)
            Text(names.prefix(6).joined(separator: ", ")).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rename() {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard trimmed != env.extras.buddyName else { return }
        var e = env.extras
        e.buddyName = trimmed
        env.extras = e
    }

    private func lockPreview(_ family: LumaWidgetFamily) -> some View {
        let frame = BuddyTimeline.frame(env.buddyGlance(now: Date()), at: Date(), beat: 0)
        return LumaBuddyWidgetView(frame: frame, name: env.extras.name, family: family)
            .foregroundStyle(.white)
            .padding(family == .circular ? 0 : 10)
            .background {
                if family == .circular { Circle().fill(Color.white.opacity(0.12)) }
                else { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)) }
            }
    }
}

/// The states still to come today, each from the time it begins.
private struct BuddyDayCard: View {
    @EnvironmentObject private var env: LumaEnv
    let now: Date

    var body: some View {
        let moments = Array(Buddy.schedule(env.buddyFacts(now: now), from: now).dropFirst().prefix(6))
        if !moments.isEmpty {
            LumaSection(title: "The day ahead")
            LumaGroup {
                ForEach(Array(moments.enumerated()), id: \.offset) { _, m in
                    HStack(spacing: 12) {
                        GlimmFigure(mood: m.look.mood.glimm.rawValue, outfit: env.glimmOutfit(for: m.look.mood, at: m.at).code, flat: true)
                            .frame(width: 40, height: 48)
                        Text(m.at.formatted(date: .omitted, time: .shortened)).font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                            .frame(width: 70, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.look.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                            Text(m.look.line).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 16)
                }
            }
            LumaNote("Worked out from today's numbers as they stand, with what it will be wearing by then. It changes when they do: a session, a weigh-in, a glass of water.")
        }
    }
}

/// Every state the companion has, side by side, each in the clothes it wears for it.
struct BuddyMoodGrid: View {
    var outfit: (BuddyMood) -> String = { _ in GlimmLook.signature }
    var ink: GlimmInk = .color

    private static let names: [(BuddyMood, String)] = [
        (.charged, "Charged"), (.steady, "Steady"), (.drained, "Drained"), (.sleeping, "Asleep"), (.sleepy, "Winding down"),
        (.training, "In session"), (.worked, "Session done"), (.celebrating, "New best"), (.unwell, "Run down"), (.thirsty, "Thirsty"),
        (.hungry, "Hungry"), (.waiting, "No score yet"),
    ]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BuddyMoodGrid.names, id: \.1) { mood, title in
                VStack(spacing: 4) {
                    GlimmFigure(kind: mood.kind, outfit: outfit(mood), ink: ink, flat: true).frame(height: 104)
                    Text(title).font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(LumaPanel(radius: 18))
            }
        }
    }
}
