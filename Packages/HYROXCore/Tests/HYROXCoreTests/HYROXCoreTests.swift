import XCTest
@testable import HYROXCore

final class FakeClock: MonotonicClock, @unchecked Sendable {
    var ms: Int64 = 1_000_000
    func nowMs() -> Int64 { ms }
    func tick(_ s: Double) { ms += Int64(s * 1000) }
}

final class RaceModelTests: XCTestCase {
    func testFullRaceHas8Runs8Stations15Roxzones() {
        let plan = RacePlanBuilder.fullRace(format: .openSingles, sex: .male)
        XCTAssertEqual(plan.filter { $0.kind == .run }.count, 8)
        XCTAssertEqual(plan.filter { $0.kind == .station }.count, 8)
        XCTAssertEqual(plan.filter { $0.kind == .roxzone }.count, 15)
        XCTAssertEqual(plan.first?.kind, .run)
        XCTAssertEqual(plan.last?.station, .wallBalls)
    }

    func testOfficialLoads() {
        XCTAssertEqual(Station.sledPush.loadKg(format: .openSingles, sex: .male), 152)
        XCTAssertEqual(Station.sledPush.loadKg(format: .proSingles, sex: .male), 202)
        XCTAssertEqual(Station.wallBalls.loadKg(format: .openSingles, sex: .female), 4)
        XCTAssertEqual(Station.farmersCarry.loadKg(format: .proSingles, sex: .female), 48)
        XCTAssertEqual(Station.skiErg.loadKg(format: .proSingles, sex: .male), 0)
        XCTAssertEqual(Station.sledPull.loadKg(format: .doubles, sex: .male), 103)   // doubles use Open loads
    }
}

final class SplitRecorderTests: XCTestCase {
    func testAdvanceStampsMillisecondsAndAutosaveShape() {
        let clock = FakeClock()
        let plan = RacePlanBuilder.compromised(station: .wallBalls, rounds: 2, format: .openSingles, sex: .male)
        var rec = SplitRecorder(session: Session(kind: .compromisedRunning(.wallBalls), format: .openSingles, sex: .male, startedAt: Date()),
                                plan: plan, clock: clock)
        rec.start()
        XCTAssertEqual(rec.session.segments.count, 1)
        XCTAssertEqual(rec.current?.kind, .station)
        clock.tick(245.5)
        let closed = rec.advance(hr: HRSummary(avg: 160, max: 175, min: 140, sampleCount: 240, expectedCount: 245, source: .wristOptical))
        XCTAssertEqual(closed?.durationMs, 245_500)
        XCTAssertEqual(closed?.hr?.max, 175)
        XCTAssertEqual(rec.session.segments.count, 2)   // one closed, one open — persistable mid-session
        XCTAssertNil(rec.session.segments.last?.endMs)
        clock.tick(300)
        rec.advance(); clock.tick(200); rec.advance(); clock.tick(290); rec.advance()
        XCTAssertTrue(rec.isFinished)
        XCTAssertNotNil(rec.session.endedAt)
        XCTAssertEqual(rec.session.totalMs, 1_035_500)
        XCTAssertEqual(rec.session.runs.last?.paceSPerKm ?? 0, 290, accuracy: 0.01)
    }

    func testUndoMergesBack() {
        let clock = FakeClock()
        let plan = RacePlanBuilder.halfRace(secondHalf: false, format: .openSingles, sex: .male)
        var rec = SplitRecorder(session: Session(kind: .halfSimulation(secondHalf: false), format: .openSingles, sex: .male, startedAt: Date()), plan: plan, clock: clock)
        rec.start(); clock.tick(10); rec.advance()
        XCTAssertEqual(rec.currentIndex, 1)
        rec.undoLastAdvance()
        XCTAssertEqual(rec.currentIndex, 0)
        XCTAssertEqual(rec.session.segments.count, 1)
        XCTAssertNil(rec.session.segments[0].endMs)
    }

    func testSessionRoundTripsThroughJSON() throws {
        let plan = RacePlanBuilder.fullRace(format: .proSingles, sex: .female)
        var rec = SplitRecorder(session: Session(kind: .fullSimulation, format: .proSingles, sex: .female, startedAt: Date()), plan: plan, clock: FakeClock())
        rec.start(); rec.advance()
        let data = try JSONEncoder().encode(rec.session)
        let back = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(back, rec.session)
    }
}

