import XCTest
@testable import LumaCore

/// A SkiErg, a rower and a bike are counted in distance, time or calories, not in kilograms. These
/// are the rules for asking for that amount and reading what is typed.
final class AmountTests: XCTestCase {
    func testAnErgIsCountedInMetresAndAPlankInSeconds() {
        XCTAssertEqual(ExerciseLibrary.match("SkiErg")?.counts, .meters)
        XCTAssertEqual(ExerciseLibrary.match("Rowerg")?.counts, .meters)
        XCTAssertEqual(ExerciseLibrary.match("BikeErg")?.counts, .meters)
        XCTAssertEqual(ExerciseLibrary.match("Sled push")?.counts, .meters)
        XCTAssertEqual(ExerciseLibrary.match("Plank")?.counts, .seconds)
        XCTAssertEqual(ExerciseLibrary.match("Back squat")?.counts, .reps)
        // None of the three takes a load.
        for name in ["SkiErg", "RowErg", "BikeErg"] {
            XCTAssertEqual(ExerciseLibrary.match(name)?.resistance, false, name)
        }
    }

    func testAMovementReadWithNothingCountedAsksForItsAmountInItsOwnMeasure() {
        var ski = LiftExercise(name: "SkiErg")
        XCTAssertTrue(ski.needsAmount)
        XCTAssertEqual(ski.measure, .meters)
        ski.setLoggedAmount(1000, .meters)
        XCTAssertFalse(ski.needsAmount)
        XCTAssertEqual(ski.sets.count, 1)
        XCTAssertEqual(ski.setsText, "1 km")
        XCTAssertEqual(ski.commonAmount(.meters), 1000)

        // What a set already holds decides the measure, whatever the movement usually counts.
        let bike = LiftExercise(name: "BikeErg", sets: [LiftSet(reps: 0, kg: 0, done: true, calories: 30)])
        XCTAssertEqual(bike.measure, .calories)
        XCTAssertFalse(bike.needsAmount)
        // A movement Luma does not know is counted in reps until something says otherwise.
        XCTAssertEqual(LiftExercise(name: "Zercher shuffle").measure, .reps)
    }

    func testAnAmountGoesToEverySetAndLeavesLoadsAlone() {
        var sled = LiftExercise(name: "Sled push", sets: [LiftSet(reps: 0, kg: 100), LiftSet(reps: 0, kg: 120)])
        XCTAssertTrue(sled.needsAmount)
        sled.setLoggedAmount(25, .meters)
        XCTAssertEqual(sled.sets.map { $0.meters }, [25, 25])
        XCTAssertEqual(sled.sets.map { $0.kg }, [100, 120])
        XCTAssertTrue(sled.sets.allSatisfy { $0.done })
        XCTAssertEqual(sled.setsText, "25 m · 100 kg, 25 m · 120 kg")
        // Changing the unit: the old measure is cleared, the new one set.
        sled.setLoggedAmount(0, .meters)
        sled.setLoggedAmount(40, .seconds)
        XCTAssertEqual(sled.sets.map { $0.meters }, [nil, nil])
        XCTAssertEqual(sled.sets.map { $0.seconds }, [40, 40])
        XCTAssertNil(sled.commonAmount(.meters))
        // Sets that differ have no amount in common.
        var rows = LiftExercise(name: "Row", sets: [LiftSet(reps: 0, kg: 0, done: true, meters: 500), LiftSet(reps: 0, kg: 0, done: true, meters: 250)])
        XCTAssertNil(rows.commonAmount(.meters))
        rows.setLoggedAmount(.nan, .meters)
        XCTAssertEqual(rows.sets.map { $0.meters }, [500, 250], "a figure that is not a number changes nothing")
    }

    func testReadingATypedDistance() {
        XCTAssertEqual(AmountText.value("1000", .meters), 1000)
        XCTAssertEqual(AmountText.value("1,000", .meters), 1000)
        XCTAssertEqual(AmountText.value(" 500 m ", .meters), 500)
        XCTAssertEqual(AmountText.value("1.5 km", .meters), 1500)
        XCTAssertEqual(AmountText.value("1,5km", .meters), 1500)
        XCTAssertEqual(AmountText.value("1,500 m", .meters), 1500)
        XCTAssertEqual(AmountText.value("2k", .meters), 2000)
        XCTAssertEqual(AmountText.value("5 kilometres", .meters), 5000)
        XCTAssertNil(AmountText.value("", .meters))
        XCTAssertNil(AmountText.value("far", .meters))
        XCTAssertNil(AmountText.value("0", .meters))
        XCTAssertNil(AmountText.value("-200", .meters))
        XCTAssertNil(AmountText.value("900 km", .meters), "past anything a session holds")
    }

