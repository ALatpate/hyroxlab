import XCTest
@testable import LumaCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

/// HRV against its own normal band, a slow rise in resting heart rate, the Sleep Regularity Index,
/// and the week's load against the usual week.
final class BodyTrendTests: XCTestCase {
    private let cal = utc()
    private let today = "2026-11-16"

    /// Days ending today, oldest first, one for each value given; a nil leaves the night without a figure.
    private func days(hrv: [Double?] = [], restingHR: [Double?] = []) -> [LDay] {
        let n = max(hrv.count, restingHR.count)
        let keys = LDate.range(ending: today, count: n, calendar: cal)
        return keys.enumerated().map { i, key in
            LDay(day: key, restingHR: i < restingHR.count ? restingHR[i] : nil, hrv: i < hrv.count ? hrv[i] : nil)
        }
    }

    /// A steady HRV near 60 ms with a small wobble from night to night.
    private func steadyHRV(_ n: Int) -> [Double?] {
        let wobble: [Double] = [-4, 0, 4, 2, -2]
        let values: [Double] = (0..<n).map { 60 + wobble[$0 % 5] }
        return values
    }

    // MARK: HRV trend

    func testAWeekOfLowHRVSitsUnderTheAthletesOwnBand() {
        var values = steadyHRV(70)
        for i in 63..<70 { values[i] = 44 }
        let trend = HRVTrendModel.build(days: days(hrv: values), today: today, calendar: cal)
        XCTAssertTrue(trend.ready)
        XCTAssertEqual(trend.place, .below)
        XCTAssertTrue(trend.holdsBack)
        XCTAssertGreaterThanOrEqual(trend.daysThere, 3)
        XCTAssertLessThanOrEqual(trend.daysThere, 7)
        XCTAssertEqual(trend.weekMs!, 44, accuracy: 1e-6)
        XCTAssertEqual(trend.nights, 60)
        // The band is the 60-day average of the logs, half a spread either side, shown back in ms.
        let logs = values.suffix(60).compactMap { $0 }.map { log($0) }
        let mean = LStat.mean(logs)!, sd = LStat.sd(logs)!
        XCTAssertEqual(trend.lowMs!, exp(mean - 0.5 * sd), accuracy: 1e-6)
        XCTAssertEqual(trend.highMs!, exp(mean + 0.5 * sd), accuracy: 1e-6)
        XCTAssertLessThan(trend.weekMs!, trend.lowMs!)
        // Six weeks are charted, ending today, each with the night and the week's average.
        XCTAssertEqual(trend.days.count, 42)
        XCTAssertEqual(trend.days.last?.day, today)
        XCTAssertEqual(trend.days.last?.nightMs ?? 0, 44, accuracy: 1e-6)
        XCTAssertEqual(trend.days.last?.weekMs ?? 0, 44, accuracy: 1e-6)
        XCTAssertEqual(trend.headline, "HRV is under your normal")
        XCTAssertTrue(trend.detail.contains("The week's average is 44 ms"))
        XCTAssertNotNil(trend.weekSpread)
        XCTAssertNotNil(trend.usualSpread)
    }

    func testASteadyHRVSitsInsideTheBandAndTooLittleHistorySaysSo() {
        let steady = HRVTrendModel.build(days: days(hrv: steadyHRV(70)), today: today, calendar: cal)
        XCTAssertEqual(steady.place, .within)
        XCTAssertFalse(steady.holdsBack)
        XCTAssertEqual(steady.headline, "HRV is in your normal range")

        let short = HRVTrendModel.build(days: days(hrv: steadyHRV(10)), today: today, calendar: cal)
        XCTAssertFalse(short.ready)
        XCTAssertNil(short.place)
        XCTAssertNil(short.lowMs)
        XCTAssertEqual(short.headline, "Building your normal range")
        XCTAssertTrue(short.detail.contains("10 of 20 nights"))

        // The band is there, but the last week holds too few nights for an average.
        var gappy = steadyHRV(70)
        for i in 64..<70 { gappy[i] = nil }
        let thin = HRVTrendModel.build(days: days(hrv: gappy), today: today, calendar: cal)
        XCTAssertNotNil(thin.lowMs)
        XCTAssertNil(thin.weekMs)
        XCTAssertNil(thin.place)
        XCTAssertFalse(thin.ready)
        XCTAssertEqual(thin.headline, "Too few nights this week")

        // With nothing at all it still answers, with nothing to show.
        let none = HRVTrendModel.build(days: [], today: today, calendar: cal)
        XCTAssertFalse(none.ready)
        XCTAssertEqual(none.nights, 0)
        XCTAssertEqual(none.days.count, 42)
    }