final class RaceAnalyticsTests: XCTestCase {
    /// Builds a complete simulation with given run seconds and station seconds.
    func makeSim(runs: [Double], stations: [Double], rox: Double = 30, id: UUID = UUID()) -> Session {
        let clock = FakeClock()
        let plan = RacePlanBuilder.fullRace(format: .openSingles, sex: .male)
        var rec = SplitRecorder(session: Session(id: id, kind: .fullSimulation, format: .openSingles, sex: .male, startedAt: Date()), plan: plan, clock: clock)
        rec.start()
        var ri = 0, si = 0
        for p in plan {
            switch p.kind {
            case .run: clock.tick(runs[ri]); rec.advance(hr: HRSummary(avg: 150 + Double(ri) * 2, max: 170, min: 130, sampleCount: 100, expectedCount: 100, source: .wristOptical)); ri += 1
            case .station: clock.tick(stations[si]); rec.advance(hr: HRSummary(avg: 165, max: 180, min: 150, sampleCount: 100, expectedCount: 100, source: .wristOptical)); si += 1
            default: clock.tick(rox); rec.advance(hr: HRSummary(avg: 160, max: 175, min: 155, sampleCount: 30, expectedCount: 30, source: .wristOptical))
            }
        }
        return rec.session
    }

    func testReportNumbers() {
        let s = makeSim(runs: [270, 280, 285, 290, 295, 300, 305, 310], stations: [240, 180, 200, 230, 250, 120, 260, 420])
        let r = RaceAnalytics.report(s)
        XCTAssertEqual(r.runs.count, 8)
        XCTAssertEqual(r.stations.count, 8)
        XCTAssertEqual(r.roxzoneTotalS, 15 * 30, accuracy: 0.01)
        XCTAssertEqual(r.runs[7].driftVsFirstS ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(r.runs[1].compromisedIndex ?? 0, 280.0 / 270.0, accuracy: 1e-6)
        XCTAssertEqual(r.runs[1].afterStation, .skiErg)
        XCTAssertEqual(r.hrDriftBpm ?? 0, 14, accuracy: 0.01)
        XCTAssertNotNil(r.pacingCV)
        XCTAssertEqual(r.stations[7].hrrAfterS ?? 0, 25, accuracy: 0.01)
        XCTAssertEqual(r.totalS ?? 0, 2335 + 1900 + 450, accuracy: 0.01)
    }

    func testBenchmarksAndReadiness() {
        var b = Benchmarks()
        let s1 = makeSim(runs: Array(repeating: 300, count: 8), stations: [240, 180, 200, 230, 250, 120, 260, 420])
        let s2 = makeSim(runs: Array(repeating: 290, count: 8), stations: [230, 190, 210, 220, 240, 110, 250, 400])
        b.ingest(s1); b.ingest(s2); b.updateRoxzone(from: [s1, s2])
        XCTAssertEqual(b.bestStationS(.skiErg, loadKg: 0), 230)
        XCTAssertEqual(b.bestStationS(.sledPush, loadKg: 152), 180)
        XCTAssertNil(b.bestStationS(.sledPush, loadKg: 202))     // Pro load never attempted
        XCTAssertEqual(b.bestRun1kS?.seconds, 290)
        XCTAssertEqual(b.bestFullSimS?.sessionID, s2.id)
        XCTAssertEqual(b.typicalRoxzoneS ?? 0, 30, accuracy: 0.01)

        let open = RaceReadiness.assess(format: .openSingles, benchmarks: b, sessions: [s1, s2], sex: .male, fresh1kS: nil)
        XCTAssertEqual(open.verdict, .ready)
        XCTAssertNotNil(open.predictedLowS)
        XCTAssertLessThan(open.predictedLowS!, open.predictedHighS!)
        let pro = RaceReadiness.assess(format: .proSingles, benchmarks: b, sessions: [s1, s2], sex: .male, fresh1kS: nil)
        XCTAssertNotEqual(pro.verdict, .ready)
        XCTAssertTrue(pro.gaps.contains { $0.contains("Sled Push") })
    }
}

final class RunAnalyticsTests: XCTestCase {
    /// 5 km at a steady 5:00/km with HR rising.
    func steady(km: Double, paceS: Double) -> [RunSample] {
        var out: [RunSample] = []
        let total = Int(km * paceS)
        for t in 0...total {
            let d = Double(t) / paceS * 1000
            out.append(RunSample(tS: Double(t), distanceM: d, hr: 140 + Double(t) / Double(total) * 20, altitudeM: 10 + sin(Double(t) / 60) * 1))
        }
        return out
    }

