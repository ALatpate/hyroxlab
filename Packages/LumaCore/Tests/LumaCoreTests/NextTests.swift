import XCTest
@testable import LumaCore

/// The companion, supplement trials, dose curves, food against the work, the weight log, the recovery
/// model, deeper strength, easing off, the weekly review and reminders.
final class NextTests: XCTestCase {
    private let today = "2026-11-16"

    /// A moment on `day` at a local clock time; hours past 24 run into the next morning.
    private func at(_ hour: Double, on day: String? = nil) -> Date {
        LDate.startOfDay(day ?? today)!.addingTimeInterval(hour * 3600)
    }

    private func key(_ ago: Int) -> String { LDate.adding(-ago, to: today) }

    private func profile(_ kg: Double = 80) -> LProfile {
        var p = LProfile()
        p.weightKg = kg
        return p
    }

    private func meal(_ day: String, hour: Double, kcal: Double = 700, protein: Double = 40, carbs: Double = 80, caffeine: Double? = nil,
                      alcohol: Double? = nil, kind: FuelKind = .meal) -> FuelEntry {
        FuelEntry(at: at(hour, on: day), kind: kind, title: "Food",
                  items: [FuelItem(name: "Food", kcal: kcal, proteinG: protein, carbsG: carbs, fatG: 20, caffeineMg: caffeine, alcoholG: alcohol)])
    }

    private func night(_ day: String, bedtime: Double = -50, wake: Double = 420) -> SleepNight {
        SleepNight(day: day, main: nil, naps: [], asleepMin: 450, inBedMin: 480, efficiency: 93, deepMin: 90, remMin: 100, lightMin: 260,
                   awakeMin: 30, awakenings: 2, needMin: 470, debtMin: 0, score: 80, bedtime: bedtime, wake: wake, napMin: 0)
    }

    // MARK: Statistics

    func testTQuantileMatchesTheTables() {
        XCTAssertEqual(LStat.studentTQuantile(0.95, df: 10), 1.812, accuracy: 0.005)
        XCTAssertEqual(LStat.studentTQuantile(0.975, df: 30), 2.042, accuracy: 0.005)
        XCTAssertEqual(LStat.studentTQuantile(0.05, df: 10), -1.812, accuracy: 0.005)
    }

    func testRegressionRecoversSeveralEffectsAtOnce() {
        var rng = SeededRNG(seed: 10)
        var y: [Double] = [], rows: [[Double]] = []
        for _ in 0..<200 {
            let a = rng.range(0, 10), b = rng.range(0, 5), c = rng.range(-2, 2)
            rows.append([a, b, c])
            y.append(40 + 3 * a - 4 * b + 0 * c + rng.gauss() * 2)
        }
        let fit = LStat.regress(y: y, rows: rows)!
        XCTAssertEqual(fit.coefficients[0], 40, accuracy: 1.5)
        XCTAssertEqual(fit.coefficients[1], 3, accuracy: 0.2)
        XCTAssertEqual(fit.coefficients[2], -4, accuracy: 0.3)
        XCTAssertEqual(fit.coefficients[3], 0, accuracy: 0.4)
        XCTAssertLessThan(fit.p[1], 0.001)
        XCTAssertGreaterThan(fit.p[3], 0.01)
        XCTAssertGreaterThan(fit.leftOutR2, 0.9)
        let range = fit.interval(1)
        XCTAssertTrue(range.low < 3 && range.high > 3)
        // Two columns that say the same thing cannot be told apart.
        XCTAssertNil(LStat.regress(y: y, rows: rows.map { [$0[0], $0[0] * 2] }))
    }

    // MARK: The companion

    private func facts() -> BuddyFacts {
        var f = BuddyFacts(day: today)
        f.recovery = 72; f.call = "Green light"
        f.usualBedtime = -50; f.usualWake = 420; f.bedtimeTonight = -70
        f.waterTargetMl = 2800; f.waterMl = 2000; f.waterLogged = true
        f.foodEntries = 3; f.foodLogged = true
        return f
    }

