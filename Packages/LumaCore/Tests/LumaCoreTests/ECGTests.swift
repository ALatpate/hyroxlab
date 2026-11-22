import XCTest
@testable import LumaCore

// Reading a trace from the clasp, checked against traces made up for the purpose: a beat of the usual
// shape at each of a list of times, drift, and noise. Every claim about a figure is made for several
// figures, and the pace the trace is read at is itself varied, so that neither can be a constant.

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

/// A made-up trace and the moments its beats were put at, in seconds.
private struct MadeTrace {
    var samples: [Int] = []
    var beats: [Double] = []

    /// The heart rate the beats were put in at, from the usual time between them.
    var heartRate: Double {
        var between: [Double] = []
        for i in 1..<beats.count { between.append(beats[i] - beats[i - 1]) }
        return 60 / between.sorted()[between.count / 2]
    }

    /// How much the time between one beat and the next changes, in milliseconds, as put in.
    var variationMs: Double {
        var between: [Double] = []
        for i in 1..<beats.count { between.append(beats[i] - beats[i - 1]) }
        var squares = 0.0
        for i in 1..<between.count { squares += (between[i] - between[i - 1]) * (between[i] - between[i - 1]) }
        return 1000 * (squares / Double(between.count - 1)).squareRoot()
    }

    init(heartRate: Double, variationMs: Double = 30, seconds: Double = 40, perSecond fs: Double = 100, flipped: Bool = false,
         wander: Double = 200, noise: Double = 15) {
        var dice = Dice(3)
        let mean = 60 / heartRate
        let spread = variationMs / 1000 / 2.0.squareRoot()
        var times = [0.4]
        while times[times.count - 1] < seconds + 2 {
            times.append(times[times.count - 1] + max(0.25, mean + spread * 3.0.squareRoot() * dice.next()))
        }
        // The waves of one beat: when, how tall, and how wide, with the tall one in the middle.
        let waves: [(Double, Double, Double)] = [(-0.16, 0.12, 0.025), (-0.026, -0.10, 0.008), (0, 1, 0.012), (0.03, -0.22, 0.010), (0.25, 0.30, 0.04)]
        var first = 0
        for i in 0..<Int(seconds * fs) {
            let t = Double(i) / fs
            while first + 1 < times.count, times[first + 1] < t - 0.5 { first += 1 }
            var v = 0.0
            for b in times[max(0, first - 1)..<min(times.count, first + 4)] {
                for (at, tall, wide) in waves {
                    let dt = t - b - at
                    if abs(dt) < 5 * wide { v += tall * exp(-0.5 * (dt / wide) * (dt / wide)) }
                }
            }
            v = 1500 * v + wander * sin(2 * Double.pi * 0.25 * t) + noise * dice.next()
            samples.append(Int((flipped ? -v : v).rounded()))
        }
        beats = times.filter { $0 < seconds }
    }
}

/// Cuts a trace into packets as the strap would send them: a hundred readings in each, numbered, and
/// arriving a little after the last reading in them was taken. `held` keeps a few packets back and
/// then lets them all go at once.
private func packets(_ samples: [Int], perSecond fs: Double = 100, settling: Int = 0, strapClock: Bool = true,
                     held: Range<Int>? = nil) -> [ECGPacket] {
    var dice = Dice(9)
    let all = [Int](repeating: 0, count: settling) + samples
    var out: [ECGPacket] = []
    var k = 0
    while k < all.count {
        let chunk = Array(all[k..<min(all.count, k + 100)])
        var arrive = 1_000_000 + Double(k + chunk.count) / fs * 1000 + 40 + 25 * (dice.next() + 1)
        if let held, held.contains(out.count) { arrive = 1_000_000 + Double(held.upperBound * 100) / fs * 1000 + 40 + Double(out.count) }
        out.append(ECGPacket(sequence: 100 + out.count, arrivedMs: Int(arrive), strapTime: strapClock ? 5000 + Double(k) / fs : nil, samples: chunk))
        k += 100
    }
    return out
}