    func testTheDaysCallHoldsBackWhenHRVHasBeenLowForDays() {
        var values = steadyHRV(70)
        for i in 63..<70 { values[i] = 44 }
        let low = HRVTrendModel.build(days: days(hrv: values), today: today, calendar: cal)
        let clear = BodyWatch(level: .clear, signals: [], title: "", detail: "")
        let plain = DayCall.make(recovery: 80, load: nil, sleepDebtMin: 0, watch: clear)
        XCTAssertEqual(plain.level, .push)
        let held = DayCall.make(recovery: 80, load: nil, sleepDebtMin: 0, watch: clear, hrv: low)
        XCTAssertEqual(held.level, .build)
        XCTAssertTrue(held.reasons.contains { $0.hasPrefix("HRV under your normal for") }, "\(held.reasons)")
        // A steady HRV changes nothing.
        let steady = HRVTrendModel.build(days: days(hrv: steadyHRV(70)), today: today, calendar: cal)
        XCTAssertEqual(DayCall.make(recovery: 80, load: nil, sleepDebtMin: 0, watch: clear, hrv: steady), plain)
    }

    // MARK: Resting heart rate creeping up

    /// Forty nights alternating 52 and 50, the last of them a 50.
    private func usualResting() -> [Double?] {
        let values: [Double] = (0..<40).map { $0 % 2 == 0 ? 52 : 50 }
        return values
    }

    func testASustainedRiseInRestingHeartRateIsSaidAndASingleNightIsNot() {
        let rising = usualResting() + [55, 56, 56, 57, 57]
        let drift = RestingDriftModel.assess(days: days(restingHR: rising), today: today, calendar: cal)!
        XCTAssertTrue(drift.raised)
        XCTAssertEqual(drift.nights, 5)
        // Five nights, each adding the most one night can.
        XCTAssertEqual(drift.score, 10, accuracy: 1e-9)
        XCTAssertTrue((4.5...5.5).contains(drift.riseBpm), "\(drift.riseBpm)")
        XCTAssertEqual(drift.line, "Resting heart rate has been creeping up for 5 nights, about 5 bpm above your usual.")

        // The usual pattern never adds up to anything.
        let flat = RestingDriftModel.assess(days: days(restingHR: usualResting() + [52, 50, 52, 50, 52]), today: today, calendar: cal)!
        XCTAssertFalse(flat.raised)
        XCTAssertLessThan(flat.score, 1)

        // One bad night, however bad, is not a rise; nor is it one the morning after.
        let spikeToday = RestingDriftModel.assess(days: days(restingHR: usualResting() + [52, 50, 52, 50, 64]), today: today, calendar: cal)!
        XCTAssertFalse(spikeToday.raised)
        let spikeYesterday = RestingDriftModel.assess(days: days(restingHR: usualResting() + [52, 50, 52, 64, 51]), today: today, calendar: cal)!
        XCTAssertFalse(spikeYesterday.raised)

        // A rise that has ended is no longer said, even while the sum is still draining.
        let over = RestingDriftModel.assess(days: days(restingHR: usualResting() + [56, 57, 57, 57, 50]), today: today, calendar: cal)!
        XCTAssertGreaterThanOrEqual(over.score, RestingDriftModel.limit)
        XCTAssertFalse(over.raised)

        // No figure for last night, or too little history: nothing is said either way.
        XCTAssertNil(RestingDriftModel.assess(days: days(restingHR: usualResting() + [55, 56, 56, 57, nil]), today: today, calendar: cal))
        XCTAssertNil(RestingDriftModel.assess(days: days(restingHR: [50, 52, 50, 52, 50, 52, 55, 56, 57, 58]), today: today, calendar: cal))
    }

