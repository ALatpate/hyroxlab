import SwiftUI
import LumaCore
import LumaKit

// MARK: - Glimm in the app
//
// Its state still comes from the facts (`buddyLook`). This file is the rest of it: what it wears for
// that state, what it says, what it learns from a like or a pick, what it was asked to remember, and
// the chat that runs on the athlete's own key. Everything that is kept goes through `glimm`; the
// stage holds only the moment.

/// A gesture asked for, from a moment: a twirl into new clothes, a wave.
struct GlimmCue: Equatable {
    var name: String
    var at: Date
    /// The clothes worn until halfway through, when the gesture is a change of them.
    var from: String?
}

/// What Glimm is saying and doing just now. None of it is kept between launches.
@MainActor
final class GlimmStage: ObservableObject {
    /// What it is saying.
    @Published var line: GlimmLine?
    /// A mood shown for a while in place of the day's own: the one a reply came with.
    @Published var mood: String?
    @Published var moodUntil = Date.distantPast
    @Published var cue: GlimmCue?
    /// Something it suggests remembering, waiting for a yes or a no.
    @Published var proposal: String?
    /// A reply is being fetched.
    @Published var thinking = false

    /// The mood to draw at a moment: the borrowed one while it lasts, else the day's.
    func mood(or own: String, at date: Date) -> String {
        if let mood, date < moodUntil { return mood }
        return own
    }

    /// Borrows a mood for a while, then hands the day's own back.
    func show(_ mood: GlimmMood, for seconds: Double = 9) {
        self.mood = mood.rawValue
        let until = Date().addingTimeInterval(seconds)
        moodUntil = until
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, LNum.int(seconds * 1_000_000_000))))
            // A later borrowing has its own end.
            if let self, self.moodUntil == until { self.mood = nil }
        }
    }
}

extension LumaEnv {
    private func glimmClock(_ date: Date) -> (day: String, month: Int, hour: Int, weekday: Int) {
        let c = LDate.calendar.dateComponents([.month, .hour, .weekday], from: date)
        return (LDate.key(date), c.month ?? 1, c.hour ?? 12, c.weekday ?? 2)
    }

    /// The setting Glimm is dressed for in a state, at a moment.
    func glimmContext(for mood: BuddyMood, at date: Date) -> GlimmContext {
        let c = glimmClock(date)
        return GlimmStylist.context(for: mood, day: c.day, hour: c.hour, weekday: c.weekday, month: c.month)
    }

    /// What Glimm wears in a state, at a moment. The one place its clothes are chosen: the app, the
    /// widgets and the Lock Screen card all draw what this gives.
    func glimmOutfit(for mood: BuddyMood, at date: Date) -> GlimmOutfit {
        let c = glimmClock(date)
        return glimm.outfit(for: glimmContext(for: mood, at: date), day: c.day, month: c.month)
    }

    /// The companion as the Lock Screen card carries it: its state and its clothes right now, as
    /// "state~clothes". The same two readings its own screen draws.
    public func glimmTag(now: Date = Date()) -> String {
        let look = buddyLook(now: now)
        return look.mood.rawValue + "~" + glimmOutfit(for: look.mood, at: now).code
    }

    /// A new day: yesterday's picks no longer hold. Called after each reload; does nothing on the same day.
    func glimmTurnDay(now: Date = Date()) {
        guard storesReady else { return }
        let c = glimmClock(now)
        guard glimm.day != c.day else { return }
        var g = glimm
        g.turn(to: c.day, month: c.month)
        glimm = g
    }

    // MARK: Its words

    /// Says a line of its own for a moment, unless it has been asked to keep quiet. A line it is
    /// asked for directly (`always`) is said either way.
    func glimmSay(_ moment: GlimmMoment, always: Bool = false) {
        guard always || !glimm.quiet else { return }
        let line = GlimmVoice.line(moment, avoiding: glimm.said, seed: UInt64(max(0, LNum.int(Date().timeIntervalSince1970.rounded()))))
        glimmStage.line = line
        guard storesReady else { return }
        var g = glimm
        g.noteSaid(line.id)
        glimm = g
    }

    /// The line it greets with when its screen opens: the state of the day in its own words.
    func glimmGreet(_ look: BuddyLook, now: Date = Date()) {
        guard glimmStage.line == nil else { return }
        glimmSay(.state(look.mood))
    }

    /// A line for the Today card: its own words for the state, the same all hour, never recorded.
    func glimmAside(_ look: BuddyLook, now: Date = Date()) -> String {
        guard !glimm.quiet else { return look.line }
        let hour = (now.timeIntervalSince1970 / 3600).rounded(.down)
        return GlimmVoice.line(.state(look.mood), seed: UInt64(max(0, LNum.int(hour)))).text
    }

    // MARK: Its clothes

    /// Changes what it wears for the state it is in, and plays the change.
    private func glimmChange(_ mood: BuddyMood, saying moment: GlimmMoment?, _ change: (inout GlimmState, GlimmContext, String, Int) -> Void) {
        guard storesReady else { return }
        let now = Date()
        let c = glimmClock(now)
        let context = glimmContext(for: mood, at: now)
        let before = glimmOutfit(for: mood, at: now).code
        var g = glimm
        change(&g, context, c.day, c.month)
        glimm = g
        let after = glimmOutfit(for: mood, at: now).code
        if after != before { glimmStage.cue = GlimmCue(name: "twirl", at: now, from: before) }
        if let moment { glimmSay(moment) }
        LumaHaptics.select()
    }

