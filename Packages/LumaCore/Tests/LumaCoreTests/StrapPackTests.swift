import XCTest
@testable import LumaCore

/// Cues on the wrist, breathing, a workout to be led through, the notice of a newer build and a
/// route written to a file.
final class StrapPackTests: XCTestCase {

    // MARK: Zone guard

    func testZoneGuardSpeaksOnceWhenHeartRateStaysHighAndOnceWhenItIsBack() {
        var g = ZoneGuard(ceiling: 160)
        // A high reading says nothing by itself; nor do seven seconds of them.
        for t in 0..<8 { XCTAssertNil(g.feed(hr: 165, at: Double(t)), "t \(t)") }
        XCTAssertEqual(g.feed(hr: 165, at: 8), .above)
        XCTAssertTrue(g.isAbove)
        // Staying high is not said again until the quiet time has passed.
        for t in 9..<53 { XCTAssertNil(g.feed(hr: 166, at: Double(t)), "t \(t)") }
        XCTAssertEqual(g.feed(hr: 166, at: 53), .above)
        // On the line is not back: it has to come three beats under.
        XCTAssertNil(g.feed(hr: 159, at: 60))
        XCTAssertTrue(g.isAbove)
        XCTAssertEqual(g.feed(hr: 157, at: 61), .back)
        XCTAssertFalse(g.isAbove)
        XCTAssertNil(g.feed(hr: 150, at: 62))
        // A missing reading changes nothing.
        XCTAssertNil(g.feed(hr: nil, at: 63))
        XCTAssertNil(g.feed(hr: 0, at: 64))
    }

    func testZoneGuardStartsItsCountAgainAfterADip() {
        var g = ZoneGuard(ceiling: 160)
        for t in 0..<6 { XCTAssertNil(g.feed(hr: 170, at: Double(t))) }
        XCTAssertNil(g.feed(hr: 158, at: 6))
        for t in 7..<15 { XCTAssertNil(g.feed(hr: 170, at: Double(t)), "t \(t)") }
        XCTAssertEqual(g.feed(hr: 170, at: 15), .above)
    }

    func testZoneCeilingsComeFromTheAthletesOwnZones() {
        let zones = HXZones.fromMaxHR(190)
        XCTAssertEqual(ZoneGuard.ceiling(of: 2, in: zones)!, 133, accuracy: 1e-6)
        XCTAssertEqual(ZoneGuard.ceiling(of: 4, in: zones)!, 171, accuracy: 1e-6)
        // Zone 5 has no top, and there is no zone 0.
        XCTAssertNil(ZoneGuard.ceiling(of: 5, in: zones))
        XCTAssertNil(ZoneGuard.ceiling(of: 0, in: zones))
        // The two signals are told apart on the wrist.
        XCTAssertEqual(ZoneSignal.above.cue, .three)
        XCTAssertEqual(ZoneSignal.back.cue, .two)
    }

    // MARK: Go again

    func testGoAgainWaitsForHeartRateButNeverLessThanTheShortestRest() {
        var r = GoAgain(targetBpm: 130)
        // Under the target already, but the shortest rest has not passed.
        XCTAssertNil(r.feed(hr: 128, at: 5))
        XCTAssertNil(r.feed(hr: 128, at: 10))
        XCTAssertEqual(r.feed(hr: 127, at: 15), .recovered)

        // A dip that does not hold is not recovery.
        var dip = GoAgain(targetBpm: 130)
        XCTAssertNil(dip.feed(hr: 129, at: 20))
        XCTAssertNil(dip.feed(hr: 135, at: 21))
        XCTAssertNil(dip.feed(hr: 129, at: 22))
        XCTAssertNil(dip.feed(hr: 129, at: 24))
        XCTAssertEqual(dip.feed(hr: 129, at: 25), .recovered)
    }

    func testGoAgainEndsOnTheLongestRestWhenHeartRateStaysUp() {
        var slow = GoAgain(targetBpm: 130)
        for t in stride(from: 0.0, to: 180, by: 5) { XCTAssertNil(slow.feed(hr: 150, at: t), "t \(t)") }
        XCTAssertEqual(slow.feed(hr: 150, at: 180), .time)
        // With no reading at all the longest rest still ends it.
        var blind = GoAgain(targetBpm: 130)
        XCTAssertNil(blind.feed(hr: nil, at: 60))
        XCTAssertEqual(blind.feed(hr: nil, at: 181), .time)

        XCTAssertEqual(GoAgain.target(maxHR: 190), 133)
        // A share outside sensible bounds is brought back inside them.
        XCTAssertEqual(GoAgain.target(maxHR: 190, share: 0.2), 95)
        XCTAssertEqual(GoAgain.target(maxHR: 190, share: 2), 171)
    }

