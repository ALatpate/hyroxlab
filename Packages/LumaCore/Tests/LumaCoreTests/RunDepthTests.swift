import XCTest
@testable import LumaCore

/// Heart rate at the easy pace, critical speed from the fastest efforts, durability across a
/// simulation and where its minutes go.
final class RunDepthTests: XCTestCase {

    /// A run at one pace with one heart rate, a sample every five seconds.
    private func run(minutes: Double, pace: Double, hr: Double) -> [RunSample] {
        stride(from: 0.0, through: minutes * 60, by: 5).map { RunSample(tS: $0, distanceM: $0 / pace * 1000, hr: hr) }
    }

    /// A run that changes pace every minute, fast then slow.
    private func surging(minutes: Int) -> [RunSample] {
        var out: [RunSample] = [RunSample(tS: 0, distanceM: 0, hr: 150)]
        var metres = 0.0
        for step in 1...(minutes * 12) {
            let minute = (step - 1) / 12
            metres += 5 / (minute % 2 == 0 ? 300.0 : 420.0) * 1000
            out.append(RunSample(tS: Double(step) * 5, distanceM: metres, hr: 150))
        }
        return out
    }

    // MARK: Heart rate at the easy pace

    func testSteadyStretchesAreFoundAndSurgesAreNot() {
        let steady = EasyPace.stretches(run(minutes: 20, pace: 360, hr: 150))
        // Twenty minutes hold five stretches of four, one after another.
        XCTAssertEqual(steady.count, 5)
        for s in steady {
            XCTAssertEqual(s.paceSPerKm, 360, accuracy: 1e-6)
            XCTAssertEqual(s.hr, 150, accuracy: 1e-9)
        }
        XCTAssertTrue(EasyPace.stretches(run(minutes: 3, pace: 360, hr: 150)).isEmpty, "too short to hold a stretch")
        // A minute fast and a minute slow averages out over four minutes, but it is not steady running.
        XCTAssertTrue(EasyPace.stretches(surging(minutes: 20)).isEmpty)
        // With no heart rate there is nothing to read.
        let blind = run(minutes: 20, pace: 360, hr: 150).map { RunSample(tS: $0.tS, distanceM: $0.distanceM) }
        XCTAssertTrue(EasyPace.stretches(blind).isEmpty)
    }

    private func easyRuns(_ rates: [Double]) -> [(day: String, samples: [RunSample])] {
        rates.enumerated().map { i, hr in (day: String(format: "2026-10-%02d", i * 3 + 1), samples: run(minutes: 20, pace: 360, hr: hr)) }
    }

    func testTheSamePaceAtALowerHeartRateReadsAsFalling() {
        let rates: [Double] = [150, 150, 148, 146, 144, 142]
        let read = EasyPace.read(runs: easyRuns(rates))!
        XCTAssertEqual(read.paceSPerKm, 360, accuracy: 1e-6)
        XCTAssertEqual(read.points.map { $0.day }, ["2026-10-01", "2026-10-04", "2026-10-07", "2026-10-10", "2026-10-13", "2026-10-16"])
        for (point, hr) in zip(read.points, rates) { XCTAssertEqual(point.hr, hr, accuracy: 1e-9) }
        XCTAssertEqual(read.direction, .falling)
        XCTAssertEqual(read.changeBpm, -7, accuracy: 1e-9)
        XCTAssertEqual(read.headline, "Heart rate at your easy pace is falling")
        XCTAssertTrue(read.detail.contains("About 7 bpm lower at 6:00 per km"), read.detail)

        // A run at another pace is not set beside these: every point is at the same pace.
        let withFast = easyRuns(rates) + [(day: "2026-10-20", samples: run(minutes: 20, pace: 270, hr: 175))]
        let mixed = EasyPace.read(runs: withFast)!
        XCTAssertEqual(mixed.points.count, 6)
        XCTAssertEqual(mixed.paceSPerKm, 360, accuracy: 1e-6)

        XCTAssertEqual(EasyPace.read(runs: easyRuns(rates.reversed()))?.direction, .rising)
        XCTAssertEqual(EasyPace.read(runs: easyRuns([150, 150, 150, 150]))?.direction, .steady)
        // Two days are too few to speak of a direction.
        XCTAssertNil(EasyPace.read(runs: easyRuns([150, 140])))
        XCTAssertNil(EasyPace.read(runs: []))
    }

    // MARK: Critical speed from the fastest efforts