final class ECGTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    private func read(_ packets: [ECGPacket]) -> ECGRead { ECGReader.read(id: "t", takenAt: at, packets: packets) }

    // MARK: Figures that were put in come back out

    func testHeartRatesAndVariationsPutInComeBackOut() throws {
        for rate in [48.0, 62, 75, 96, 128, 150] {
            for variation in [12.0, 40, 80] {
                let made = MadeTrace(heartRate: rate, variationMs: variation)
                // Two and a half seconds of zeros first, as a strap that is still settling sends.
                let r = read(packets(made.samples, settling: 250))
                let name = "\(rate) a minute, \(variation) ms"
                XCTAssertNil(r.problem, name)
                XCTAssertEqual(try XCTUnwrap(r.perSecond), 100, accuracy: 0.5, name)
                XCTAssertEqual(Double(r.beats), Double(made.beats.count), accuracy: 2, name)
                XCTAssertEqual(try XCTUnwrap(r.heartRate), made.heartRate, accuracy: 0.5, name)
                XCTAssertEqual(try XCTUnwrap(r.variationMs), made.variationMs, accuracy: max(2, 0.05 * made.variationMs), name)
                XCTAssertEqual(r.samples, 4250)
                XCTAssertLessThan(r.seamRatio, 1.5, name)
            }
        }
    }

    /// The strap layer's notes do not establish how fast the trace is read, so nothing here takes it
    /// as a hundred a second: it is measured from the reading, and a different pace gives the same beats.
    func testThePaceOfTheReadingsIsMeasuredAndNotAssumed() throws {
        for pace in [64.0, 100, 125, 128, 250] {
            let made = MadeTrace(heartRate: 66, variationMs: 35, perSecond: pace)
            for strapClock in [true, false] {
                let r = read(packets(made.samples, perSecond: pace, strapClock: strapClock))
                let name = "\(pace) a second, strap clock \(strapClock)"
                XCTAssertNil(r.problem, name)
                XCTAssertEqual(try XCTUnwrap(r.perSecond), pace, accuracy: 0.005 * pace, name)
                XCTAssertEqual(try XCTUnwrap(r.heartRate), made.heartRate, accuracy: 0.5, name)
                XCTAssertEqual(r.clocksAgree, strapClock ? true : nil, name)
                XCTAssertEqual(try XCTUnwrap(r.seconds), 40, accuracy: 0.3, name)
            }
        }
        // Two clocks that do not agree on the pace: neither is believed, and no beat is timed.
        let made = MadeTrace(heartRate: 66, variationMs: 35)
        var odd = packets(made.samples)
        for i in odd.indices { odd[i].strapTime = odd[i].strapTime.map { 5000 + ($0 - 5000) * 1.1 } }
        let r = read(odd)
        XCTAssertEqual(r.problem, .timing)
        XCTAssertEqual(r.clocksAgree, false)
        XCTAssertNil(r.heartRate)
        XCTAssertNil(r.perSecond)
        XCTAssertNil(r.seconds)
        // The trace is still kept, to be looked at.
        XCTAssertEqual(r.trace.count, 4000)
        // Five seconds are too few to measure a pace from.
        let brief = read(packets(MadeTrace(heartRate: 70, seconds: 5).samples))
        XCTAssertEqual(brief.problem, .timing)
    }

    func testAFlippedNoisyOrDriftingTraceIsStillRead() throws {
        let cases: [(String, MadeTrace)] = [
            ("upside down", MadeTrace(heartRate: 70, flipped: true)),
            ("noisy", MadeTrace(heartRate: 70, noise: 120)),
            ("drifting", MadeTrace(heartRate: 70, wander: 1500)),
        ]
        for (name, made) in cases {
            let r = read(packets(made.samples))
            XCTAssertNil(r.problem, name)
            XCTAssertEqual(try XCTUnwrap(r.heartRate), made.heartRate, accuracy: 0.5, name)
            XCTAssertEqual(try XCTUnwrap(r.variationMs), made.variationMs, accuracy: 2, name)
        }
        // Noisier still, the beats can be counted but hardly timed: the rate holds.
        let rough = MadeTrace(heartRate: 70, noise: 300)
        XCTAssertEqual(try XCTUnwrap(read(packets(rough.samples)).heartRate), rough.heartRate, accuracy: 0.5)
    }

    // MARK: Where there is nothing to read, nothing is read

    func testATraceWithNoBeatsGivesNoFigure() {
        var dice = Dice(4)
        var hiss: [Int] = []
        for _ in 0..<4000 { hiss.append(Int(300 * dice.next())) }
        let noise = read(packets(hiss))
        XCTAssertEqual(noise.problem, .unclear)
        XCTAssertNil(noise.heartRate)
        XCTAssertNil(noise.variationMs)
        XCTAssertTrue(noise.intervalsMs.isEmpty)

        XCTAssertEqual(read(packets([Int](repeating: 0, count: 4000))).problem, .flat)
        XCTAssertEqual(read(packets([Int](repeating: 5, count: 4000))).problem, .few)
        let none = read([])
        XCTAssertEqual(none.problem, .nothing)
        XCTAssertEqual(none.packets, 0)
        XCTAssertTrue(none.trace.isEmpty)
        // Every reason has words, and none of them is about the heart.
        for problem in ECGProblem.allCases {
            XCTAssertFalse(problem.text.isEmpty)
            for word in ["rhythm", "irregular", "normal", "abnormal", "arrhythm", "fibrill"] {
                XCTAssertFalse(problem.text.lowercased().contains(word), "\(problem) says \(word)")
            }
        }
    }

    func testZerosALostPacketAndPacketsHeldBackAreReadAround() throws {
        let made = MadeTrace(heartRate: 64)
        // Nearly two seconds of zeros in the middle, as when the signal is turned away.
        let holed = Array(made.samples[0..<1500]) + [Int](repeating: 0, count: 180) + Array(made.samples[1680...])
        let dropout = read(packets(holed))
        XCTAssertNil(dropout.problem)
        XCTAssertEqual(try XCTUnwrap(dropout.heartRate), made.heartRate, accuracy: 0.5)

        var lost = packets(made.samples)
        lost.remove(at: 30)
        lost.remove(at: 9)
        let short = read(lost)
        XCTAssertEqual(short.lost, 2)
        XCTAssertEqual(short.packets, 38)
        XCTAssertNil(short.problem)
        // The pace is never measured across a packet that did not arrive, so the rate does not move.
        XCTAssertEqual(try XCTUnwrap(short.perSecond), 100, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(short.heartRate), made.heartRate, accuracy: 0.5)

        for strapClock in [true, false] {
            let bunched = read(packets(made.samples, strapClock: strapClock, held: 10..<14))
            XCTAssertEqual(try XCTUnwrap(bunched.perSecond), 100, accuracy: 0.5)
            XCTAssertEqual(try XCTUnwrap(bunched.heartRate), made.heartRate, accuracy: 0.5)
        }

        // Packets out of order, and some sent twice, are the same trace.
        let whole = packets(made.samples)
        let muddled = read(Array(whole[20...]) + Array(whole[5..<12]) + Array(whole[..<20]))
        XCTAssertEqual(muddled.packets, 40)
        XCTAssertEqual(muddled.samples, 4000)
        XCTAssertEqual(muddled.heartRate, read(whole).heartRate)
        XCTAssertEqual(muddled.trace, made.samples)
    }

    // MARK: Packets that do not join up

    /// The trap this guards against: the trace comes about a packet a second. A packet that opens with
    /// a spike of its own, or sits at its own level, puts something at every join, and that is read as
    /// sixty beats a minute from a trace with no heartbeat in it at all. With the guard, nothing is read.
    func testPacketsThatDoNotJoinUpAreNotCountedFrom() throws {
        var dice = Dice(8)
        var spiky: [Int] = []
        for _ in 0..<40 {
            for i in 0..<100 { spiky.append(Int(1200 * exp(-Double(i) / 2) + 10 * dice.next())) }
        }
        let refused = read(packets(spiky))
        XCTAssertEqual(refused.problem, .joins)
        XCTAssertNil(refused.heartRate)
        XCTAssertGreaterThan(refused.seamRatio, 3)
        let fooled = ECGReader.unguarded(id: "t", takenAt: at, packets: packets(spiky))
        XCTAssertNil(fooled.problem)
        XCTAssertEqual(try XCTUnwrap(fooled.heartRate), 60, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(fooled.beats, 30)

        var steps = Dice(8)
        var stepped: [Int] = []
        for _ in 0..<40 {
            let level = 800 * steps.next()
            for _ in 0..<100 { stepped.append(Int(level + 10 * steps.next())) }
        }
        XCTAssertEqual(read(packets(stepped)).problem, .joins)
        let alsoFooled = ECGReader.unguarded(id: "t", takenAt: at, packets: packets(stepped))
        XCTAssertEqual(try XCTUnwrap(alsoFooled.heartRate), 60, accuracy: 0.5)

        // A heart that really does beat sixty times a minute is read: its packets join up.
        let sixty = MadeTrace(heartRate: 60, variationMs: 5)
        let real = read(packets(sixty.samples))
        XCTAssertNil(real.problem)
        XCTAssertEqual(try XCTUnwrap(real.heartRate), sixty.heartRate, accuracy: 0.5)
        XCTAssertLessThan(real.seamRatio, 1.5)
    }

    // MARK: What is kept

    func testWhatIsKeptIsTheTraceAndWhereItsBeatsAre() throws {
        let made = MadeTrace(heartRate: 64)
        var sent = packets(made.samples, settling: 250)
        for i in sent.indices {
            sent[i].contact = i % 2 == 0
            sent[i].strapHeartRate = [0, 61, 62, 62, 66][i % 5]
        }
        let r = ECGReader.read(id: "kept", takenAt: at, packets: sent, wristHeartRate: 63)
        XCTAssertEqual(r.id, "kept")
        XCTAssertEqual(r.takenAt, at)
        XCTAssertEqual(r.trace.count, 4250)
        XCTAssertEqual(Array(r.trace[250...]), made.samples)
        XCTAssertEqual(r.beatsAt.count, r.beats)
        // Every beat put in, bar the two at the ends, is marked within three readings of where it is.
        for beat in made.beats.dropFirst().dropLast() {
            let place = beat * 100 + 250
            XCTAssertTrue(r.beatsAt.contains { abs(Double($0) - place) <= 3 }, "no mark at \(place)")
        }
        // Twenty-one packets of a hundred and one of fifty were touched, of 4,250 readings.
        XCTAssertEqual(r.contactShare, 2150.0 / 4250, accuracy: 0.0001)
        // The strap's own figure is the middle one of those it gave, with the zeros left out.
        XCTAssertEqual(r.strapHeartRate, 62)
        XCTAssertEqual(r.wristHeartRate, 63)
        XCTAssertEqual(r.beatsAMinute, 64)
        XCTAssertFalse(r.intervalsMs.isEmpty)
        XCTAssertEqual(Double(r.intervalsMs.sorted()[r.intervalsMs.count / 2]), 60_000 / made.heartRate, accuracy: 10)

        let again = try JSONDecoder().decode(ECGRead.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(again, r)

        // A long trace keeps its last six thousand readings, and its marks move with it.
        let long = MadeTrace(heartRate: 64, seconds: 80)
        let kept = read(packets(long.samples))
        XCTAssertNil(kept.problem)
        XCTAssertEqual(kept.samples, 8000)
        XCTAssertEqual(kept.trace, Array(long.samples[2000...]))
        XCTAssertEqual(try XCTUnwrap(kept.heartRate), long.heartRate, accuracy: 0.5)
        for beat in long.beats.dropFirst().dropLast() where beat * 100 - 2000 >= 3 {
            let place = beat * 100 - 2000
            XCTAssertTrue(kept.beatsAt.contains { abs(Double($0) - place) <= 3 }, "no mark at \(place)")
        }
        XCTAssertTrue(kept.beatsAt.allSatisfy { $0 >= 0 && $0 < 6000 })
    }

    /// What the strap's own software concluded about a trace is not Luma's to show. There is no field
    /// to carry it in, and this is the list of the fields there are: adding one is a decision.
    func testNothingTheStrapConcludedHasAFieldToTravelIn() {
        let packet = ECGPacket(sequence: 1, arrivedMs: 0, samples: [])
        XCTAssertEqual(Mirror(reflecting: packet).children.compactMap(\.label),
                       ["sequence", "arrivedMs", "strapTime", "samples", "contact", "strapHeartRate"])
        XCTAssertEqual(Mirror(reflecting: ECGRead(id: "a", takenAt: at)).children.compactMap(\.label),
                       ["id", "takenAt", "packets", "lost", "samples", "perSecond", "clocksAgree", "beats", "heartRate", "variationMs",
                        "intervalsMs", "contactShare", "strapHeartRate", "wristHeartRate", "seamRatio", "problem", "trace", "beatsAt"])
    }
}
