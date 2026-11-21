import SwiftUI
import LumaCore
import LumaKit

// MARK: - Glimm in the app
//
// Its state still comes from the facts (`buddyLook`). This file is the rest of it: what it chooses
// to wear for that state, what it says, what it was asked to remember, and the chat that runs on the
// athlete's own key. Nothing here lets anyone dress it: its clothes are its own pick, and the only
// changes are the ones it makes. Everything that is kept goes through `glimm`; the stage holds only
// the moment.

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
    /// A small job it offers to do because it was asked for one, waiting for a tap.
    @Published var offer: GlimmAction?
    /// Says its replies aloud, when that is switched on.
    let voice = SessionVoice()
    /// A reply is being fetched.
    @Published var thinking = false
    /// The state it last put into words, so it says so once and not at every redraw.
    var greeted: BuddyMood?
    /// What it wears for a setting on a day, as already worked out. Emptied whenever what it keeps
    /// changes: the same answer is asked for at every redraw, by the glance and by the Lock Screen card.
    var outfits: [String: GlimmOutfit] = [:]

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
        let context = GlimmStylist.context(for: mood, day: c.day, hour: c.hour, weekday: c.weekday, month: c.month)
        let key = c.day + "|" + context.rawValue
        if let known = glimmStage.outfits[key] { return known }
        let outfit = glimm.outfit(for: context, day: c.day, month: c.month)
        if glimmStage.outfits.count > 200 { glimmStage.outfits = [:] }
        glimmStage.outfits[key] = outfit
        return outfit
    }

    /// The companion as the Lock Screen card carries it: its state and its clothes right now, as
    /// "state~clothes". The same two readings its own screen draws.
    public func glimmTag(now: Date = Date()) -> String {
        let look = buddyLook(now: now)
        return look.mood.rawValue + "~" + glimmOutfit(for: look.mood, at: now).code
    }

    /// Why it has on what it has on in a state, at a moment.
    func glimmWhy(for mood: BuddyMood, at date: Date) -> GlimmWhy {
        glimm.why(glimmOutfit(for: mood, at: date), for: glimmContext(for: mood, at: date), day: glimmClock(date).day)
    }

    /// The colour it is into for now, by name.
    func glimmPhase(at date: Date = Date()) -> String { GlimmStylist.phase(day: glimmClock(date).day).name }

    /// Keeps Glimm up with the day. Called after each reload: a new day turns its clothes over; once
    /// the day's recovery is in, it knows how the day feels; and a new best makes the top it trains in
    /// its lucky one. Each does nothing when there is nothing new.
    func glimmKeepUp(now: Date = Date()) {
        guard storesReady else { return }
        let c = glimmClock(now)
        var g = glimm
        g.turn(to: c.day, month: c.month)
        let facts = buddyFacts(now: now)
        // The same score, by the same bands, that makes the day charged, steady or drained.
        if let score = facts.recovery { g.feel = GlimmFeel(recovery: score) }
        if Buddy.look(facts, at: now).mood == .celebrating { g.noteBest(day: c.day, month: c.month) }
        if g != glimm { glimm = g }
    }

    /// The demo's Glimm has a little behind it, so every line of its taste has something to show:
    /// kind words about an outfit, and a new best today.
    func stageDemoGlimm(now: Date = Date()) {
        guard isDemo, glimm.lucky == nil else { return }
        let c = glimmClock(now)
        var g = glimm
        g.turn(to: c.day, month: c.month)
        g.enjoyed(GlimmStylist.outfit(context: .rain, day: "2026-11-01", month: 11))
        g.noteBest(day: c.day, month: c.month)
        // A notebook with a little in it, and lines for today, as a week of its learning would leave them.
        g.notice("Trains hardest on Tuesdays and Thursdays.", now: now.addingTimeInterval(-5 * 86_400))
        g.notice("Sleeps about forty minutes longer at weekends.", now: now.addingTimeInterval(-3 * 86_400))
        g.notice("Likes the morning class better than the evening one.", now: now.addingTimeInterval(-86_400))
        g.lines = GlimmDayLines(day: c.day,
                                morning: GlimmSaying(text: "Morning. You slept like someone with plans. Shall we go and do them?", mood: .focused),
                                afterTraining: GlimmSaying(text: "That is the work done. Eat something proper, then let the legs be.", mood: .proud),
                                evening: GlimmSaying(text: "Day's done. An early night would suit us both.", mood: .sleepy))
        g.linesAsked = c.day
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

    /// The state of the day in its own words: said when its screen opens and when the state changes.
    /// Not before the day's numbers are in: "no score yet" would be said of a day that has one.
    func glimmGreet(_ look: BuddyLook) {
        guard loaded, glimmStage.greeted != look.mood else { return }
        glimmStage.greeted = look.mood
        // A line written for today, when one fits the state it is in; its own fixed lines otherwise.
        if let saying = glimmDayLine(for: look) {
            glimmStage.line = GlimmLine(id: "day-" + look.mood.rawValue, text: saying.text)
            glimmStage.show(saying.mood)
            return
        }
        glimmSay(.state(look.mood))
    }

    /// A line for the Today card: its own words for the state, the same all hour, never recorded.
    func glimmAside(_ look: BuddyLook, now: Date = Date()) -> String {
        guard !glimm.quiet else { return look.line }
        if let saying = glimmDayLine(for: look, now: now) { return saying.text }
        let hour = (now.timeIntervalSince1970 / 3600).rounded(.down)
        return GlimmVoice.line(.state(look.mood), seed: UInt64(max(0, LNum.int(hour)))).text
    }

    // MARK: Its clothes

    /// Glimm changes its mind: other clothes for the state it is in, dressed for `setting` when it
    /// names one, in a colour it fancies when it names one. Only a reply of its own calls this; there
    /// is no button for it.
    private func glimmChangeMind(_ mood: BuddyMood, to setting: GlimmContext?, fancying colour: String?) {
        guard storesReady else { return }
        let now = Date()
        let c = glimmClock(now)
        let context = glimmContext(for: mood, at: now)
        let before = glimmOutfit(for: mood, at: now).code
        var g = glimm
        let target = setting ?? context
        let next = g.another(for: target, day: c.day, month: c.month, prefer: colour)
        // Dressed for something other than the moment: it is worn now all the same.
        if target != context { g.chosen[context.rawValue] = next }
        glimm = g
        let after = glimmOutfit(for: mood, at: now).code
        if after != before { glimmStage.cue = GlimmCue(name: "twirl", at: now, from: before) }
        LumaHaptics.select()
    }

    /// Its clothes changed while its screen was open, because the day moved on: it turns into the
    /// new ones and says so. A change it has just made itself has already been played.
    func glimmNoticeChange(from before: String) {
        let now = Date()
        if let cue = glimmStage.cue, cue.name == "twirl", now.timeIntervalSince(cue.at) < 2 { return }
        glimmStage.cue = GlimmCue(name: "twirl", at: now, from: before)
        if !glimmStage.thinking { glimmSay(.outfitNew) }
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
    /// decides on one, a compliment taken to heart, and a suggestion of something to remember, which
    /// waits for a yes.
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
        let worn = glimmOutfit(for: look.mood, at: now)
        let share = profile.shareHealthWithCoach
        // What it worked out by itself came from the day's readings, so it goes only with leave to share those.
        let kept = share ? glimm.memories : glimm.memories.filter { $0.source != GlimmState.noticed }
        let brief = GlimmBrief.facts(analysis: analysis, planned: planned, workouts: workouts, today: today, shareHealth: share)
        let facts = GlimmChat.facts(name: profile.name, look: look, shareHealth: share, outfit: worn,
                                    why: glimmWhy(for: look.mood, at: now), into: glimmPhase(at: now), memories: kept, clock: said,
                                    taste: glimm.taste, brief: brief)
        let request = GlimmChat.request(message: message, mood: mood, context: "companion screen", facts: facts)
        let messages = GlimmChat.messages(history: history, request: request, mood: mood)
        glimmStage.thinking = true
        glimmStage.offer = nil
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
            // Something kind about what it had on when the message was sent: it grows fonder of it.
            if reply.complimented { g.enjoyed(worn) }
            self.glimm = g
            self.glimmStage.line = GlimmLine(id: "chat", text: reply.text)
            self.glimmStage.show(reply.mood)
            self.glimmStage.offer = reply.action
            if self.extras.glimmAloud { self.glimmStage.voice.say(reply.text) }
            if let setting = reply.outfit {
                // Its own decision: the reply's words stay up, and the change of clothes says the rest.
                self.glimmChangeMind(look.mood, to: setting, fancying: reply.colour)
            } else if reply.complimented {
                self.glimmStage.cue = GlimmCue(name: "shy", at: Date())
            }
            if let keep = reply.remember, !self.glimm.memories.contains(where: { $0.text.lowercased() == keep.lowercased() }) {
                self.glimmStage.proposal = keep
            }
        }
    }
}