    func testAutoLapsAndPartial() {
        let laps = RunAnalytics.laps(steady(km: 5.3, paceS: 300))
        XCTAssertEqual(laps.count, 6)
        XCTAssertEqual(laps[0].seconds, 300, accuracy: 0.5)
        XCTAssertEqual(laps[4].paceSPerKm, 300, accuracy: 0.5)
        XCTAssertTrue(laps[5].isPartial)
        XCTAssertEqual(laps[5].distanceM, 300, accuracy: 5)
    }

    func testFastestWindowAndPBs() {
        var s = steady(km: 3, paceS: 300)
        // A fast 1 km in the middle: regenerate with a surge from 1–2 km at 4:00/km.
        s = []
        var d = 0.0
        for t in 0...900 {
            let pace = (d >= 1000 && d < 2000) ? 240.0 : 300.0
            d += 1000 / pace
            s.append(RunSample(tS: Double(t), distanceM: d, hr: 150))
        }
        let f = RunAnalytics.fastest(s, distanceM: 1000)
        XCTAssertEqual(f ?? 0, 240, accuracy: 1.5)
        let pbs = RunAnalytics.personalBests(s)
        XCTAssertEqual(pbs.map(\.distanceM), [1000, 1609])
        XCTAssertNil(RunAnalytics.fastest(s, distanceM: 5000))
    }

    func testPaceSmootherFloorsAndWarmsUp() {
        var p = PaceSmoother()
        XCTAssertNil(p.push(tS: 0, distanceM: 0))
        XCTAssertNil(p.push(tS: 1, distanceM: 3))
        let v = p.push(tS: 5, distanceM: 16.5)
        XCTAssertEqual(v ?? 0, 303, accuracy: 1)
        _ = p.push(tS: 6, distanceM: 100)        // GPS jump → clamped to floor
        XCTAssertEqual(p.push(tS: 7, distanceM: 120) ?? 0, 150, accuracy: 0.01)
    }

    func testZonesAndDecoupling() {
        let z = HRZones.fromMaxHR(190)
        XCTAssertEqual(z.zone(for: 100), 1)
        XCTAssertEqual(z.zone(for: 150), 3)
        XCTAssertEqual(z.zone(for: 185), 5)
        let shares = RunAnalytics.zoneShares(steady(km: 5, paceS: 300), zones: z)
        XCTAssertEqual(shares.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-6)
        let dec = RunAnalytics.decouplingPercent(steady(km: 5, paceS: 300))
        XCTAssertNotNil(dec)
        XCTAssertGreaterThan(dec!, 0)      // HR rose at constant pace → positive decoupling
        XCTAssertGreaterThan(RunAnalytics.elevationGainM(steady(km: 1, paceS: 300)), -0.01)
    }

    func testRiegel() {
        let t10 = RunPredictor.predict(fromDistanceM: 5000, timeS: 1500, toDistanceM: 10000)
        XCTAssertEqual(t10, 1500 * pow(2, 1.06), accuracy: 0.01)
        let pbs = [PersonalBest(distanceM: 1000, seconds: 240), PersonalBest(distanceM: 5000, seconds: 1400)]
        let k = RunPredictor.fitExponent(pbs)!
        XCTAssertEqual(k, log(1400.0 / 240.0) / log(5.0), accuracy: 1e-6)
        XCTAssertNotNil(RunPredictor.range(for: 21097, pbs: pbs))
    }
}

final class ReadinessTests: XCTestCase {
    func testBaselineGating() {
        XCTAssertNil(RobustBaseline(history: Array(repeating: 60, count: 10)))
        let b = RobustBaseline(history: (0..<30).map { 60 + Double($0 % 5) })
        XCTAssertNotNil(b)
        XCTAssertEqual(b!.median, 62)
    }

