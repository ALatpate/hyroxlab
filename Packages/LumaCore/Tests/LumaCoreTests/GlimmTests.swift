import XCTest
@testable import LumaCore

/// Glimm: the wardrobe, getting dressed, the taste it learns, what it keeps and what it says.
final class GlimmTests: XCTestCase {
    private func days(_ n: Int) -> [String] { LDate.range(ending: "2026-11-21", count: n) }

    // MARK: The wardrobe

    func testTheWardrobeHoldsWhatItSaysItHolds() {
        XCTAssertEqual(GlimmWardrobe.styles.count, 64)
        XCTAssertEqual(Set(GlimmWardrobe.styles.map { $0.id }).count, 64)
        XCTAssertEqual(GlimmWardrobe.palettes.count, 16)
        XCTAssertEqual(GlimmWardrobe.styles(in: .top).count, 24)
        for slot in [GlimmSlot.bottom, .feet, .head, .accessory] { XCTAssertEqual(GlimmWardrobe.styles(in: slot).count, 10, slot.rawValue) }
        // A top comes in every pattern; the rest are plain.
        XCTAssertEqual(GlimmWardrobe.items(in: .top).count, 2304)
        XCTAssertEqual(GlimmWardrobe.items(in: .feet).count, 160)
        XCTAssertEqual(GlimmWardrobe.count, 2944)
        XCTAssertEqual(GlimmSlot.allCases.reduce(0) { $0 + GlimmWardrobe.items(in: $1).count }, GlimmWardrobe.count)
        // Two cuts in one slot never share the name the drawing knows them by.
        for slot in GlimmSlot.allCases {
            let shapes = GlimmWardrobe.styles(in: slot).map { $0.shape }
            XCTAssertEqual(Set(shapes).count, shapes.count, slot.rawValue)
        }
    }

    func testAnItemIsNamedAndFoundByItsID() {
        let item = GlimmItem(style: "zip-hoodie", palette: "coral", pattern: "stripes")
        XCTAssertEqual(item.id, "zip-hoodie__coral__stripes")
        XCTAssertEqual(GlimmItem(id: item.id), item)
        XCTAssertEqual(item.name, "striped coral zip hoodie")
        XCTAssertEqual(item.code, "zip:FF766B:stripes")
        XCTAssertNil(GlimmItem(id: "zip-hoodie__coral"))
        XCTAssertNil(GlimmItem(id: "cape__coral__plain"))
        XCTAssertNil(GlimmItem(id: "zip-hoodie__puce__plain"))
        // Only a top is patterned.
        XCTAssertNil(GlimmItem(id: "joggers__teal__dots"))
        XCTAssertNotNil(GlimmItem(id: "joggers__teal__plain"))
    }

    func testTheSignatureLookIsTheOneTheDrawingFallsBackOn() {
        let look = GlimmOutfit.signature
        XCTAssertTrue(look.isValid)
        // The same string as `GlimmLook.signature` in LumaKit, which cannot see this type.
        XCTAssertEqual(look.code, "zip:FF766B:plain|joggers:36BFB0:plain|chunky:B5A0EF:plain|-|bag:B5A0EF:plain")
        XCTAssertEqual(look.name, "A coral zip hoodie, teal soft joggers and lilac chunky trainers, with a lilac mini crossbody.")
    }

    // MARK: Getting dressed

    func testADayKeepsItsLookAndTheNextDayBringsAnother() {
        let a = GlimmStylist.outfit(context: .everyday, day: "2026-11-20", month: 11)
        XCTAssertEqual(a, GlimmStylist.outfit(context: .everyday, day: "2026-11-20", month: 11))
        XCTAssertTrue(a.isValid)
        let week = days(14).map { GlimmStylist.outfit(context: .everyday, day: $0, month: 11) }
        XCTAssertGreaterThanOrEqual(Set(week.map { $0.key }).count, 12, "a fortnight should not repeat itself")
        XCTAssertGreaterThanOrEqual(Set(week.map { $0.top.style }).count, 4)
        // Asking for another gives another.
        XCTAssertNotEqual(a, GlimmStylist.outfit(context: .everyday, day: "2026-11-20", salt: 1, month: 11))
    }

