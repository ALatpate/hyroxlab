import SwiftUI
import LumaCore
import LumaKit

// MARK: - Small settings

/// Settings and marks that belong to the companion, the reminders and the ease-off offer, kept in one
/// small file. Every field is optional on the way in, so a file from an earlier build still loads.
struct LumaExtras: Codable, Equatable {
    var buddyName = "Glim"
    var buddyOnToday = true
    /// The reminders that are switched on (`ReminderKind` raw values). None until the athlete picks some.
    var reminders: [String] = []
    /// Hard sessions for which the offer to ease off has been answered, either way.
    var easeSettled: [UUID] = []
    /// The latest new best, for the companion to celebrate for a while.
    var bestLift: String?
    var bestKg: Double?
    var bestAt: Date?

    init() {}

    enum CodingKeys: String, CodingKey { case buddyName, buddyOnToday, reminders, easeSettled, bestLift, bestKg, bestAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buddyName = try c.decodeIfPresent(String.self, forKey: .buddyName) ?? "Glim"
        buddyOnToday = try c.decodeIfPresent(Bool.self, forKey: .buddyOnToday) ?? true
        reminders = try c.decodeIfPresent([String].self, forKey: .reminders) ?? []
        easeSettled = try c.decodeIfPresent([UUID].self, forKey: .easeSettled) ?? []
        bestLift = try c.decodeIfPresent(String.self, forKey: .bestLift)
        bestKg = try c.decodeIfPresent(Double.self, forKey: .bestKg)
        bestAt = try c.decodeIfPresent(Date.self, forKey: .bestAt)
    }

    var reminderKinds: Set<ReminderKind> { Set(reminders.compactMap { ReminderKind(rawValue: $0) }) }

    var name: String {
        let trimmed = buddyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Glim" : trimmed
    }

    var best: BuddyBest? {
        guard let bestLift, let bestKg, let bestAt else { return nil }
        return BuddyBest(lift: bestLift, kg: bestKg, at: bestAt)
    }
}

// MARK: - What the newer records add up to

/// Everything the newer screens read, worked out in one place (`LumaEnv.refreshNext`) from the strap's
/// days and the athlete's logs. A screen never works one of these out for itself.
struct LumaNext {
    var dose = DoseRead.empty
    var drivers = DriverRead.empty
    var help = TrainingHelpRead.empty
    var weight = WeightRead.empty
    var energy = EnergyRead.empty
    /// The athlete's measured sweat rate, ml an hour; nil until they have tested it.
    var sweatRate: Double?
    var stalled: [StalledLift] = []
    var weeklySets: [MuscleWeeks] = []
    var ease: EaseOffer?
    var trialReads: [UUID: TrialRead] = [:]
    var build = BuddyBuild(parts: [])
}

extension LumaEnv {
    func refreshNext() {
        let today = LumaAnalysis.todayKey()
        let nights = analysis.sleep.nights
        let usual = analysis.sleep.typicalBedtime
        var n = LumaNext()
        n.dose = DoseModel.read(days: days, nights: nights, fuel: fuel, usualBedtime: usual)
        n.weight = BodyWeight.read(weights, today: today)
        n.energy = EnergyModel.read(weights: weights, fuel: fuel, days: days, today: today)
        n.sweatRate = SweatModel.rate(sweatTests)
        n.help = TrainingHelpModel.read(progress: progress, days: days, fuel: fuel, supplements: supplements, profile: profile, today: today)
        n.drivers = DriverModel.read(days: days, nights: nights, fuel: fuel, usualBedtime: usual, profile: profile, today: driverToday(today))
        n.stalled = StrengthDepth.stalled(progress, sessions: lifts, today: today)
        n.weeklySets = StrengthDepth.weeklySets(sessions: lifts, today: today)
        n.ease = EaseOff.offer(days: days, today: today, planned: planned, settled: Set(extras.easeSettled))
        for trial in trials { n.trialReads[trial.id] = TrialModel.read(trial, days: days, fuel: fuel, today: today) }
        n.build = Buddy.build(progress)
        next = n
    }