    // MARK: Breathing

    func testBreathPacesAndWhereABreathIs() {
        XCTAssertEqual(BreathPace.calm.cycleS, 10)
        XCTAssertEqual(BreathPace.calm.breathsPerMinute, 6)
        XCTAssertEqual(BreathPace.calm.parts.map { $0.part }, [.breatheIn, .breatheOut])
        XCTAssertEqual(BreathPace.box.parts.map { $0.part }, [.breatheIn, .holdFull, .breatheOut, .holdEmpty])
        XCTAssertEqual(Set(BreathPace.all.map { $0.id }).count, BreathPace.all.count)

        let half = BreathPace.calm.moment(at: 2)
        XCTAssertEqual(half.part, .breatheIn)
        XCTAssertEqual(half.fill, 0.5, accuracy: 1e-9)
        XCTAssertEqual(half.remainingS, 2, accuracy: 1e-9)
        XCTAssertEqual(half.breath, 0)

        let out = BreathPace.calm.moment(at: 7)
        XCTAssertEqual(out.part, .breatheOut)
        XCTAssertEqual(out.fill, 0.5, accuracy: 1e-9)

        // Three breaths done; the fourth has just turned.
        let later = BreathPace.calm.moment(at: 34)
        XCTAssertEqual(later.breath, 3)
        XCTAssertEqual(later.part, .breatheOut)
        XCTAssertEqual(later.fill, 1, accuracy: 1e-9)

        // Box breathing holds full after the breath in and empty after the breath out.
        XCTAssertEqual(BreathPace.box.moment(at: 5).part, .holdFull)
        XCTAssertEqual(BreathPace.box.moment(at: 5).fill, 1)
        XCTAssertEqual(BreathPace.box.moment(at: 13).part, .holdEmpty)
        XCTAssertEqual(BreathPace.box.moment(at: 13).fill, 0)

        // One buzz in, two out, nothing for a hold.
        XCTAssertEqual(BreathPart.breatheIn.cue, .one)
        XCTAssertEqual(BreathPart.breatheOut.cue, .two)
        XCTAssertNil(BreathPart.holdFull.cue)
        XCTAssertNil(BreathPart.holdEmpty.cue)
    }

    func testLiveVariationIsRMSSDWithMissedBeatsLeftOut() {
        // Beats alternating between 800 and 850 ms differ by 50 every time.
        let beats: [Double] = (0..<40).map { $0 % 2 == 0 ? 800 : 850 }
        XCTAssertEqual(LiveHRV.rmssd(beats)!, 50, accuracy: 1e-9)
        XCTAssertNil(LiveHRV.rmssd(Array(beats.prefix(10))), "too few beats to say")
        // A doubled interval is a missed beat: the pairs it sits in are left out.
        var withMiss = beats
        withMiss.insert(1700, at: 11)
        XCTAssertEqual(LiveHRV.rmssd(withMiss)!, 50, accuracy: 1e-9)
        // An interval no heart produces is dropped before anything is paired.
        var withNoise = beats
        withNoise.insert(120, at: 20)
        XCTAssertEqual(LiveHRV.rmssd(withNoise)!, 50, accuracy: 1e-9)

        var live = LiveHRV(windowS: 60, minBeats: 20)
        XCTAssertNil(live.rmssd)
        for i in 0..<30 { live.add([i % 2 == 0 ? 800 : 850], at: Double(i)) }
        XCTAssertEqual(live.rmssd!, 50, accuracy: 1e-9)
        XCTAssertEqual(live.heartRate!, 60_000 / 825, accuracy: 0.01)
        // Beats older than the window fall out.
        live.add([900], at: 200)
        XCTAssertEqual(live.beatCount, 1)
        XCTAssertNil(live.rmssd)
    }

