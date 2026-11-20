import XCTest
@testable import LumaCore

/// Racing a past effort, setting two efforts side by side, and keeping an official race typed in
/// from its results page.
final class RaceBookTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_795_000_000)

    /// A full race with every run, every station and the roxzone at round times, so the sums are plain.
    private func race(run: Double = 300, station: Double = 240, rox: Double = 450, event: String = "HYROX Dublin", at: Date? = nil,
                      format: RaceFormat = .openSingles) -> RaceEntry {
        var e = RaceEntry(event: event, startedAt: at ?? day, format: format, sex: .male)
        e.runs = Array(repeating: run, count: 8)
        e.stations = Array(repeating: station, count: 8)
        e.roxzoneS = rox
        return e
    }

    // MARK: Clock times

    func testClockTimesAreReadAsAResultsPageWritesThem() {
        XCTAssertEqual(SplitText.raceSeconds("4:35"), 275)
        XCTAssertEqual(SplitText.raceSeconds("00:04:35"), 275)
        XCTAssertEqual(SplitText.raceSeconds("1:02:33"), 3753)
        XCTAssertEqual(SplitText.raceSeconds("62:33"), 3753)
        XCTAssertEqual(SplitText.raceSeconds(" 0:45 "), 45)
        for bad in ["", "275", "4:75", "1:75:00", "4:3a", "::", "4:35:10:02", "-4:35", "4.35", "4:1234", "seven minutes"] {
            XCTAssertNil(SplitText.raceSeconds(bad), bad)
        }
        XCTAssertEqual(SplitText.raceClock(275), "4:35")
        XCTAssertEqual(SplitText.raceClock(3753), "1:02:33")
        XCTAssertEqual(SplitText.raceClock(59.6), "1:00")
        XCTAssertEqual(SplitText.raceClock(0), "0:00")
        for s in [45.0, 275, 3599, 3600, 5025] { XCTAssertEqual(SplitText.raceSeconds(SplitText.raceClock(s)), s) }
        // Typed on a form: with colons, with the number pad's full stop or comma, or as digits alone.
        XCTAssertEqual(SplitText.typedSeconds("4:35"), 275)
        XCTAssertEqual(SplitText.typedSeconds("4.35"), 275)
        XCTAssertEqual(SplitText.typedSeconds("4,35"), 275)
        XCTAssertEqual(SplitText.typedSeconds("435"), 275)
        XCTAssertEqual(SplitText.typedSeconds("45"), 45)
        XCTAssertEqual(SplitText.typedSeconds("6233"), 3753)
        XCTAssertEqual(SplitText.typedSeconds("10233"), 3753)
        XCTAssertEqual(SplitText.typedSeconds("1.02.33"), 3753)
        for bad in ["", "475", "16233", "1234567", "ab", "4:75", "4."] { XCTAssertNil(SplitText.typedSeconds(bad), bad) }
    }

    // MARK: A race typed in

    func testARaceIsKeptOnceItAddsUp() {
        let blank = RaceEntry(startedAt: day, format: .openSingles, sex: .male)
        XCTAssertFalse(blank.isReady)
        XCTAssertTrue(blank.problems.contains { $0.hasPrefix("Still to enter: Run 1,") })
        XCTAssertNil(blank.session())

        let whole = race()
        XCTAssertTrue(whole.isReady, whole.problems.joined(separator: " "))
        XCTAssertEqual(whole.total, 4770)

        // The finish time alone is enough: the roxzone is what it leaves.
        var byFinish = race()
        byFinish.roxzoneS = nil
        byFinish.finishS = 4770
        XCTAssertTrue(byFinish.isReady)
        XCTAssertEqual(byFinish.roxzone, 450)

        // Neither is asked for; both that disagree are said to.
        var neither = race()
        neither.roxzoneS = nil
        XCTAssertTrue(neither.problems.contains { $0.contains("roxzone time or the finish time") })
        var both = race()
        both.finishS = 4790
        XCTAssertTrue(both.problems.contains { $0.contains("One of them is mistyped") })
        both.finishS = 4772
        XCTAssertTrue(both.isReady, "a page rounds each split to the second")

        // A slip of the finger is caught: a kilometre in 45 seconds, a finish time under the splits.
        var slip = race()
        slip.runs[2] = 45
        XCTAssertTrue(slip.problems.contains { $0.contains("Run 3 reads 0:45") })
        var short = race()
        short.roxzoneS = nil
        short.finishS = 4000
        XCTAssertTrue(short.problems.contains { $0.contains("more than the finish time") })
        var long = race()
        long.roxzoneS = nil
        long.finishS = 9000
        XCTAssertTrue(long.problems.contains { $0.contains("too long") })
    }

    func testATypedRaceIsASessionLikeAnyOther() throws {
        let entry = race()
        let s = try XCTUnwrap(entry.session())
        XCTAssertEqual(s.kind, .fullSimulation)
        XCTAssertEqual(s.event, "HYROX Dublin")
        XCTAssertEqual(s.title, "HYROX Dublin")
        XCTAssertTrue(s.isOfficialRace)
        XCTAssertTrue(s.isComplete)
        XCTAssertEqual(s.segments.count, 31)
        XCTAssertEqual(s.runs.count, 8)
        XCTAssertEqual(s.stations.count, 8)
        XCTAssertEqual(s.roxzones.count, 15)
        XCTAssertEqual(s.totalS ?? 0, 4770, accuracy: 0.01)
        XCTAssertEqual(s.runs.compactMap { $0.durationS }.reduce(0, +), 2400, accuracy: 0.01)
        XCTAssertEqual(s.roxzones.compactMap { $0.durationS }.reduce(0, +), 450, accuracy: 0.02)
        // Every segment follows the one before with no gap.
        for (a, b) in zip(s.segments, s.segments.dropFirst()) { XCTAssertEqual(a.endMs, b.startMs) }
        // The stations are in race order, at the loads of the format.
        XCTAssertEqual(s.stations.map { $0.station }, Station.allCases.map { Optional($0) })
        XCTAssertEqual(s.stations[1].loadKg, Station.sledPush.loadKg(format: .openSingles, sex: .male))

        // Its report reads like a simulation's.
        let report = RaceAnalytics.report(s)
        XCTAssertEqual(report.runs.count, 8)
        XCTAssertEqual(report.roxzoneTotalS, 450, accuracy: 0.02)

        // It feeds the bests, and taking it away takes them away again.
        var bests = Benchmarks.rebuilt(from: [s])
        XCTAssertEqual(bests.bestStationS(.skiErg, loadKg: s.stations[0].loadKg) ?? 0, 240, accuracy: 0.01)
        XCTAssertEqual(bests.bestFullSimS?.seconds ?? 0, 4770, accuracy: 0.01)
        XCTAssertEqual(bests.typicalRoxzoneS ?? 0, 30, accuracy: 0.01)
        bests = Benchmarks.rebuilt(from: [])
        XCTAssertNil(bests.bestFullSimS)
        XCTAssertTrue(bests.stationBests.isEmpty)

        // Read back to be corrected, it is the entry it was made from, and saves as the same session.
        let again = try XCTUnwrap(RaceEntry(s))
        XCTAssertEqual(again.runs, entry.runs)
        XCTAssertEqual(again.stations, entry.stations)
        XCTAssertEqual(again.roxzoneS, 450)
        XCTAssertEqual(again.finishS, 4770)
        XCTAssertEqual(again.session(id: s.id), s)

        // A session recorded here is not an entry; a race given no name is still a race.
        XCTAssertNil(RaceEntry(HXSession(kind: .fullSimulation, format: .openSingles, sex: .male, startedAt: day)))
        XCTAssertEqual(race(event: "  ").session()?.event, "Race")
        // A session kept before races had names still reads.
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":{"fullSimulation":{}},"format":"openSingles","sex":"male","startedAt":0,"segments":[]}"#
        let read = try JSONDecoder().decode(HXSession.self, from: Data(old.utf8))
        XCTAssertNil(read.event)
        XCTAssertEqual(read.title, "Full simulation")
    }

    // MARK: Racing a past effort

    func testAPastEffortIsRacedSegmentBySegment() throws {
        let plan = RacePlanBuilder.fullRace(format: .openSingles, sex: .male)
        let then = try XCTUnwrap(race().session())
        let ghost = try XCTUnwrap(RaceGhost(then, plan: plan))
        XCTAssertEqual(ghost.totalS, 4770, accuracy: 0.01)
        XCTAssertEqual(ghost.segments.count, 31)
        XCTAssertEqual(ghost.event, "HYROX Dublin")
        // At the gun: level.
        XCTAssertEqual(ghost.lead(done: [], current: plan[0], segmentElapsed: 0, elapsed: 0), 0, accuracy: 0.001)
        // Through the first run ten seconds quicker than then: ten ahead as the roxzone begins.
        XCTAssertEqual(ghost.lead(done: [plan[0]], current: plan[1], segmentElapsed: 0, elapsed: 290), 10, accuracy: 0.001)
        // Inside a segment the lead holds until the segment has run longer than it did then.
        XCTAssertEqual(ghost.lead(done: [], current: plan[0], segmentElapsed: 200, elapsed: 200), 0, accuracy: 0.001)
        XCTAssertEqual(ghost.lead(done: [], current: plan[0], segmentElapsed: 320, elapsed: 320), -20, accuracy: 0.001)
        // Finished: the whole difference.
        XCTAssertEqual(ghost.lead(done: plan, current: nil, segmentElapsed: 0, elapsed: 4700), 70, accuracy: 0.01)
        // The same sums serve a set of targets, and an undone changeover is simply not counted.
        let targets = Dictionary(uniqueKeysWithValues: plan.map { ($0.id, 100.0) })
        XCTAssertEqual(RacePace.lead(over: targets, done: Array(plan.prefix(3)), current: plan[3], segmentElapsed: 50, elapsed: 330), 20, accuracy: 0.001)
        XCTAssertEqual(RacePace.lead(over: targets, done: Array(plan.prefix(2)), current: plan[2], segmentElapsed: 130, elapsed: 330), -30, accuracy: 0.001)

        // Only a finished effort of the same shape is raced: not one ended early, not another format, not a half.
        var early = then
        early.id = UUID()
        early.segments.removeLast(4)
        XCTAssertNil(RaceGhost(early, plan: plan))
        let pro = try XCTUnwrap(race(format: .proSingles).session())
        let newer = try XCTUnwrap(race(run: 290, at: day.addingTimeInterval(86_400 * 7)).session())
        let efforts = RaceGhost.efforts(like: .fullSimulation, format: .openSingles, sex: .male, plan: plan, in: [then, early, pro, newer])
        XCTAssertEqual(efforts.map { $0.sessionID }, [newer.id, then.id], "newest first")
        XCTAssertTrue(RaceGhost.efforts(like: .halfSimulation(secondHalf: false), format: .openSingles, sex: .male,
                                        plan: RacePlanBuilder.halfRace(secondHalf: false, format: .openSingles, sex: .male), in: [then, newer]).isEmpty)
    }

    // MARK: Side by side

    func testTwoEffortsAreSetSideBySide() throws {
        let then = try XCTUnwrap(race().session())
        var quicker = race(at: day.addingTimeInterval(86_400 * 30))
        quicker.runs[0] = 280
        quicker.stations[1] = 200
        quicker.stations[7] = 270
        quicker.roxzoneS = 420
        let now = try XCTUnwrap(quicker.session())
        let c = try XCTUnwrap(RaceComparison.of(now, against: then))
        XCTAssertEqual(c.deltaS, -60, accuracy: 0.05)
        XCTAssertEqual(c.lines.count, 17, "eight runs, eight stations and the roxzone")
        XCTAssertEqual(c.won.map { $0.label }, ["Sled Push", "Roxzone", "Run 1"])
        XCTAssertEqual(c.lost.map { $0.label }, ["Wall Balls"])
        XCTAssertEqual(c.thenEvent, "HYROX Dublin")
        // The lines add up to the whole.
        XCTAssertEqual(c.lines.reduce(0) { $0 + $1.deltaS }, c.deltaS, accuracy: 0.1)
        // Nothing is set beside itself, or beside another format.
        XCTAssertNil(RaceComparison.of(now, against: now))
        XCTAssertNil(RaceComparison.of(now, against: try XCTUnwrap(race(format: .proSingles).session())))
        // The one before it in time is the one it is set beside.
        let oldest = try XCTUnwrap(race(run: 330, at: day.addingTimeInterval(-86_400 * 30)).session())
        XCTAssertEqual(RaceComparison.withPrevious(now, in: [now, oldest, then])?.thenID, then.id)
        XCTAssertNil(RaceComparison.withPrevious(oldest, in: [now, oldest, then]))

        // Four efforts at one station are told apart by their turn.
        func practice(_ seconds: Double, at: Date) -> HXSession {
            var segments: [HXSegment] = []
            var ms: Int64 = 0
            for planned in RacePlanBuilder.stationPractice(station: .sledPush, sets: 4, format: .openSingles, sex: .male) {
                let took = Int64(planned.kind == .rest ? 60_000 : seconds * 1000)
                segments.append(HXSegment(id: planned.id, kind: planned.kind, station: planned.station, label: planned.label, startMs: ms, endMs: ms + took,
                                          loadKg: planned.loadKg))
                ms += took
            }
            return HXSession(kind: .stationPractice(.sledPush), format: .openSingles, sex: .male, startedAt: at, endedAt: at.addingTimeInterval(Double(ms) / 1000),
                             segments: segments)
        }
        let sets = try XCTUnwrap(RaceComparison.of(practice(50, at: day.addingTimeInterval(86_400)), against: practice(55, at: day)))
        XCTAssertEqual(sets.lines.map { $0.label }, ["Sled Push 1", "Sled Push 2", "Sled Push 3", "Sled Push 4"])
        XCTAssertEqual(sets.deltaS, -20, accuracy: 0.01)
    }

    // MARK: Reading a results page

    func testAReadingOfAResultsPageIsAnEntryToCheck() {
        let read: JSONValue = [
            "event": "HYROX Dublin", "date": "2026-10-04", "division": "proSingles",
            "runs": ["0:04:35", "5:01", "", "5:10", "5:12", "5:20", "5:31", "5:40"],
            "stations": ["ski_erg": "4:20", "sled_push": "3:05", "sled_pull": "4:45", "burpee_broad_jump": "5:30", "row": "4:40", "farmers_carry": "2:10",
                         "sandbag_lunges": "5:05", "wall_balls": "seven minutes"],
            "roxzone": "7:45", "finish": "1:28:02", "rank": "412",
        ]
        let e = CoachTools.raceEntry(read, format: .openSingles, sex: .female, now: day)
        XCTAssertEqual(e.event, "HYROX Dublin")
        XCTAssertEqual(e.format, .proSingles)
        XCTAssertEqual(e.sex, .female)
        XCTAssertEqual(e.runs[0], 275)
        XCTAssertNil(e.runs[2], "a split that was not read is left to be typed, not guessed")
        XCTAssertNil(e.stations[7])
        XCTAssertEqual(e.stations[0], 260)
        XCTAssertEqual(e.roxzoneS, 465)
        XCTAssertEqual(e.finishS, 5282)
        XCTAssertFalse(e.isReady)
        XCTAssertTrue(e.problems.first?.contains("Run 3, Wall Balls") ?? false)
        XCTAssertEqual(LDate.key(e.startedAt), "2026-10-04")

        // A page that names no division or day: the athlete's own format, and now.
        let bare = CoachTools.raceEntry(["runs": [], "stations": [:]], format: .doubles, sex: .male, now: day)
        XCTAssertEqual(bare.format, .doubles)
        XCTAssertEqual(bare.startedAt, day)
        XCTAssertEqual(bare.runs.count, 8)
        XCTAssertTrue(bare.runs.allSatisfy { $0 == nil })

        // The tool asks for all of it by name, and nothing is asked to be worked out.
        let tool = CoachTools.raceTool()
        XCTAssertEqual(tool.name, "submit_race")
        for key in CoachTools.raceStationNames { XCTAssertTrue(tool.inputSchema.text.contains(key), key) }
        XCTAssertEqual(CoachTools.raceStationNames.count, Station.allCases.count)
        XCTAssertTrue(CoachPrompt.raceExtraction.contains("Never work a time out"))
    }
}