    func testASlowRiseLiftsAClearMorningAndIsQuotedForWhatItIs() {
        let drift = RestingDriftModel.assess(days: days(restingHR: usualResting() + [55, 56, 56, 57, 57]), today: today, calendar: cal)!
        let clear = BodyWatch(level: .clear, signals: [], title: "No warning signs", detail: "Overnight signals are inside your normal range.")
        let lifted = clear.adding(drift)
        XCTAssertEqual(lifted.level, .watch)
        XCTAssertEqual(lifted.title, "Resting heart rate is creeping up")
        XCTAssertTrue(lifted.detail.hasPrefix(drift.line))
        // Nothing to add leaves the watch as it was.
        XCTAssertEqual(clear.adding(nil), clear)
        let quiet = RestingDriftModel.assess(days: days(restingHR: usualResting() + [52, 50, 52, 50, 52]), today: today, calendar: cal)
        XCTAssertEqual(clear.adding(quiet), clear)
        // A morning already flagged keeps its level and gains the line.
        let alert = BodyWatch(level: .alert, signals: [], title: "Your body is under strain", detail: "Three signals are off.")
        XCTAssertEqual(alert.adding(drift).level, .alert)
        XCTAssertEqual(alert.adding(drift).title, "Your body is under strain")
        XCTAssertEqual(alert.adding(drift).detail, "Three signals are off. " + drift.line)

        // The day's call names the rise, and does not claim two signals that are not there.
        let call = DayCall.make(recovery: 80, load: nil, sleepDebtMin: 0, watch: lifted)
        XCTAssertEqual(call.level, .build)
        XCTAssertTrue(call.reasons.contains("Resting heart rate is creeping up"), "\(call.reasons)")
        XCTAssertFalse(call.reasons.contains("Two overnight signals off"))
    }

    // MARK: Sleep Regularity Index

    /// A sleep that ends on `day`, given as hours from that day's midnight: -1 is 23:00 the evening before.
    private func sleep(_ day: String, from: Double, to: Double, nap: Bool = false, incomplete: Bool = false) -> LSleep {
        let midnight = LDate.startOfDay(day, calendar: cal)!.timeIntervalSince1970
        return LSleep(start: midnight + from * 3600, end: midnight + to * 3600, day: day, isNap: nap, incomplete: incomplete)
    }

    func testTheSameNightEveryNightScoresAHundred() {
        let keys = LDate.range(ending: today, count: 10, calendar: cal)
        let regular = keys.map { sleep($0, from: -1, to: 7) }
        let r = SleepRegularityModel.read(sleeps: regular, today: today, calendar: cal)!
        XCTAssertEqual(r.index, 100, accuracy: 1e-9)
        XCTAssertEqual(r.pairs, 9)
        XCTAssertEqual(r.headline, "Very regular sleep")
        XCTAssertTrue(r.detail.contains("Sleep Regularity Index 100 of 100 over 9 pairs of days"))

        // A nap on one afternoon is an hour in a different state on either side of it.
        let withNap = regular + [sleep(keys[4], from: 14, to: 15, nap: true)]
        let napped = SleepRegularityModel.read(sleeps: withNap, today: today, calendar: cal)!
        XCTAssertEqual(napped.pairs, 9)
        XCTAssertEqual(napped.index, -100 + 200 * (214.0 / 216.0), accuracy: 1e-6)
    }

    func testNightsFourHoursApartScoreLow() {
        let keys = LDate.range(ending: today, count: 10, calendar: cal)
        // Asleep 22:00 to 06:00 one night and 02:00 to 10:00 the next: the same state for 16 hours in 24.
        let scattered = keys.enumerated().map { i, key in i % 2 == 0 ? sleep(key, from: -2, to: 6) : sleep(key, from: 2, to: 10) }
        let r = SleepRegularityModel.read(sleeps: scattered, today: today, calendar: cal)!
        XCTAssertEqual(r.index, -100 + 200 * (16.0 / 24.0), accuracy: 1e-6)
        XCTAssertEqual(r.headline, "Sleep times are scattered")
    }

