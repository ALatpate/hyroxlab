import XCTest
@testable import LumaCore

final class RecordTests: XCTestCase {
    /// Midnight, 2026-11-15 00:00:00 UTC.
    private let midnight: Double = 1_794_700_800

    private func at(_ hour: Int, _ minute: Int) -> Double { midnight + Double(hour * 3600 + minute * 60) }

    /// One reading a minute from `from` up to, not including, `to`.
    private func readings(_ from: Double, _ to: Double) -> [Double] {
        Array(stride(from: from, to: to, by: 60))
    }

    func testReadingsBecomeStretchesSplitAtHoles() {
        // A four-minute dropout is bridged; a six-minute one is a hole.
        let times = readings(at(0, 10), at(1, 0)) + readings(at(1, 4), at(2, 0)) + readings(at(2, 6), at(2, 30))
        let stretches = RecordCheck.stretches(readingsAt: times.shuffled(), spacing: 60)
        XCTAssertEqual(stretches, [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(2, 6), end: at(2, 30))])
    }

    func testHourlyCoverageAndGaps() {
        let stretches = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        let hours = RecordCheck.hourly(stretches, endingAt: at(10, 1), hours: 11)
        XCTAssertEqual(hours.first?.hourStart, at(0, 0))
        XCTAssertEqual(hours.map { $0.seconds / 60 }, [50, 60, 0, 0, 0, 0, 0, 0, 0, 10, 1])
        let gaps = RecordCheck.gaps(stretches, from: at(0, 0), to: at(10, 1), minimum: 20 * 60)
        // The ten minutes before the first reading are under the minimum.
        XCTAssertEqual(gaps, [RecordStretch(start: at(2, 0), end: at(9, 50))])
    }

    func testReadingsAreLaidOnTheClockWithMissingTimeLeftEmpty() {
        let points = [LHRPoint(t: at(0, 10), bpm: 60, lo: 58, hi: 62), LHRPoint(t: at(0, 20), bpm: 61, lo: 59, hi: 63),
                      LHRPoint(t: at(1, 0), bpm: 70, lo: 66, hi: 75), LHRPoint(t: at(2, 0), bpm: 80, lo: 78, hi: 82)]
        // Ten-minute slots from midnight to 01:10. The forty minutes with nothing stay empty, and a
        // reading past the end is not squeezed in.
        let slots = RecordCheck.slots(points, from: at(0, 0), to: at(1, 10), step: 600)
        XCTAssertEqual(slots, [nil, 60, 61, nil, nil, nil, 70])
        XCTAssertEqual(RecordCheck.slots(points, from: at(0, 0), to: at(0, 0), step: 600), [])
        // Readings come in buckets that start on whole multiples of the step. A window that starts
        // between two of them begins its grid at the bucket that holds its start.
        XCTAssertEqual(RecordCheck.slotStart(at(0, 13), step: 600), at(0, 10))
        XCTAssertEqual(RecordCheck.slots(points, from: at(0, 13), to: at(0, 33), step: 600), [60, 61, nil])
    }

    /// The morning this was written for: asleep at 01:00, up at 09:30, and at 10:01 the phone held the
    /// strap's readings only up to 02:00 and from 09:50.
    func testANightThatEndsWhereTheRecordStopsIsCutOffNotFinished() {
        let stretches = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        let night = RecordCheck.night(start: at(1, 0), end: at(2, 0), stretches: stretches, now: at(10, 1))
        XCTAssertEqual(night, .cutOff(at: at(2, 0), resumes: at(9, 50)))
        XCTAssertFalse(night.isComplete)
        XCTAssertTrue(night.isPartial)
        // Corrected by hand to the real times, the same hole is still there to be named.
        let corrected = RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: stretches, now: at(10, 1))
        XCTAssertEqual(corrected, .cutOff(at: at(2, 0), resumes: at(9, 50)))
    }

    func testANightIsCompleteOnceTheRecordRunsPastItsEnd() {
        let whole = [RecordStretch(start: at(0, 10), end: at(10, 0))]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: whole, now: at(10, 1)), .complete)
        // Up three minutes ago: the record has not run far enough past the night to call it over.
        let justUp = [RecordStretch(start: at(0, 10), end: at(9, 33))]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: justUp, now: at(9, 35)), .stillGoing)
        XCTAssertTrue(NightRecord.stillGoing.isPartial)
        // Forty minutes with nothing after waking (a walk away from the phone) is tolerated.
        let walk = [RecordStretch(start: at(0, 10), end: at(9, 33)), RecordStretch(start: at(10, 13), end: at(10, 30))]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: walk, now: at(10, 30)), .complete)
        // Nothing for over an hour, and the same night was not seen to end.
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: justUp, now: at(10, 40)),
                       .cutOff(at: at(9, 33), resumes: nil))
        // A dropout inside the night that stays under an hour is not a missing night.
        let dropout = [RecordStretch(start: at(0, 10), end: at(4, 0)), RecordStretch(start: at(4, 45), end: at(10, 0))]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: dropout, now: at(10, 1)), .complete)
        // Two hours missing in the middle is.
        let hole = [RecordStretch(start: at(0, 10), end: at(3, 0)), RecordStretch(start: at(5, 0), end: at(10, 0))]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 30), stretches: hole, now: at(10, 1)),
                       .cutOff(at: at(3, 0), resumes: at(5, 0)))
    }

    func testANightWithNoRecordBehindItIsNotJudged() {
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 0), stretches: [], now: at(10, 0)), .complete)
        let yesterday = [RecordStretch(start: at(0, 0) - 20 * 3600, end: at(0, 0) - 19 * 3600)]
        XCTAssertEqual(RecordCheck.night(start: at(1, 0), end: at(9, 0), stretches: yesterday, now: at(10, 0)), .complete)
    }

    func testAMarkedHoleCountsUntilTheRecordFillsIt() {
        let mark = NightMark(day: "2026-11-15", at: at(2, 0), resumes: at(9, 50))
        let asFound = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        XCTAssertTrue(RecordCheck.stillMissing(mark, stretches: asFound))
        // The strap handed over the rest later.
        XCTAssertFalse(RecordCheck.stillMissing(mark, stretches: [RecordStretch(start: at(0, 10), end: at(10, 1))]))
        // Most of it arrived; what is left is under an hour.
        let mostly = [RecordStretch(start: at(0, 10), end: at(9, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        XCTAssertFalse(RecordCheck.stillMissing(mark, stretches: mostly))
        // A record that never started again is judged on the hour after it stopped.
        let open = NightMark(day: "2026-11-15", at: at(2, 0), resumes: nil)
        XCTAssertTrue(RecordCheck.stillMissing(open, stretches: [RecordStretch(start: at(0, 10), end: at(2, 0))]))
        XCTAssertFalse(RecordCheck.stillMissing(open, stretches: [RecordStretch(start: at(0, 10), end: at(2, 30))]))
    }

    func testTheReasonForNoScoreIsResolvedOnceInOrder() {
        let cut = NightRecord.cutOff(at: at(2, 0), resumes: at(9, 50))
        let learning = LCalibration(have: 2, need: 4)
        XCTAssertNil(RecordCheck.gap(recovery: 61, night: cut, reading: true, calibration: learning))
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: cut, reading: true, calibration: learning), .reading)
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: cut, reading: false, calibration: learning), .calibrating(learning))
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: cut, reading: false, calibration: nil), .cutOff(at: at(2, 0)))
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: .none, reading: false, calibration: LCalibration(have: 4, need: 4)), .noNight)
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: .stillGoing, reading: false, calibration: nil), .stillGoing)
        XCTAssertEqual(RecordCheck.gap(recovery: nil, night: .complete, reading: false, calibration: nil), .unscored)
    }

    func testOneNoticeAboutTheDataIsChosenInAFixedOrder() {
        let cut = NightRecord.cutOff(at: at(2, 0), resumes: at(9, 50))
        func notice(connected: Bool = true, secure: Bool = true, syncing: Bool = false, pending: Bool = false,
                    historyEmpty: Bool = false, continuous: Bool = true, needsRestart: Bool = false, syncError: String? = nil,
                    night: NightRecord = .complete) -> DataNotice? {
            DataNotice.resolve(connected: connected, secure: secure, syncing: syncing, parts: 7, pending: pending,
                               historyEmpty: historyEmpty, continuous: continuous, needsRestart: needsRestart,
                               syncError: syncError, lastSync: at(0, 0), night: night)
        }
        XCTAssertNil(notice())
        // Everything wrong at once: the link comes first, because nothing else can move without it.
        XCTAssertEqual(notice(connected: false, secure: false, syncing: true, pending: true, historyEmpty: true, needsRestart: true,
                              syncError: "x", night: cut), .offline(lastSync: at(0, 0)))
        XCTAssertEqual(notice(secure: false, syncing: true, night: cut), .notPaired)
        XCTAssertEqual(notice(syncing: true, pending: true, needsRestart: true, night: cut), .needsRestart)
        XCTAssertEqual(notice(syncing: true, pending: true, night: cut), .reading(parts: 7))
        XCTAssertEqual(notice(pending: true, night: cut), .pending)
        // Once the read is done, a hole in the night is named with its times, and whether it can still fill.
        XCTAssertEqual(notice(syncError: "x", night: cut), .hole(from: at(2, 0), to: at(9, 50), lost: false))
        XCTAssertEqual(notice(historyEmpty: true, night: cut), .hole(from: at(2, 0), to: at(9, 50), lost: true))
        // A strap that hands over nothing stored is a notice only while Luma is not recording all the time.
        XCTAssertEqual(notice(historyEmpty: true, continuous: false, syncError: "x"), .notRecording)
        XCTAssertEqual(notice(historyEmpty: true, syncError: "stopped early"), .syncError("stopped early"))
        XCTAssertNil(notice(historyEmpty: true))
        XCTAssertNil(notice(syncError: ""))
        XCTAssertNil(notice(night: .stillGoing))
    }

    func testTheAnalysisSaysWhyThereIsNoScoreAndHoldsBackWhatItCannotJudge() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = "2026-11-15"
        let now = Date(timeIntervalSince1970: at(10, 1))
        let days = [LDay(day: "2026-11-14", sleepMin: 430, restingHR: 56, hrv: 62),
                    LDay(day: today, sleepMin: 60, restingHR: 70, hrv: 45, respRate: 17.1)]
        let sleeps = [LSleep(start: at(1, 0), end: at(2, 0), day: today, restingHR: 70, hrv: 45)]
        let record = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        let learning = LCalibration(have: 2, need: 4)

        let a = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [],
                                   record: record, reading: false, calibration: learning, today: today, now: now, calendar: cal)
        XCTAssertEqual(a.night, .cutOff(at: at(2, 0), resumes: at(9, 50)))
        XCTAssertEqual(a.gap, .calibrating(learning))
        XCTAssertEqual(a.call.title, "Learning your normal")
        XCTAssertTrue(a.call.body.contains("You have 2"))
        // The Recovery screen words the same reason; it has no second opinion.
        XCTAssertEqual(a.recovery?.headline, "Learning your normal")
        // A night with part of its record missing is not compared with the athlete's normal.
        XCTAssertEqual(a.watch.title, "Not assessed")
        XCTAssertNil(a.lastScored)
        XCTAssertEqual(a.recovery?.factors.count, 4)
        XCTAssertTrue(a.recovery?.factors.allSatisfy { $0.baseline == nil && $0.effect == 0 && $0.note == "From the recorded part" } ?? false)

        // The coach is given the same reason and told how to read the night, so it does not advise as
        // if the athlete had slept one hour.
        let world = CoachWorld(today: today, now: now, profile: LProfile(), days: days, workouts: [], analysis: a, planned: [], routine: [],
                               fuel: [], supplements: [], checkIns: [], lifts: [], sessions: [], benchmarks: Benchmarks(),
                               personalBests: [], notes: [], shareHealth: true)
        let overview = CoachTools.overview(world, calendar: cal)
        XCTAssertEqual(overview["sleep_last_night"]?["partly_recorded"]?.bool, true)
        XCTAssertEqual(overview["sleep_last_night"]?["its_record"]?.string, "the record stops at 02:00, readings start again at 09:50")
        XCTAssertTrue(overview["recovery"]?["why_today_has_no_score"]?.string?.hasPrefix("Learning your normal. ") ?? false)
        let nights = CoachTools.read("get_sleep", input: .object(["start_date": .string("2026-11-14"), "end_date": .string(today)]), world: world, calendar: cal)
        XCTAssertEqual(nights?["nights"]?.array?.map { $0["partly_recorded"]?.bool }, [false, true])
        let rows = CoachTools.read("get_daily_metrics", input: .object(["start_date": .string("2026-11-14"), "end_date": .string(today)]), world: world, calendar: cal)
        XCTAssertEqual(rows?["partly_recorded_nights"]?.array?.compactMap { $0.string }, [today])
        // It is listed with what was recorded, has no score, and is not a short night: the one hour that
        // reached the phone adds nothing to the sleep debt. Only the night before does (35 min short, a day old).
        XCTAssertEqual(a.sleep.last?.partial, true)
        XCTAssertEqual(a.sleep.last?.asleepMin, 60)
        XCTAssertNil(a.sleep.last?.score)
        XCTAssertEqual(a.sleep.debtMin, 31.5, accuracy: 0.001)

        // While the strap's record is still arriving, that is the reason given, whatever else is true.
        let reading = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [],
                                         record: record, reading: true, calibration: learning, today: today, now: now, calendar: cal)
        XCTAssertEqual(reading.gap, .reading)
        XCTAssertEqual(reading.call.title, "Reading last night")

        // Given no record to check against, the same night is taken as it stands: one hour of sleep.
        let plain = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [],
                                       today: today, now: now, calendar: cal)
        XCTAssertEqual(plain.night, .complete)
        XCTAssertEqual(plain.gap, .unscored)
        XCTAssertEqual(plain.call.title, "No recovery score")
        XCTAssertEqual(plain.sleep.last?.partial, false)
        XCTAssertEqual(plain.sleep.debtMin, 436.5, accuracy: 0.001)

        // A record read a while ago says nothing about the time since: judged as of when it was read,
        // the night is still going, not cut off by the hours the phone did not look.
        let stale = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [],
                                       record: [RecordStretch(start: at(0, 10), end: at(2, 0))], recordAsOf: at(2, 5),
                                       today: today, now: now, calendar: cal)
        XCTAssertEqual(stale.night, .stillGoing)
    }

    func testAScoreFromPartOfANightSaysSo() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = "2026-11-15"
        let days = [LDay(day: today, sleepMin: 60, restingHR: 70, hrv: 45, recovery: 61)]
        let sleeps = [LSleep(start: at(1, 0), end: at(2, 0), day: today)]
        let record = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        let a = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [], record: record,
                                   today: today, now: Date(timeIntervalSince1970: at(10, 1)), calendar: cal)
        XCTAssertNil(a.gap)
        XCTAssertTrue(a.call.body.hasSuffix("treat it as a rough guide."))
        let whole = LumaAnalysis.build(days: days, sleeps: sleeps, workouts: [], profile: LProfile(), planned: [],
                                       today: today, now: Date(timeIntervalSince1970: at(10, 1)), calendar: cal)
        XCTAssertFalse(whole.call.body.contains("rough guide"))
    }

    func testAMarkedNightStaysOutOfLaterDebtAndAverages() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let days = [LDay(day: "2026-11-14", sleepMin: 430), LDay(day: "2026-11-15", sleepMin: 60, restingHR: 70, hrv: 45),
                    LDay(day: "2026-11-16", sleepMin: 450)]
        let s = SleepModel.summarize(days: days, sleeps: [], partial: ["2026-11-15"], today: "2026-11-16", calendar: cal)
        XCTAssertEqual(s.nights.map { $0.partial }, [false, true, false])
        XCTAssertNil(s.nights[1].score)
        XCTAssertNotNil(s.nights[2].score)
        // 35 min short two days ago (weighted 0.8) and 15 min short last night: the marked night adds nothing.
        XCTAssertEqual(s.debtMin, 43, accuracy: 0.001)
        XCTAssertEqual(s.avg7Min ?? 0, 440, accuracy: 0.001)
        // The day's own row keeps what it measured; only the night is taken out of what feeds baselines.
        let stripped = days[1].withoutNight
        XCTAssertNil(stripped.sleepMin)
        XCTAssertNil(stripped.restingHR)
        XCTAssertNil(stripped.hrv)
        XCTAssertFalse(stripped.hasNight)
    }

    func testTheReportListsWhatWasRecorded() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = "2026-11-15"
        let record = [RecordStretch(start: at(0, 10), end: at(2, 0)), RecordStretch(start: at(9, 50), end: at(10, 1))]
        let text = RecordReport.text(version: "Version 1, build 2", now: at(10, 1), stretches: record,
                                     night: .cutOff(at: at(2, 0), resumes: at(9, 50)),
                                     sleeps: [LSleep(start: at(1, 0), end: at(2, 0), day: today)],
                                     days: [LDay(day: today, sleepMin: 60, restingHR: 70, hrv: 45)],
                                     marks: [NightMark(day: today, at: at(2, 0), resumes: at(9, 50))],
                                     facts: [LFact("Strap", "Connected", "yes"), LFact("Strap", "Paired", "yes"), LFact("Stored", "Movement readings", "0")],
                                     calendar: cal)
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(Array(lines.prefix(3)), ["Luma data check", "Version 1, build 2", "Sun 15 Nov 10:01"])
        XCTAssertTrue(lines.contains("Sun 15 Nov 10:00  1"))
        XCTAssertTrue(lines.contains("Sun 15 Nov 09:00  10"))
        XCTAssertTrue(lines.contains("Sun 15 Nov 03:00  0"))
        XCTAssertTrue(lines.contains("Sun 15 Nov 01:00  60"))
        XCTAssertTrue(lines.contains("Sun 15 Nov 00:00  50"))
        XCTAssertTrue(lines.contains("02:00 to 09:50 (7h 50m)"))
        XCTAssertTrue(lines.contains("Last night: the record stops at 02:00, readings start again at 09:50"))
        XCTAssertTrue(lines.contains("2026-11-15  01:00 to 02:00  asleep 54m  [marked part night]"))
        XCTAssertTrue(lines.contains("2026-11-15  recovery –  strain –  sleep 60 min  resting 70  HRV 45  breaths –  steps –"))
        // Facts are grouped under the heading they were given, in the order they came.
        let strap = lines.firstIndex(of: "Strap") ?? -1
        XCTAssertEqual(Array(lines[(strap + 1)...(strap + 2)]), ["Connected: yes", "Paired: yes"])
        XCTAssertEqual(Array(lines.suffix(2)), ["Stored", "Movement readings: 0"])
    }
}
