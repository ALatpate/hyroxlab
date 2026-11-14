import XCTest
@testable import LumaCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

final class StatTests: XCTestCase {
    func testPercentileAndRobustSpread() {
        XCTAssertEqual(LStat.median([3, 1, 2])!, 2)
        XCTAssertEqual(LStat.percentile([0, 10], 0.25)!, 2.5)
        // MAD of 1…9 is 2 → robust SD 2.9652
        XCTAssertEqual(LStat.robustSD((1...9).map(Double.init))!, 2.9652, accuracy: 1e-4)
    }

    func testStudentTAgainstKnownValues() {
        // Two-sided p for t = 2.0 with 10 df is 0.0734; t = 2.228 is the 5 % critical value.
        XCTAssertEqual(2 * (1 - LStat.studentTCDF(2.0, df: 10)), 0.0734, accuracy: 5e-4)
        XCTAssertEqual(2 * (1 - LStat.studentTCDF(2.228, df: 10)), 0.05, accuracy: 5e-4)
        XCTAssertEqual(LStat.studentTCDF(0, df: 7), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LStat.normalCDF(1.96), 0.975, accuracy: 1e-4)
    }

    func testTrendTests() {
        let rising: [Double] = (0..<20).map { (i: Int) -> Double in
            let wobble: Double = Double(i % 3) - 1
            return Double(i) * 0.5 + wobble * 0.2
        }
        let ts = LStat.theilSen(rising)!
        XCTAssertEqual(ts.slope, 0.5, accuracy: 0.05)
        let mk = LStat.mannKendall(rising)!
        XCTAssertGreaterThan(mk.tau, 0.9)
        XCTAssertLessThan(mk.p, 0.001)
        let flat = [5.0, 4, 6, 5, 4, 6, 5, 4, 6, 5, 4, 6]
        XCTAssertGreaterThan(LStat.mannKendall(flat)!.p, 0.3)
    }

    func testWelchAndFDR() {
        let a = [60.0, 62, 61, 63, 59, 64, 62, 61], b = [52.0, 50, 54, 51, 53, 49]
        let t = LStat.welch(a, b)!
        XCTAssertEqual(t.delta, 61.5 - 51.5, accuracy: 1e-9)
        XCTAssertLessThan(t.p, 0.0001)
        XCTAssertGreaterThan(t.g, 3)
        // Classic BH example: only the smallest p-values survive.
        let keep = LStat.benjaminiHochberg([0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.074, 0.205, 0.212, 0.216], q: 0.05)
        XCTAssertEqual(keep.filter { $0 }.count, 2)
        XCTAssertTrue(keep[0] && keep[1])
    }

    func testCorrelation() {
        let x = (0..<30).map(Double.init)
        let y = x.map { 2 * $0 + 1 }
        XCTAssertEqual(LStat.pearson(x, y)!.r, 1, accuracy: 1e-9)
        XCTAssertEqual(LStat.spearman(x, x.map { $0 * $0 })!.r, 1, accuracy: 1e-9)
        XCTAssertEqual(LStat.linearFit(x, y)!.slope, 2, accuracy: 1e-9)
    }

    func testBaselineNeedsEnoughNights() {
        XCTAssertNil(LBaseline([60, 61, 62]))
        let history: [Double] = (0..<20).map { (i: Int) -> Double in 60 + Double(i % 5) }
        let b = LBaseline(history)!
        XCTAssertEqual(b.center, 62)
        XCTAssertTrue(b.isEstablished)
        XCTAssertEqual(b.z(62 + b.spread), 1, accuracy: 1e-9)
        // A perfectly flat history still yields a usable (non-zero) spread.
        XCTAssertGreaterThan(LBaseline(Array(repeating: 50, count: 10))!.spread, 0)
    }
}

final class DateTests: XCTestCase {
    func testKeysAndWeekdays() {
        let cal = utc()
        XCTAssertEqual(LDate.adding(1, to: "2026-02-28", calendar: cal), "2026-03-01")
        XCTAssertEqual(LDate.daysBetween("2026-11-01", "2026-11-14", calendar: cal), 13)
        XCTAssertEqual(LDate.weekday("2026-11-14", calendar: cal), 6)          // a Saturday
        XCTAssertEqual(LDate.weekStart("2026-11-14", calendar: cal), "2026-11-09")
        XCTAssertEqual(LDate.range(ending: "2026-11-02", count: 3, calendar: cal), ["2026-10-31", "2026-11-01", "2026-11-02"])
        XCTAssertEqual(LFormat.timeOfDay(minutes: -50), "23:10")
        XCTAssertEqual(LFormat.grouped(12345), "12,345")
        XCTAssertEqual(LFormat.hm(minutes: 462), "7h 42m")
    }
}

