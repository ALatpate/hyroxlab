import XCTest
@testable import LumaCore

// Counting from wrist motion, checked against motion made up for the purpose: gravity, a movement of a
// known rate, and a little noise. Every claim about a rate is made for several rates, so that a method
// which only ever answered one number could not pass.

/// Numbers that look random and are the same on every run.
private struct Dice {
    var state: UInt64

    init(_ seed: UInt64) { state = seed }

    /// The next number, from minus one up to one.
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / 9007199254740992.0 * 2 - 1
    }
}

private typealias Pull = (Double, Double, Double)

/// What the wrist feels lying still: gravity, off the axes.
private let gravity: Pull = (0.30, -0.20, 0.93)

/// Wrist motion made up a second at a time, as the strap would send it.
private struct MadeMotion {
    var seconds: [MotionSecond] = []
    var ts = 1_800_000_000
    /// How far the phone's clock is ahead of the strap's.
    var clockAhead = 3.4
    var noise = 0.01
    var dice = Dice(7)

    /// Adds seconds of motion. `pull` gives the acceleration in g at a time since this part began.
    /// `rate` is how often the wrist is really read: only the first hundred readings of each second
    /// are kept, as the strap keeps them. `offset` gives every second a shift of its own.
    mutating func add(_ count: Int, rate: Double = 100, offset: Double = 0, _ pull: (Double) -> Pull) {
        for k in 0..<count {
            var columns = [Int16](repeating: 0, count: 600)
            var off: Pull = (0, 0, 0)
            if offset > 0 { off = (offset * dice.next(), offset * dice.next(), offset * dice.next()) }
            for i in 0..<100 {
                let v = pull(Double(k) + Double(i) / rate)
                columns[i] = MadeMotion.counts(v.0 + off.0 + noise * dice.next())
                columns[100 + i] = MadeMotion.counts(v.1 + off.1 + noise * dice.next())
                columns[200 + i] = MadeMotion.counts(v.2 + off.2 + noise * dice.next())
            }
            let late = 0.12 + 0.05 * (dice.next() + 1)
            let received = Int(((Double(ts) + 1 + clockAhead + late) * 1000).rounded())
            seconds.append(MotionSecond(ts: ts, receivedMs: received, columns: columns))
            ts += 1
        }
    }

    static func counts(_ g: Double) -> Int16 { Int16(max(-32768, min(32767, (g * 4096).rounded()))) }

    /// When the first reading was taken, by the phone's clock.
    var start: Double { Double(seconds[0].ts) + clockAhead }
    var track: MotionTrack { MotionTrack.build(seconds) }
}

private func still(_ t: Double) -> Pull { gravity }

/// A wrist that is still, read with a drift that starts again at every second.
private func ramp(_ t: Double) -> Pull {
    (gravity.0, gravity.1, gravity.2 + 0.25 * (t.truncatingRemainder(dividingBy: 1) - 0.5))
}

/// A stroke or rep: the wrist goes out and back along one line, so many times a minute.
private func strokes(_ perMinute: Double, size: Double = 0.35) -> (Double) -> Pull {
    let f = perMinute / 60
    let n = (0.6 * 0.6 + 0.7 * 0.7 + 0.39 * 0.39).squareRoot()
    let d: Pull = (0.6 / n, 0.7 / n, 0.39 / n)
    return { t in
        let s = size * sin(2 * Double.pi * f * t) + 0.3 * size * sin(4 * Double.pi * f * t + 0.7)
        return (gravity.0 + d.0 * s, gravity.1 + d.1 * s, gravity.2 + d.2 * s)
    }
}

/// Footfalls: a jolt at each step, and the arm swinging once for every two. `weak` makes every other
/// step land more softly, as one foot does.
private func footfalls(_ perMinute: Double, size: Double = 1.2, weak: Double? = nil, swing: Double = 0.3) -> (Double) -> Pull {
    let f = perMinute / 60
    return { t in
        let phase = (t * f).truncatingRemainder(dividingBy: 1)
        let odd = Int(t * f) % 2 == 1
        let jolt = sin(Double.pi * phase / 0.25)
        let pulse = phase < 0.25 ? jolt * jolt : 0
        let land = odd ? (weak ?? size) : size
        return (gravity.0 + swing * sin(Double.pi * f * t), gravity.1, gravity.2 + land * pulse)
    }
}