    func testABreathingSittingSaysWhatChanged() {
        let up = BreathOutcome(endedAt: 1, paceID: "calm", seconds: 300, hrvBefore: 40, hrvAfter: 52, heartRateBefore: 62, heartRateAfter: 58)
        XCTAssertEqual(up.line, "Beat-to-beat variation rose from 40 to 52 ms.")
        let same = BreathOutcome(endedAt: 1, paceID: "calm", seconds: 300, hrvBefore: 40, hrvAfter: 41, heartRateBefore: 62, heartRateAfter: 61)
        XCTAssertEqual(same.line, "Beat-to-beat variation held near 41 ms.")
        // With no figure at either end there is nothing to compare.
        let blank = BreathOutcome(endedAt: 1, paceID: "calm", seconds: 300, hrvBefore: nil, hrvAfter: 52, heartRateBefore: nil, heartRateAfter: nil)
        XCTAssertNil(blank.line)
    }

    // MARK: A workout to be led through

    private func classWorkout() -> GuidedWorkout {
        GuidedWorkout(title: "Class", blocks: [
            GuidedBlock(name: "Warm-up", steps: [GuidedStep(name: "Row", measure: .time(300))]),
            GuidedBlock(name: "Part A", rounds: 3, steps: [
                GuidedStep(name: "Wall balls", measure: .reps(20), load: "6 kg", restS: 30),
                GuidedStep(name: "Run", measure: .distance(400)),
            ], restBetweenRoundsS: 60),
        ])
    }

    func testAWorkoutUnfoldsIntoEffortsAndRestsInOrder() throws {
        let w = classWorkout()
        XCTAssertTrue(w.isReady, "\(w.problems)")
        let segs = w.segments
        // Row, then three rounds of wall balls, rest, run, with a rest between rounds and none at the end.
        XCTAssertEqual(segs.count, 12)
        XCTAssertEqual(segs.filter { !$0.isRest }.count, 7)
        XCTAssertEqual(segs.map { $0.id }, Array(0..<12))
        XCTAssertEqual(segs[0].title, "Row")
        XCTAssertEqual(segs[0].seconds, 300)
        XCTAssertEqual(segs[0].detail, "5:00")
        XCTAssertEqual(segs[1].title, "Wall balls")
        XCTAssertEqual(segs[1].detail, "20 reps · 6 kg")
        XCTAssertNil(segs[1].seconds)
        XCTAssertEqual(segs[1].round, 1)
        XCTAssertEqual(segs[1].rounds, 3)
        XCTAssertTrue(segs[2].isRest)
        XCTAssertEqual(segs[2].seconds, 30)
        XCTAssertEqual(segs[2].detail, "30 s")
        XCTAssertEqual(segs[3].detail, "400 m")
        XCTAssertTrue(segs[4].isRest)
        XCTAssertEqual(segs[4].detail, "1:00")
        XCTAssertEqual(segs.last?.title, "Run")
        XCTAssertEqual(segs.last?.round, 3)
        // Some stretches last until the athlete moves on, so there is no set length for the whole.
        XCTAssertNil(w.plannedS)
        XCTAssertEqual(w.summary, "2 blocks, 7 efforts")
        // It survives being saved and read back.
        let data = try JSONEncoder().encode(w)
        XCTAssertEqual(try JSONDecoder().decode(GuidedWorkout.self, from: data), w)
    }

    func testATimedWorkoutAddsUpAndAnUnusableOneSaysWhy() {
        let emom = GuidedWorkout(title: "EMOM 12", blocks: [
            GuidedBlock(name: "EMOM 12", rounds: 6, steps: [GuidedStep(name: "Burpees", measure: .time(60)), GuidedStep(name: "Row", measure: .time(60))]),
        ])
        XCTAssertEqual(emom.plannedS, 720)
        XCTAssertEqual(GuidedWorkout.lengthText(90), "1:30")
        XCTAssertEqual(GuidedWorkout.lengthText(45), "45 s")

        XCTAssertEqual(GuidedWorkout(title: "x", blocks: []).problems, ["There is nothing to do in it yet."])
        XCTAssertFalse(GuidedWorkout(title: "x", blocks: [GuidedBlock(name: "A", rounds: 0, steps: [GuidedStep(name: "Run", measure: .open)])]).isReady)
        XCTAssertFalse(GuidedWorkout(title: "x", blocks: [GuidedBlock(name: "A", steps: [GuidedStep(name: "Squat", measure: .reps(0))])]).isReady)
        XCTAssertFalse(GuidedWorkout(title: "x", blocks: [GuidedBlock(name: "A", steps: [])]).isReady)
        let long = GuidedWorkout(title: "x", blocks: [
            GuidedBlock(name: "A", rounds: 50, steps: (0..<5).map { GuidedStep(name: "Move \($0)", measure: .time(20), restS: 10) }),
        ])
        XCTAssertEqual(long.problems, ["It is too long to lead through in one go."])
    }

