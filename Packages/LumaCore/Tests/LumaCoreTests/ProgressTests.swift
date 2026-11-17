import XCTest
@testable import LumaCore

/// The training log, the muscle model and the progress read built from them.
final class ProgressTests: XCTestCase {
    private let today = "2026-11-16"

    /// Local noon of a day `ago` days before today, so its day key is the same in any time zone.
    private func noon(_ ago: Int) -> Date { LDate.date(LDate.adding(-ago, to: today))! }

    private func sets(_ kg: Double, _ reps: Int, _ n: Int) -> [LiftSet] { (0..<n).map { _ in LiftSet(reps: reps, kg: kg, done: true) } }

    private func profile(_ kg: Double = 80, sex: Sex = .male) -> LProfile {
        var p = LProfile()
        p.weightKg = kg; p.sex = sex
        return p
    }

    private func build(_ lifts: [LiftSession], fuel: [FuelEntry] = [], supplements: [SupplementPlan] = [], workouts: [LWorkout] = [],
                       profile p: LProfile? = nil) -> TrainingProgress {
        TrainingProgress.build(lifts: lifts, workouts: workouts, fuel: fuel, supplements: supplements, profile: p ?? profile(), today: today)
    }

    // MARK: The log

    func testALogWrittenBeforeSessionsCarriedKindsStillReads() throws {
        let old = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","start":700000000,"end":700003300,"title":"Lower body strength","note":"",
          "exercises":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964F0","name":"Back squat",
                        "sets":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964F1","reps":5,"kg":100,"done":true}]}]}]
        """
        let read = try JSONDecoder().decode([LiftSession].self, from: Data(old.utf8))
        XCTAssertEqual(read.count, 1)
        XCTAssertNil(read[0].kind)
        XCTAssertEqual(read[0].resolvedKind, .strength)
        XCTAssertNil(read[0].exercises[0].sets[0].meters)
        XCTAssertEqual(read[0].exercises[0].setsText, "5 × 100 kg")
        // And what is written now reads back whole.
        var s = read[0]
        s.kind = .hyrox; s.source = "photo"; s.photos = ["a.jpg"]; s.asWritten = "4 rounds"
        s.exercises.append(LiftExercise(name: "Sled push", sets: [LiftSet(reps: 0, kg: 152, done: true, meters: 25)], note: "heavy"))
        let again = try JSONDecoder().decode([LiftSession].self, from: JSONEncoder().encode([s]))
        XCTAssertEqual(again, [s])
    }

    func testASetReadsAsWhatWasCounted() {
        XCTAssertEqual(LiftSet(reps: 5, kg: 100).text, "5 × 100 kg")
        XCTAssertEqual(LiftSet(reps: 12, kg: 0).text, "12 reps")
        XCTAssertEqual(LiftSet(reps: 0, kg: 152, meters: 25).text, "25 m · 152 kg")
        XCTAssertEqual(LiftSet(reps: 0, kg: 0, meters: 1500).text, "1.5 km")
        XCTAssertEqual(LiftSet(reps: 0, kg: 0, seconds: 45).text, "45 s")
        XCTAssertEqual(LiftSet(reps: 0, kg: 0, seconds: 150).text, "2:30")
        XCTAssertEqual(LiftSet(reps: 0, kg: 0, calories: 20).text, "20 cal")
        XCTAssertFalse(LiftSet(reps: 0, kg: 40).hasContent)
        let e = LiftExercise(name: "Back squat", sets: sets(100, 5, 4))
        XCTAssertEqual(e.setsText, "4 × 5 × 100 kg")
        let mixed = LiftExercise(name: "Back squat", sets: [LiftSet(reps: 5, kg: 100, done: true), LiftSet(reps: 3, kg: 110, done: true)])
        XCTAssertEqual(mixed.setsText, "5 × 100 kg, 3 × 110 kg")
    }

    func testAnEstimateNeedsALoadAndFewEnoughReps() {
        XCTAssertNil(LiftMath.estimate(LiftSet(reps: 20, kg: 60, done: true), bodyweightLift: false, bodyKg: 80))
        XCTAssertNil(LiftMath.estimate(LiftSet(reps: 8, kg: 0, done: true), bodyweightLift: false, bodyKg: 80))
        XCTAssertNil(LiftMath.estimate(LiftSet(reps: 5, kg: 100, done: false), bodyweightLift: false, bodyKg: 80))
        XCTAssertEqual(LiftMath.estimate(LiftSet(reps: 5, kg: 100, done: true), bodyweightLift: false, bodyKg: 80)!, 100 * (1 + 5.0 / 30), accuracy: 1e-9)
        // A pull-up moves the body too: six with 10 kg added is six at 90 kg.
        XCTAssertEqual(LiftMath.estimate(LiftSet(reps: 6, kg: 10, done: true), bodyweightLift: true, bodyKg: 80)!, 90 * 1.2, accuracy: 1e-9)
        XCTAssertEqual(LiftMath.best(LiftExercise(name: "Pull-up", sets: sets(0, 8, 3)), bodyKg: 75)!, 75 * (1 + 8.0 / 30), accuracy: 1e-9)
        XCTAssertNil(LiftMath.best(LiftExercise(name: "Sled push", sets: [LiftSet(reps: 0, kg: 152, done: true, meters: 25)]), bodyKg: 75))
    }

    func testAMissingLoadIsNoticedOnlyWhereOneIsExpected() {
        // A board gives the sets of a squat and not what was on the bar: the log is missing that.
        XCTAssertTrue(LiftExercise(name: "Back squat", sets: sets(0, 5, 4)).needsLoad)
        XCTAssertFalse(LiftExercise(name: "Back squat", sets: sets(100, 5, 4)).needsLoad)
        XCTAssertTrue(LiftExercise(name: "Sled push", sets: [LiftSet(reps: 0, kg: 0, done: true, meters: 25)]).needsLoad)
        // A push-up, a pull-up, a run and a movement Luma does not know are not missing anything.
        XCTAssertFalse(LiftExercise(name: "Push-up", sets: sets(0, 12, 3)).needsLoad)
        XCTAssertFalse(LiftExercise(name: "Pull-up", sets: sets(0, 8, 3)).needsLoad)
        XCTAssertFalse(LiftExercise(name: "Run", sets: [LiftSet(reps: 0, kg: 0, done: true, meters: 400)]).needsLoad)
        XCTAssertFalse(LiftExercise(name: "Zottman thing", sets: sets(0, 10, 3)).needsLoad)
        XCTAssertFalse(LiftExercise(name: "Back squat", sets: []).needsLoad)
        XCTAssertEqual(LiftSet(reps: 5, kg: 100).amountText, "5 reps")
        XCTAssertEqual(LiftSet(reps: 0, kg: 152, meters: 25).amountText, "25 m")
    }

    func testAnExerciseTypedInByHand() throws {
        let squat = try XCTUnwrap(LiftExercise.typed(name: " back squats ", sets: 5, amount: 5, measure: .reps, kg: 102.5))
        XCTAssertEqual(squat.name, "Back squat")
        XCTAssertEqual(squat.setsText, "5 × 5 × 102.5 kg")
        XCTAssertEqual(Set(squat.sets.map { $0.id }).count, 5)
        XCTAssertTrue(squat.sets.allSatisfy { $0.done })
        let sled = try XCTUnwrap(LiftExercise.typed(name: "Sled push", sets: 4, amount: 25, measure: .meters, kg: 150))
        XCTAssertEqual(sled.setsText, "4 × 25 m · 150 kg")
        let hold = try XCTUnwrap(LiftExercise.typed(name: "Copenhagen plank", sets: 3, amount: 30, measure: .seconds, kg: 0))
        XCTAssertEqual(hold.name, "Copenhagen plank")
        XCTAssertEqual(hold.setsText, "3 × 30 s")
        XCTAssertNil(LiftExercise.typed(name: "  ", sets: 3, amount: 10, measure: .reps, kg: 0))
        XCTAssertNil(LiftExercise.typed(name: "Row", sets: 0, amount: 500, measure: .meters, kg: 0))
        XCTAssertNil(LiftExercise.typed(name: "Row", sets: 3, amount: 0, measure: .meters, kg: 0))
    }

    // MARK: Names and muscles

    func testEveryNameInThePickerIsKnownUnderThatName() {
        for name in LiftMath.catalog {
            let info = ExerciseLibrary.match(name)
            XCTAssertEqual(info?.name, name, name)
            XCTAssertFalse(info?.primary.isEmpty ?? true, name)
        }
    }

    func testOtherWordingsFileUnderLumasName() {
        XCTAssertEqual(ExerciseLibrary.filedName("RDL"), "Romanian deadlift")
        XCTAssertEqual(ExerciseLibrary.filedName("wall balls"), "Wall ball")
        XCTAssertEqual(ExerciseLibrary.filedName("Pull-ups"), "Pull-up")
        XCTAssertEqual(ExerciseLibrary.filedName("Barbell back squat"), "Back squat")
        XCTAssertEqual(ExerciseLibrary.filedName("Back squat 5x5"), "Back squat")
        XCTAssertNotNil(ExerciseLibrary.match("Back squat 5x5")?.scale)
        XCTAssertEqual(ExerciseLibrary.filedName("KB swings"), "Kettlebell swing")
        XCTAssertEqual(ExerciseLibrary.filedName("Farmers walk"), "Farmers carry")
    }

    func testAVariationKeepsItsNameAndIsNotGraded() {
        let paused = ExerciseLibrary.match("paused back squat")
        XCTAssertEqual(paused?.name, "Paused back squat")
        XCTAssertEqual(paused?.primary, [.quads, .glutes])
        XCTAssertNil(paused?.scale)
        let single = ExerciseLibrary.match("Single leg RDL")
        XCTAssertEqual(single?.primary, [.hamstrings, .glutes])
        XCTAssertNil(single?.scale)
    }

    func testARowOnTheBoardIsTheMachineAndAnUprightRowIsALift() {
        XCTAssertEqual(ExerciseLibrary.match("Row")?.resistance, false)
        XCTAssertEqual(ExerciseLibrary.match("500 m row")?.name, "Row")
        XCTAssertEqual(ExerciseLibrary.match("Upright row")?.primary, [.shoulders, .traps])
        XCTAssertEqual(ExerciseLibrary.match("Landmine row")?.resistance, true)
        XCTAssertEqual(ExerciseLibrary.match("Landmine row")?.primary, [.upperBack, .lats])
        XCTAssertEqual(ExerciseLibrary.match("400 m run")?.resistance, false)
        XCTAssertEqual(ExerciseLibrary.match("Ski erg")?.name, "SkiErg")
    }

    func testAnUnknownMovementUsesTheMusclesReadWithIt() {
        XCTAssertNil(ExerciseLibrary.match("Zottman thing"))
        let read = ExerciseLibrary.work(LiftExercise(name: "Zottman thing", sets: sets(10, 10, 3), muscles: ["forearms", "nonsense"]))
        XCTAssertEqual(read.primary, [.forearms])
        XCTAssertTrue(read.resistance)
        let none = ExerciseLibrary.work(LiftExercise(name: "Zottman thing", sets: sets(10, 10, 3)))
        XCTAssertTrue(none.primary.isEmpty)
        XCTAssertFalse(none.resistance)
    }

    func testTheScaleRunsFromStartingToExceptional() throws {
        let squat = try XCTUnwrap(ExerciseLibrary.match("Back squat")?.scale)
        XCTAssertEqual(squat.level(ratio: 1.5, sex: .male, bodyweightLift: false), 3, accuracy: 1e-9)
        XCTAssertEqual(StrengthLevel(squat.level(ratio: 1.5, sex: .male, bodyweightLift: false)), .strong)
        XCTAssertEqual(squat.level(ratio: 0.375, sex: .male, bodyweightLift: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(StrengthLevel(squat.level(ratio: 0.375, sex: .male, bodyweightLift: false)), .starting)
        XCTAssertEqual(squat.level(ratio: 4, sex: .male, bodyweightLift: false), 5)
        XCTAssertEqual(squat.level(ratio: 1.3, sex: .male, bodyweightLift: false), 2.5, accuracy: 1e-9)
        // The same lift sits higher on a woman's scale.
        XCTAssertGreaterThan(squat.level(ratio: 1.3, sex: .female, bodyweightLift: false), 3)
        let pull = try XCTUnwrap(ExerciseLibrary.match("Pull-up")?.scale)
        XCTAssertEqual(pull.marks(for: .female, bodyweightLift: true).first, 1)
        for name in LiftMath.catalog {
            guard let marks = ExerciseLibrary.match(name)?.scale?.marks else { continue }
            XCTAssertEqual(marks.count, 5, name)
            XCTAssertEqual(marks, marks.sorted(), name)
        }
    }

    // MARK: Progress

    func testALiftsFigureIsItsRecentBestAndItsChangeIsAgainstTheSixWeeksBefore() throws {
        let logs = [
            LiftSession(start: noon(70), exercises: [LiftExercise(name: "Bench press", sets: sets(80, 5, 3))]),
            LiftSession(start: noon(50), exercises: [LiftExercise(name: "Bench press", sets: sets(82.5, 5, 3))]),
            LiftSession(start: noon(20), exercises: [LiftExercise(name: "Bench press", sets: sets(75, 5, 3))]),
            LiftSession(start: noon(3), exercises: [LiftExercise(name: "Bench press", sets: sets(77.5, 5, 3))]),
        ]
        let p = build(logs)
        let bench = try XCTUnwrap(p.lifts.first { $0.name == "Bench press" })
        XCTAssertEqual(bench.points.count, 4)
        XCTAssertEqual(bench.current!, 77.5 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(bench.previousBest!, 82.5 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(bench.change!, (77.5 - 82.5) / 82.5, accuracy: 1e-9)
        XCTAssertEqual(bench.trend, .down)
        XCTAssertEqual(bench.allTimeDay, LDate.adding(-50, to: today))
        XCTAssertTrue(p.weakPoints.contains { $0.id == "down-Bench press" })
        // Chest and triceps are read from it.
        XCTAssertEqual(p.state(.chest).basis?.name, "Bench press")
        XCTAssertEqual(p.state(.triceps).level, bench.level)
        XCTAssertEqual(p.state(.chest).trend, .down)
        XCTAssertNil(p.state(.quads).level)
    }

    func testALiftNotLoggedInTwelveWeeksHasNoCurrentFigure() throws {
        let p = build([LiftSession(start: noon(120), exercises: [LiftExercise(name: "Deadlift", sets: sets(140, 3, 3))])])
        let dead = try XCTUnwrap(p.lifts.first)
        XCTAssertNil(dead.current)
        XCTAssertNil(dead.level)
        XCTAssertEqual(dead.allTime, 140 * 1.1, accuracy: 1e-9)
        XCTAssertNil(p.state(.hamstrings).level)
        XCTAssertTrue(p.graded.isEmpty)
    }

    func testSetsCountOneForDirectWorkAndHalfForAssisting() {
        let session = LiftSession(start: noon(1), exercises: [
            LiftExercise(name: "Bench press", sets: sets(80, 5, 4)),
            LiftExercise(name: "Run", sets: [LiftSet(reps: 0, kg: 0, done: true, meters: 400), LiftSet(reps: 0, kg: 0, done: true, meters: 400)]),
            LiftExercise(name: "Wall ball", sets: [LiftSet(reps: 25, kg: 6, done: true), LiftSet(reps: 25, kg: 6, done: false)]),
        ])
        let p = build([session])
        XCTAssertEqual(p.state(.chest).weekSets, 4)
        XCTAssertEqual(p.state(.triceps).weekSets, 2.5)   // half of four bench sets, half of one wall-ball set
        XCTAssertEqual(p.state(.quads).weekSets, 1)       // only the done wall-ball set
        XCTAssertEqual(p.state(.calves).weekSets, 0.5)
        XCTAssertEqual(p.state(.hamstrings).weekSets, 0)
        XCTAssertEqual(p.state(.chest).band, .low)
        XCTAssertEqual(SetBand(0), .none)
        XCTAssertEqual(SetBand(7), .middle)
        XCTAssertEqual(SetBand(10), .high)
        XCTAssertNil(p.state(.chest).usualSets)            // one day of log is no usual
        XCTAssertEqual(p.state(.chest).lastDirect, LDate.adding(-1, to: today))
        XCTAssertEqual(p.state(.chest).movements, ["Bench press"])
    }

    func testMuscleGroupsNothingReachesAreNamedOnceThereIsEnoughLogged() {
        let bench = { (ago: Int) in LiftSession(start: self.noon(ago), exercises: [LiftExercise(name: "Bench press", sets: self.sets(80, 5, 4))]) }
        let two = build([bench(2), bench(5)])
        XCTAssertFalse(two.weakPoints.contains { $0.id == "untouched" })
        let three = build([bench(2), bench(5), bench(9)])
        let note = three.weakPoints.first { $0.id == "untouched" }
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.muscles.contains(.quads) ?? false)
        XCTAssertFalse(note?.muscles.contains(.chest) ?? true)
        XCTAssertFalse(note?.muscles.contains(.shoulders) ?? true)   // assisting work reaches the shoulders
    }

    func testTheDemoLogShowsOneOfEachKindOfFinding() throws {
        let now = noon(0)
        let p = build(LumaDemoContent.lifts(today: now), profile: LumaDemoContent.profile())
        let squat = try XCTUnwrap(p.lifts.first { $0.name == "Back squat" })
        XCTAssertEqual(StrengthLevel(try XCTUnwrap(squat.level)), .strong)
        XCTAssertEqual(squat.trend, .up)
        XCTAssertEqual(p.graded.first?.name, "Back squat")
        XCTAssertTrue(p.strengths.contains { $0.id == "top-Back squat" })
        XCTAssertTrue(p.strengths.contains { $0.id == "up-Back squat" })
        XCTAssertTrue(p.weakPoints.contains { $0.id == "low-Push press" })
        XCTAssertTrue(p.weakPoints.contains { $0.id == "down-Bench press" })
        XCTAssertEqual(p.state(.shoulders).basis?.name, "Push press")
        XCTAssertEqual(StrengthLevel(try XCTUnwrap(p.state(.shoulders).level)), .solid)
        XCTAssertNil(p.state(.calves).level)
        XCTAssertNil(p.state(.lowerBack).level)
        XCTAssertGreaterThan(p.state(.quads).weekSets, 5)
        XCTAssertNotNil(p.state(.quads).usualSets)
        XCTAssertEqual(Set(p.mix.map { $0.kind }), [.strength, .hyrox, .gymClass])
        XCTAssertEqual(p.muscles.count, Muscle.allCases.count)
        // A sled length with a load is work for the legs and no estimate of a max.
        XCTAssertNil(p.lifts.first { $0.name == "Sled push" })
        XCTAssertEqual(p.state(.calves).movements.first, "Sled push")
    }

    // MARK: Fuel and supplements

    private func meal(_ ago: Int, hour: Double, kcal: Double, protein: Double, carbs: Double = 0, alcohol: Double? = nil,
                      caffeine: Double? = nil, kind: FuelKind = .meal) -> FuelEntry {
        let start = LDate.calendar.startOfDay(for: noon(ago))
        return FuelEntry(at: start.addingTimeInterval(hour * 3600), kind: kind, title: "Meal",
                         items: [FuelItem(name: "Food", kcal: kcal, proteinG: protein, carbsG: carbs, caffeineMg: caffeine, alcoholG: alcohol)])
    }

    func testTheFoodLogIsReadOnlyOnDaysFullEnoughToRead() throws {
        var fuel: [FuelEntry] = []
        for ago in [1, 2, 3] {   // full days: 2,400 kcal, 170 g protein
            fuel += [meal(ago, hour: 8, kcal: 800, protein: 50, carbs: 100), meal(ago, hour: 13, kcal: 800, protein: 60, carbs: 100),
                     meal(ago, hour: 19, kcal: 800, protein: 60, carbs: 100)]
        }
        fuel.append(meal(4, hour: 13, kcal: 600, protein: 30))     // one entry: under-logged, not read
        fuel += [meal(0, hour: 8, kcal: 900, protein: 80), meal(0, hour: 12, kcal: 900, protein: 80)]   // today is still being written
        let trained = LiftSession(start: noon(2), exercises: [LiftExercise(name: "Back squat", sets: sets(100, 5, 3))])
        let read = try XCTUnwrap(build([trained], fuel: fuel).fuel)
        XCTAssertEqual(read.window, 14)
        XCTAssertEqual(read.loggedDays, 3)
        XCTAssertEqual(read.proteinPerKg!, 170.0 / 80, accuracy: 1e-9)
        XCTAssertEqual(read.proteinTargetPerKg, 2, accuracy: 1e-9)
        XCTAssertEqual(read.proteinDaysMet, 3)
        XCTAssertEqual(read.trainingDays, 1)
        XCTAssertEqual(read.restDays, 2)
        XCTAssertEqual(read.trainingCarbsPerKg!, 300.0 / 80, accuracy: 1e-9)
        XCTAssertNil(build([], fuel: [meal(4, hour: 13, kcal: 600, protein: 30)]).fuel)
    }

    func testSupplementAdherenceCountsFromTheFirstLog() throws {
        let plan = SupplementPlan(dose: SupplementDose(name: "Creatine monohydrate", amount: 5, unit: "g"))
        let other = SupplementPlan(dose: SupplementDose(name: "Vitamin D3", amount: 2000, unit: "IU"))
        func took(_ ago: Int) -> FuelEntry {
            FuelEntry(at: noon(ago), kind: .supplement, title: "Creatine monohydrate", supplement: plan.dose, source: .quick)
        }
        let p = build([], fuel: [took(5), took(4), took(2), took(1), took(0)], supplements: [plan, other])
        let creatine = try XCTUnwrap(p.supplements.first { $0.name == "Creatine monohydrate" })
        XCTAssertEqual(creatine.window, 6)
        XCTAssertEqual(creatine.daysTaken, 5)
        XCTAssertEqual(creatine.streak, 3)
        let d3 = try XCTUnwrap(p.supplements.first { $0.name == "Vitamin D3" })
        XCTAssertEqual(d3.daysTaken, 0)
        XCTAssertEqual(d3.window, 14)
        XCTAssertEqual(d3.streak, 0)
        // Not yet taken today does not break a streak that ran to yesterday.
        let yesterday = build([], fuel: [took(3), took(2), took(1)], supplements: [plan])
        XCTAssertEqual(yesterday.supplements.first?.streak, 3)
    }

    func testHabitsAreReadFromTheLogsAsWellAsCheckIns() {
        let days = (0..<30).map { LDay(day: LDate.adding(-$0, to: today)) }
        let checkIns = [CheckIn(day: LDate.adding(-10, to: today), tags: [.alcohol]), CheckIn(day: LDate.adding(-11, to: today), tags: [])]
        let fuel = [
            meal(3, hour: 20, kcal: 300, protein: 2, alcohol: 28, kind: .drink),
            meal(5, hour: 15, kcal: 5, protein: 0, caffeine: 120, kind: .drink),
            meal(6, hour: 9, kcal: 5, protein: 0, caffeine: 120, kind: .drink),
            meal(7, hour: 21.5, kcal: 700, protein: 40),
            FuelEntry(at: noon(8), kind: .supplement, title: "Magnesium glycinate", supplement: SupplementDose(name: "Magnesium glycinate", amount: 400, unit: "mg"), source: .quick),
        ]
        let plan = SupplementPlan(dose: SupplementDose(name: "Magnesium glycinate", amount: 400, unit: "mg"))
        let all = EffectModel.factors(days: days, checkIns: checkIns, workouts: [], fuel: fuel, supplements: [plan], profile: profile())
        let by = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        // One habit, fed by the check-in and by the food log.
        XCTAssertEqual(by["alcohol"]?.days, [LDate.adding(-10, to: today), LDate.adding(-3, to: today)])
        XCTAssertEqual(all.filter { $0.key == "alcohol" }.count, 1)
        XCTAssertTrue(by["alcohol"]?.known?.contains(LDate.adding(-11, to: today)) ?? false)   // a check-in day
        XCTAssertTrue(by["alcohol"]?.known?.contains(LDate.adding(-7, to: today)) ?? false)    // a food-log day
        XCTAssertFalse(by["alcohol"]?.known?.contains(LDate.adding(-20, to: today)) ?? true)   // nothing logged: not known
        XCTAssertEqual(by["lateCaffeine"]?.days, [LDate.adding(-5, to: today)])                 // the 09:00 coffee is not late
        XCTAssertEqual(by["lateMeal"]?.days, [LDate.adding(-7, to: today)])
        // Before the first log of a supplement there is no telling whether it was taken.
        XCTAssertEqual(by["supplement:Magnesium glycinate"]?.days, [LDate.adding(-8, to: today)])
        XCTAssertEqual(by["supplement:Magnesium glycinate"]?.known?.count, 9)
        // Sauna was only ever answerable in a check-in.
        XCTAssertNil(by["sauna"])
    }

    // MARK: Reading sessions

    private func json(_ text: String) -> JSONValue { JSONValue.parse(text) ?? .null }

    func testSeveralSessionsAreReadFromOneAnswer() {
        let input = json("""
        {"workouts": [
          {"title": "Lower body strength", "kind": "strength", "photos": [1],
           "movements": [{"name": "Barbell back squat", "sets": [{"reps": 5, "kg": 100}, {"reps": 5, "kg": 100}, {"reps": 5}]},
                         {"name": "RDL", "sets": [{"reps": 8}, {"reps": 8}], "note": "tempo 3-1-1"}]},
          {"title": "HYROX class", "kind": "hyrox", "photos": [2, 3], "date": "2026-11-14", "duration_min": 60,
           "as_written": "4 rounds\\n25 m sled push",
           "movements": [{"name": "Sled push", "sets": [{"meters": 25, "kg": 152}, {"meters": 25, "kg": 152}]},
                         {"name": "Devil's staircase", "sets": [{"seconds": 90}], "muscles": ["quads", "calves", "wings"]},
                         {"name": "", "sets": [{"reps": 3}]}]},
          {"title": "Nothing readable", "kind": "other", "movements": []}
        ]}
        """)
        let read = CoachTools.loggedSessions(input, day: today, now: noon(0))
        XCTAssertEqual(read.count, 2)
        guard read.count == 2 else { return }
        let lower = read[0].session
        XCTAssertEqual(lower.kind, .strength)
        XCTAssertEqual(lower.source, "photo")
        XCTAssertEqual(lower.day, today)
        XCTAssertEqual(lower.exercises.map { $0.name }, ["Back squat", "Romanian deadlift"])
        XCTAssertEqual(lower.exercises[0].sets.map { $0.kg }, [100, 100, 0])       // a load that is not written stays unwritten
        XCTAssertTrue(lower.exercises[0].sets.allSatisfy { $0.done })
        XCTAssertEqual(lower.exercises[1].note, "tempo 3-1-1")
        XCTAssertEqual(read[0].photos, [1])
        let race = read[1].session
        XCTAssertEqual(race.kind, .hyrox)
        XCTAssertEqual(race.day, "2026-11-14")
        XCTAssertEqual(race.minutes ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(race.asWritten, "4 rounds\n25 m sled push")
        XCTAssertEqual(race.exercises.count, 2)
        XCTAssertEqual(race.exercises.first?.sets.first?.text, "25 m · 152 kg")
        XCTAssertEqual(race.exercises.last?.muscles, ["quads", "calves"])
        XCTAssertEqual(read[1].photos, [2, 3])
    }

    func testADayInTheFutureOrLongAgoIsNotBelieved() {
        let lift = #"[{"name": "Deadlift", "sets": [{"reps": 3, "kg": 140}]}]"#
        let future = CoachTools.loggedSession(json(#"{"title": "X", "date": "2027-01-01", "movements": \#(lift)}"#), day: today,
                                              source: "photo", now: noon(0))
        XCTAssertEqual(future?.day, today)
        let ancient = CoachTools.loggedSession(json(#"{"title": "X", "date": "2019-01-01", "movements": \#(lift)}"#), day: today,
                                               source: "photo", now: noon(0))
        XCTAssertEqual(ancient?.day, today)
        // A board with nothing in a form Luma keeps, but transcribed, is still kept as written.
        let words = CoachTools.loggedSession(json(#"{"title": "Mobility", "kind": "mobility", "as_written": "20 min flow", "movements": []}"#),
                                             day: today, source: "photo", now: noon(0))
        XCTAssertEqual(words?.asWritten, "20 min flow")
        XCTAssertEqual(words?.kind, .mobility)
        XCTAssertNil(CoachTools.loggedSession(json(#"{"title": "Empty", "movements": []}"#), day: today, source: "photo", now: noon(0)))
        // A count in place of a list of sets.
        let counted = CoachTools.exercises(json(#"[{"name": "Bench press", "sets": 4, "reps": 6, "kg": 70}]"#))
        XCTAssertEqual(counted.first?.sets.count, 4)
        XCTAssertEqual(counted.first?.sets.first?.text, "6 × 70 kg")
    }

    func testTheReadingToolAndItsInstructions() {
        let tool = CoachTools.workoutsTool()
        XCTAssertEqual(tool.inputSchema["type"]?.string, "object")
        XCTAssertNotNil(tool.inputSchema["properties"]?["workouts"])
        let text = CoachPrompt.workoutExtraction(today: today, sex: .male)
        XCTAssertTrue(text.contains("Monday \(today)"))
        XCTAssertTrue(text.contains("never guess a load"))
        XCTAssertTrue(text.contains("Romanian deadlift"))
    }

    // MARK: Body map

    func testEveryMuscleHasAPlaceOnTheFigure() {
        let shown = Set(BodySide.allCases.flatMap { BodyMap.muscles(on: $0) })
        XCTAssertEqual(shown, Set(Muscle.allCases))
        for side in BodySide.allCases {
            for region in BodyMap.regions(side) {
                XCTAssertEqual(region.outlines.count, 2, region.muscle.rawValue)
                for outline in region.outlines {
                    XCTAssertGreaterThanOrEqual(outline.count, 5, region.muscle.rawValue)
                    for p in outline {
                        XCTAssertTrue((0...BodyMap.width).contains(p.x) && (0...BodyMap.height).contains(p.y), region.muscle.rawValue)
                    }
                }
                // Left is the mirror image of right.
                let right = region.outlines[0], left = region.outlines[1]
                for (a, b) in zip(right, left) {
                    XCTAssertEqual(a.x + b.x, BodyMap.width, accuracy: 1e-9)
                    XCTAssertEqual(a.y, b.y)
                }
                XCTAssertTrue(right.allSatisfy { $0.x >= BodyMap.width / 2 }, region.muscle.rawValue)
            }
        }
        XCTAssertEqual(BodyMap.silhouette.count, 6)
    }

    func testAnOutlineIsAClosedCurveThroughItsPoints() {
        let outline = BodyMap.regions(.front)[0].outlines[0]
        let curve = BodyMap.curve(outline)
        XCTAssertEqual(curve.start, outline[0])
        XCTAssertEqual(curve.segments.count, outline.count)
        XCTAssertEqual(curve.segments.last?.end, outline[0])
        for (i, s) in curve.segments.dropLast().enumerated() { XCTAssertEqual(s.end, outline[i + 1]) }
        XCTAssertTrue(BodyMap.curve([BodyPoint(x: 0, y: 0), BodyPoint(x: 1, y: 1)]).segments.isEmpty)
    }
}