    func glimmAnother(_ mood: BuddyMood, prefer: String? = nil, in setting: GlimmContext? = nil) {
        glimmChange(mood, saying: .outfitNew) { g, context, day, month in
            let target = setting ?? context
            let next = g.another(for: target, day: day, month: month, prefer: prefer)
            // Asked to dress for something other than the moment: it is worn now all the same.
            if target != context { g.chosen[context.rawValue] = next }
        }
    }

    func glimmWear(_ item: GlimmItem, _ mood: BuddyMood) {
        glimmChange(mood, saying: .outfitWore) { g, context, day, month in g.wear(item, for: context, day: day, month: month) }
    }

    func glimmTakeOff(_ slot: GlimmSlot, _ mood: BuddyMood) {
        glimmChange(mood, saying: nil) { g, context, day, month in g.takeOff(slot, for: context, day: day, month: month) }
    }

    /// A like or a dislike of what it has on. A dislike also changes it.
    func glimmRate(_ mood: BuddyMood, like: Bool) {
        guard storesReady else { return }
        let now = Date()
        let worn = glimmOutfit(for: mood, at: now)
        var g = glimm
        g.taste.rate(worn, like: like)
        glimm = g
        if like {
            glimmStage.cue = GlimmCue(name: "cheer", at: now)
            glimmSay(.outfitLiked)
            LumaHaptics.select()
        } else {
            glimmChange(mood, saying: .outfitDisliked) { g, context, day, month in g.another(for: context, day: day, month: month) }
        }
    }

    /// Keeps on what it is wearing, whatever the day, or lets it choose again.
    func glimmKeep(_ on: Bool, _ mood: BuddyMood) {
        guard storesReady else { return }
        var g = glimm
        g.lock = on ? glimmOutfit(for: mood, at: Date()) : nil
        glimm = g
        glimmSay(on ? .outfitKept : .outfitFreed)
        LumaHaptics.select()
    }

    // MARK: What it remembers

    func glimmRemember(_ text: String, source: String) {
        guard storesReady else { return }
        var g = glimm
        guard g.remember(text, source: source) else { return }
        glimm = g
        glimmSay(.remembered, always: true)
    }

    func glimmForget(_ id: String) {
        guard storesReady else { return }
        var g = glimm
        g.forget(id)
        glimm = g
        glimmSay(.forgot, always: true)
    }

    func glimmQuiet(_ on: Bool) {
        guard storesReady else { return }
        var g = glimm
        g.quiet = on
        glimm = g
        if on { glimmStage.line = nil }
        glimmSay(on ? .quietOn : .quietOff, always: true)
    }

    func glimmForgetTaste() {
        guard storesReady else { return }
        var g = glimm
        g.taste = GlimmTaste()
        glimm = g
    }

    func glimmClearChat() {
        guard storesReady else { return }
        var g = glimm
        g.chat = []
        glimm = g
    }

    // MARK: Talking with it

    /// Whether a chat can be had: a key is connected.
    var glimmCanTalk: Bool { coach.hasKey }

    /// Sends one message to Glimm and plays its answer: its words, its mood, a change of clothes if it
    /// was asked for one, and a suggestion of something to remember, which waits for a yes.
    func glimmSend(_ text: String, look: BuddyLook) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !glimmStage.thinking, storesReady else { return }
        guard glimmCanTalk, !isDemo else {
            glimmSay(.noKey, always: true)
            return
        }
        let now = Date()
        let history = glimm.chat
        var g = glimm
        g.addTurn(mine: true, text: message, now: now)
        glimm = g
        let mood = look.mood.glimm
        let said = now.formatted(.dateTime.weekday(.wide)) + " " + ["morning", "afternoon", "evening"][GlimmVoice.part(ofDay: glimmClock(now).hour)]
        let facts = GlimmChat.facts(name: profile.name, look: look, shareHealth: profile.shareHealthWithCoach, outfit: glimmOutfit(for: look.mood, at: now),
                                    memories: glimm.memories, clock: said, taste: glimm.taste)
        let request = GlimmChat.request(message: message, mood: mood, context: "companion screen", facts: facts)
        let messages = GlimmChat.messages(history: history, request: request, mood: mood)
        glimmStage.thinking = true
        glimmStage.show(.curious, for: 30)
        Task { [weak self] in
            guard let self else { return }
            defer { self.glimmStage.thinking = false }
            let raw = try? await self.coach.glimmReply(messages)
            guard let raw, let reply = GlimmChat.parse(raw, fallback: mood) else {
                self.glimmStage.moodUntil = .distantPast
                self.glimmSay(.chatFailed, always: true)
                return
            }
            var g = self.glimm
            g.addTurn(mine: false, text: reply.text)
            self.glimm = g
            self.glimmStage.line = GlimmLine(id: "chat", text: reply.text)
            self.glimmStage.show(reply.mood)
            if let setting = reply.outfit {
                self.glimmAnother(look.mood, prefer: reply.colour, in: setting)
                // The reply's own words stay up; the change of clothes says enough.
                self.glimmStage.line = GlimmLine(id: "chat", text: reply.text)
            }
            if let keep = reply.remember, !self.glimm.memories.contains(where: { $0.text.lowercased() == keep.lowercased() }) {
                self.glimmStage.proposal = keep
            }
        }
    }
}