    func testTrainingAndBedtimeAreDressedFor() {
        for day in days(80) {
            let kit = GlimmStylist.outfit(context: .training, day: day, month: 7)
            for item in kit.items {
                let style = GlimmWardrobe.style(item.style)!
                XCTAssertLessThanOrEqual(style.warmth, 2, "\(item.id) on \(day)")
            }
            XCTAssertTrue(["runners", "court", "trail", "retro"].contains(GlimmWardrobe.style(kit.feet.style)!.shape))
            if let hat = kit.head { XCTAssertTrue(["headband", "visor", "cap"].contains(GlimmWardrobe.style(hat.style)!.shape)) }
            if let extra = kit.accessory { XCTAssertTrue(["watch", "pin"].contains(GlimmWardrobe.style(extra.style)!.shape)) }

            let night = GlimmStylist.outfit(context: .sleep, day: day, month: 7)
            XCTAssertTrue(["pyjama", "lounge", "crew"].contains(GlimmWardrobe.style(night.top.style)!.shape))
            XCTAssertEqual(GlimmWardrobe.style(night.feet.style)!.shape, "slipper")
            XCTAssertNil(night.head)
            XCTAssertNil(night.accessory)

            // By day, night clothes stay at home.
            let plain = GlimmStylist.outfit(context: .everyday, day: day, month: 7)
            XCTAssertFalse(plain.items.contains { ["pyjama", "sleep", "slipper"].contains(GlimmWardrobe.style($0.style)!.shape) })
        }
    }

    func testWhatCannotBeWornTogetherIsNot() {
        for day in days(120) {
            for context in [GlimmContext.rain, .cold, .focus, .everyday] {
                let o = GlimmStylist.outfit(context: context, day: day, month: 1)
                let top = GlimmWardrobe.style(o.top.style)!.shape
                let hat = o.head.flatMap { GlimmWardrobe.style($0.style)?.shape }
                let extra = o.accessory.flatMap { GlimmWardrobe.style($0.style)?.shape }
                if top == "coat" { XCTAssertNil(hat, "a hat under a hood on \(day)") }
                if extra == "headphones", let hat { XCTAssertTrue(["headband", "visor"].contains(hat), "headphones over a \(hat)") }
            }
        }
        // By hand: the piece just put on is the one kept.
        var o = GlimmOutfit.signature.wearing(GlimmItem(style: "raincoat", palette: "butter"))
        o = o.wearing(GlimmItem(style: "beanie", palette: "plum"))
        XCTAssertEqual(o.head?.style, "beanie")
        XCTAssertEqual(o.top.style, "zip-hoodie", "the raincoat gives way to the hat")
        XCTAssertEqual(o.top.palette, "butter")
        o = o.wearing(GlimmItem(style: "headphones", palette: "navy"))
        XCTAssertNil(o.head, "the beanie gives way to the headphones")
        o = o.wearing(GlimmItem(style: "sunhat", palette: "cream"))
        XCTAssertNil(o.accessory)
        XCTAssertEqual(o.without(.head).head, nil)
        // A piece from the wrong shelf changes nothing.
        XCTAssertEqual(GlimmOutfit.signature.wearing(GlimmItem(style: "nothing", palette: "coral")), .signature)
    }

    func testTheSeasonLeansOnWarmth() {
        func warmth(_ month: Int) -> Double {
            let all = days(200).map { GlimmStylist.outfit(context: .everyday, day: $0, month: month) }
            return LStat.mean(all.map { Double(GlimmWardrobe.style($0.top.style)!.warmth) }) ?? 0
        }
        XCTAssertGreaterThan(warmth(1), warmth(7) + 0.25)
    }

    func testAStateOfTheDayIsDressedFor() {
        func context(_ mood: BuddyMood, hour: Int = 20, weekday: Int = 4) -> GlimmContext {
            GlimmStylist.context(for: mood, day: "2026-04-15", hour: hour, weekday: weekday, month: 4)
        }
        XCTAssertEqual(context(.training), .training)
        XCTAssertEqual(context(.sleeping), .sleep)
        XCTAssertEqual(context(.sleepy), .sleep)
        XCTAssertEqual(context(.celebrating), .celebration)
        XCTAssertEqual(context(.unwell), .relax)
        XCTAssertEqual(context(.hungry), .cooking)
        // Every state has a mood to be shown in.
        XCTAssertEqual(Set(BuddyMood.allCases.map { $0.glimm }).count, 12)
        // A plain day is one of the day's own settings, never night clothes.
        for mood in [BuddyMood.steady, .charged, .waiting, .thirsty] {
            for hour in [8, 11, 15, 20] {
                XCTAssertTrue([.everyday, .focus, .adventure, .rain, .cold, .sun].contains(context(mood, hour: hour)))
            }
        }
    }