final class HealthModelTests: XCTestCase {
    private let cal = utc()
    private lazy var demo = LumaDemoSource(dayCount: 120, today: Date(timeIntervalSince1970: 1_794_657_600), calendar: cal)

    func testDemoIsDeterministicAndPlausible() {
        let again = LumaDemoSource(dayCount: 120, today: Date(timeIntervalSince1970: 1_794_657_600), calendar: cal)
        XCTAssertEqual(demo.days, again.days)
        XCTAssertEqual(demo.days.count, 120)
        for d in demo.days {
            XCTAssertTrue((300...620).contains(d.sleepMin!), "sleep \(d.sleepMin!) on \(d.day)")
            XCTAssertTrue((35...110).contains(d.hrv!))
            XCTAssertTrue((6...98).contains(d.recovery!))
            XCTAssertTrue((40...70).contains(d.restingHR!))
        }
        XCTAssertGreaterThan(demo.workouts.count, 60)
    }

    func testBaselinesAndRecoveryRead() {
        let today = demo.days.last!
        let b = LBaselines.compute(days: demo.days, before: today.day)
        XCTAssertEqual(b.nights, 119)
        XCTAssertNotNil(b.hrv)
        let read = RecoveryModel.read(day: today, baselines: b)
        XCTAssertEqual(read.score, today.recovery)
        XCTAssertEqual(read.nightsToBaseline, 0)
        XCTAssertTrue(read.factors.contains { $0.metric == .hrv })
        // A night far below baseline must show HRV as the drag.
        var bad = today
        bad.hrv = b.hrv!.center - 3 * b.hrv!.spread
        bad.recovery = 20
        let r2 = RecoveryModel.read(day: bad, baselines: b)
        XCTAssertEqual(r2.band, .low)
        XCTAssertLessThan(r2.factors.first { $0.metric == .hrv }!.effect, -2)
    }

    func testBodyWatchFlagsTheUnwellSpell() {
        // The demo has an off-colour spell 21–24 days before the end.
        let day = demo.days[demo.days.count - 1 - 22]
        let w = BodyWatch.assess(day: day, baselines: LBaselines.compute(days: demo.days, before: day.day))
        XCTAssertGreaterThanOrEqual(w.level, .watch)
        let normal = demo.days[demo.days.count - 1 - 60]
        XCTAssertEqual(BodyWatch.assess(day: normal, baselines: LBaselines.compute(days: demo.days, before: normal.day)).level, .clear)
    }

    func testSleepSummary() {
        let s = SleepModel.summarize(days: demo.days, sleeps: demo.sleeps, today: demo.today, calendar: cal)
        XCTAssertEqual(s.nights.count, 120)
        let last = s.last!
        XCTAssertEqual(last.asleepMin, demo.days.last!.sleepMin!, accuracy: 1e-6)
        XCTAssertNotNil(last.score)
        XCTAssertNotNil(s.consistency)
        // Weekday bedtime is before midnight, wake around 06:30.
        XCTAssertTrue((-140...60).contains(s.typicalBedtime!))
        XCTAssertTrue((330...520).contains(s.typicalWake!))
        // Weekend nights run later than weekday nights in the demo.
        XCTAssertGreaterThan(s.socialJetlagMin!, 20)
        XCTAssertGreaterThanOrEqual(s.tonightNeedMin, SleepModel.defaultNeedMin)
        XCTAssertLessThan(s.recommendedBedtime!, s.typicalWake! - 400)
    }

    func testSleepNeedGrowsWithStrainAndDebt() {
        let base = SleepModel.need(baseMin: 465, priorStrain: 30, debtMin: 0)
        XCTAssertEqual(base, 465, accuracy: 1e-9)
        XCTAssertGreaterThan(SleepModel.need(baseMin: 465, priorStrain: 85, debtMin: 0), base + 30)
        XCTAssertEqual(SleepModel.need(baseMin: 465, priorStrain: 30, debtMin: 1000), base + 45, accuracy: 1e-9)
    }