    func testReadingATypedTime() {
        XCTAssertEqual(AmountText.value("4:05", .seconds), 245)
        XCTAssertEqual(AmountText.value("1:02:30", .seconds), 3750)
        XCTAssertEqual(AmountText.value("0:45", .seconds), 45)
        XCTAssertEqual(AmountText.value("45 s", .seconds), 45)
        XCTAssertEqual(AmountText.value("90sec", .seconds), 90)
        XCTAssertEqual(AmountText.value("2", .seconds), 120, "a bare number is minutes")
        XCTAssertEqual(AmountText.value("1.5 min", .seconds), 90)
        XCTAssertEqual(AmountText.value("2 mins", .seconds), 120)
        XCTAssertNil(AmountText.value("4:", .seconds))
        XCTAssertNil(AmountText.value("4:05:06:07", .seconds))
        XCTAssertNil(AmountText.value("0:00", .seconds))
    }

    func testReadingCaloriesAndReps() {
        XCTAssertEqual(AmountText.value("30", .calories), 30)
        XCTAssertEqual(AmountText.value("30 cal", .calories), 30)
        XCTAssertEqual(AmountText.value("12 reps", .reps), 12)
        XCTAssertEqual(AmountText.value("12.4", .reps), 12)
        XCTAssertNil(AmountText.value("0", .reps))
        XCTAssertNil(AmountText.value("9000", .calories))
    }

    func testAnAmountIsWrittenBackAsItWouldBeTyped() {
        XCTAssertEqual(AmountText.text(1000, .meters), "1000")
        XCTAssertEqual(AmountText.text(402.5, .meters), "402.5")
        XCTAssertEqual(AmountText.text(245, .seconds), "4:05")
        XCTAssertEqual(AmountText.text(45, .seconds), "0:45")
        XCTAssertEqual(AmountText.text(3750, .seconds), "1:02:30")
        XCTAssertEqual(AmountText.text(30, .calories), "30")
        XCTAssertEqual(AmountText.text(0, .meters), "")
        XCTAssertEqual(AmountText.text(.nan, .meters), "")
        // Each reads back to the amount it was written from.
        for (amount, measure) in [(1000.0, SetMeasure.meters), (245, .seconds), (3750, .seconds), (30, .calories), (12, .reps)] {
            XCTAssertEqual(AmountText.value(AmountText.text(amount, measure), measure), amount)
        }
    }

    func testASetsMeasuresAreSetOneAtATime() {
        var set = LiftSet(reps: 0, kg: 20, meters: 500, seconds: 105)
        set.setAmount(600, .meters)
        XCTAssertEqual(set.meters, 600)
        XCTAssertEqual(set.seconds, 105, "the time of the piece is left alone")
        XCTAssertEqual(set.kg, 20)
        set.setAmount(0, .seconds)
        XCTAssertNil(set.seconds)
        set.setAmount(12.6, .reps)
        XCTAssertEqual(set.reps, 13)
        set.setAmount(.infinity, .calories)
        XCTAssertNil(set.calories)
        XCTAssertEqual(set.amount(.meters), 600)
        XCTAssertEqual(set.amount(.calories), 0)
    }

    func testALiveSessionOpensAMovementInWhatItIsCountedIn() {
        let squat = LiftExercise.toDo(name: " Back squat ", previous: [])
        XCTAssertEqual(squat.name, "Back squat")
        XCTAssertEqual(squat.sets.map { $0.reps }, [8, 8, 8])
        XCTAssertEqual(squat.sets.map { $0.kg }, [20, 20, 20])
        XCTAssertEqual(Set(squat.sets.map { $0.id }).count, 3)

        let ski = LiftExercise.toDo(name: "SkiErg", previous: [])
        XCTAssertEqual(ski.sets.count, 1)
        XCTAssertEqual(ski.sets.first?.meters, 500)
        XCTAssertEqual(ski.sets.first?.reps, 0)
        XCTAssertEqual(ski.sets.first?.kg, 0, "an erg has no load")
        XCTAssertEqual(ski.measure, .meters)

        let sled = LiftExercise.toDo(name: "Sled push", previous: [])
        XCTAssertEqual(sled.sets.first?.meters, 25)
        XCTAssertEqual(sled.sets.first?.kg, 20)
        XCTAssertEqual(LiftExercise.toDo(name: "Push-up", previous: []).sets.first?.kg, 0, "done with the body alone")

        // Last time's sets come back whole, distance and time included, and none of them ticked.
        let before = [LiftSet(reps: 0, kg: 0, done: true, meters: 1000, seconds: 250)]
        let again = LiftExercise.toDo(name: "Row", previous: before)
        XCTAssertEqual(again.sets.first?.meters, 1000)
        XCTAssertEqual(again.sets.first?.seconds, 250)
        XCTAssertEqual(again.sets.first?.done, false)
    }

    /// A trial whose stored shape is wrong has no position; it does not stop the app.
    func testATrialWithNoDaysToABlockHasNoPosition() {
        var trial = SupplementTrial(supplement: "Creatine", outcome: .recovery, blockDays: 7, washoutDays: 2,
                                    startDay: "2026-11-01", order: [true, false])
        XCTAssertNotNil(trial.position(on: "2026-11-03"))
        trial.blockDays = 0
        XCTAssertNil(trial.position(on: "2026-11-03"))
        trial.blockDays = 7
        trial.order = []
        XCTAssertNil(trial.position(on: "2026-11-03"))
    }
}