    func testCriticalSpeedIsTheSlopeThroughTheFastestEfforts() {
        // Efforts that sit on one line: 3.5 m/s with 150 m in reserve.
        func effort(_ metres: Double) -> PersonalBest { PersonalBest(distanceM: metres, seconds: (metres - 150) / 3.5) }
        let three = [effort(400), effort(800), effort(5000)]
        let fit = CriticalSpeedEfforts.fit(three)!
        XCTAssertEqual(fit.cs, 3.5, accuracy: 1e-6)
        XCTAssertEqual(fit.dPrime, 150, accuracy: 1e-3)
        // With the three the published fit used all present, slower efforts in between are left out.
        let padded = three + [PersonalBest(distanceM: 1000, seconds: 300), PersonalBest(distanceM: 3000, seconds: 1000)]
        XCTAssertEqual(CriticalSpeedEfforts.fit(padded)!.cs, 3.5, accuracy: 1e-6)
        // Without all three, whatever there is gets used, down to two.
        XCTAssertEqual(CriticalSpeedEfforts.fit([effort(400), effort(1000), effort(3000)])!.cs, 3.5, accuracy: 1e-6)
        XCTAssertEqual(CriticalSpeedEfforts.fit([effort(400), effort(5000)])!.cs, 3.5, accuracy: 1e-6)

        XCTAssertNil(CriticalSpeedEfforts.fit([effort(400)]))
        // Two efforts under a minute apart say nothing about what can be held.
        XCTAssertNil(CriticalSpeedEfforts.fit([PersonalBest(distanceM: 400, seconds: 71), PersonalBest(distanceM: 800, seconds: 120)]))
        // A speed no runner holds is a bad recording, not a result.
        XCTAssertNil(CriticalSpeedEfforts.fit([PersonalBest(distanceM: 400, seconds: 60), PersonalBest(distanceM: 5000, seconds: 200)]))

        XCTAssertEqual(CriticalSpeedEfforts.pace(cs: 4, share: 0.85)!, 1000 / 3.4, accuracy: 1e-9)
        XCTAssertNil(CriticalSpeedEfforts.pace(cs: 0, share: 0.85))
    }

    func testTheFastestEffortsAreFoundInsideRuns() {
        let steady6k = stride(from: 0.0, through: 1500, by: 5).map { RunSample(tS: $0, distanceM: $0 * 4) }
        let quick1k = stride(from: 0.0, through: 200, by: 5).map { RunSample(tS: $0, distanceM: $0 * 5) }
        let bests = CriticalSpeedEfforts.fastest(in: [steady6k, quick1k])
        XCTAssertEqual(bests.map { $0.distanceM }, [400, 800, 1000, 1500, 3000, 5000])
        let expected: [Double] = [80, 160, 200, 375, 750, 1250]
        for (best, seconds) in zip(bests, expected) { XCTAssertEqual(best.seconds, seconds, accuracy: 0.01, "\(best.distanceM) m") }
        let fit = CriticalSpeedEfforts.fit(bests)!
        XCTAssertTrue((3.5...4.5).contains(fit.cs), "\(fit.cs)")
        // A run shorter than every distance gives nothing.
        XCTAssertTrue(CriticalSpeedEfforts.fastest(in: [Array(quick1k.prefix(10))]).isEmpty)
        XCTAssertTrue(CriticalSpeedEfforts.fastest(in: []).isEmpty)
    }

    // MARK: Durability

    func testDurabilityIsLateRunsAgainstEarlyRunsForTheSameSpeed() {
        let drifting = Durability.read(costs: [40, 40, 40, 40.4, 40.8, 43, 46, 48])!
        // Runs two and three against runs six and seven: the opening and the finish are left out.
        XCTAssertEqual(drifting.ratio, 44.5 / 40, accuracy: 1e-9)
        XCTAssertEqual(drifting.band, .moderate)
        XCTAssertEqual(drifting.onsetRun, 6)
        XCTAssertEqual(drifting.perRun.count, 8)
        XCTAssertEqual(drifting.headline, "Some drift late in the runs")
        XCTAssertTrue(drifting.detail.contains("1.11 times"), drifting.detail)
        XCTAssertTrue(drifting.detail.contains("from run 6"), drifting.detail)

        let held = Durability.read(costs: [40, 40, 40, 40, 40, 40.4, 40.4, 40.8])!
        XCTAssertEqual(held.band, .low)
        XCTAssertNil(held.onsetRun)
        XCTAssertEqual(held.headline, "You held your speed for the heart rate")

        XCTAssertEqual(Durability.read(costs: [40, 40, 40, 44, 46, 48, 50, 52])?.band, .high)

        // With four runs, the first two stand against the last two.
        let short = Durability.read(costs: [40, 40, 44, 46])!
        XCTAssertEqual(short.ratio, 1.125, accuracy: 1e-9)
        XCTAssertEqual(short.onsetRun, 3)
        XCTAssertNil(Durability.read(costs: [40, 41, 44]))

        XCTAssertEqual(Durability.band(1.09), .low)
        XCTAssertEqual(Durability.band(1.1), .moderate)
        XCTAssertEqual(Durability.band(1.2), .high)
    }

