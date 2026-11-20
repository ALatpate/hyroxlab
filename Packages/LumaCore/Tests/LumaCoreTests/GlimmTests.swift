import XCTest
@testable import LumaCore

/// Glimm: the wardrobe, how it dresses itself, a taste of its own, what it keeps and what it says.
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
            XCTAssertEqual(night.top.style, "pyjamas")
            XCTAssertEqual(night.bottom.style, "sleep-pants")
            XCTAssertEqual(GlimmWardrobe.style(night.feet.style)!.shape, "slipper")
            XCTAssertNil(night.head)
            XCTAssertNil(night.accessory)

            // Night clothes, party clothes and a chef's coat are for their own occasions: on any other
            // day they would say something about the day that is not so.
            for context in [GlimmContext.everyday, .focus, .relax, .training, .rain, .cold, .sun, .adventure] {
                let worn = GlimmStylist.outfit(context: context, day: day, month: 7)
                XCTAssertFalse(worn.items.contains { GlimmStylist.occasions.contains(GlimmWardrobe.style($0.style)!.context) }, "\(context.rawValue) on \(day)")
            }
            // And on the occasion they are what it wears.
            XCTAssertEqual(GlimmStylist.outfit(context: .celebration, day: day, month: 7).top.style, "varsity")
            XCTAssertEqual(GlimmStylist.outfit(context: .cooking, day: day, month: 7).top.style, "chef-coat")
        }
        // A new best nearly always gets the hat as well.
        let hats = days(80).filter { GlimmStylist.outfit(context: .celebration, day: $0, month: 7).head?.style == "partyhat" }
        XCTAssertGreaterThan(hats.count, 60)
        // For a setting that is not an occasion, what was made for it is worn most days and not all.
        let work = days(200).map { GlimmStylist.outfit(context: .focus, day: $0, month: 4).top.style }
        let cardigans = work.filter { $0 == "cardigan" }.count
        XCTAssertGreaterThan(cardigans, 90)
        XCTAssertLessThan(cardigans, 170)
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
        // A piece shown on the figure leaves off a hat it cannot be worn with.
        var o = GlimmOutfit.signature.wearing(GlimmItem(style: "beanie", palette: "plum"))
        XCTAssertEqual(o.head?.style, "beanie")
        o = o.wearing(GlimmItem(style: "raincoat", palette: "butter"))
        XCTAssertNil(o.head, "no hat under a hood that is up")
        o = GlimmOutfit.signature.wearing(GlimmItem(style: "sunhat", palette: "cream")).wearing(GlimmItem(style: "headphones", palette: "navy"))
        XCTAssertNil(o.head, "the hat gives way to the headphones")
        // A piece the wardrobe does not hold changes nothing.
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

    // MARK: A taste of its own

    func testItHasFavouritesFromTheFirstDay() {
        XCTAssertGreaterThan(GlimmNature.score(GlimmItem(style: "zip-hoodie", palette: "coral")), GlimmNature.score(GlimmItem(style: "everyday-tee", palette: "charcoal")) + 2)
        XCTAssertTrue(GlimmNature.isFavourite(GlimmItem(style: "trainers", palette: "navy")))
        XCTAssertFalse(GlimmNature.isFavourite(GlimmItem(style: "wellies", palette: "coral")))
        XCTAssertEqual(GlimmNature.favourites.colours.first, "Coral")
        XCTAssertEqual(GlimmNature.favourites.cuts.first, "Zip hoodie")
        // Every piece it is said to like is one the wardrobe holds.
        for key in GlimmNature.leanings.keys {
            let name = String(key.split(separator: ":").last ?? "")
            XCTAssertTrue(key.hasPrefix("palette:") ? GlimmWardrobe.palette(name) != nil : GlimmWardrobe.style(name) != nil, key)
        }
        // With nothing learnt and nobody asked, its big hoodie is what it most often takes it easy in.
        let tops = days(240).map { GlimmStylist.outfit(context: .relax, day: $0, month: 4).top.style }
        XCTAssertGreaterThan(tops.filter { $0 == "zip-hoodie" }.count, tops.filter { $0 == "lounge-top" }.count)
    }

    func testAPhaseLastsAFewDaysAndShowsInWhatItWears() {
        XCTAssertEqual(GlimmStylist.dayNumber("1970-01-01"), 0)
        XCTAssertEqual(GlimmStylist.dayNumber("1969-12-31"), -1)
        XCTAssertEqual(GlimmStylist.dayNumber("2000-03-01"), 11017)
        XCTAssertEqual(GlimmStylist.dayNumber("2024-02-29"), 19782)
        XCTAssertEqual(GlimmStylist.dayNumber("2026-11-20"), 20777)
        XCTAssertNil(GlimmStylist.dayNumber("someday"))
        XCTAssertNil(GlimmStylist.dayNumber("2026-13-01"))
        // What a phase adds to a colour is the same for every piece in it.
        let tee = GlimmItem(style: "everyday-tee", palette: "sage")
        let cut = GlimmWardrobe.style("everyday-tee")!
        XCTAssertEqual(GlimmStylist.score(tee, style: cut, context: .everyday, taste: GlimmTaste(), recentTops: [], month: 4, phase: "sage")
                       - GlimmStylist.score(tee, style: cut, context: .everyday, taste: GlimmTaste(), recentTops: [], month: 4, phase: "rose"),
                       GlimmStylist.phasePull, accuracy: 0.0001)
        // The run that holds 2026-11-20 began on 2026-11-15 (day 20772, which is 9 × 2308).
        XCTAssertEqual(GlimmStylist.phase(day: "2026-11-15"), GlimmStylist.phase(day: "2026-11-23"))
        let all = days(270)
        var runs: [Int: Set<String>] = [:]
        for day in all { runs[(GlimmStylist.dayNumber(day) ?? 0) / GlimmStylist.phaseDays, default: []].insert(GlimmStylist.phase(day: day).id) }
        XCTAssertTrue(runs.values.allSatisfy { $0.count == 1 }, "one colour for the whole of a run")
        XCTAssertGreaterThanOrEqual(Set(all.map { GlimmStylist.phase(day: $0).id }).count, 8, "and many colours over the months")
        // The colour it is into is on its top far more often than one colour in sixteen would be.
        let into = all.filter { GlimmStylist.outfit(context: .everyday, day: $0, month: 4).top.palette == GlimmStylist.phase(day: $0).id }
        XCTAssertGreaterThan(Double(into.count) / Double(all.count), 0.085)
    }

    func testTheDaysFeelShowsInItsClothes() {
        // The bands are the recovery ring's own: charged is bright, drained is soft.
        XCTAssertEqual(GlimmFeel(recovery: 80), .bright)
        XCTAssertEqual(GlimmFeel(recovery: 67), .bright)
        XCTAssertEqual(GlimmFeel(recovery: 66.9), .even)
        XCTAssertEqual(GlimmFeel(recovery: 34), .even)
        XCTAssertEqual(GlimmFeel(recovery: 33.9), .soft)
        XCTAssertEqual(GlimmFeel(recovery: nil), .even)
        func tops(_ feel: GlimmFeel) -> [GlimmItem] { days(300).map { GlimmStylist.outfit(context: .everyday, day: $0, month: 4, feel: feel).top } }
        func share(_ items: [GlimmItem], _ test: (GlimmItem) -> Bool) -> Double { Double(items.filter(test).count) / Double(items.count) }
        let bright = tops(.bright), soft = tops(.soft)
        XCTAssertGreaterThan(share(bright) { GlimmFeel.loud.contains($0.palette) }, share(soft) { GlimmFeel.loud.contains($0.palette) } + 0.1)
        XCTAssertGreaterThan(share(soft) { GlimmFeel.gentle.contains($0.palette) }, share(bright) { GlimmFeel.gentle.contains($0.palette) } + 0.1)
        XCTAssertGreaterThan(share(bright) { $0.pattern != "plain" }, share(soft) { $0.pattern != "plain" } + 0.15)
        // An even day is dressed as it always was: the feeling adds nothing to it.
        XCTAssertEqual(GlimmStylist.outfit(context: .everyday, day: "2026-11-20", month: 11, feel: .even), GlimmStylist.outfit(context: .everyday, day: "2026-11-20", month: 11))
    }

    func testTheTopItTrainedInOnTheDayOfANewBestIsItsLuckyOne() {
        var state = GlimmState()
        state.turn(to: "2026-11-20", month: 11)
        XCTAssertNil(state.lucky)
        let kit = state.outfit(for: .training, day: "2026-11-20", month: 11)
        state.noteBest(day: "2026-11-20", month: 11)
        XCTAssertEqual(state.lucky, kit.top.id)
        XCTAssertEqual(state.why(kit, for: .training, day: "2026-11-20"), .lucky)
        // The day's kit is the same with a lucky top as without: only the top can differ, and today it is the lucky one.
        XCTAssertEqual(state.outfit(for: .training, day: "2026-11-20", month: 11).bottom, kit.bottom)
        // From then on it trains in it on some days, not all.
        let after = LDate.range(ending: "2027-03-10", count: 100)
        let worn = after.filter { GlimmStylist.outfit(context: .training, day: $0, month: 1, lucky: state.lucky).top.id == state.lucky }.count
        XCTAssertGreaterThan(worn, 25)
        XCTAssertLessThan(worn, 60)
        // It is for training in: a training top does not turn up at bedtime.
        if GlimmWardrobe.style(kit.top.style)?.context == .training {
            XCTAssertFalse(after.contains { GlimmStylist.outfit(context: .sleep, day: $0, month: 1, lucky: state.lucky).top.id == state.lucky })
        }
        // A second best on the same day changes nothing; one on a later day can.
        let first = state
        state.noteBest(day: "2026-11-20", month: 11)
        XCTAssertEqual(state, first)
        state.noteBest(day: "2026-11-22", month: 11)
        XCTAssertEqual(state.luckyDay, "2026-11-22")
    }

    func testItSaysWhyItPickedWhatItHasOn() {
        var state = GlimmState()
        state.turn(to: "2026-11-20", month: 11)
        let into = GlimmStylist.phase(day: "2026-11-20").id
        let other = GlimmWardrobe.palettes.map { $0.id }.first { $0 != into } ?? "navy"
        // Nothing it has always liked, not the colour it is into, on an ordinary day: it just felt like it.
        let plain = GlimmOutfit(top: GlimmItem(style: "everyday-tee", palette: other), bottom: GlimmItem(style: "jeans", palette: other),
                                feet: GlimmItem(style: "court-shoes", palette: other))
        XCTAssertEqual(state.why(plain, for: .everyday, day: "2026-11-20"), .fancy)
        // The colour it is into, and nothing else to say: that is the reason.
        let phased = GlimmOutfit(top: GlimmItem(style: "everyday-tee", palette: into), bottom: plain.bottom, feet: plain.feet)
        XCTAssertEqual(state.why(phased, for: .everyday, day: "2026-11-20"), .phase(into))
        // An old favourite.
        let fav = GlimmOutfit(top: GlimmItem(style: "zip-hoodie", palette: other), bottom: plain.bottom, feet: plain.feet)
        XCTAssertEqual(state.why(fav, for: .everyday, day: "2026-11-20"), .favourite("zip-hoodie"))
        // A setting with nothing else to say is the reason, and the same reason all day; but only when
        // something it has on was made for the setting.
        XCTAssertEqual(state.why(plain, for: .training, day: "2026-11-20"), .setting(.training), "the court shoes are training shoes")
        XCTAssertEqual(state.why(plain, for: .rain, day: "2026-11-20"), .fancy, "nothing here is for rain, so rain is not the reason")
        XCTAssertEqual(state.why(fav, for: .relax, day: "2026-11-20"), state.why(fav, for: .relax, day: "2026-11-20"))
        XCTAssertTrue([GlimmWhy.setting(.relax), .favourite("zip-hoodie")].contains(state.why(fav, for: .relax, day: "2026-11-20")))
        // A change of mind is always the reason for what it changed into.
        let changed = state.another(for: .everyday, day: "2026-11-20", month: 11)
        XCTAssertEqual(state.why(changed, for: .everyday, day: "2026-11-20"), .changed)
        // Every reason has words, with the colour or the piece in them.
        for seed in 0..<6 {
            let phase = GlimmVoice.line(.outfit(.phase("butter")), seed: UInt64(seed)).text
            XCTAssertTrue(phase.contains("butter"), phase)
            XCTAssertFalse(phase.contains("{"), phase)
            let piece = GlimmVoice.line(.outfit(.favourite("zip-hoodie")), seed: UInt64(seed)).text
            XCTAssertTrue(piece.contains("zip hoodie"), piece)
            XCTAssertFalse(piece.contains("{"), piece)
        }
        XCTAssertEqual(GlimmVoice.worn(.fancy, outfit: plain, day: "2026-11-20"), GlimmVoice.worn(.fancy, outfit: plain, day: "2026-11-20"))
        XCTAssertEqual(GlimmWhy.phase("butter").told, "it is in a butter phase")
        XCTAssertTrue(GlimmWhy.setting(.rain).told.contains("without knowing the weather"))
    }

    func testWhatIsAdmiredIsLearntOnceAndCanBeTakenBack() {
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
        XCTAssertEqual(keen.fondOf.first, "Lilac")
        // Something kind said about what it has on is how it grows fond of it.
        var state = GlimmState()
        state.enjoyed(look)
        XCTAssertEqual(state.taste.rating(of: look), 1)
        XCTAssertTrue(state.taste.fondOf.contains("Coral"))
        XCTAssertTrue(state.taste.fondOf.contains("Zip hoodie"))
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

        // Tomorrow is dressed, today, as it will be once the day has turned: the widgets are told ahead.
        state.feel = .bright
        let ahead = state.outfit(for: .everyday, day: "2026-11-21", month: 11)
        state.turn(to: "2026-11-21", month: 11)
        XCTAssertTrue(state.chosen.isEmpty)
        XCTAssertEqual(state.feel, .even, "how a new day feels is not known until its score is in")
        XCTAssertEqual(state.recentTops.count, 1, "yesterday's top is remembered so it is not worn again at once")
        XCTAssertEqual(state.outfit(for: .everyday, day: "2026-11-21", month: 11), ahead)
        XCTAssertNotEqual(ahead, second)

        // What it says or is told changes no clothes; a change of mind, a feeling or a lucky top can.
        var chatty = state
        chatty.noteSaid("state.steady#0")
        chatty.remember("Likes the lilac trainers.", source: "told")
        XCTAssertTrue(chatty.dressesAs(state))
        var changed = state
        changed.another(for: .everyday, day: "2026-11-21", month: 11)
        XCTAssertFalse(changed.dressesAs(state))
        var feeling = state
        feeling.feel = .soft
        XCTAssertFalse(feeling.dressesAs(state))
        var lucky = state
        lucky.noteBest(day: "2026-11-21", month: 11)
        XCTAssertFalse(lucky.dressesAs(state))
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
        // A file from the build that let an outfit be kept on by hand still reads, and the outfit is not held to.
        let old = #"{"day":"2026-11-20","lock":{"top":{"style":"zip-hoodie","palette":"coral","pattern":"plain"},"bottom":{"style":"joggers","palette":"teal","pattern":"plain"},"feet":{"style":"trainers","palette":"lilac","pattern":"plain"}}}"#
        let read = try JSONDecoder().decode(GlimmState.self, from: Data(old.utf8))
        XCTAssertEqual(read.day, "2026-11-20")
        XCTAssertEqual(read.outfit(for: .sleep, day: "2026-11-20", month: 11), GlimmStylist.outfit(context: .sleep, day: "2026-11-20", month: 11))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(read), as: UTF8.self).contains("lock"))
    }

    // MARK: Its voice

    func testEveryMomentHasWordsAndNoneStatesAFigure() {
        var moments: [GlimmMoment] = BuddyMood.allCases.map { .state($0) }
        moments += [.greeting(0), .greeting(1), .greeting(2), .back, .outfitNew, .complimented, .remembered, .forgot, .quietOn, .quietOff, .noKey, .chatFailed]
        moments += [.outfit(.changed), .outfit(.lucky), .outfit(.phase("butter")), .outfit(.favourite("zip-hoodie")), .outfit(.fancy)]
        moments += GlimmContext.allCases.map { .outfit(.setting($0)) }
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
        // Kind words about its clothes are noted only when it says so plainly.
        XCTAssertEqual(GlimmChat.parse(#"{"text":"Oh, thank you.","mood":"joyful","complimented":true}"#, fallback: .steady)?.complimented, true)
        XCTAssertEqual(GlimmChat.parse(#"{"text":"Oh, thank you.","mood":"joyful","complimented":"yes"}"#, fallback: .steady)?.complimented, false)
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
        let shared = GlimmChat.facts(name: "Alex", look: look, shareHealth: true, outfit: .signature, why: .setting(.relax), into: "Butter",
                                     memories: state.memories, clock: "Thursday evening", taste: GlimmTaste())
        XCTAssertEqual(shared.count, GlimmChat.factLimit)
        XCTAssertTrue(shared.contains { $0.contains("Recovery 24%") })
        XCTAssertTrue(shared.contains { $0.contains("fact 19") }, "the newest memories go first")
        var fond = GlimmTaste()
        fond.rate(.signature, like: true)
        let held = GlimmChat.facts(name: "Alex", look: look, shareHealth: false, outfit: .signature, why: .setting(.relax), into: "Butter", memories: [],
                                   clock: "Thursday evening", taste: fond)
        XCTAssertFalse(held.contains { $0.contains("24") || $0.contains("Drained") }, "no reading leaves the phone without leave")
        // What it has on is told as its own pick, with its reason; so is what it likes.
        XCTAssertTrue(held.contains { $0.contains("coral zip hoodie") })
        XCTAssertTrue(held.contains { $0.contains("picked these clothes itself") && $0.contains("it dressed for taking it easy") })
        XCTAssertTrue(held.contains { $0.contains("into butter") && $0.contains("always liked coral") && $0.contains("grown fond of") })
        XCTAssertTrue(held.allSatisfy { $0.count < GlimmChat.factLength }, "nothing is cut short")

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
        XCTAssertTrue(GlimmChat.system.contains("You choose your own clothes"))
        for mood in GlimmMood.allCases { XCTAssertTrue(GlimmChat.system.contains(mood.rawValue)) }
    }
}