    func testAWorkoutIsReadFromWhatTheModelHandsOver() {
        let input = JSONValue.parse(#"{"title":"Tuesday class","sport":"HYROX","blocks":[{"name":"Tabata","rounds":8,"steps":[{"name":"Wall balls","seconds":20,"rest_s":10,"load":"6 kg"}]},{"name":"Finisher","rounds":1,"steps":[{"name":"Run","distance_m":1000},{"name":"","reps":5},{"name":"Farmers carry","reps":0}]},{"name":"Empty","rounds":2,"steps":[]}],"note":"Scale as needed"}"#)!
        let read = GuidedReading.workout(from: input)!
        XCTAssertEqual(read.title, "Tuesday class")
        XCTAssertEqual(read.sport, "HYROX")
        // A block with no steps is dropped, and so is a step with no name.
        XCTAssertEqual(read.blocks.map { $0.name }, ["Tabata", "Finisher"])
        XCTAssertEqual(read.blocks[0].rounds, 8)
        XCTAssertEqual(read.blocks[0].steps, [GuidedStep(name: "Wall balls", measure: .time(20), load: "6 kg", restS: 10)])
        XCTAssertEqual(read.blocks[1].steps.map { $0.name }, ["Run", "Farmers carry"])
        XCTAssertEqual(read.blocks[1].steps[0].measure, .distance(1000))
        // No reps is not a count: the step lasts until the athlete moves on.
        XCTAssertEqual(read.blocks[1].steps[1].measure, .open)
        XCTAssertEqual(read.note, "Scale as needed")
        XCTAssertTrue(read.isReady, "\(read.problems)")
        // Tabata: eight rounds of 20 on and 10 off, less the rest after the last one.
        XCTAssertEqual(GuidedWorkout(title: "t", blocks: [read.blocks[0]]).plannedS, 230)

        XCTAssertNil(GuidedReading.workout(from: ["title": "x"]))
        XCTAssertNil(GuidedReading.workout(from: ["blocks": .array([])]))
        // Values outside the limits are brought back inside them.
        let wild = GuidedReading.workout(from: JSONValue.parse(#"{"blocks":[{"name":"A","rounds":900,"steps":[{"name":"Plank","seconds":99999,"rest_s":-5}]}]}"#)!)!
        XCTAssertEqual(wild.blocks[0].rounds, GuidedWorkout.maxRounds)
        XCTAssertEqual(wild.blocks[0].steps[0].measure, .time(GuidedWorkout.maxStepS))
        XCTAssertEqual(wild.blocks[0].steps[0].restS, 0)
        XCTAssertEqual(wild.title, "Workout")
        XCTAssertEqual(wild.sport, "Class")

        let tool = GuidedReading.tool()
        XCTAssertEqual(tool.name, GuidedReading.toolName)
        XCTAssertEqual(tool.inputSchema["properties"]?["blocks"]?["items"]?["properties"]?["steps"]?["type"]?.string, "array")
        XCTAssertTrue(GuidedReading.system.contains(GuidedReading.toolName))
    }

    // MARK: A newer build

    func testTheListingIsReadForItsNewestBuild() {
        // The listing as AltStore reads it: the build is written as text.
        let listing = #"{"name":"Luma","apps":[{"name":"Luma","versions":[{"version":"12.1.0","buildVersion":"21","date":"2026-11-22"},{"version":"12.1.0","buildVersion":"20"}]}]}"#
        XCTAssertEqual(NewBuild.listed(from: listing), ListedBuild(version: "12.1.0", build: 21, date: "2026-11-22"))
        XCTAssertEqual(NewBuild.listed(from: #"{"apps":[{"versions":[{"version":"12.1.0","buildVersion":22}]}]}"#)?.build, 22)
        XCTAssertNil(NewBuild.listed(from: "not json"))
        XCTAssertNil(NewBuild.listed(from: #"{"apps":[]}"#))
        XCTAssertNil(NewBuild.listed(from: #"{"apps":[{"versions":[{"version":"12.1.0"}]}]}"#))

        XCTAssertEqual(NewBuild.newer(ListedBuild(version: "12.1.0", build: 21), than: 20)?.build, 21)
        XCTAssertNil(NewBuild.newer(ListedBuild(version: "12.1.0", build: 20), than: 20))
        XCTAssertNil(NewBuild.newer(ListedBuild(version: "12.1.0", build: 19), than: 20))
        // With the installed build unknown, nothing is claimed.
        XCTAssertNil(NewBuild.newer(ListedBuild(version: "12.1.0", build: 21), than: nil))
        XCTAssertNil(NewBuild.newer(nil, than: 20))
        XCTAssertEqual(NewBuild.title(ListedBuild(version: "12.1.0", build: 21)), "Build 21 is out")
        XCTAssertTrue(NewBuild.howTo.contains("pull the list down"))
    }

    func testTheListingIsLookedAtOnceADayAndOnlyWhenSwitchedOn() {
        XCTAssertTrue(NewBuild.due(enabled: true, lastLookedAt: 0, now: 1000))
        XCTAssertFalse(NewBuild.due(enabled: false, lastLookedAt: 0, now: 1000))
        XCTAssertFalse(NewBuild.due(enabled: true, lastLookedAt: 1000, now: 1000 + 3600))
        XCTAssertTrue(NewBuild.due(enabled: true, lastLookedAt: 1000, now: 1000 + 86_400))
        // A clock that went backwards does not park the next look in the future.
        XCTAssertTrue(NewBuild.due(enabled: true, lastLookedAt: 5000, now: 1000))
    }

    // MARK: A route as a file

    func testARouteIsWrittenAsGPX() {
        let samples = [RunSample(tS: 0, distanceM: 0, hr: 120, altitudeM: 12.34, lat: 53.3331, lon: -6.2489),
                       RunSample(tS: 5, distanceM: 15, lat: 53.3332, lon: -6.249),
                       RunSample(tS: 10, distanceM: 30, hr: 131.6),
                       RunSample(tS: 15, distanceM: 45, lat: 0, lon: 0)]
        // A sample with no position, or with the empty position a lost fix leaves, is not a point.
        let points = GPX.points(from: samples)
        XCTAssertEqual(points.count, 2)
        let doc = GPX.document(name: "Outdoor run <5k> & back", startedAt: Date(timeIntervalSince1970: 1_795_000_000), points: points)!
        XCTAssertTrue(doc.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(doc.contains("<gpx version=\"1.1\" creator=\"Luma\""))
        XCTAssertTrue(doc.contains("<name>Outdoor run &lt;5k&gt; &amp; back</name>"))
        XCTAssertTrue(doc.contains("<trkpt lat=\"53.333100\" lon=\"-6.248900\"><ele>12.3</ele><time>2026-11-18T11:06:40Z</time>"))
        XCTAssertTrue(doc.contains("<trkpt lat=\"53.333200\" lon=\"-6.249000\"><time>2026-11-18T11:06:45Z</time></trkpt>"))
        XCTAssertEqual(doc.components(separatedBy: "<trkpt").count - 1, 2)
        // Heart rate is written only where there was a reading.
        XCTAssertEqual(doc.components(separatedBy: "<gpxtpx:hr>").count - 1, 1)
        XCTAssertTrue(doc.contains("<gpxtpx:hr>120</gpxtpx:hr>"))
        XCTAssertTrue(doc.hasSuffix("</gpx>\n"))
        // One point is not a line.
        XCTAssertNil(GPX.document(name: "x", startedAt: Date(timeIntervalSince1970: 0), points: Array(points.prefix(1))))
        XCTAssertEqual(GPX.fileName(name: "Outdoor run / 5k", day: "2026-11-21"), "Luma Outdoor run 5k 2026-11-21.gpx")
        XCTAssertEqual(GPX.fileName(name: "//", day: "2026-11-21"), "Luma run 2026-11-21.gpx")
    }
}