    func testTooFewNightsGiveNoIndex() {
        let keys = LDate.range(ending: today, count: 4, calendar: cal)
        XCTAssertNil(SleepRegularityModel.read(sleeps: keys.map { sleep($0, from: -1, to: 7) }, today: today, calendar: cal))
        // A night the strap marked incomplete is not counted as a night.
        let ten = LDate.range(ending: today, count: 10, calendar: cal)
        let broken = ten.enumerated().map { i, key in sleep(key, from: -1, to: 7, incomplete: i % 2 == 0) }
        XCTAssertNil(SleepRegularityModel.read(sleeps: broken, today: today, calendar: cal))
        XCTAssertNil(SleepRegularityModel.read(sleeps: [], today: today, calendar: cal))
    }

    // MARK: The week against the usual week

    func testAWeekIsSetAgainstTheUsualWeek() {
        var flat: [String: Double] = [:]
        for k in LDate.range(ending: today, count: 300, calendar: cal) { flat[k] = 100 }
        let steady = LoadModel.compute(loads: flat, today: today, calendar: cal)
        XCTAssertEqual(steady.usualWeek!, 700, accuracy: 1e-9)
        XCTAssertEqual(steady.weekShare!, 1, accuracy: 1e-9)
        XCTAssertEqual(steady.status, .productive)

        func withLastWeek(_ load: Double) -> LoadState {
            var loads = flat
            for k in LDate.range(ending: today, count: 7, calendar: cal) { loads[k] = load }
            return LoadModel.compute(loads: loads, today: today, calendar: cal)
        }
        let spike = withLastWeek(320)
        XCTAssertEqual(spike.weekShare!, 3.2, accuracy: 1e-9)
        XCTAssertEqual(spike.status, .spike)
        XCTAssertEqual(spike.headline, "Well above your usual week")
        XCTAssertTrue(spike.detail.contains("220% above your usual week"))
        XCTAssertEqual(withLastWeek(140).status, .pushing)
        XCTAssertEqual(withLastWeek(125).status, .productive)
        XCTAssertEqual(withLastWeek(50).status, .fresh)

        // One heavy week among the six before does not move the usual week: it is the middle one.
        var lumpy = flat
        for k in LDate.range(ending: LDate.adding(-14, to: today, calendar: cal), count: 7, calendar: cal) { lumpy[k] = 400 }
        XCTAssertEqual(LoadModel.compute(loads: lumpy, today: today, calendar: cal).usualWeek!, 700, accuracy: 1e-9)
    }

    func testAWeekAfterABreakHasNoUsualWeekToBeSetAgainst() {
        var loads: [String: Double] = [LDate.adding(-100, to: today, calendar: cal): 50]
        for k in LDate.range(ending: today, count: 3, calendar: cal) { loads[k] = 100 }
        let back = LoadModel.compute(loads: loads, today: today, calendar: cal)
        XCTAssertTrue(back.ready)
        XCTAssertNil(back.usualWeek)
        XCTAssertNil(back.weekShare)
        XCTAssertEqual(back.status, .building)
        XCTAssertEqual(back.headline, "Building back")

        // Under four weeks of history nothing is judged at all.
        var young: [String: Double] = [:]
        for k in LDate.range(ending: today, count: 20, calendar: cal) { young[k] = 100 }
        let early = LoadModel.compute(loads: young, today: today, calendar: cal)
        XCTAssertFalse(early.ready)
        XCTAssertNil(early.weekShare)
        XCTAssertEqual(early.headline, "Building a baseline")
    }

    func testTheDaysCallReadsTheWeekShareAndNotTheOldRatio() {
        var flat: [String: Double] = [:]
        for k in LDate.range(ending: today, count: 300, calendar: cal) { flat[k] = 100 }
        for k in LDate.range(ending: today, count: 7, calendar: cal) { flat[k] = 320 }
        let spike = LoadModel.compute(loads: flat, today: today, calendar: cal)
        let clear = BodyWatch(level: .clear, signals: [], title: "", detail: "")
        let call = DayCall.make(recovery: 80, load: spike, sleepDebtMin: 0, watch: clear)
        XCTAssertEqual(call.title, "Ready, but hold the reins")
        XCTAssertTrue(call.reasons.contains("Week load 320% of usual"), "\(call.reasons)")
        XCTAssertFalse(call.reasons.contains { $0.hasPrefix("Load ratio") })
    }
}