    /// Today so far, in the terms the recovery model is fitted in.
    private func driverToday(_ today: String) -> DriverToday {
        let entries = fuel.filter { $0.day == today }
        let food = entries.filter { $0.kind != .water && $0.kind != .supplement }
        let calendar = LDate.calendar
        var grams = 0.0, caffeine = 0.0, protein = 0.0, water = 0.0
        var lateMeal = false
        for e in food {
            grams += e.alcoholG
            protein += e.proteinG
            let hour = calendar.component(.hour, from: e.at)
            if hour >= EffectModel.lateCaffeineHour { caffeine += e.caffeineMg }
            if e.kind != .drink, e.kcal >= 200, hour >= EffectModel.lateMealHour { lateMeal = true }
        }
        for e in entries where e.kind == .water { water += e.waterMl ?? 0 }
        return DriverToday(strain21: day(today)?.strain.map(LScale.strain21), sleepHours: analysis.sleep.avg7Min.map { $0 / 60 },
                           foodLogged: !food.isEmpty, drinks: grams / DoseModel.gramsPerDrink, lateCaffeineMg: caffeine, lateMeal: lateMeal,
                           proteinPerKg: protein / max(30, profile.weightKg), waterL: water / 1000)
    }

    // MARK: Weight

    /// A weigh-in moves the trend, and the trend is the weight every other figure is worked from: the
    /// profile follows it, so energy, protein and strength ratios all read one number.
    func weightsChanged() {
        let read = BodyWeight.read(weights, today: LumaAnalysis.todayKey())
        if let current = read.current {
            let rounded = (current * 10).rounded() / 10
            if abs(rounded - profile.weightKg) >= 0.05 {
                // The profile's own change rebuilds everything that reads it.
                profile.weightKg = rounded
                return
            }
        }
        refreshNext()
    }

    func addWeight(_ kg: Double, at: Date = Date()) {
        guard kg >= 30, kg <= 250 else { return }
        weights.append(WeightEntry(at: at, kg: kg))
    }

    func deleteWeight(_ id: UUID) { weights.removeAll { $0.id == id } }

    func addSweatTest(_ test: SweatTest) { sweatTests.append(test) }
    func deleteSweatTest(_ id: UUID) { sweatTests.removeAll { $0.id == id } }

    // MARK: New bests