    func testReadinessScoresAndAdvice() {
        let good = ReadinessInputs(charge: 85, hrvToday: 70, hrvHistory: Array(repeating: 65, count: 30) + [60, 70],
                                   rhrToday: 50, rhrHistory: Array(repeating: 51, count: 30), sleepHoursLastNight: 8,
                                   dailyLoads: Array(repeating: 200, count: 28), hasHardSessionPlannedToday: true)
        let g = ReadinessEngine.compute(good)
        XCTAssertGreaterThan(g.score, 75)
        XCTAssertEqual(g.advice, .goAsPlanned)
        XCTAssertEqual(g.drivers.count, 3)
        XCTAssertGreaterThan(g.confidence, 0.9)

        var bad = good
        bad.charge = 20; bad.hrvToday = 40; bad.sleepHoursLastNight = 4.5
        bad.dailyLoads = Array(repeating: 100, count: 27) + [900]
        let b = ReadinessEngine.compute(bad)
        XCTAssertLessThan(b.score, 40)
        XCTAssertEqual(b.advice, .rest)
        XCTAssertTrue(b.drivers.contains { $0.label.hasPrefix("Charge") })
    }

    func testLoadAndAcwr() {
        let ac = TrainingLoad.acuteChronic(dailyLoads: Array(repeating: 100, count: 60))
        XCTAssertEqual(ac.ratio ?? 0, 1, accuracy: 0.02)
        let spike = TrainingLoad.acuteChronic(dailyLoads: Array(repeating: 100, count: 56) + Array(repeating: 400, count: 4))
        XCTAssertGreaterThan(spike.ratio ?? 0, 1.3)
        let l = TrainingLoad.load(minutes: 60, rpe: 7, zoneShares: nil, hrQuality: nil)
        XCTAssertEqual(l.load, 420); XCTAssertEqual(l.method, "RPE")
    }

    func testNutrition() {
        let t = NutritionPlanner.targets(massKg: 80, heightCm: 180, age: 34, sex: .male, day: .hard)
        XCTAssertEqual(t.proteinG, 144)
        XCTAssertEqual(t.carbsG, 560)
        XCTAssertGreaterThan(t.kcal, 2800)
        XCTAssertEqual(t.waterMl, 3300)
    }
}

final class PlanTests: XCTestCase {
    func testWeekIsClassAwareAndCoversEveryDay() {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        // Monday 2026-11-16
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16))!
        let p = PlanProfile(classWeekdays: [2, 3, 4, 5, 6], fiveKSeconds: 24 * 60, targetFormat: .openSingles,
                            raceDate: cal.date(byAdding: .weekOfYear, value: 6, to: monday), runsPerWeek: 3, weakestStations: [.sledPush])
        let week = PlanGenerator.week(starting: monday, profile: p, readiness: 80, calendar: cal)
        XCTAssertEqual(week.filter { $0.type == .gymClass }.count, 5)
        XCTAssertEqual(Set(week.map { cal.component(.day, from: $0.date) }).count, 7)
        XCTAssertEqual(week.filter { $0.type.isRun }.count, 3)
        XCTAssertTrue(week.contains { $0.type == .fullSimulation || $0.type == .halfSimulation })
        XCTAssertEqual(PlanGenerator.block(weeksToRace: 6), .build)
        let longRun = week.first { $0.type == .longRun }!
        XCTAssertEqual(cal.component(.weekday, from: longRun.date), 1)  // Sunday, the last free day
    }

    func testLowReadinessDowngradesHardWork() {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16))!
        let p = PlanProfile(fiveKSeconds: 1500, raceDate: cal.date(byAdding: .weekOfYear, value: 3, to: monday))
        let hi = PlanGenerator.week(starting: monday, profile: p, readiness: 90, calendar: cal)
        let lo = PlanGenerator.week(starting: monday, profile: p, readiness: 40, calendar: cal)
        XCTAssertGreaterThanOrEqual(hi.filter { $0.type.isHard }.count, lo.filter { $0.type.isHard }.count + 1)
    }

    func testPaces() {
        let p = TrainingPaces(fiveKSeconds: 1500)
        XCTAssertEqual(p.easy, 390, accuracy: 0.01)
        XCTAssertEqual(p.hyroxRace, 330, accuracy: 0.01)
        XCTAssertEqual(Format.pace(p.threshold), "5:24")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.durationTenths(64.26), "1:04.3")
    }
}