final class MotionTests: XCTestCase {

    // MARK: The file

    /// A file laid out as the strap layer lays it out, with nothing packed: the unpacking is the phone's.
    private func file(_ blocks: [[MotionSecond]], rate: Int = 100, magic: String = "NOOPIMU2") -> Data {
        func big(_ value: Int, _ bytes: Int) -> [UInt8] { (0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * (bytes - 1 - $0))) } }
        var out = Array(magic.utf8) + big(1_799_999_000, 8) + big(rate, 4) + big(6, 4)
        for block in blocks {
            var raw: [UInt8] = []
            for second in block {
                raw += big(second.ts, 8) + big(second.receivedMs, 8) + big(1200, 4)
                for value in second.columns {
                    raw.append(UInt8(truncatingIfNeeded: value)); raw.append(UInt8(truncatingIfNeeded: value >> 8))
                }
            }
            out += big(block.count, 4) + big(raw.count, 4) + big(raw.count, 4) + raw
        }
        return Data(out)
    }

    func testAFileOfMotionIsReadBackAsItWasWritten() {
        var made = MadeMotion()
        made.add(35, strokes(30))
        made.seconds[3].columns[0] = -32768
        made.seconds[3].columns[599] = 32767
        let data = file([Array(made.seconds[0..<30]), Array(made.seconds[30..<35])])
        let same: (Data, Int) -> Data? = { packed, size in packed.count == size ? packed : nil }
        XCTAssertEqual(MotionFile.seconds(from: data, inflate: same), made.seconds)

        // Not a motion file, or not at a hundred readings a second: nothing is read from it.
        XCTAssertTrue(MotionFile.seconds(from: file([made.seconds], magic: "NOOPIMU1"), inflate: same).isEmpty)
        XCTAssertTrue(MotionFile.seconds(from: file([Array(made.seconds[0..<30])], rate: 50), inflate: same).isEmpty)
        XCTAssertTrue(MotionFile.seconds(from: Data([1, 2, 3]), inflate: same).isEmpty)

        // A block that will not unpack ends the reading; what came before it is kept.
        var calls = 0
        let failsSecond: (Data, Int) -> Data? = { packed, _ in calls += 1; return calls == 1 ? packed : nil }
        XCTAssertEqual(MotionFile.seconds(from: data, inflate: failsSecond).count, 30)
        // A file cut off part-way through a block gives the whole blocks before the cut.
        XCTAssertEqual(MotionFile.seconds(from: data.prefix(data.count - 100), inflate: same).count, 30)
    }

    // MARK: Rates that were put in come back out

    private func count(_ kind: MotionKind, seconds: Int = 120, _ pull: (Double) -> Pull) -> MotionCount? {
        var made = MadeMotion()
        made.add(seconds, pull)
        return MotionCounter.count(made.track, from: made.start, to: made.start + Double(seconds), kind: kind)
    }

    func testStrokesAndRepsAreCountedAtEveryRatePutIn() throws {
        let cases: [(MotionKind, [Double], Int)] = [
            (.row, [18, 26, 31, 38], 120),
            (.skiErg, [28, 36, 47, 66], 120),
            (.work, [12, 22, 47, 58], 120),
            (.wallBalls, [14, 20, 35], 150),
            (.sledPull, [18, 40], 120),
            (.burpees, [8, 17, 24], 180),
        ]
        for (kind, rates, seconds) in cases {
            for rate in rates {
                let c = try XCTUnwrap(count(kind, seconds: seconds, strokes(rate)), "\(kind) at \(rate)")
                let put = rate * Double(seconds) / 60
                XCTAssertEqual(Double(c.count), put, accuracy: 1, "\(kind) at \(rate)")
                XCTAssertEqual(try XCTUnwrap(c.perMinute), rate, accuracy: rate * 0.01, "\(kind) at \(rate)")
                XCTAssertGreaterThan(c.steady, 0.95)
            }
        }
    }

    func testStepsAreCountedAtEveryPacePutIn() throws {
        let cases: [(MotionKind, [Double], Double, Double)] = [
            (.run, [150, 162, 176, 196], 1.2, 0.3),
            (.walk, [84, 100, 132], 0.5, 0.15),
            (.lunges, [24, 36, 52], 0.4, 0),
        ]
        for (kind, paces, size, swing) in cases {
            for pace in paces {
                let c = try XCTUnwrap(count(kind, footfalls(pace, size: size, swing: swing)), "\(kind) at \(pace)")
                XCTAssertEqual(try XCTUnwrap(c.perMinute), pace, accuracy: pace * 0.01, "\(kind) at \(pace)")
                XCTAssertEqual(Double(c.count), pace * 2, accuracy: pace * 0.02, "\(kind) at \(pace)")
            }
        }
    }

    /// One foot lands harder than the other, so the wrist repeats best every two steps; and with no
    /// jolt at all, only the arm's swing repeats. Either way a step is a step.
    func testUnevenFeetAreStillCountedAStepAtATime() throws {
        for pace in [150.0, 172, 186] {
            let c = try XCTUnwrap(count(.run, footfalls(pace, weak: 0.5)))
            XCTAssertEqual(try XCTUnwrap(c.perMinute), pace, accuracy: pace * 0.01, "uneven run at \(pace)")
        }
        let walk = try XCTUnwrap(count(.walk, footfalls(126, size: 0.6, weak: 0.25, swing: 0.15)))
        XCTAssertEqual(try XCTUnwrap(walk.perMinute), 126, accuracy: 1.3)
        let lunges = try XCTUnwrap(count(.lunges, footfalls(40, size: 0.5, weak: 0.3, swing: 0)))
        XCTAssertEqual(try XCTUnwrap(lunges.perMinute), 40, accuracy: 0.4)
        XCTAssertEqual(Double(lunges.count), 80, accuracy: 1)
        let swingOnly = try XCTUnwrap(count(.run, footfalls(170, size: 0, swing: 0.4)))
        XCTAssertEqual(try XCTUnwrap(swingOnly.perMinute), 170, accuracy: 1.7)
    }

    func testARateThatDriftsIsFollowed() throws {
        // From 22 a minute to 30 over two minutes: 52 strokes in all.
        let drifting: (Double) -> Pull = { t in
            let from = 22.0 / 60, to = 30.0 / 60
            let phase = 2 * Double.pi * (from * t + (to - from) * t * t / 240)
            let s = 0.35 * sin(phase) + 0.1 * sin(2 * phase + 0.7)
            return (gravity.0 + 0.6 * s, gravity.1 + 0.7 * s, gravity.2 + 0.39 * s)
        }
        let c = try XCTUnwrap(count(.row, drifting))
        XCTAssertEqual(Double(c.count), 52, accuracy: 1)
    }

    // MARK: What is not a repeat is not counted

    func testStillnessAndShakingCountNothing() throws {
        let quiet = try XCTUnwrap(count(.row, still))
        XCTAssertEqual(quiet.count, 0)
        XCTAssertNil(quiet.perMinute)
        XCTAssertEqual(quiet.steady, 0)
        XCTAssertEqual(quiet.coveredS, 120, accuracy: 1)

        for kind in [MotionKind.row, .work, .run, .burpees] {
            var shake = Dice(99)
            let shaken = count(kind) { _ in
                let x = shake.next(), y = shake.next(), z = shake.next()
                return (gravity.0 + 0.3 * x, gravity.1 + 0.3 * y, gravity.2 + 0.3 * z)
            }
            let c = try XCTUnwrap(shaken)
            XCTAssertEqual(c.count, 0, "\(kind)")
            XCTAssertNil(c.perMinute, "\(kind)")
        }
        // Nothing is counted for a part that is a rest, or a sled being pushed.
        XCTAssertNil(count(.rest, strokes(30)))
        XCTAssertNil(count(.sledPush, strokes(30)))
    }

    func testAPauseBetweenTwoSetsIsNotCountedForEither() throws {
        // Forty seconds at 30 a minute, thirty seconds still, forty more: forty strokes.
        var made = MadeMotion()
        made.add(40, strokes(30)); made.add(30, still); made.add(40, strokes(30))
        for kind in [MotionKind.row, .work, .skiErg] {
            let c = try XCTUnwrap(MotionCounter.count(made.track, from: made.start, to: made.start + 110, kind: kind))
            XCTAssertEqual(Double(c.count), 40, accuracy: 1.5, "\(kind)")
            XCTAssertEqual(try XCTUnwrap(c.perMinute), 30, accuracy: 0.3)
        }
        // Shaking the arms out between the sets is movement, and is not strokes.
        var shake = Dice(11)
        var loose = MadeMotion()
        loose.add(40, strokes(30))
        loose.add(30) { _ in
            let x = shake.next(), y = shake.next(), z = shake.next()
            return (gravity.0 + 0.25 * x, gravity.1 + 0.25 * y, gravity.2 + 0.25 * z)
        }
        loose.add(40, strokes(30))
        let c = try XCTUnwrap(MotionCounter.count(loose.track, from: loose.start, to: loose.start + 110, kind: .row))
        XCTAssertEqual(Double(c.count), 40, accuracy: 3)
        XCTAssertLessThan(c.steady, 0.9)
    }

    /// Strokes of very uneven length do not keep a beat. They are under-counted, never over-counted,
    /// and the share of the time a beat was kept says so.
    func testStrokesTooUnevenToFollowAreLeftOutAndSaidToBe() throws {
        func uneven(_ by: Double) -> (pull: (Double) -> Pull, edges: [Double]) {
            var dice = Dice(5)
            var edges = [0.0]
            while edges[edges.count - 1] < 200 { edges.append(edges[edges.count - 1] + 60.0 / 28 * (1 + by * dice.next())) }
            let line = strokes(1)
            let marks = edges
            // One whole stroke between each pair of edges.
            let pull: (Double) -> Pull = { t in
                let k = (marks.firstIndex(where: { $0 > t }) ?? 1) - 1
                return line((t - marks[k]) / (marks[k + 1] - marks[k]) * 60)
            }
            return (pull, marks)
        }
        let mild = uneven(0.1)
        let put = Double(mild.edges.filter { $0 < 120 }.count - 1)
        let followed = try XCTUnwrap(count(.row, mild.pull))
        XCTAssertEqual(Double(followed.count), put, accuracy: 2)

        let wild = uneven(0.3)
        let lost = try XCTUnwrap(count(.row, wild.pull))
        XCTAssertLessThan(lost.count, wild.edges.filter { $0 < 120 }.count)
        XCTAssertLessThan(lost.steady, 0.8)
    }

    // MARK: Parts, gaps and clocks

    func testOnlyThePartAskedForIsCounted() throws {
        var made = MadeMotion()
        made.add(60, footfalls(170)); made.add(60, strokes(24)); made.add(60, footfalls(170))
        let track = made.track
        // The phone's clock is what parts are timed by: the track sits on it to within a quarter of a second.
        XCTAssertEqual(track.stretches.count, 1)
        XCTAssertEqual(track.stretches[0].start, made.start, accuracy: 0.25)
        XCTAssertEqual(track.seconds, 180, accuracy: 0.01)

        let row = try XCTUnwrap(MotionCounter.count(track, from: made.start + 60, to: made.start + 120, kind: .row))
        XCTAssertEqual(Double(row.count), 24, accuracy: 1)
        let run = try XCTUnwrap(MotionCounter.count(track, from: made.start + 120, to: made.start + 180, kind: .run))
        XCTAssertEqual(try XCTUnwrap(run.perMinute), 170, accuracy: 1.7)
        XCTAssertEqual(Double(run.count), 170, accuracy: 3)
    }

    func testLostSecondsAreNeitherCountedNorJoinedAcross() throws {
        var made = MadeMotion()
        made.add(90, strokes(30))
        // Fifteen seconds lost in the middle: two stretches, and the strokes of the seventy-five that arrived.
        let holed = MotionTrack.build(Array(made.seconds[0..<30]) + Array(made.seconds[45..<90]))
        XCTAssertEqual(holed.stretches.count, 2)
        XCTAssertEqual(holed.stretches[1].start - holed.stretches[0].start, 45, accuracy: 0.001)
        let c = try XCTUnwrap(MotionCounter.count(holed, from: made.start, to: made.start + 90, kind: .row))
        XCTAssertEqual(Double(c.count), 37.5, accuracy: 1.5)
        XCTAssertEqual(c.coveredS, 75, accuracy: 1)

        // With most of the part lost there is nothing to say.
        XCTAssertNil(MotionCounter.count(MotionTrack.build(Array(made.seconds[0..<20])), from: made.start, to: made.start + 90, kind: .row))
        XCTAssertTrue(MotionTrack.build([]).isEmpty)

        // Seconds sent twice and out of order are the same recording.
        let muddled = MotionTrack.build(Array(made.seconds[40..<90]) + Array(made.seconds[10..<20]) + Array(made.seconds[0..<60]))
        XCTAssertEqual(muddled.stretches.count, 1)
        XCTAssertEqual(muddled.seconds, 90, accuracy: 0.01)
        let whole = try XCTUnwrap(MotionCounter.count(muddled, from: made.start, to: made.start + 90, kind: .row))
        XCTAssertEqual(Double(whole.count), 45, accuracy: 1)
        // A second with readings missing is not a second.
        var short = made.seconds
        short[5].columns.removeLast()
        XCTAssertEqual(MotionTrack.build(short).stretches.count, 2)
    }

    // MARK: Seconds that do not join up

    /// The trap this guards against: the strap sends a fixed hundred readings a second, and if each
    /// second carries the same small drift, the reset at every join repeats once a second. Without the
    /// guard that is counted as sixty a minute from a wrist that never moved; with it, nothing is.
    func testSecondsThatDoNotJoinUpAreNotCountedFrom() throws {
        var made = MadeMotion()
        made.add(120, ramp)
        let ramped = made.track
        XCTAssertTrue(ramped.hasSeams)
        XCTAssertGreaterThan(ramped.seamRatio, 5)
        for kind in [MotionKind.work, .skiErg] {
            XCTAssertNil(MotionCounter.count(ramped, from: made.start, to: made.start + 120, kind: kind))
            let fooled = try XCTUnwrap(MotionCounter.unguarded(ramped, from: made.start, to: made.start + 120, kind: kind))
            XCTAssertEqual(try XCTUnwrap(fooled.perMinute), 60, accuracy: 0.6, "\(kind)")
            XCTAssertEqual(Double(fooled.count), 120, accuracy: 2, "\(kind)")
        }
        // The same drift under real rowing is refused too: the rowing cannot be told from it.
        var mixed = MadeMotion()
        let row = strokes(24)
        mixed.add(120) { t in
            let v = row(t), drift = ramp(t)
            return (v.0, v.1, v.2 + drift.2 - gravity.2)
        }
        XCTAssertTrue(mixed.track.hasSeams)
        XCTAssertNil(MotionCounter.count(mixed.track, from: mixed.start, to: mixed.start + 120, kind: .row))
        XCTAssertTrue(MotionSplit.spans(mixed.track, from: mixed.start, to: mixed.start + 120).isEmpty)

        // Each second shifted by its own amount.
        var shifted = MadeMotion()
        shifted.add(120, offset: 0.08, strokes(24))
        XCTAssertTrue(shifted.track.hasSeams)
        // A wrist read 104 times a second with 100 kept: brisk movement shows the joins. A slow one
        // that does not is still counted right, because every second still starts on time.
        for rate in [31.0, 47] {
            var cut = MadeMotion()
            cut.add(120, rate: 104, strokes(rate))
            XCTAssertTrue(cut.track.hasSeams, "cut at \(rate)")
        }
        var slow = MadeMotion()
        slow.add(120, rate: 104, strokes(24))
        let kept = try XCTUnwrap(MotionCounter.unguarded(slow.track, from: slow.start, to: slow.start + 120, kind: .row))
        XCTAssertEqual(Double(kept.count), 48, accuracy: 1)

        // Recordings whose seconds do join up are not refused, whatever the movement: stillness,
        // strokes, and a run at exactly three steps a second, where every join falls at the same
        // point of the stride.
        var quiet = MadeMotion()
        quiet.add(120, still)
        XCTAssertLessThan(quiet.track.seamRatio, 1.4)
        for pull in [strokes(22), strokes(58), footfalls(180), footfalls(150), footfalls(168)] {
            var joined = MadeMotion()
            joined.add(120, pull)
            XCTAssertLessThan(joined.track.seamRatio, 1.4)
            XCTAssertFalse(joined.track.hasSeams)
        }
        // Too few joins to judge by are not judged.
        var brief = MadeMotion()
        brief.add(8, offset: 0.08, still)
        XCTAssertFalse(brief.track.hasSeams)
    }

    // MARK: A session split by its motion

    func testASessionWithNoMarksIsSplitIntoRunsWorkAndRest() throws {
        var made = MadeMotion()
        made.add(120, footfalls(168)); made.add(90, strokes(30)); made.add(60, still); made.add(120, footfalls(176))
        let spans = MotionSplit.spans(made.track, from: made.start, to: made.start + 390)
        XCTAssertEqual(spans.map(\.kind), [.run, .work, .rest, .run])
        for (span, edge) in zip(spans.dropFirst(), [120.0, 210, 270]) {
            XCTAssertEqual(span.start - made.start, edge, accuracy: 6)
        }
        XCTAssertEqual(spans[0].start - made.start, 0, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(spans.last).end - made.start, 390, accuracy: 0.5)
        for (a, b) in zip(spans, spans.dropFirst()) { XCTAssertEqual(a.end, b.start, accuracy: 0.001) }

        // Walking is not running; a slow run is; and a twenty-second stop inside a run is not a part.
        var other = MadeMotion()
        other.add(120, footfalls(110, size: 0.45, swing: 0.15)); other.add(120, footfalls(144, size: 0.9))
        other.add(20, still); other.add(120, footfalls(160))
        let found = MotionSplit.spans(other.track, from: other.start, to: other.start + 380)
        XCTAssertEqual(found.map(\.kind), [.work, .run])
        XCTAssertEqual(found[1].start - other.start, 120, accuracy: 6)
        // A foot that lands harder than the other is still running.
        var limp = MadeMotion()
        limp.add(120, footfalls(172, weak: 0.5))
        XCTAssertEqual(MotionSplit.spans(limp.track, from: limp.start, to: limp.start + 120).map(\.kind), [.run])
        // Nothing at all is one rest.
        var quiet = MadeMotion()
        quiet.add(90, still)
        XCTAssertEqual(MotionSplit.spans(quiet.track, from: quiet.start, to: quiet.start + 90).map(\.kind), [.rest])
    }

    // MARK: The reading that is kept

    func testAReadTakesItsPartsFromTheSessionsMarksWhenItHasThem() throws {
        var made = MadeMotion()
        made.add(120, footfalls(168)); made.add(20, still); made.add(90, strokes(44)); made.add(20, still); made.add(90, strokes(24))
        let start = made.start
        let marks = [MotionMark(at: start + 0.4, text: "Run 1"), MotionMark(at: start + 120, text: "Roxzone"),
                     MotionMark(at: start + 140, text: "SkiErg"), MotionMark(at: start + 230, text: "Roxzone"),
                     MotionMark(at: start + 250, text: "Wall Balls"),
                     // A mark from another session altogether is not this recording's.
                     MotionMark(at: start + 4000, text: "Rowing")]
        let read = MotionRead.make(id: "a", startedAt: Date(timeIntervalSince1970: start), seconds: 340, marks: marks, track: made.track)
        XCTAssertFalse(read.fromMotion)
        XCTAssertNil(read.problem)
        XCTAssertEqual(read.parts.map(\.label), ["Run 1", "Roxzone", "SkiErg", "Roxzone", "Wall Balls"])
        XCTAssertEqual(read.parts.map(\.kind), [.run, .rest, .skiErg, .rest, .wallBalls])
        XCTAssertEqual(read.parts.map(\.id), [0, 1, 2, 3, 4])
        XCTAssertEqual(read.parts[0].figure, 168)
        XCTAssertEqual(read.parts[0].said, "168 steps a minute")
        XCTAssertNil(read.parts[1].count)
        XCTAssertNil(read.parts[1].said)
        XCTAssertEqual(Double(try XCTUnwrap(read.parts[2].count)), 66, accuracy: 1)
        XCTAssertEqual(Double(try XCTUnwrap(read.parts[4].count)), 36, accuracy: 1)
        XCTAssertEqual(read.parts[2].startS, 140, accuracy: 0.01)
        XCTAssertEqual(read.parts[2].durationS, 90, accuracy: 0.01)
        XCTAssertEqual(read.endedAt.timeIntervalSince1970, start + 340, accuracy: 0.001)

        // What is kept survives being stored and read back.
        let again = try JSONDecoder().decode(MotionRead.self, from: JSONEncoder().encode(read))
        XCTAssertEqual(again, read)

        // A stretch before the first mark is a part too, named for where it is.
        let late = MotionRead.make(id: "b", startedAt: Date(timeIntervalSince1970: start), seconds: 340,
                                   marks: Array(marks[1...4]), track: made.track, other: .run)
        XCTAssertEqual(late.parts.map(\.label), ["Start", "Roxzone", "SkiErg", "Roxzone", "Wall Balls"])
        XCTAssertEqual(late.parts[0].kind, .run)
        XCTAssertEqual(late.parts[0].figure, 168)
    }

    func testAReadWithNoMarksIsSplitByItsMotionAndSaysSo() throws {
        var made = MadeMotion()
        made.add(120, footfalls(168)); made.add(90, strokes(30)); made.add(60, still); made.add(120, footfalls(176))
        let at = Date(timeIntervalSince1970: made.start)
        let read = MotionRead.make(id: "c", startedAt: at, seconds: 390, marks: [], track: made.track)
        XCTAssertTrue(read.fromMotion)
        XCTAssertEqual(read.parts.map(\.label), ["Run", "Work", "Rest", "Run"])
        XCTAssertEqual(read.parts[0].figure, 168)
        XCTAssertEqual(read.parts[3].figure, 176)
        XCTAssertEqual(Double(try XCTUnwrap(read.parts[1].count)), 45, accuracy: 3)
        XCTAssertNil(read.parts[2].figure)

        // One mark whose name says nothing about the movement does not make a part of the whole session.
        let vague = MotionRead.make(id: "d", startedAt: at, seconds: 390, marks: [MotionMark(at: made.start, text: "Warm up")], track: made.track)
        XCTAssertTrue(vague.fromMotion)
        // One mark that names the movement does.
        var rowing = MadeMotion()
        rowing.add(120, strokes(26))
        let named = MotionRead.make(id: "e", startedAt: Date(timeIntervalSince1970: rowing.start), seconds: 120,
                                    marks: [MotionMark(at: rowing.start, text: "Row 500 m")], track: rowing.track)
        XCTAssertFalse(named.fromMotion)
        XCTAssertEqual(named.parts.map(\.kind), [.row])
        XCTAssertEqual(named.parts[0].said, "52 strokes, 26 a minute")

        // Nothing recorded, and seconds that do not join up, are said and not counted.
        let empty = MotionRead.make(id: "f", startedAt: at, seconds: 390, marks: [], track: MotionTrack())
        XCTAssertEqual(empty.problem, MotionRead.noMotion)
        XCTAssertTrue(empty.parts.isEmpty)
        var ramped = MadeMotion()
        ramped.add(120, ramp)
        let refused = MotionRead.make(id: "g", startedAt: Date(timeIntervalSince1970: ramped.start), seconds: 120, marks: [], track: ramped.track)
        XCTAssertEqual(refused.problem, MotionRead.seams)
        XCTAssertTrue(refused.parts.isEmpty)
    }

    func testNamesPointToTheMovementTheyName() {
        let expected: [(String, MotionKind?)] = [
            ("SkiErg", .skiErg), ("Sled Push", .sledPush), ("Sled Pull", .sledPull), ("Burpee Broad Jump", .burpees),
            ("Rowing", .row), ("Farmers Carry", .walk), ("Sandbag Lunges", .lunges), ("Wall Balls", .wallBalls),
            ("Run 3", .run), ("Run 1 km", .run), ("Roxzone", .rest), ("Rest", .rest), ("Recover", .rest),
            ("Row 500 m", .row), ("Treadmill", .run), ("Walk", .walk),
            ("Work 2 of 6", nil), ("Warm up", nil), ("Cool down", nil), ("Goblet squats", nil), ("Narrow push-ups", nil), ("", nil),
        ]
        for (label, kind) in expected { XCTAssertEqual(MotionKind.named(label), kind, label) }
        XCTAssertEqual(MotionKind.infer("Work 2 of 6", other: .run), .run)
        XCTAssertEqual(MotionKind.infer("Goblet squats"), .work)
        // Every kind that is counted has a word for what is counted, and the others have none.
        for kind in MotionKind.allCases { XCTAssertEqual(kind.counts, !kind.unit.isEmpty, "\(kind)") }
    }

    func testAPartSaysWhatWasCountedAndChecksAddUp() {
        let run = MotionPart(id: 0, label: "Run", kind: .run, startS: 0, durationS: 300, count: 840, perMinute: 168.2, steady: 1)
        XCTAssertEqual(run.figure, 168)
        XCTAssertEqual(run.figureUnit, "steps a minute")
        let balls = MotionPart(id: 1, label: "Wall Balls", kind: .wallBalls, startS: 300, durationS: 240, count: 92, perMinute: 24.6, steady: 0.4)
        XCTAssertEqual(balls.figure, 92)
        XCTAssertEqual(balls.said, "92 reps, 25 a minute")
        XCTAssertTrue(balls.uneven)
        XCTAssertFalse(run.uneven)
        let none = MotionPart(id: 2, label: "Rowing", kind: .row, startS: 0, durationS: 60, count: 0, perMinute: nil, steady: 0)
        XCTAssertEqual(none.said, "no steady strokes")
        XCTAssertFalse(none.uneven)
        let lost = MotionPart(id: 3, label: "Run", kind: .run, startS: 0, durationS: 60, count: 0, perMinute: nil, steady: 0)
        XCTAssertNil(lost.figure)
        XCTAssertEqual(lost.said, "no steady step")
        let rest = MotionPart(id: 4, label: "Rest", kind: .rest, startS: 0, durationS: 60)
        XCTAssertNil(rest.said)

        // With no real numbers entered there is nothing to say about how right the counting is.
        var read = MotionRead(id: "a", startedAt: Date(timeIntervalSince1970: 0), seconds: 600, parts: [run, balls, none])
        XCTAssertNil(MotionChecks.summary([read]))
        read.parts[1].actual = 100
        XCTAssertEqual(MotionChecks.summary([read]), MotionChecks(checked: 1, typicalError: 0.08))
        XCTAssertEqual(MotionChecks.summary([read])?.line, "Checked against your own numbers once: typically off by 8%.")
        // A run is checked by its pace.
        read.parts[0].actual = 170
        var second = read
        second.id = "b"
        second.parts[1].actual = 92
        let checks = MotionChecks.summary([read, second])
        XCTAssertEqual(checks?.checked, 4)
        XCTAssertEqual(checks?.typicalError ?? 0, 2.0 / 170, accuracy: 0.0001)
        XCTAssertEqual(checks?.line, "Checked against your own numbers 4 times: typically off by 1%.")
    }
}
