import XCTest
@testable import LumaCore

/// Luma Doctor's weekly check: the athlete's numbers against their own usual range.
final class DoctorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Dublin")!
        c.firstWeekday = 2
        return c
    }()

    /// Saturday 21 November 2026 ends the week checked.
    private let weekEnd = "2026-11-21"

    /// Sixty steady days ending on `weekEnd`, with small day-to-day movement so a range exists.
    private func steady() -> [LDay] {
        LDate.range(ending: weekEnd, count: 60, calendar: calendar).enumerated().map { i, day in
            let wobble = Double((i * 7) % 5) - 2          // −2 … 2, never the same two days running
            return LDay(day: day, sleepMin: 440 + wobble * 8, restingHR: 50 + wobble * 0.6, hrv: 80 + wobble * 3,
                        recovery: 66 + wobble * 4, strain: 55 + wobble * 3, spo2: 96 + wobble * 0.3,
                        skinTempDev: wobble * 0.1, respRate: 14.5 + wobble * 0.15)
        }
    }

    private func check(_ days: [LDay], sleeps: [LSleep] = [], loads: [String: Double] = [:]) -> DoctorReport {
        Doctor.check(days: days, sleeps: sleeps, loads: loads, weekEnd: weekEnd, scheduled: true,
                     now: Date(timeIntervalSince1970: 1_795_000_000), calendar: calendar)
    }

    private func finding(_ report: DoctorReport, _ id: String) -> DoctorFinding? { report.findings.first { $0.id == id } }

    func testASteadyWeekIsSaidToBeInRange() {
        // The same training every day: a load that is what the body is used to.
        var loads: [String: Double] = [:]
        for day in LDate.range(ending: weekEnd, count: 60, calendar: calendar) { loads[day] = 80 }
        let report = check(steady(), loads: loads)
        XCTAssertEqual(report.id, weekEnd)
        XCTAssertEqual(report.weekStart, "2026-11-15")
        XCTAssertEqual(report.nights, 7)
        for id in ["restingHR", "hrv", "respRate", "skinTempDev", "spo2", "together", "sleep", "recovery", "load"] {
            XCTAssertEqual(finding(report, id)?.level, .steady, id)
        }
        XCTAssertEqual(report.headline, "Everything checked is in your usual range")
        XCTAssertEqual(finding(report, "restingHR")?.series.count, 28)
        XCTAssertEqual(report.level, .steady)

        // With no sessions the load cannot be judged. That is not a concern, and it is not passed off as fine.
        let bare = check(steady())
        XCTAssertEqual(finding(bare, "load")?.level, .noData)
        XCTAssertEqual(bare.headline, "What could be checked is in your usual range")
        XCTAssertEqual(bare.level, .steady)
    }

    func testAHeartRateRaisedOnMostNightsIsOutsideTheRange() {
        var days = steady()
        for i in (days.count - 4)..<days.count { days[i].restingHR = 58 }
        let report = check(days)
        let rhr = finding(report, "restingHR")
        XCTAssertEqual(rhr?.level, .outside)
        XCTAssertEqual(rhr?.line.hasPrefix("4 of 7 nights were above your usual range"), true)
        XCTAssertEqual(report.outside.map { $0.id }, ["restingHR"])
        XCTAssertEqual(report.headline, "1 reading outside your usual range")
        // The weekly count is the daily read's own: a night it flagged, and no other.
        let known = days
        let daily = LDate.range(ending: weekEnd, count: 7, calendar: calendar).filter { day in
            guard let row = known.first(where: { $0.day == day }) else { return false }
            return BodyWatch.assess(day: row, baselines: LBaselines.compute(days: known, before: day)).signals
                .contains { $0.metric == .restingHR && $0.flagged }
        }
        XCTAssertEqual(daily.count, 4)
    }

    func testTwoLowNightsAreWorthWatchingAndOneIsNot() {
        var two = steady()
        two[two.count - 2].hrv = 50
        two[two.count - 5].hrv = 52
        XCTAssertEqual(finding(check(two), "hrv")?.level, .watch)
        XCTAssertEqual(check(two).headline, "1 thing worth watching")

        var one = steady()
        one[one.count - 2].hrv = 50
        let single = finding(check(one), "hrv")
        XCTAssertEqual(single?.level, .steady)
        XCTAssertEqual(single?.line.hasSuffix("One night was below it."), true)
    }

    func testSeveralSignalsOffOnOneMorningIsCountedOnce() {
        var days = steady()
        let i = days.count - 3
        days[i].restingHR = 60; days[i].hrv = 45; days[i].respRate = 17; days[i].skinTempDev = 0.9
        let report = check(days)
        XCTAssertEqual(finding(report, "together")?.level, .outside)
        XCTAssertEqual(finding(report, "together")?.figure, "1 morning")
        // One night is not a week: each signal on its own stays in range.
        XCTAssertEqual(finding(report, "restingHR")?.level, .steady)
    }

    func testADriftIsSeenBeforeItLeavesTheRange() {
        var days = steady()
        // A slow rise over four weeks, each night still inside the range the daily read allows.
        for k in 0..<28 { days[days.count - 28 + k].restingHR = 49.5 + Double(k) * 0.14 + (k % 2 == 0 ? 0.05 : -0.05) }
        let rhr = finding(check(days), "restingHR")
        XCTAssertEqual(rhr?.level, .watch)
        XCTAssertEqual(rhr?.line.contains("has risen by about"), true)
    }

    func testTooFewNightsAreNotJudged() {
        var days = steady()
        for i in (days.count - 7)..<(days.count - 2) { days[i] = days[i].withoutNight }
        let report = check(days)
        XCTAssertEqual(report.nights, 2)
        XCTAssertEqual(finding(report, "hrv")?.level, .noData)
        XCTAssertEqual(finding(report, "hrv")?.line, "Only 2 of 7 nights have a reading, too few to judge a week by.")
        XCTAssertEqual(finding(report, "sleep")?.level, .noData)
        // And a first fortnight has no usual range to be held against.
        let early = Array(steady().suffix(10))
        XCTAssertEqual(finding(check(early), "restingHR")?.line, "Luma needs about two weeks of nights before it knows what is usual for you.")
        XCTAssertEqual(check(early).headline, "What could be checked is in your usual range")
        XCTAssertEqual(check([]).headline, "Not enough data to check yet")
    }

    func testAShortWeekOfSleepAndRedMornings() {
        var days = steady()
        for i in (days.count - 7)..<days.count { days[i].sleepMin = 330 }
        for i in (days.count - 3)..<days.count { days[i].recovery = 25 }
        let report = check(days)
        XCTAssertEqual(finding(report, "sleep")?.level, .outside)
        XCTAssertEqual(finding(report, "sleep")?.figure, "5h 30m")
        XCTAssertEqual(finding(report, "recovery")?.level, .outside)
        XCTAssertEqual(finding(report, "recovery")?.line.hasSuffix("3 mornings were in the red."), true)
        XCTAssertEqual(report.headline, "2 readings outside your usual range")
    }

    func testBedtimeThatMovesAroundIsWorthWatching() {
        let week = LDate.range(ending: weekEnd, count: 7, calendar: calendar)
        func night(_ day: String, bedtime minutes: Double) -> LSleep {
            let midnight = LDate.startOfDay(day, calendar: calendar)!.timeIntervalSince1970
            return LSleep(start: midnight + minutes * 60, end: midnight + 7 * 3600, day: day)
        }
        let regular = week.enumerated().map { i, day in night(day, bedtime: -50 + Double(i % 2) * 20) }
        XCTAssertEqual(finding(check(steady(), sleeps: regular), "bedtime")?.level, .steady)
        let late: [Double] = [-60, 120, -30, 150, -90, 100, 0]
        let moving = week.enumerated().map { i, day in night(day, bedtime: late[i]) }
        let found = finding(check(steady(), sleeps: moving), "bedtime")
        XCTAssertEqual(found?.level, .watch)
        XCTAssertEqual(found?.line.contains("earliest 22:30, latest 2:30"), true)
        // Fewer than four nights say nothing about a habit.
        XCTAssertNil(finding(check(steady(), sleeps: Array(regular.prefix(3))), "bedtime"))
    }

    func testALoadSpikeIsReadByTheLoadScreensOwnModel() {
        var loads: [String: Double] = [:]
        let span = LDate.range(ending: weekEnd, count: 60, calendar: calendar)
        for (i, day) in span.enumerated() { loads[day] = i >= 53 ? 260 : 80 }
        let found = finding(check(steady(), loads: loads), "load")
        let state = LoadModel.compute(loads: loads, today: weekEnd, calendar: calendar)
        XCTAssertEqual(state.status, .spike)
        XCTAssertEqual(found?.level, (state.acwr ?? 0) >= 2 ? .outside : .watch)
        XCTAssertEqual(found?.figure, String(format: "%.1f×", state.acwr ?? 0))
    }

    func testTheCheckIsDueFromSundayMidnightForTheWeekJustEnded() {
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }
        // Saturday night: last week's check is the one due.
        XCTAssertEqual(DoctorSchedule.weekEnd(asOf: at(2026, 11, 21, 23, 59), calendar: calendar), "2026-11-14")
        // Five past midnight on Sunday: the week that ended yesterday.
        XCTAssertEqual(DoctorSchedule.weekEnd(asOf: at(2026, 11, 22, 0, 5), calendar: calendar), "2026-11-21")
        XCTAssertEqual(DoctorSchedule.weekEnd(asOf: at(2026, 11, 25, 12, 0), calendar: calendar), "2026-11-21")
        XCTAssertEqual(DoctorSchedule.next(after: at(2026, 11, 22, 0, 5), calendar: calendar), at(2026, 11, 29, 0, 0))
        XCTAssertEqual(DoctorSchedule.next(after: at(2026, 11, 21, 23, 59), calendar: calendar), at(2026, 11, 22, 0, 0))

        let done = check(steady())
        XCTAssertNil(DoctorSchedule.due(now: at(2026, 11, 24, 9, 0), reports: [done], calendar: calendar))
        XCTAssertEqual(DoctorSchedule.due(now: at(2026, 11, 29, 0, 1), reports: [done], calendar: calendar), "2026-11-28")
        // A check asked for by hand does not stand in for the weekly one.
        var asked = done
        asked.scheduled = false
        XCTAssertEqual(DoctorSchedule.due(now: at(2026, 11, 24, 9, 0), reports: [asked], calendar: calendar), "2026-11-21")
    }

    func testWhatIsSentForTheWrittenRead() {
        var days = steady()
        for i in (days.count - 4)..<days.count { days[i].restingHR = 58 }
        let report = check(days)
        let without = DoctorPrompt.ask(report, days: days, shareDays: false, calendar: calendar)
        XCTAssertTrue(without.contains("Week checked: 2026-11-15 to 2026-11-21. Nights with a reading: 7 of 7."))
        XCTAssertTrue(without.contains("- Resting heart rate: Outside your usual range. 4 of 7 nights were above your usual range."))
        XCTAssertFalse(without.contains("2026-11-20:"), "no day-by-day figures without leave to share them")
        let with = DoctorPrompt.ask(report, days: days, shareDays: true, calendar: calendar)
        XCTAssertTrue(with.contains("2026-11-21: "))
        XCTAssertEqual(with.components(separatedBy: "\n").filter { $0.hasPrefix("2026-") }.count, 28)
        XCTAssertFalse(with.contains("2026-10-20:"), "four weeks, no more")
        XCTAssertTrue(DoctorPrompt.system.contains("never diagnose"))
        XCTAssertEqual(DoctorPrompt.tidy("  A steady week.\n"), "A steady week.")
        XCTAssertNil(DoctorPrompt.tidy("  \n "))
    }

    func testTheStrongestModelAKeyReachesComesFirst() {
        let listed = [
            AIModel(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5", line: "sonnet", images: true),
            AIModel(id: "claude-haiku-5-5", name: "Claude Haiku 5.5", line: "haiku", images: true),
            AIModel(id: "claude-opus-5-5", name: "Claude Opus 5.5", line: "opus", images: true),
            AIModel(id: "claude-fable-5-2", name: "Claude Fable 5.2", line: "fable", images: true),
            AIModel(id: "claude-opus-5", name: "Claude Opus 5", line: "opus", images: true),
            AIModel(id: "claude-fable-5-1", name: "Claude Fable 5.1", line: "fable", images: true),
            AIModel(id: "claude-other-1", name: "Other", line: nil, images: true),
        ]
        XCTAssertEqual(AIModel.byStrength(listed).map { $0.id },
                       ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-other-1"])
        // A key that does not reach the top line gets the best it does reach.
        XCTAssertEqual(AIModel.byStrength(Array(listed.prefix(3))).first?.id, "claude-opus-5-5")
        XCTAssertTrue(AIModel.byStrength([]).isEmpty)
    }

    func testAReportSurvivesBeingStored() throws {
        var report = check(steady())
        report.read = "A steady week."
        report.readModel = "claude-fable-5-2"
        report.readAt = Date(timeIntervalSince1970: 1_795_000_500)
        let data = try JSONEncoder().encode([report])
        XCTAssertEqual(try JSONDecoder().decode([DoctorReport].self, from: data), [report])
    }
}