    // MARK: Taste

    func testALikeIsLearntOnceAndCanBeTakenBack() {
        var taste = GlimmTaste()
        let look = GlimmOutfit.signature
        taste.rate(look, like: true)
        let once = taste
        taste.rate(look, like: true)
        XCTAssertEqual(taste, once, "saying it twice changes nothing")
        XCTAssertEqual(taste.scores["palette:coral"] ?? 0, GlimmTaste.step, accuracy: 0.0001)
        // Lilac is on two pieces and still counts once.
        XCTAssertEqual(taste.scores["palette:lilac"] ?? 0, GlimmTaste.step, accuracy: 0.0001)
        XCTAssertEqual(taste.rating(of: look), 1)
        taste.rate(look, like: false)
        XCTAssertEqual(taste.scores["palette:coral"] ?? 0, -GlimmTaste.step, accuracy: 0.0001)
        XCTAssertEqual(taste.rating(of: look), -1)
        XCTAssertEqual(taste.order.count, 1)

        // However often something is liked, its score stays inside its bounds.
        var keen = GlimmTaste()
        for day in days(60) {
            let o = GlimmOutfit(top: GlimmItem(style: "cardigan", palette: "lilac", pattern: "plain"),
                                bottom: GlimmItem(style: "chinos", palette: "navy"), feet: GlimmItem(style: "trainers", palette: "lilac"),
                                head: GlimmStylist.outfit(context: .everyday, day: day, month: 3).head)
            keen.rate(o, like: true)
        }
        XCTAssertLessThanOrEqual(keen.scores.values.max() ?? 0, GlimmTaste.bound)
        XCTAssertEqual(keen.colours(liked: true).first, "Lilac")
    }

    func testWhatIsLikedIsWornMoreOften() {
        func share(_ taste: GlimmTaste) -> Double {
            let tops = days(300).map { GlimmStylist.outfit(context: .everyday, taste: taste, day: $0, month: 4).top }
            return Double(tops.filter { $0.palette == "lilac" }.count) / Double(tops.count)
        }
        var taste = GlimmTaste()
        taste.scores["palette:lilac"] = 4
        XCTAssertGreaterThan(share(taste), share(GlimmTaste()) * 2.5)
        var against = GlimmTaste()
        against.scores["palette:lilac"] = -4
        XCTAssertLessThan(share(against), share(GlimmTaste()))
    }

    // MARK: What it keeps

    func testTheDayHoldsWhatWasPickedAndTheNextDayStartsAfresh() {
        var state = GlimmState()
        state.turn(to: "2026-11-20", month: 11)
        let first = state.outfit(for: .everyday, day: "2026-11-20", month: 11)
        XCTAssertEqual(first, state.outfit(for: .everyday, day: "2026-11-20", month: 11))
        let second = state.another(for: .everyday, day: "2026-11-20", month: 11)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(state.outfit(for: .everyday, day: "2026-11-20", month: 11), second)
        // Another setting is not touched by it.
        XCTAssertEqual(state.outfit(for: .training, day: "2026-11-20", month: 11), GlimmStylist.outfit(context: .training, day: "2026-11-20", month: 11))

        let worn = state.wear(GlimmItem(style: "beanie", palette: "plum"), for: .everyday, day: "2026-11-20", month: 11)
        XCTAssertEqual(worn.head?.style, "beanie")
        XCTAssertEqual(state.taste.scores["style:beanie"] ?? 0, GlimmTaste.nudge, accuracy: 0.0001)
        XCTAssertNil(state.takeOff(.head, for: .everyday, day: "2026-11-20", month: 11).head)

        state.turn(to: "2026-11-21", month: 11)
        XCTAssertTrue(state.chosen.isEmpty)
        XCTAssertEqual(state.recentTops.count, 1, "yesterday's top is remembered so it is not worn again at once")
        XCTAssertNotEqual(state.outfit(for: .everyday, day: "2026-11-21", month: 11), second)

        // An outfit kept on is worn whatever the day or the setting, until it is let go.
        state.lock = second
        XCTAssertEqual(state.outfit(for: .sleep, day: "2026-11-25", month: 11), second)
        state.lock = nil
        XCTAssertNotEqual(state.outfit(for: .sleep, day: "2026-11-25", month: 11), second)
    }