    func testLoadModel() {
        let loads = LoadModel.dailyLoads(workouts: demo.workouts, restHR: 52, maxHR: 187, sex: .male)
        let state = LoadModel.compute(loads: loads, today: demo.today, calendar: cal)
        XCTAssertTrue(state.ready)
        XCTAssertEqual(state.days.last!.day, demo.today)
        XCTAssertTrue((0.5...1.6).contains(state.acwr!), "acwr \(state.acwr!)")
        // Constant load converges: fitness == fatigue == load, ratio 1, form 0.
        var flat: [String: Double] = [:]
        for k in LDate.range(ending: "2026-11-14", count: 300, calendar: cal) { flat[k] = 100 }
        let steady = LoadModel.compute(loads: flat, today: "2026-11-14", calendar: cal)
        XCTAssertEqual(steady.acwr!, 1, accuracy: 0.01)
        XCTAssertEqual(steady.status, .productive)
        XCTAssertNil(steady.monotony)   // zero variance: undefined, not infinite
        // A sudden doubling over the final week reads as a spike.
        for k in LDate.range(ending: "2026-11-14", count: 7, calendar: cal) { flat[k] = 320 }
        XCTAssertEqual(LoadModel.compute(loads: flat, today: "2026-11-14", calendar: cal).status, .spike)
    }

    func testTrimpIsHigherForHarderSessions() {
        let easy = SessionLoad.trimp(minutes: 60, avgHR: 120, restHR: 50, maxHR: 190, sex: .male)!
        let hard = SessionLoad.trimp(minutes: 60, avgHR: 165, restHR: 50, maxHR: 190, sex: .male)!
        XCTAssertGreaterThan(hard, easy * 2)
        XCTAssertNil(SessionLoad.trimp(minutes: 60, avgHR: 45, restHR: 50, maxHR: 190, sex: .male))
        XCTAssertGreaterThan(SessionLoad.fromStrain21(18), SessionLoad.fromStrain21(10) * 2)
    }

    func testDayCall() {
        let clear = BodyWatch(level: .clear, signals: [], title: "", detail: "")
        XCTAssertEqual(DayCall.make(recovery: 85, load: nil, sleepDebtMin: 0, watch: clear).level, .push)
        XCTAssertEqual(DayCall.make(recovery: 50, load: nil, sleepDebtMin: 0, watch: clear).level, .steady)
        XCTAssertEqual(DayCall.make(recovery: 50, load: nil, sleepDebtMin: 200, watch: clear).level, .easy)
        XCTAssertEqual(DayCall.make(recovery: 20, load: nil, sleepDebtMin: 0, watch: clear).level, .easy)
        XCTAssertEqual(DayCall.make(recovery: nil, load: nil, sleepDebtMin: 0, watch: clear).level, .unknown)
        let alert = BodyWatch(level: .alert, signals: [], title: "", detail: "")
        XCTAssertEqual(DayCall.make(recovery: 90, load: nil, sleepDebtMin: 0, watch: alert).level, .rest)
    }
}

final class AthleteTests: XCTestCase {
    private let cal = utc()