    /// A session of runs, each followed by a Roxzone and a station.
    private func simulation(runHR: [Double?], runS: Double = 300, stationS: Double = 250, roxS: Double = 50,
                            kind: HXSessionKind = .fullSimulation, sex: Sex = .male) -> HXSession {
        var segments: [HXSegment] = []
        var clock: Int64 = 0
        func add(_ kind: SegmentKind, _ label: String, seconds: Double, metres: Double? = nil, hr: Double? = nil) {
            let end = clock + Int64(seconds * 1000)
            let summary = hr.map { HRSummary(avg: $0, max: $0 + 5, min: $0 - 5, sampleCount: 100, expectedCount: 100, source: .wristOptical) }
            segments.append(HXSegment(id: segments.count, kind: kind, label: label, startMs: clock, endMs: end, distanceM: metres, hr: summary))
            clock = end
        }
        for (i, hr) in runHR.enumerated() {
            add(.run, "Run \(i + 1)", seconds: runS, metres: 1000, hr: hr)
            if roxS > 0 { add(.roxzone, "Roxzone", seconds: roxS) }
            add(.station, "Station \(i + 1)", seconds: stationS)
        }
        return HXSession(kind: kind, format: .openSingles, sex: sex, startedAt: Date(timeIntervalSince1970: 1_795_000_000), segments: segments)
    }

    func testDurabilityIsReadFromTheRunsOfASession() {
        let session = simulation(runHR: [150, 150, 150, 151.5, 153, 161.25, 172.5, 180])
        let read = Durability.read(session)!
        XCTAssertEqual(read.ratio, 1.1125, accuracy: 1e-9)
        XCTAssertEqual(read.onsetRun, 6)
        // Runs with no heart rate are left out; with too few left there is nothing to read.
        XCTAssertNil(Durability.read(simulation(runHR: [150, nil, nil, 152, nil, nil, 160, nil])))
    }

    // MARK: Where the minutes go

    func testTheSharesOfASimulationAreSetBesideTheReference() {
        let even = TimeSharesModel.read(simulation(runHR: Array(repeating: 150, count: 8)))!
        XCTAssertEqual(even.run, 0.5, accuracy: 1e-9)
        XCTAssertEqual(even.stations, 2000.0 / 4800, accuracy: 1e-9)
        XCTAssertEqual(even.roxzone, 400.0 / 4800, accuracy: 1e-9)
        XCTAssertEqual(even.run + even.stations + even.roxzone, 1, accuracy: 1e-9)
        XCTAssertEqual(even.referenceRun, 0.485)
        XCTAssertEqual(even.line, "Your time is split much as in the reference.")

        let slowChanges = TimeSharesModel.read(simulation(runHR: Array(repeating: 150, count: 8), roxS: 100))!
        XCTAssertEqual(slowChanges.roxzone, 800.0 / 5200, accuracy: 1e-9)
        XCTAssertEqual(slowChanges.line, "More of your time goes on the Roxzone than in the reference, by 8 points.")

        // The reference differs a little between men and women, and each adds up to the whole.
        let women = TimeSharesModel.reference(.female), men = TimeSharesModel.reference(.male)
        XCTAssertEqual(women.run + women.stations + women.roxzone, 1, accuracy: 1e-9)
        XCTAssertEqual(men.run + men.stations + men.roxzone, 1, accuracy: 1e-9)
        XCTAssertEqual(TimeSharesModel.read(simulation(runHR: Array(repeating: 150, count: 8), sex: .female))?.referenceRun, 0.479)

        // Only a full simulation is set beside full results, and only with its changeovers timed.
        XCTAssertNil(TimeSharesModel.read(simulation(runHR: Array(repeating: 150, count: 4), kind: .halfSimulation(secondHalf: false))))
        XCTAssertNil(TimeSharesModel.read(simulation(runHR: Array(repeating: 150, count: 8), roxS: 0)))
    }
}