    func testTheCompanionFollowsTheDay() {
        var f = facts()
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .charged)
        XCTAssertEqual(Buddy.look(f, at: at(10)).line, "Recovery 72%. Green light.")
        f.recovery = 50
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .steady)
        f.recovery = 20
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .drained)
        // No score: it waits, in the words given for why.
        f.recovery = nil; f.noScore = "Luma is still reading last night."
        let waiting = Buddy.look(f, at: at(10))
        XCTAssertEqual(waiting.mood, .waiting)
        XCTAssertEqual(waiting.line, "Luma is still reading last night.")
        XCTAssertNil(waiting.energy)
    }

    func testWhatIsHappeningNowComesBeforeHowTheBodyIs() {
        var f = facts()
        f.unwell = "Resting heart rate and skin temperature are up."
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .unwell)
        f.lastSessionEnd = at(9.5); f.lastSession = "Class done, strain 12.4."
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .worked)
        XCTAssertEqual(Buddy.look(f, at: at(11.5)).mood, .unwell, "the cool-down passes")
        f.best = BuddyBest(lift: "Back squat", kg: 133, at: at(9.6))
        XCTAssertEqual(Buddy.look(f, at: at(10)).line, "Back squat: est. max 133 kg.")
        f.sessionStart = at(9.9); f.sessionTitle = "Gym class"
        XCTAssertEqual(Buddy.look(f, at: at(10)).mood, .training)
        XCTAssertEqual(Buddy.look(f, at: at(15)).mood, .unwell, "a session is not believed to run for five hours")
    }

    func testTheLogsOnlySpeakWhenTheyAreKept() {
        var f = facts()
        f.waterMl = 300
        XCTAssertEqual(Buddy.look(f, at: at(15)).mood, .thirsty)
        XCTAssertEqual(Buddy.look(f, at: at(15)).line, "0.3 of 2.8 L so far.")
        XCTAssertEqual(Buddy.look(f, at: at(9)).mood, .charged, "too early in the day to be behind")
        f.waterLogged = false
        XCTAssertEqual(Buddy.look(f, at: at(15)).mood, .charged, "an unused water log says nothing")
        f.foodEntries = 0
        XCTAssertEqual(Buddy.look(f, at: at(14)).mood, .hungry)
        f.foodLogged = false
        XCTAssertEqual(Buddy.look(f, at: at(14)).mood, .charged)
    }

    func testTheCompanionSleepsThroughTheUsualNight() {
        let f = facts()
        XCTAssertEqual(Buddy.look(f, at: at(22.2)).mood, .sleepy)
        XCTAssertEqual(Buddy.look(f, at: at(23.5)).mood, .sleeping)
        XCTAssertEqual(Buddy.look(f, at: at(26)).mood, .sleeping, "02:00, the same training day")
        // Past 04:00 the facts are yesterday's, but the usual night is still the usual night.
        XCTAssertEqual(Buddy.look(f, at: at(29)).mood, .sleeping)
        XCTAssertEqual(Buddy.look(f, at: at(32)).mood, .waiting, "08:00 the next day with nothing new read")
        // Without a usual night there is none to sleep through.
        var unknown = f
        unknown.usualBedtime = nil; unknown.usualWake = nil; unknown.bedtimeTonight = nil
        XCTAssertEqual(Buddy.look(unknown, at: at(26)).mood, .charged)
    }

    func testTheScheduleHoldsEachChangeOnce() {
        var f = facts()
        f.waterMl = 2800
        f.lastSessionEnd = at(9.5); f.lastSession = "Class done."
        let moments = Buddy.schedule(f, from: at(10))
        XCTAssertEqual(moments.first?.look.mood, .worked)
        XCTAssertEqual(moments.map { $0.look.mood }, [.worked, .charged, .sleepy, .sleeping, .waiting])
        for (a, b) in zip(moments, moments.dropFirst()) { XCTAssertLessThan(a.at, b.at); XCTAssertNotEqual(a.look, b.look) }
        // A widget shows the last moment that has begun, and agrees with asking directly.
        for hour in [10.5, 12, 22.3, 23.9, 27, 31.5] {
            XCTAssertEqual(Buddy.look(in: moments, at: at(hour)), Buddy.look(f, at: at(hour)), "at \(hour)")
        }
    }

    func testAChangeBeginsOnTheMinuteItsLineNames() {
        // Bed and wake times are averages: 23:05 and 42 seconds, lights out at 21:49 and 36 seconds.
        // Their lines print them to the minute, and each change begins on that minute, not at the next
        // half-hour mark and not a minute to either side.
        var f = facts()
        f.waterMl = 2800
        f.usualBedtime = -54.3; f.usualWake = 400.6; f.bedtimeTonight = -130.4
        let moments = Buddy.schedule(f, from: at(10))
        XCTAssertEqual(moments.map { $0.look.mood }, [.charged, .sleepy, .sleeping, .waiting])
        func clock(_ m: BuddyMoment) -> String {
            let c = LDate.calendar.dateComponents([.hour, .minute], from: m.at)
            return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        XCTAssertEqual(moments[1].look.line, "Lights out by 21:50 covers tonight's sleep.")
        XCTAssertEqual(clock(moments[1]), "21:05", "45 minutes before the lights-out the line names")
        XCTAssertEqual(moments[2].look.line, "Usual night: 23:06 to 6:41.")
        XCTAssertEqual(clock(moments[2]), "23:06")
        XCTAssertEqual(clock(moments[3]), "6:41")
        // Asking the rule directly gives the same answer either side of each minute.
        XCTAssertEqual(Buddy.look(f, at: at(23.0 + 5.9 / 60)).mood, .sleepy)
        XCTAssertEqual(Buddy.look(f, at: at(23.0 + 6.1 / 60)).mood, .sleeping)
        XCTAssertEqual(Buddy.look(f, at: at(24 + 6 + 40.9 / 60)).mood, .sleeping)
        XCTAssertEqual(Buddy.look(f, at: at(24 + 6 + 41.1 / 60)).mood, .waiting)
    }

    func testTheBuildIsTheAthletesOwnLevels() {
        func session(_ ago: Int, _ name: String, _ kg: Double) -> LiftSession {
            LiftSession(start: LDate.date(key(ago))!, title: "Strength",
                        exercises: [LiftExercise(name: name, sets: (0..<3).map { _ in LiftSet(reps: 5, kg: kg, done: true) })])
        }
        let none = Buddy.build(TrainingProgress.build(lifts: [], workouts: [], fuel: [], supplements: [], profile: profile(), today: today))
        XCTAssertEqual(none.measured, 0)
        XCTAssertEqual(none.levels, [-1, -1, -1, -1, -1, -1])
        let logs = [session(3, "Back squat", 140), session(5, "Bench press", 60)]
        let progress = TrainingProgress.build(lifts: logs, workouts: [], fuel: [], supplements: [], profile: profile(), today: today)
        let build = Buddy.build(progress)
        let legs = try! XCTUnwrap(build.level("legs")), chest = try! XCTUnwrap(build.level("chest"))
        XCTAssertGreaterThan(legs, chest, "a strong squat and a modest bench")
        XCTAssertEqual(legs, progress.state(.quads).level ?? -1, accuracy: 1.5)
        XCTAssertEqual(build.parts.first { $0.key == "legs" }?.from, ["Back squat"])
        XCTAssertNil(build.level("core"), "nothing logged measures it, so it is not drawn as weak")
    }

    // MARK: Supplement trials

    func testATrialIsPairsInADrawnOrder() {
        var rng = SeededRNG(seed: 3)
        let trial = SupplementTrial.plan(supplement: "Magnesium", outcome: .deepMin, blockDays: 7, rounds: 3, washoutDays: 2, startDay: key(41), using: &rng)
        XCTAssertEqual(trial.order.count, 6)
        for r in 0..<3 { XCTAssertNotEqual(trial.order[r * 2], trial.order[r * 2 + 1], "each round has one block on and one off") }
        XCTAssertNil(trial.position(on: key(42)))
        let first = trial.position(on: key(41))!
        XCTAssertEqual(first.dayInBlock, 1)
        XCTAssertFalse(first.counted, "the first days of a block are left out")
        XCTAssertTrue(trial.position(on: key(39))!.counted)
        XCTAssertEqual(trial.position(on: key(34))!.block, 1)
        XCTAssertEqual(trial.lastDay(), key(0))
        XCTAssertNil(trial.position(on: LDate.adding(1, to: today)))
        XCTAssertNotNil(trial.instruction(on: key(41)))
    }

    private func runTrial(effect: Double, noise: Double, skipOffDays: Bool = false) -> TrialRead {
        var rng = SeededRNG(seed: 11)
        let start = key(42)
        let trial = SupplementTrial(supplement: "Magnesium", outcome: .deepMin, blockDays: 7, washoutDays: 2, startDay: start,
                                    order: [true, false, false, true, true, false])
        var days: [LDay] = [], fuel: [FuelEntry] = []
        for i in 0..<43 {
            let d = LDate.adding(i, to: start)
            let p = trial.position(on: d)
            let on = p?.on ?? false
            if on { fuel.append(FuelEntry(at: at(21, on: d), kind: .supplement, title: "Magnesium",
                                           supplement: SupplementDose(name: "Magnesium", amount: 400, unit: "mg"))) }
            if skipOffDays, p?.on == false, i % 2 == 0 {
                fuel.append(FuelEntry(at: at(21, on: d), kind: .supplement, title: "Magnesium",
                                      supplement: SupplementDose(name: "Magnesium", amount: 400, unit: "mg")))
            }
            // The night after day d is on day d + 1.
            days.append(LDay(day: LDate.adding(1, to: d), deepMin: 90 + (on ? effect : 0) + rng.gauss() * noise))
        }
        return TrialModel.read(trial, days: days, fuel: fuel, today: LDate.adding(1, to: today))
    }

    func testATrialFindsAnEffectThatIsThereAndNotOneThatIsNot() {
        let real = runTrial(effect: 15, noise: 5)
        XCTAssertEqual(real.verdict, .higher)
        XCTAssertEqual(real.nOn, 15)
        XCTAssertEqual(real.nOff, 15)
        XCTAssertEqual(real.delta ?? 0, 15, accuracy: 4)
        XCTAssertTrue((real.low ?? 0) > 0 && (real.high ?? 0) > 15 - 4)
        XCTAssertEqual(real.helps(.deepMin), true)
        XCTAssertTrue(real.finished)
        let nothing = runTrial(effect: 0, noise: 8)
        XCTAssertEqual(nothing.verdict, .unclear)
        XCTAssertNil(nothing.helps(.deepMin))
        // Days the plan was not followed are left out, not counted on the wrong side.
        let broken = runTrial(effect: 15, noise: 5, skipOffDays: true)
        XCTAssertGreaterThan(broken.broken, 0)
        XCTAssertEqual(broken.nOn, 15)
        XCTAssertLessThan(broken.nOff, 15)
    }

    func testATrialSaysNothingEarly() {
        var rng = SeededRNG(seed: 5)
        let trial = SupplementTrial.plan(supplement: "Magnesium", outcome: .deepMin, startDay: key(4), using: &rng)
        let days = (0..<6).map { LDay(day: key($0), deepMin: 90) }
        let read = TrialModel.read(trial, days: days, fuel: [], today: today)
        XCTAssertEqual(read.verdict, .tooEarly)
        XCTAssertNil(read.delta)
        XCTAssertFalse(read.finished)
    }

    func testADifferenceIsWordedAsItReadsFromTheTwoFiguresBesideIt() {
        // 127.6 against 124.3 is printed as 128 and 124, so the difference said is 4, not 3.
        XCTAssertEqual(LMetric.deepMin.shownDifference(127.6, 124.3), 4)
        XCTAssertEqual(LMetric.sleepHours.shownDifference(7.44, 7.06), 0.3, accuracy: 1e-9)
        // On a percent scale a difference is in points.
        XCTAssertEqual(LMetric.recovery.gap(12), "12 points")
        XCTAssertEqual(LMetric.recovery.gap(1), "1 point")
        XCTAssertEqual(LMetric.recovery.gap(-3.2, signed: true), "−3 points")
        XCTAssertEqual(LMetric.hrv.gap(5), "5 ms")
    }

    // MARK: How much and how late

    func testDoseFindsWhatTheDaysHold() {
        var rng = SeededRNG(seed: 21)
        var days: [LDay] = [], fuel: [FuelEntry] = [], nights: [SleepNight] = []
        for i in stride(from: 60, through: 1, by: -1) {
            let d = key(i)
            let drinks = Double(i % 4)                     // 0, 1, 2, 3 drinks
            let lateCoffee = i % 3 == 0                    // a 16:00 coffee every third day
            fuel.append(meal(d, hour: 8, caffeine: 100))
            fuel.append(meal(d, hour: 13))
            if lateCoffee { fuel.append(meal(d, hour: 16, kcal: 5, protein: 0, carbs: 0, caffeine: 100, kind: .drink)) }
            fuel.append(meal(d, hour: 19.5, alcohol: drinks > 0 ? drinks * 10 : nil))
            let next = key(i - 1)
            days.append(LDay(day: next, sleepMin: 440, deepMin: 95 - (lateCoffee ? 20 : 0) + rng.gauss() * 4,
                             restingHR: 52, hrv: 70 - 6 * drinks + rng.gauss() * 3, recovery: 70 - 5 * drinks + rng.gauss() * 4))
            nights.append(night(next))
        }
        let read = DoseModel.read(days: days, nights: nights, fuel: fuel, usualBedtime: -50)
        XCTAssertEqual(read.loggedDays, 60)
        let alcohol = try! XCTUnwrap(read.findings.first { $0.key == "alcohol" && $0.outcome == .hrv })
        XCTAssertEqual(alcohol.strength, .clear)
        XCTAssertEqual(alcohol.perStep, -6, accuracy: 1.2)
        XCTAssertEqual(alcohol.bins.map { $0.n }, [15, 15, 15, 15])
        XCTAssertTrue(alcohol.sentence.hasPrefix("Each drink goes with"))
        let cut = try! XCTUnwrap(read.cutoff("caffeine"))
        XCTAssertEqual(cut.outcome, .deepMin)
        XCTAssertLessThan(cut.delta, -12)
        XCTAssertEqual(cut.hour, 16, "the earliest late caffeine actually logged")
        XCTAssertTrue(cut.sentence.hasPrefix("On days with caffeine from 16:00 on"))
        XCTAssertTrue(cut.firm)
        // Bedtime never varied, so nothing is said about it.
        XCTAssertNil(read.findings.first { $0.key == "bedtime" })
    }

    func testDoseSaysNothingOnAThinLog() {
        let read = DoseModel.read(days: (0..<10).map { LDay(day: key($0), hrv: 60) }, nights: [], fuel: [meal(key(3), hour: 9)], usualBedtime: nil)
        XCTAssertTrue(read.findings.isEmpty)
        XCTAssertTrue(read.cutoffs.isEmpty)
    }

    // MARK: Food matched to the work

    func testADaysFoodIsReadAgainstTheWorkDone() {
        XCTAssertEqual(FuelMatch.dayClass(strain21: 16, sessions: 1, raced: false), .hard)
        XCTAssertEqual(FuelMatch.dayClass(strain21: 6, sessions: 1, raced: false), .moderate)
        XCTAssertEqual(FuelMatch.dayClass(strain21: 4, sessions: 0, raced: false), .rest)
        let d = key(1)
        let workout = LWorkout(start: at(18, on: d).timeIntervalSince1970, end: at(19, on: d).timeIntervalSince1970, sport: "Functional Fitness")
        // A hard day on rest-day carbs, protein in two sittings, nothing after the session.
        let thin = [meal(d, hour: 8, kcal: 700, protein: 80, carbs: 100), meal(d, hour: 13, kcal: 800, protein: 80, carbs: 120)]
        let read = FuelMatch.read(day: d, entries: thin, workouts: [workout], strain21: 16, profile: profile(), closed: true)
        XCTAssertEqual(read.dayClass, .hard)
        XCTAssertTrue(read.usable)
        XCTAssertEqual(read.checks.map { $0.id }, ["carbs", "protein", "before", "after"])
        XCTAssertEqual(read.checks[0].met, false)
        XCTAssertEqual(read.checks[1].met, false, "enough protein, but in two sittings")
        XCTAssertEqual(read.checks[3].met, false)
        XCTAssertEqual(read.headline, "0 of 4 matched")
        // The same day eaten to match.
        let good = [meal(d, hour: 8, kcal: 900, protein: 40, carbs: 150), meal(d, hour: 12.5, kcal: 900, protein: 40, carbs: 150),
                    meal(d, hour: 16, kcal: 600, protein: 30, carbs: 110), meal(d, hour: 19.5, kcal: 900, protein: 45, carbs: 130)]
        let matched = FuelMatch.read(day: d, entries: good, workouts: [workout], strain21: 16, profile: profile(), closed: true)
        XCTAssertEqual(matched.metCount, 4)
        // A day still open is not held to a total it has not reached.
        let open = FuelMatch.read(day: today, entries: [meal(today, hour: 8), meal(today, hour: 12)], workouts: [], strain21: 3, profile: profile(), closed: false)
        XCTAssertNil(open.checks.first { $0.id == "protein" }?.met)
        // A thin log on a finished day is not read at all.
        XCTAssertFalse(FuelMatch.read(day: d, entries: [meal(d, hour: 8, kcal: 300)], workouts: [], strain21: 3, profile: profile(), closed: true).usable)
        // Shown beside the day's targets, the read takes their class for the day: the two then judge the
        // same carbohydrate figure. The same food that matches a training day is short for a race day.
        let training = FuelMatch.read(day: d, entries: good, workouts: [workout], strain21: 16, dayClass: .moderate, profile: profile(), closed: true)
        XCTAssertEqual(training.dayClass, .moderate)
        XCTAssertEqual(training.checks.first { $0.id == "carbs" }?.met, true)
        let race = FuelMatch.read(day: d, entries: good, workouts: [workout], strain21: 16, dayClass: .race, profile: profile(), closed: true)
        XCTAssertEqual(race.dayClass, .race)
        XCTAssertEqual(race.checks.first { $0.id == "carbs" }?.met, false)
    }

    // MARK: Weight and energy

    func testTheWeightTrendMovesPartOfTheWayToEachWeighIn() {
        let entries = [WeightEntry(at: at(7, on: key(10)), kg: 80), WeightEntry(at: at(7, on: key(9)), kg: 82), WeightEntry(at: at(7, on: key(1)), kg: 79)]
        let read = BodyWeight.read(entries, today: today)
        XCTAssertEqual(read.weighIns, 3)
        XCTAssertEqual(read.points.first?.trend, 80)
        let second = read.points[1].trend
        XCTAssertTrue(second > 80 && second < 81, "one high weigh-in moves the trend a little")
        let now = try! XCTUnwrap(read.current)
        XCTAssertTrue(now > 79 && now < 80.5)
        XCTAssertEqual(read.points.count, 11)
        XCTAssertNil(read.points[5].kg)
        // A log gone quiet no longer speaks for today.
        XCTAssertNil(BodyWeight.read([WeightEntry(at: at(7, on: key(40)), kg: 80)], today: today).current)
        XCTAssertEqual(BodyWeight.read([], today: today), .empty)
    }

    func testEnergyUseIsWorkedOutFromFoodAndWeight() {
        // Eating 2,500 a day while losing 0.07 kg a day: about 460 kcal a day under.
        var fuel: [FuelEntry] = [], weights: [WeightEntry] = []
        for i in 1...28 {
            fuel += [meal(key(i), hour: 8, kcal: 1250), meal(key(i), hour: 19, kcal: 1250)]
            if i % 3 == 0 { weights.append(WeightEntry(at: at(7, on: key(i)), kg: 80 + 0.07 * Double(i))) }
        }
        let read = EnergyModel.read(weights: weights, fuel: fuel, days: [], today: today)
        XCTAssertEqual(read.loggedDays, 28)
        XCTAssertNil(read.missing)
        XCTAssertEqual(read.intake, 2500)
        XCTAssertEqual(read.kgPerWeek ?? 0, -0.49, accuracy: 0.01)
        // The change beside the weight trend is the same line, so the two cannot differ.
        let trend = BodyWeight.read(weights, today: today)
        XCTAssertEqual(trend.change28, read.kgChange)
        XCTAssertEqual(trend.change28 ?? 0, -0.07 * 28, accuracy: 0.02)
        let burn = try! XCTUnwrap(read.burn), low = try! XCTUnwrap(read.low), high = try! XCTUnwrap(read.high)
        XCTAssertEqual(burn, 2500 + 0.07 * 6600, accuracy: 15)
        XCTAssertTrue(low <= burn && burn <= high)
        XCTAssertEqual(low, 2500 + 0.07 * 5500, accuracy: 30)
        XCTAssertEqual(high, 2500 + 0.07 * 7700, accuracy: 30)
        XCTAssertLessThan(read.balance ?? 0, -400)
        XCTAssertNil(read.shortfall, "no slipping signals were given, so nothing is raised")
        // The same shortfall with HRV well under the weeks before is said.
        var days: [LDay] = []
        for i in 0..<56 { days.append(LDay(day: key(i), restingHR: 52, hrv: i < 14 ? 55 : 68)) }
        XCTAssertNotNil(EnergyModel.read(weights: weights, fuel: fuel, days: days, today: today).shortfall)
        // Too little to go on says what is missing instead of a figure.
        let thin = EnergyModel.read(weights: Array(weights.prefix(2)), fuel: fuel, days: [], today: today)
        XCTAssertNil(thin.burn)
        XCTAssertEqual(thin.missing, "Needs 3 more weigh-ins.")
        XCTAssertNil(BodyWeight.read(Array(weights.prefix(2)), today: today).change28, "and no change is claimed from two weigh-ins")
    }

    func testSweatRateIsWhatWasLostPlusWhatWasDrunk() {
        let test = SweatTest(day: key(2), beforeKg: 80.0, afterKg: 79.2, drankMl: 500, minutes: 60)
        XCTAssertEqual(test.mlPerHour ?? 0, 1300, accuracy: 1)
        XCTAssertEqual(test.percentLost, 1.0, accuracy: 0.01)
        XCTAssertNil(SweatTest(day: key(2), beforeKg: 80, afterKg: 79.9, drankMl: 0, minutes: 10).mlPerHour, "too short to tell")
        XCTAssertNil(SweatModel.rate([]))
        XCTAssertEqual(SweatModel.rate([test, SweatTest(day: key(1), beforeKg: 80, afterKg: 79.4, drankMl: 300, minutes: 60)]) ?? 0, 1100, accuracy: 1)
        // The water target takes the athlete's own rate.
        let on = LDate.date(today)!
        let standard = FuelPlanner.targets(profile: profile(), dayClass: .hard, trainingMinutes: 60, on: on)
        let own = FuelPlanner.targets(profile: profile(), dayClass: .hard, trainingMinutes: 60, sweatMlPerHour: 1300, on: on)
        XCTAssertEqual(own.waterMl - standard.waterMl, 700, accuracy: 50)
    }

    // MARK: Deeper strength and easing off

    func testRepBestsAndWeeklySets() {
        func session(_ ago: Int, _ sets: [LiftSet]) -> LiftSession {
            LiftSession(start: LDate.date(key(ago))!, title: "Strength", exercises: [LiftExercise(name: "Back squat", sets: sets)])
        }
        let logs = [session(20, [LiftSet(reps: 8, kg: 90, done: true), LiftSet(reps: 5, kg: 100, done: true)]),
                    session(3, [LiftSet(reps: 3, kg: 120, done: true), LiftSet(reps: 1, kg: 130, done: true), LiftSet(reps: 5, kg: 110, done: false)])]
        let bests = StrengthDepth.repBests("Back squat", sessions: logs)
        XCTAssertEqual(bests.map { $0.reps }, [1, 3, 5, 8])
        XCTAssertEqual(bests.map { $0.kg }, [130, 120, 100, 90], "a set not done sets no best")
        XCTAssertEqual(bests[0].day, key(3))
        let weeks = StrengthDepth.weeklySets(sessions: logs, today: today)
        let quads = try! XCTUnwrap(weeks.first { $0.muscle == .quads })
        XCTAssertEqual(quads.sets.count, 8)
        XCTAssertEqual(quads.sets.last, 2)
        XCTAssertEqual(quads.sets[5], 2)
        let progress = TrainingProgress.build(lifts: logs, workouts: [], fuel: [], supplements: [], profile: profile(), today: today)
        let history = StrengthDepth.history("Back squat", sessions: logs, progress: progress, bodyKg: 80, today: today)
        XCTAssertEqual(history.days.map { $0.day }, [key(3), key(20)])
        XCTAssertEqual(history.days[0].top, "1 × 130 kg")
        XCTAssertNil(history.stall)
    }

    func testEasingOffIsOfferedAfterTwoLowMornings() {
        let hard = PlannedSession(day: today, kind: .intervals, title: "6 × 800 m", durationMin: 60, intensity: .hard)
        let low = [LDay(day: key(1), recovery: 28), LDay(day: today, recovery: 31)]
        let offer = try! XCTUnwrap(EaseOff.offer(days: low, today: today, planned: [hard], settled: []))
        XCTAssertEqual(offer.eased.kind, .easyRun)
        XCTAssertEqual(offer.eased.intensity, .easy)
        XCTAssertEqual(offer.eased.durationMin, 45)
        XCTAssertEqual(offer.eased.id, hard.id, "the same slot, changed")
        XCTAssertEqual(offer.reason, "Recovery was 28% yesterday and 31% today.")
        XCTAssertNil(EaseOff.offer(days: low, today: today, planned: [hard], settled: [hard.id]), "an answer already given stands")
        XCTAssertNil(EaseOff.offer(days: [LDay(day: key(1), recovery: 60), LDay(day: today, recovery: 31)], today: today, planned: [hard], settled: []))
        XCTAssertNil(EaseOff.offer(days: [LDay(day: today, recovery: 31)], today: today, planned: [hard], settled: []), "yesterday unknown")
        let easy = PlannedSession(day: today, kind: .easyRun, title: "Easy run", intensity: .easy)
        XCTAssertNil(EaseOff.offer(days: low, today: today, planned: [easy], settled: []))
        let lesson = EaseOff.eased(PlannedSession(day: today, kind: .gymClass, title: "Gym class", durationMin: 60, intensity: .hard))
        XCTAssertEqual(lesson.kind, .gymClass, "a class stays the class")
    }

    // MARK: Models that need months

    func testTheRecoveryModelSeparatesWhatTravelsTogether() {
        var rng = SeededRNG(seed: 31)
        let count = 122
        // Each day's strain and drinks, drawn first. A drink means an hour later to bed and half an hour
        // less sleep that night: the two travel together.
        var strain: [Double] = [], drinks: [Double] = []
        for _ in 0..<count {
            strain.append(rng.range(4, 18))
            drinks.append(rng.unit() < 0.35 ? Double(Int(rng.range(1, 4))) : 0)
        }
        var days: [LDay] = [], nights: [SleepNight] = [], fuel: [FuelEntry] = []
        for t in 0..<count {
            let d = key(count - 1 - t)
            fuel += [meal(d, hour: 8), meal(d, hour: 13), meal(d, hour: 19.5, alcohol: drinks[t] > 0 ? drinks[t] * 10 : nil)]
            // The night that ended this morning followed day t − 1.
            let before = t > 0 ? drinks[t - 1] : 0
            let sleep = rng.range(5.5, 8.5) - (before > 0 ? 0.5 : 0)
            let recovery = t > 0 ? 40 - 1.5 * strain[t - 1] + 6 * sleep - 5 * before + rng.gauss() * 4 : 60
            days.append(LDay(day: d, sleepMin: sleep * 60, recovery: recovery, strain: LScale.strain100(strain[t])))
            nights.append(night(d, bedtime: before > 0 ? 10 : -50))
        }
        let now = DriverToday(strain21: 12, sleepHours: 7.5, foodLogged: true, drinks: 0)
        let read = DriverModel.read(days: days, nights: nights, fuel: fuel, usualBedtime: -50, profile: profile(), today: now)
        XCTAssertTrue(read.ready)
        XCTAssertEqual(read.nights, count - 1)
        XCTAssertEqual(read.loggedNights, count - 1)
        let strainEffect = try! XCTUnwrap(read.effects.first { $0.key == "strain" })
        let sleepEffect = try! XCTUnwrap(read.effects.first { $0.key == "sleep" })
        let drinkEffect = try! XCTUnwrap(read.effects.first { $0.key == "drinks" })
        let lateEffect = try! XCTUnwrap(read.effects.first { $0.key == "late" })
        XCTAssertEqual(strainEffect.effect, -1.5, accuracy: 0.4)
        XCTAssertEqual(sleepEffect.effect, 6, accuracy: 1.5)
        XCTAssertEqual(drinkEffect.effect, -5, accuracy: 2)
        XCTAssertEqual(strainEffect.strength, .clear)
        XCTAssertEqual(sleepEffect.strength, .clear)
        // A later bedtime went with every drink but did nothing by itself, and is not given the drink's share.
        XCTAssertTrue(lateEffect.low < 0 && lateEffect.high > 0)
        XCTAssertNil(read.effects.first { $0.key == "protein" }, "it never varied, so nothing is said about it")
        let forecast = try! XCTUnwrap(read.forecast)
        XCTAssertEqual(forecast.value, 40 - 1.5 * 12 + 6 * 7.5, accuracy: 6)
        XCTAssertTrue(forecast.low < forecast.value && forecast.value < forecast.high)
    }

    func testTheModelsSayNothingBeforeTheyHaveEnough() {
        let few = (0..<30).map { LDay(day: key($0), sleepMin: 440, recovery: 60, strain: 50) }
        let read = DriverModel.read(days: few, nights: [], fuel: [], usualBedtime: nil, profile: profile())
        XCTAssertFalse(read.ready)
        XCTAssertTrue(read.effects.isEmpty)
        XCTAssertNil(read.forecast)
        let progress = TrainingProgress.build(lifts: [], workouts: [], fuel: [], supplements: [], profile: profile(), today: today)
        let help = TrainingHelpModel.read(progress: progress, days: few, fuel: [], supplements: [], profile: profile(), today: today)
        XCTAssertFalse(help.ready)
        XCTAssertTrue(help.findings.isEmpty)
    }

    func testProteinWeeksShowInHowTheLiftsMoved() {
        // Twenty-six weeks of squatting once a week. In even weeks protein is hit and the lift gains
        // 2%; in odd weeks it is not and the lift holds.
        var lifts: [LiftSession] = [], fuel: [FuelEntry] = []
        let thisWeek = LDate.weekStart(today)
        var kg = 100.0
        for back in stride(from: 30, through: 1, by: -1) {
            let start = LDate.adding(-7 * back, to: thisWeek)
            let good = back % 2 == 0
            // Up about 2% in a good week and level in the others, never by exactly the same amount.
            kg *= good ? 1.015 + 0.002 * Double(back % 5) : 1.0 + 0.001 * Double(back % 3)
            lifts.append(LiftSession(start: LDate.date(LDate.adding(2, to: start))!, title: "Strength",
                                     exercises: [LiftExercise(name: "Back squat", sets: [LiftSet(reps: 5, kg: kg, done: true)])]))
            for i in 0..<7 {
                let d = LDate.adding(i, to: start)
                fuel += [meal(d, hour: 8, kcal: 900, protein: good ? 90 : 40), meal(d, hour: 19, kcal: 900, protein: good ? 90 : 40)]
            }
        }
        let progress = TrainingProgress.build(lifts: lifts, workouts: [], fuel: [], supplements: [], profile: profile(), today: today)
        let read = TrainingHelpModel.read(progress: progress, days: [], fuel: fuel, supplements: [], profile: profile(), today: today)
        XCTAssertTrue(read.ready)
        let protein = try! XCTUnwrap(read.findings.first { $0.key == "protein" })
        XCTAssertEqual(protein.strength, .clear)
        XCTAssertGreaterThan(protein.meanWith, protein.meanWithout)
        XCTAssertTrue(protein.sentence.contains("protein target"))
    }

    // MARK: Weekly review and reminders

    func testTheReviewIsOfTheWeekThatHasRun() {
        XCTAssertEqual(LDate.weekday(today), 1, "the fixture day is a Monday")
        XCTAssertEqual(WeekDigest.weekStart(for: today), key(7))
        XCTAssertEqual(WeekDigest.weekStart(for: key(1)), key(7), "on Sunday the week in progress is reviewed")
        XCTAssertEqual(WeekDigest.weekStart(for: key(2)), key(14))
        XCTAssertEqual(WeekDigest.title("2026-11-09"), "9 to 15 Nov")
        XCTAssertEqual(WeekDigest.title("2026-10-26"), "26 Oct to 1 Nov")
        let input: JSONValue = ["headline": "A steady week.", "went_well": ["Squat up 3%."], "watch": [], "next_week": ["Bench twice.", " ", "Bed by 23:00.", "Carbs on Thursday.", "A fourth"]]
        let review = try! XCTUnwrap(CoachTools.review(from: input, weekStart: key(7), figures: []))
        XCTAssertEqual(review.next, ["Bench twice.", "Bed by 23:00.", "Carbs on Thursday."])
        XCTAssertNil(CoachTools.review(from: ["headline": "x", "next_week": []], weekStart: key(7), figures: []))
        XCTAssertEqual(WeekDigest.due(today: today, reviews: [review]), nil)
        XCTAssertEqual(WeekDigest.due(today: today, reviews: []), key(7))
        let data = try! JSONEncoder().encode([review])
        XCTAssertEqual(try! JSONDecoder().decode([WeeklyReview].self, from: data), [review])
    }

    func testRemindersComeFromTheDaysOwnNumbers() {
        var f = ReminderFacts(now: at(9), today: today)
        f.usualBedtime = -60; f.bedtimeTonight = -90
        f.supplements = [(SupplementPlan(dose: SupplementDose(name: "Creatine", amount: 5, unit: "g"), timing: .morning), false),
                         (SupplementPlan(dose: SupplementDose(name: "Magnesium", amount: 400, unit: "mg"), timing: .evening), false),
                         (SupplementPlan(dose: SupplementDose(name: "Vitamin D", amount: 1000, unit: "IU"), timing: .morning), true)]
        f.proteinG = 40; f.proteinTarget = 160; f.foodEntries = 2
        f.trialToday = "Off block: skip Magnesium today (2 more days in this block)."
        f.paused = ["Magnesium"]
        let all = Set(ReminderKind.allCases)
        let plan = ReminderPlanner.plan(f, on: all)
        XCTAssertEqual(plan.map { $0.kind }, [.supplements, .caffeine, .protein, .bedtime])
        XCTAssertEqual(plan[0].body, "Creatine.", "ticked ones and one paused by a trial are left out")
        XCTAssertEqual(plan[1].at.timeIntervalSince(at(13)), 52 * 60, accuracy: 1, "8.8 hours before a 23:00 bedtime, less twenty minutes")
        XCTAssertEqual(plan[3].at.timeIntervalSince(at(22)), 0, accuracy: 1)
        XCTAssertTrue(plan.allSatisfy { $0.at > f.now })
        XCTAssertEqual(Set(plan.map { $0.id }).count, plan.count)
        // Nothing switched on, nothing planned; and a reason that has gone plans nothing.
        XCTAssertTrue(ReminderPlanner.plan(f, on: []).isEmpty)
        f.proteinG = 120
        XCTAssertFalse(ReminderPlanner.plan(f, on: all).contains { $0.kind == .protein })
        // The athlete's own cut-off replaces the general one.
        f.caffeineCutoff = DoseCutoff(key: "caffeine", outcome: .deepMin, hour: 14.5, delta: -18, nLate: 9, nEarly: 21, p: 0.004, firm: true, sentence: "")
        let own = try! XCTUnwrap(ReminderPlanner.plan(f, on: [.caffeine]).first)
        XCTAssertEqual(own.at.timeIntervalSince(at(14)), 10 * 60, accuracy: 1)
        XCTAssertEqual(own.body, "After 14:30 it has gone with 18 min less deep sleep for you.")
    }
}