    /// After a session is saved: whether it lifted the estimated max of a lift past its old best.
    func noteBests(since before: [LiftProgress], in session: LiftSession) {
        let old = Dictionary(before.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var found: LiftProgress?
        var previous = 0.0
        var gain = 0.0
        for lift in progress.lifts {
            // A lift logged for the first or second time has no best worth beating yet.
            guard let was = old[lift.name], was.points.count >= 2, was.allTime > 0, lift.allTimeDay == session.day else { continue }
            let rise = (lift.allTime - was.allTime) / was.allTime
            if lift.allTime >= was.allTime + 0.5, rise > gain {
                found = lift
                previous = was.allTime
                gain = rise
            }
        }
        guard let found else { return }
        celebration = LumaBest(lift: found.name, kg: found.allTime, previous: previous)
        LumaHaptics.success()
        // A session filed days late is still a best, but it did not happen today: the companion keeps its state.
        if session.day >= LDate.adding(-1, to: LumaAnalysis.todayKey()) {
            var e = extras
            e.bestLift = found.name
            e.bestKg = found.allTime
            e.bestAt = Date()
            extras = e
        }
    }

    // MARK: Companion

    /// What the companion goes by. Every field is taken from where its screen takes it, so the
    /// companion cannot say something the app does not.
    func buddyFacts(now: Date = Date()) -> BuddyFacts {
        let a = analysis
        let today = a.today
        var f = BuddyFacts(day: today)
        let scored: LDay? = a.lastNight?.day == today ? a.lastNight : nil
        f.recovery = scored?.recovery
        f.call = a.call.level == .unknown ? nil : a.call.title
        f.noScore = LumaWords.gapLine(a.gap)
        f.usualBedtime = a.sleep.typicalBedtime
        f.usualWake = a.sleep.typicalWake
        f.bedtimeTonight = a.sleep.recommendedBedtime
        if let recorder, recorder.isRunning {
            // To the minute, so a paused session does not move the schedule with every second.
            let start = now.addingTimeInterval(-recorder.elapsed).timeIntervalSince1970
            f.sessionStart = Date(timeIntervalSince1970: (start / 60).rounded(.down) * 60)
        }
        let nowS = now.timeIntervalSince1970
        if let last = workouts.filter({ $0.end <= nowS && nowS - $0.end < 3 * 3600 }).max(by: { $0.end < $1.end }) {
            f.lastSessionEnd = Date(timeIntervalSince1970: last.end)
            let name: String = last.kind == .other ? last.sport : last.kind.title
            var line: String = name + " done"
            if let strain = last.strain { line += ", strain " + LScale.text(strain, on21: profile.strainOn21) }
            f.lastSession = line + "."
        }
        f.best = extras.best
        if a.watch.level >= .watch, a.lastNight?.day == today { f.unwell = a.watch.title }
        f.waterMl = fuelTotals(on: today).waterMl
        f.waterTargetMl = fuelTargets(on: today).waterMl
        // A low figure only says something when the log is being kept: three of the last seven days.
        let week = Set(LDate.range(ending: LDate.adding(-1, to: today), count: 7))
        var waterDays: Set<String> = [], foodDays: Set<String> = []
        var foodToday = 0
        for e in fuel {
            let d = e.day
            if d == today, e.kind != .water, e.kind != .supplement { foodToday += 1 }
            guard week.contains(d) else { continue }
            if e.kind == .water { waterDays.insert(d) } else if e.kind != .supplement { foodDays.insert(d) }
        }
        f.waterLogged = waterDays.count >= 3
        f.foodLogged = foodDays.count >= 3
        f.foodEntries = foodToday
        return f
    }

    /// The companion's look right now.
    func buddyLook(now: Date = Date()) -> BuddyLook { Buddy.look(buddyFacts(now: now), at: now) }

    /// The companion as the widgets get it: its name, its build and every state from now on.
    func buddyGlance(now: Date) -> LumaGlance.Buddy {
        let moments = Buddy.schedule(buddyFacts(now: now), from: now)
        return LumaGlance.Buddy(name: extras.name, levels: next.build.levels, moments: moments.map {
            LumaGlance.Buddy.Moment(at: $0.at, kind: $0.look.mood.rawValue, title: $0.look.title, line: $0.look.line, energy: $0.look.energy ?? -1)
        })
    }

    // MARK: Supplement trials

    /// The trial under way or about to start. One at a time: two at once would each blur the other.
    var openTrial: SupplementTrial? {
        let today = LumaAnalysis.todayKey()
        return trials.first { $0.stoppedDay == nil && $0.lastDay() >= today }
    }

    func startTrial(supplement: String, outcome: LMetric, blockDays: Int, rounds: Int) {
        guard openTrial == nil else { return }
        var rng = SystemRandomNumberGenerator()
        let start = LDate.adding(1, to: LumaAnalysis.todayKey())
        trials.append(SupplementTrial.plan(supplement: supplement, outcome: outcome, blockDays: blockDays, rounds: rounds, washoutDays: 2,
                                           startDay: start, using: &rng))
    }

    func stopTrial(_ id: UUID) {
        guard let i = trials.firstIndex(where: { $0.id == id }) else { return }
        trials[i].stoppedDay = LumaAnalysis.todayKey()
    }

    func deleteTrial(_ id: UUID) { trials.removeAll { $0.id == id } }

    /// Today's instruction for a supplement that is on trial ("Off block: skip it today").
    func trialNote(for supplement: String, on day: String) -> (text: String, on: Bool)? {
        for t in trials where t.supplement == supplement {
            if let p = t.position(on: day), let text = t.instruction(on: day) { return (text, p.on) }
        }
        return nil
    }

    // MARK: Food matched to the work

    func fuelMatch(on day: String) -> FuelDayRead {
        let entries = fuel.filter { $0.day == day }
        let sessions = workouts.filter { $0.day == day }
        // Classed as the day's targets are, so the card and the targets beside it name the day the same way.
        return FuelMatch.read(day: day, entries: entries, workouts: sessions, strain21: self.day(day)?.strain.map(LScale.strain21),
                              dayClass: fuelTargets(on: day).dayClass, profile: profile, closed: day < today)
    }

    // MARK: Easing off

    func acceptEase(_ offer: EaseOffer) {
        settleEase(offer)
        upsert(offer.eased)
    }

    func declineEase(_ offer: EaseOffer) { settleEase(offer) }

    private func settleEase(_ offer: EaseOffer) {
        var e = extras
        e.easeSettled = Array((e.easeSettled + [offer.session.id]).suffix(60))
        extras = e
    }

    // MARK: Reminders

    func setReminder(_ kind: ReminderKind, on: Bool) {
        var e = extras
        e.reminders.removeAll { $0 == kind.rawValue }
        if on { e.reminders.append(kind.rawValue) }
        extras = e
    }

    /// The reminders due from now to the end of tomorrow, worked out from today's own numbers. The app
    /// hands them to iOS each time something they depend on changes.
    public func plannedReminders(now: Date = Date()) -> [PlannedReminder] {
        let kinds = extras.reminderKinds
        guard !kinds.isEmpty, loaded else { return [] }
        let today = LumaAnalysis.todayKey(now: now)
        var f = ReminderFacts(now: now, today: today)
        f.usualBedtime = analysis.sleep.typicalBedtime
        f.bedtimeTonight = analysis.sleep.recommendedBedtime
        // Only a firm cut-off that went with a worse night is worth a reminder.
        if let cut = next.dose.cutoff("caffeine"), cut.firm, cut.delta < 0 { f.caffeineCutoff = cut }
        f.supplements = supplements.filter { $0.active }.map { (plan: $0, taken: supplementTaken($0, on: today) != nil) }
        var paused: Set<String> = []
        for t in trials { if let p = t.position(on: today), !p.on { paused.insert(t.supplement) } }
        f.paused = paused
        f.proteinG = fuelTotals(on: today).proteinG
        f.proteinTarget = fuelTargets(on: today).proteinG
        f.foodEntries = fuel.filter { $0.day == today && $0.kind != .water && $0.kind != .supplement }.count
        let tomorrow = LDate.adding(1, to: today)
        f.trialToday = trials.compactMap { $0.instruction(on: today) }.first
        f.trialTomorrow = trials.compactMap { $0.instruction(on: tomorrow) }.first
        f.weighsIn = !weights.isEmpty
        f.reviewDue = WeekDigest.due(today: today, reviews: reviews) != nil
        return ReminderPlanner.plan(f, on: kinds)
    }

    // MARK: Logged from outside the app

    /// Files what was logged from a widget or a shortcut while the app was not running.
    public func applyQuickLog() {
        // With the records unread there is nowhere to file anything: the queue is left as it is.
        guard storesReady else { return }
        let items = LumaQuickLog.drain()
        guard !items.isEmpty else { return }
        var added: [FuelEntry] = []
        for item in items {
            switch item.kind {
            case .water:
                if item.amount > 0, item.amount <= 3000 {
                    added.append(FuelEntry(at: item.at, kind: .water, title: "Water", waterMl: item.amount, source: .quick))
                }
            case .supplements:
                let day = LDate.key(item.at)
                for plan in supplements where plan.active {
                    // A supplement on an off block of a trial is meant to be skipped.
                    if let note = trialNote(for: plan.dose.name, on: day), !note.on { continue }
                    let name = plan.dose.name
                    let has = fuel.contains { $0.day == day && $0.kind == .supplement && $0.title == name }
                        || added.contains { $0.day == day && $0.kind == .supplement && $0.title == name }
                    if !has { added.append(FuelEntry(at: item.at, kind: .supplement, title: name, supplement: plan.dose, source: .quick)) }
                }
            case .weight:
                addWeight(item.amount, at: item.at)
            }
        }
        if !added.isEmpty { fuel.append(contentsOf: added) }
    }

    // MARK: Weekly review

    /// The week whose review is due and not yet written.
    var reviewDue: String? { loaded ? WeekDigest.due(today: today, reviews: reviews) : nil }

    private func weekSchedule(_ weekStart: String) -> [ScheduleDay] { scheduleDays((0..<7).map { LDate.adding($0, to: weekStart) }) }

    /// The week's own figures, which Luma shows with or without the coach's write-up.
    func reviewFigures(_ weekStart: String) -> [ReviewFigure] {
        WeekDigest.figures(weekStart: weekStart, days: days, schedule: weekSchedule(weekStart), fuel: fuel, profile: profile)
    }

    /// Whether a review can be written: it is made from health data, so it needs a key and consent.
    var canWriteReview: Bool { coach.hasKey && profile.shareHealthWithCoach }

    /// Has the coach write the review of a week from Luma's figures, and keeps it.
    func writeReview(for weekStart: String) async {
        guard canWriteReview, !reviewWriting else { return }
        reviewWriting = true
        reviewError = nil
        defer { reviewWriting = false }
        let figures = reviewFigures(weekStart)
        var extra: [String] = []
        if let change = next.weight.change28, let now = next.weight.current {
            extra.append(String(format: "Body weight trend %.1f kg, %+.1f kg over four weeks.", now, change))
        }
        for lift in next.stalled.prefix(2) { extra.append(lift.text) }
        for f in next.dose.findings.filter({ $0.strength == .clear }).prefix(2) { extra.append(f.sentence) }
        for t in trials { if t.isRunning(on: today), let read = next.trialReads[t.id] { extra.append("Supplement trial: " + read.sentence) } }
        let text = WeekDigest.text(weekStart: weekStart, days: days, schedule: weekSchedule(weekStart), progress: progress, fuel: fuel,
                                   profile: profile, extra: extra)
        do {
            let acc = try await coach.askOnce(system: CoachPrompt.weeklyReview(profile: profile), tool: CoachTools.reviewTool(), text: text,
                                              photos: [], maxTokens: 2048)
            guard let call = acc.toolCalls.first(where: { $0.name == "write_weekly_review" }),
                  let review = CoachTools.review(from: call.input, weekStart: weekStart, figures: figures) else {
                reviewError = "The coach sent back nothing that could be used. Try again."
                return
            }
            var all = reviews.filter { $0.weekStart != weekStart }
            all.append(review)
            reviews = all.sorted { $0.weekStart > $1.weekStart }
        } catch {
            reviewError = error.localizedDescription
        }
    }
}

// MARK: - Gallery data

/// Made-up records for the gallery, so the newer screens can be judged with something on them: three
/// months of food log that follows the demo's own evenings, weigh-ins, two sweat tests, a supplement
/// trial part-way through and last week's review. Nothing here describes a real person.
@MainActor
enum LumaDemoNext {
    static func stage(_ env: LumaEnv, source: LumaDemoSource) {
        let today = LumaAnalysis.todayKey()
        var rng = SeededRNG(seed: 0x4E58)
        func at(_ day: String, _ hour: Double) -> Date { (LDate.startOfDay(day) ?? Date()).addingTimeInterval(hour * 3600) }
        var fuel = env.fuel
        let logged = Set(fuel.map { $0.day })
        let tags = Dictionary(source.checkIns.map { ($0.day, $0.tags) }, uniquingKeysWith: { a, _ in a })

        // The evenings the demo's nights were made from: a drink, a late coffee.
        for offset in stride(from: -90, through: -1, by: 1) {
            let day = LDate.adding(offset, to: today)
            let scale = rng.range(0.9, 1.1)
            if !logged.contains(day) {
                fuel.append(FuelEntry(at: at(day, 7.6), kind: .meal, title: "Overnight oats, banana, whey", items: [
                    FuelItem(name: "Oats, banana and whey", quantity: "1 bowl", kcal: 490 * scale, proteinG: 34, carbsG: 76 * scale, fatG: 7)], source: .typed))
                fuel.append(FuelEntry(at: at(day, 8.1), kind: .drink, title: "Flat white", items: [
                    FuelItem(name: "Flat white", quantity: "1 cup", kcal: 110, proteinG: 6, carbsG: 9, fatG: 6, caffeineMg: 130)], source: .quick))
                fuel.append(FuelEntry(at: at(day, 13.1), kind: .meal, title: "Chicken, rice and greens", items: [
                    FuelItem(name: "Chicken, rice and greens", quantity: "1 plate", kcal: 655 * scale, proteinG: 51, carbsG: 67 * scale, fatG: 18)], source: .photo))
                fuel.append(FuelEntry(at: at(day, 19.6), kind: .meal, title: "Salmon, potatoes, salad", items: [
                    FuelItem(name: "Salmon, potatoes, salad", quantity: "1 plate", kcal: 670 * scale, proteinG: 40, carbsG: 52 * scale, fatG: 33)], source: .typed))
                for w in 0..<4 { fuel.append(FuelEntry(at: at(day, 8 + Double(w) * 3), kind: .water, title: "Water", waterMl: 500, source: .quick)) }
            }
            let evening = tags[day] ?? []
            if evening.contains(.alcohol) {
                let drinks = Double(LNum.int(rng.range(2, 4.99)))
                fuel.append(FuelEntry(at: at(day, 20.8), kind: .drink, title: drinks >= 3 ? "Three pints" : "Two glasses of wine", items: [
                    FuelItem(name: drinks >= 3 ? "Lager" : "Red wine", quantity: "\(LNum.int(drinks)) drinks", kcal: 160 * drinks, carbsG: 8 * drinks,
                             alcoholG: 10 * drinks)], source: .typed))
            }
            if evening.contains(.lateCaffeine) {
                fuel.append(FuelEntry(at: at(day, 16.2), kind: .drink, title: "Americano", items: [
                    FuelItem(name: "Americano", quantity: "1 cup", kcal: 5, caffeineMg: 95)], source: .quick))
            }
        }

        // A trial of the evening magnesium, part-way through, followed but for one slip.
        var trial = SupplementTrial.plan(supplement: "Magnesium glycinate", outcome: .deepMin, blockDays: 7, rounds: 3, washoutDays: 2,
                                         startDay: LDate.adding(-30, to: today), using: &rng)
        trial.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? trial.id
        let slip = LDate.adding(-11, to: today)
        fuel.removeAll { $0.kind == .supplement && $0.title == trial.supplement && $0.day >= trial.startDay && $0.day < today }
        var day = trial.startDay
        while day < today {
            if let p = trial.position(on: day), p.on != (day == slip) {
                fuel.append(FuelEntry(at: at(day, 21.5), kind: .supplement, title: trial.supplement,
                                      supplement: SupplementDose(name: trial.supplement, amount: 400, unit: "mg"), source: .quick))
            }
            day = LDate.adding(1, to: day)
        }
        env.fuel = fuel
        env.trials = [trial]

        // Weigh-ins three mornings a week, drifting down a little.
        var weights: [WeightEntry] = []
        for offset in stride(from: -84, through: 0, by: 1) {
            let key = LDate.adding(offset, to: today)
            guard [1, 3, 5].contains(LDate.weekday(key)) else { continue }
            let kg = 78.9 + Double(offset + 84) / 84 * -1.4 + rng.gauss() * 0.35
            weights.append(WeightEntry(at: at(key, 7.2), kg: (kg * 10).rounded() / 10))
        }
        env.weights = weights
        env.sweatTests = [SweatTest(day: LDate.adding(-33, to: today), beforeKg: 78.4, afterKg: 77.8, drankMl: 400, minutes: 55),
                          SweatTest(day: LDate.adding(-12, to: today), beforeKg: 77.9, afterKg: 77.1, drankMl: 500, minutes: 60)]

        // Last week's review, worded from the week's own figures so the two cannot disagree.
        let week = LDate.adding(-7, to: LDate.weekStart(today))
        // The strap data has not been loaded into the environment yet, so the figures are read from the source.
        let schedule = Schedule.days((0..<7).map { LDate.adding($0, to: week) }, planned: env.planned, workouts: source.workouts, logs: env.lifts)
        let figures = WeekDigest.figures(weekStart: week, days: source.days, schedule: schedule, fuel: fuel, profile: env.profile)
        func figure(_ label: String) -> String? { figures.first { $0.label == label }?.value }
        var well: [String] = [], watch: [String] = []
        if let s = figure("Sessions") { well.append("Sessions: \(s).") }
        if let p = figure("Protein") { well.append("Protein held at \(p).") }
        if let r = figure("Recovery") { watch.append("Recovery sat at \(r), pulled down by the weekend.") }
        if let s = figure("Sleep") { watch.append("Sleep averaged \(s); the short nights were the late ones.") }
        env.reviews = [WeeklyReview(weekStart: week, createdAt: at(LDate.adding(6, to: week), 18.5),
                                    headline: "A steady week of training, with the weekend costing the most recovery.",
                                    wentWell: well, watch: watch,
                                    next: ["Keep both strength classes and add 2.5 kg to the squat top set.",
                                           "Lights out by 22:45 on the two nights before the HYROX class.",
                                           "Stop caffeine by 14:00 on class days."],
                                    figures: figures)]
    }
}