    func testOldProfileFilesStillDecode() throws {
        // Shape written by the first build: none of the newer keys exist.
        let old = #"{"onboarded":true,"format":"openSingles","fiveKSeconds":1500,"classWeekdays":[2,3,4,5,6],"runsPerWeek":3,"raceName":"","weakestStations":[],"voiceCues":true,"cueEveryKm":true,"autoPause":false,"sleepNeedHours":7.5}"#
        let p = try JSONDecoder().decode(LProfile.self, from: Data(old.utf8))
        XCTAssertEqual(p.fiveKSeconds, 1500)
        XCTAssertFalse(p.autoPause)
        XCTAssertFalse(p.isSetUp)
        XCTAssertEqual(p.resolvedMaxHR(on: Date(timeIntervalSince1970: 1_794_657_600)), (208 - 0.7 * 34).rounded())
        let round = try JSONDecoder().decode(LProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(round, p)
    }

    func testRoutineMaterializesOnceAndRespectsRemovals() {
        let slot = RoutineSlot(weekday: 2, kind: .strength, title: "Strength")
        var plan = Schedule.materialize(routine: [slot], existing: [], from: "2026-11-09", days: 14, calendar: cal)
        XCTAssertEqual(plan.map { $0.day }, ["2026-11-10", "2026-11-17"])
        plan[0].status = .removed
        let again = Schedule.materialize(routine: [slot], existing: plan, from: "2026-11-09", days: 14, calendar: cal)
        XCTAssertEqual(again.count, 2)   // the removed entry is not re-created
        XCTAssertEqual(Schedule.pruneRoutine(again, routine: [], from: "2026-11-09").count, 1)  // tombstone stays
    }

    func testPlannedSessionsMatchRecordedWorkouts() {
        let day = "2026-11-10"
        let t = LDate.startOfDay(day, calendar: cal)!.timeIntervalSince1970
        let run = PlannedSession(day: day, kind: .easyRun, title: "Easy run")
        let lift = PlannedSession(day: day, kind: .strength, title: "Strength")
        var w = LWorkout(start: t + 7 * 3600, end: t + 8 * 3600, sport: "Running")
        let saved = LDate.calendar
        LDate.calendar = cal
        defer { LDate.calendar = saved }
        w.distanceM = 9000
        let d = Schedule.days([day], planned: [run, lift], workouts: [w])[0]
        XCTAssertTrue(d.isDone(run))
        XCTAssertFalse(d.isDone(lift))
        XCTAssertTrue(d.unplannedWorkouts.isEmpty)
        let a = Schedule.adherence([d], through: day)!
        XCTAssertEqual(a.done, 1)
        XCTAssertEqual(a.planned, 2)
    }

    func testLiftMath() {
        XCTAssertEqual(LiftMath.e1RM(kg: 100, reps: 1), 100)
        XCTAssertEqual(LiftMath.e1RM(kg: 100, reps: 5), 100 * (1 + 5.0 / 30), accuracy: 1e-9)
        let s = LumaDemoContent.lifts(today: Date(timeIntervalSince1970: 1_794_657_600))
        let rec = LiftMath.records(s)
        XCTAssertNotNil(rec["Back squat"])
        XCTAssertFalse(LiftMath.lastSets("Back squat", in: s).isEmpty)
    }
}

final class FuelTests: XCTestCase {
    func testTargetsScaleWithTheDay() {
        var p = LProfile()
        p.weightKg = 80; p.heightCm = 180; p.birthYear = 1992
        let on = Date(timeIntervalSince1970: 1_794_657_600)   // 2026 → age 34
        XCTAssertEqual(FuelPlanner.restingEnergy(massKg: 80, heightCm: 180, age: 34, sex: .male), 800 + 1125 - 170 + 5)
        let rest = FuelPlanner.targets(profile: p, dayClass: .rest, on: on)
        let hard = FuelPlanner.targets(profile: p, dayClass: .hard, on: on)
        XCTAssertEqual(rest.proteinG, 160)
        XCTAssertGreaterThan(hard.kcal, rest.kcal + 500)
        XCTAssertGreaterThan(hard.carbsG, rest.carbsG * 1.8)
        XCTAssertGreaterThanOrEqual(hard.fatG, 64 - 1)
        XCTAssertEqual(rest.waterMl, 2800)
        XCTAssertEqual(hard.waterMl, 3400)
        // Energy accounts for the macros within rounding.
        XCTAssertEqual(hard.proteinG * 4 + hard.carbsG * 4 + hard.fatG * 9, hard.kcal, accuracy: 60)
    }

    func testTotalsAndDayClass() {
        let e = LumaDemoContent.fuel(today: Date(timeIntervalSince1970: 1_794_657_600 + 3 * 3600))
        let todayKey = LDate.key(Date(timeIntervalSince1970: 1_794_657_600 + 3 * 3600))
        let t = FuelTotals.of(e.filter { $0.day == todayKey })
        XCTAssertGreaterThan(t.proteinG, 60)
        XCTAssertEqual(t.waterMl, 1500)
        XCTAssertGreaterThan(t.caffeineMg, 100)
        let sim = PlannedSession(day: todayKey, kind: .simulation, title: "Sim")
        XCTAssertEqual(FuelPlanner.dayClass(planned: [sim], strain21: nil), .race)
        XCTAssertEqual(FuelPlanner.dayClass(planned: [], strain21: 4), .rest)
        XCTAssertEqual(FuelPlanner.dayClass(planned: [], strain21: 16), .hard)
        XCTAssertEqual(SupplementDose(name: "Omega-3", amount: 2, unit: "capsule").text, "2 capsules")
    }
}