    func testOnlyWhatIsNewIsRememberedAndItCanBeForgotten() throws {
        var state = GlimmState()
        XCTAssertTrue(state.remember("  I train before work.  ", source: "told", now: Date(timeIntervalSince1970: 1_795_000_000)))
        XCTAssertFalse(state.remember("i train before work.", source: "chat"))
        XCTAssertFalse(state.remember("   ", source: "told"))
        XCTAssertEqual(state.memories.map { $0.text }, ["I train before work."])
        XCTAssertTrue(state.remember(String(repeating: "x", count: 500), source: "told"))
        XCTAssertEqual(state.memories.last?.text.count, GlimmState.memoryLength)
        for i in 0..<80 { state.remember("fact \(i)", source: "told", now: Date(timeIntervalSince1970: 1_795_000_100 + Double(i))) }
        XCTAssertEqual(state.memories.count, GlimmState.memoryLimit)
        XCTAssertEqual(Set(state.memories.map { $0.id }).count, state.memories.count)
        let gone = state.memories[3].id
        state.forget(gone)
        XCTAssertFalse(state.memories.contains { $0.id == gone })

        // It is kept as it stands, and a file from before a field existed still reads.
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(GlimmState.self, from: data), state)
        XCTAssertEqual(try JSONDecoder().decode(GlimmState.self, from: Data("{}".utf8)), GlimmState())
        let odd = #"{"lock":{"top":{"style":"cape","palette":"coral","pattern":"plain"},"bottom":{"style":"joggers","palette":"teal","pattern":"plain"},"feet":{"style":"trainers","palette":"lilac","pattern":"plain"}}}"#
        XCTAssertNil(try JSONDecoder().decode(GlimmState.self, from: Data(odd.utf8)).lock, "a piece the wardrobe does not hold is not kept on")
    }

    // MARK: Its voice

    func testEveryMomentHasWordsAndNoneStatesAFigure() {
        var moments: [GlimmMoment] = BuddyMood.allCases.map { .state($0) }
        moments += [.greeting(0), .greeting(1), .greeting(2), .back, .outfitNew, .outfitLiked, .outfitDisliked, .outfitKept, .outfitFreed, .outfitWore,
                    .remembered, .forgot, .quietOn, .quietOff, .noKey, .chatFailed]
        moments += ["leaf", "head", "cheek", "belly", "feet", "hand", "hug"].map { .tap($0) }
        for moment in moments {
            XCTAssertNotNil(GlimmVoice.lines[moment.key], moment.key)
            XCTAssertFalse(GlimmVoice.line(moment).text.isEmpty)
        }
        for (key, lines) in GlimmVoice.lines {
            XCTAssertFalse(lines.isEmpty, key)
            for line in lines {
                // The figure behind a state is the fact line beside it; Glimm's own words carry none.
                XCTAssertNil(line.rangeOfCharacter(from: .decimalDigits), "\(key): \(line)")
                XCTAssertLessThanOrEqual(line.count, 120, line)
            }
        }
    }

    func testALineIsNotSaidTwiceRunning() {
        var recent: [String] = []
        var texts: [String] = []
        for seed in 0..<4 {
            let line = GlimmVoice.line(.state(.steady), avoiding: recent, seed: UInt64(seed))
            recent.append(line.id)
            texts.append(line.text)
        }
        XCTAssertEqual(Set(texts).count, 4, "four different lines before any is repeated")
        XCTAssertEqual(GlimmVoice.line(.tap("leaf"), seed: 7), GlimmVoice.line(.tap("leaf"), seed: 7))
        XCTAssertEqual(GlimmVoice.part(ofDay: 7), 0)
        XCTAssertEqual(GlimmVoice.part(ofDay: 13), 1)
        XCTAssertEqual(GlimmVoice.part(ofDay: 21), 2)
    }

    // MARK: Talking with it

    func testAReplyIsCheckedBeforeItIsUsed() {
        let good = GlimmChat.parse(#"{"text":"Trainers on. Shall we?","mood":"focused","outfit":"training","colour":"teal","remember":" Prefers morning sessions. "}"#, fallback: .steady)
        XCTAssertEqual(good, GlimmReply(text: "Trainers on. Shall we?", mood: .focused, remember: "Prefers morning sessions.", outfit: .training, colour: "teal"))
        // Wrapped in a fence, or with words around it.
        XCTAssertEqual(GlimmChat.parse("```json\n{\"text\":\"Hello.\",\"mood\":\"joyful\"}\n```", fallback: .steady)?.text, "Hello.")
        // A mood it does not have, a setting that is not one, a colour with no outfit: left out, not guessed.
        let odd = GlimmChat.parse(#"{"text":"Hm.","mood":"furious","outfit":"spacesuit","colour":"teal","action":"buy"}"#, fallback: .curious)
        XCTAssertEqual(odd, GlimmReply(text: "Hm.", mood: .curious))
        XCTAssertNil(GlimmChat.parse(#"{"text":"Blue it is.","mood":"steady","outfit":"everyday","colour":"puce"}"#, fallback: .steady)?.colour)
        // Too long is cut at a word.
        let long = GlimmChat.parse("{\"text\":\"" + String(repeating: "tiny trainers ", count: 40) + "\",\"mood\":\"steady\"}", fallback: .steady)
        XCTAssertLessThanOrEqual(long?.text.count ?? 999, GlimmChat.textLimit)
        XCTAssertTrue(long?.text.hasSuffix("…") ?? false)
        // Plain words are still words; a broken wrapping, or nothing, is not said.
        XCTAssertEqual(GlimmChat.parse("Hello there.", fallback: .steady), GlimmReply(text: "Hello there.", mood: .steady))
        XCTAssertNil(GlimmChat.parse("{\"text\": \"Hel", fallback: .steady))
        XCTAssertNil(GlimmChat.parse(#"{"text":"  ","mood":"steady"}"#, fallback: .steady))
        XCTAssertNil(GlimmChat.parse("", fallback: .steady))
    }

    func testOnlyWhatMayBeSharedIsShared() {
        let look = BuddyLook(mood: .drained, title: "Drained", line: "Recovery 24%. Take it easy.", energy: 0.24)
        var state = GlimmState()
        for i in 0..<20 { state.remember("fact \(i)", source: "told", now: Date(timeIntervalSince1970: 1_795_000_000 + Double(i))) }
        let shared = GlimmChat.facts(name: "Alex", look: look, shareHealth: true, outfit: .signature, memories: state.memories, clock: "Thursday evening",
                                     taste: GlimmTaste())
        XCTAssertEqual(shared.count, GlimmChat.factLimit)
        XCTAssertTrue(shared.contains { $0.contains("Recovery 24%") })
        XCTAssertTrue(shared.contains { $0.contains("fact 19") }, "the newest memories go first")
        let held = GlimmChat.facts(name: "Alex", look: look, shareHealth: false, outfit: .signature, memories: [], clock: "Thursday evening", taste: GlimmTaste())
        XCTAssertFalse(held.contains { $0.contains("24") || $0.contains("Drained") }, "no reading leaves the phone without leave")
        XCTAssertTrue(held.contains { $0.contains("coral zip hoodie") })

        let request = GlimmChat.request(message: "hello", mood: .steady, context: "companion", facts: shared)
        let json = JSONValue.parse(request)
        XCTAssertEqual(Set(json?.object?.keys.map { $0 } ?? []), ["message", "mood", "context", "sharedFacts"])
        XCTAssertEqual(json?["sharedFacts"]?.array?.count, GlimmChat.factLimit)

        // What was said before goes as whole exchanges, the user's turn first.
        let t = Date(timeIntervalSince1970: 1_795_000_000)
        let history = [GlimmTurn(mine: false, text: "Hello.", at: t), GlimmTurn(mine: true, text: "hi", at: t), GlimmTurn(mine: false, text: "There you are.", at: t),
                       GlimmTurn(mine: true, text: "unanswered", at: t)]
        let messages = GlimmChat.messages(history: history, request: request, mood: .steady)
        XCTAssertEqual(messages.map { $0.role }, ["user", "assistant", "user"])
        XCTAssertTrue(GlimmChat.system.contains("Return ONLY a JSON object"))
        for mood in GlimmMood.allCases { XCTAssertTrue(GlimmChat.system.contains(mood.rawValue)) }
    }
}
