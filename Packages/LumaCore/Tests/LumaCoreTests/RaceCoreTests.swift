import XCTest
@testable import LumaCore

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
        var rec = SplitRecorder(session: HXSession(kind: .compromisedRunning(.wallBalls), format: .openSingles, sex: .male, startedAt: Date()),
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
        var rec = SplitRecorder(session: HXSession(kind: .halfSimulation(secondHalf: false), format: .openSingles, sex: .male, startedAt: Date()), plan: plan, clock: clock)
        rec.start(); clock.tick(10); rec.advance()
        XCTAssertEqual(rec.currentIndex, 1)
        rec.undoLastAdvance()
        XCTAssertEqual(rec.currentIndex, 0)
        XCTAssertEqual(rec.session.segments.count, 1)
        XCTAssertNil(rec.session.segments[0].endMs)
    }

    func testSessionRoundTripsThroughJSON() throws {
        let plan = RacePlanBuilder.fullRace(format: .proSingles, sex: .female)
        var rec = SplitRecorder(session: HXSession(kind: .fullSimulation, format: .proSingles, sex: .female, startedAt: Date()), plan: plan, clock: FakeClock())
        rec.start(); rec.advance()
        let data = try JSONEncoder().encode(rec.session)
        let back = try JSONDecoder().decode(HXSession.self, from: data)
        XCTAssertEqual(back, rec.session)
    }
}

final class RaceAnalyticsTests: XCTestCase {
    /// Builds a complete simulation with given run seconds and station seconds.
    func makeSim(runs: [Double], stations: [Double], rox: Double = 30, id: UUID = UUID(), startedAt: Date = Date()) -> HXSession {
        let clock = FakeClock()
        let plan = RacePlanBuilder.fullRace(format: .openSingles, sex: .male)
        var rec = SplitRecorder(session: HXSession(id: id, kind: .fullSimulation, format: .openSingles, sex: .male, startedAt: startedAt), plan: plan, clock: clock)
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
        XCTAssertEqual(r.stations[0].hrrAfterS ?? 0, 25, accuracy: 0.01)
        XCTAssertNil(r.stations[7].hrrAfterS)   // no roxzone after the last station
        XCTAssertEqual(r.totalS ?? 0, 2335 + 1900 + 450, accuracy: 0.01)
    }

    func testBenchmarksAndReadiness() {
        var b = Benchmarks()
        let s1 = makeSim(runs: Array(repeating: 300, count: 8), stations: [240, 180, 200, 230, 250, 120, 260, 420],
                         startedAt: Date(timeIntervalSince1970: 1_780_000_000))
        let s2 = makeSim(runs: Array(repeating: 290, count: 8), stations: [230, 190, 210, 220, 240, 110, 250, 400],
                         startedAt: Date(timeIntervalSince1970: 1_781_000_000))
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

        // A shared race is faster than a solo one on the same athlete's times, and says what it assumed.
        let doubles = RaceReadiness.assess(format: .doubles, benchmarks: b, sessions: [s1, s2], sex: .male, fresh1kS: 250)
        let relay = RaceReadiness.assess(format: .relay, benchmarks: b, sessions: [s1, s2], sex: .male, fresh1kS: 250)
        XCTAssertNil(open.assumption)
        XCTAssertNotNil(doubles.assumption)
        XCTAssertNotNil(relay.assumption)
        let mid: (FormatReadiness) -> Double = { r in ((r.predictedLowS ?? 0) + (r.predictedHighS ?? 0)) / 2 }
        XCTAssertLessThan(mid(doubles), mid(open))
        XCTAssertLessThan(mid(relay), mid(open))
        // Calibrated on the latest simulation, the solo prediction reproduces that simulation's time,
        // all fifteen transitions included.
        let simTotal: Double = s2.totalS ?? 0
        let expectedSim: Double = 2320.0 + 1850.0 + 450.0          // eight runs, eight stations, fifteen transitions
        XCTAssertEqual(mid(open), simTotal, accuracy: 0.5)
        XCTAssertEqual(simTotal, expectedSim, accuracy: 0.01)
        // Relay kilometres are run near the fresh 1 km time, not at race pace.
        let relayRuns: Double = 250.0 * 1.03 * 8.0
        let expectedRelay: Double = 1830.0 + 3.0 + relayRuns + 450.0
        XCTAssertEqual(mid(relay), expectedRelay, accuracy: 0.5)
        // The running in a doubles race is still the athlete's own eight kilometres.
        XCTAssertGreaterThan(mid(doubles), 2320.0)
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
        let z = HXZones.fromMaxHR(190)
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
}
