import XCTest
@testable import LumaCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

final class SuggestionTests: XCTestCase {
    private let maxHR: Double = 190
    /// 2026-11-10 12:00:00 UTC.
    private let noon: Double = 1_794_312_000

    private func stretch(_ startOffset: Double, minutes: Double, avg: Double, peak: Double) -> LSuggestedSession {
        let start: Double = noon + startOffset
        return LSuggestedSession(start: start, end: start + minutes * 60, avgHR: avg, peakHR: peak)
    }

    func testOnlyTrainingIntensityIsOffered() {
        let now: Double = noon + 6 * 3600
        let gymClass = stretch(0, minutes: 56, avg: 141, peak: 172)
        // Strength: a modest average, but the peak clears 75 % of 190 (142.5).
        let strength = stretch(3600 + 1800, minutes: 48, avg: 104, peak: 150)
        // A brisk walk: raised enough for the detector, well under 55 % of 190 (104.5) and its peak under 142.5.
        let walk = stretch(3 * 3600, minutes: 25, avg: 96, peak: 118)
        let open = SessionSuggestions.open([walk, gymClass, strength], workouts: [], dismissed: [], maxHR: maxHR, now: now)
        XCTAssertEqual(open.map(\.id), [strength.id, gymClass.id])
    }

    func testShortRecentDismissedAndCoveredStretchesAreLeftOut() {
        let now: Double = noon + 4 * 3600
        let short = stretch(0, minutes: 14, avg: 150, peak: 175)
        let dismissed = stretch(1800, minutes: 40, avg: 150, peak: 175)
        // Ended five minutes before `now`: it may not be over.
        let recent = stretch(4 * 3600 - 45 * 60, minutes: 40, avg: 150, peak: 175)
        let covered = stretch(2 * 3600, minutes: 40, avg: 150, peak: 175)
        let stored = LWorkout(start: covered.start + 300, end: covered.end + 300, sport: "Strength")
        let free = stretch(-3 * 3600, minutes: 30, avg: 150, peak: 175)
        let open = SessionSuggestions.open([short, dismissed, recent, covered, free], workouts: [stored],
                                           dismissed: [dismissed.id], maxHR: maxHR, now: now)
        XCTAssertEqual(open.map(\.id), [free.id])
    }

    func testDismissalsAreForgottenAfterAMonth() {
        let now: Double = noon
        let recentEnd: Double = now - 2 * 86_400
        let oldEnd: Double = now - 31 * 86_400
        let recent = "\(Int(recentEnd - 1800)):\(Int(recentEnd))"
        let old = "\(Int(oldEnd - 1800)):\(Int(oldEnd))"
        XCTAssertEqual(SessionSuggestions.prune([recent, old, "not-a-stretch"], now: now), [recent])
    }

    func testLikelyPlanIsTheNearestOpenEntryThatDay() {
        let cal = utc()
        // 18:30 UTC on 2026-11-10.
        let evening = stretch(6 * 3600 + 1800, minutes: 55, avg: 140, peak: 170)
        let morning = PlannedSession(day: "2026-11-10", kind: .strength, title: "Strength class", startMinutes: 6 * 60 + 30)
        let night = PlannedSession(day: "2026-11-10", kind: .hyrox, title: "HYROX class", startMinutes: 18 * 60 + 30)
        let untimed = PlannedSession(day: "2026-11-10", kind: .mobility, title: "Mobility")
        let rest = PlannedSession(day: "2026-11-10", kind: .rest, title: "Rest")
        let otherDay = PlannedSession(day: "2026-11-11", kind: .easyRun, title: "Easy run", startMinutes: 18 * 60 + 30)
        let skipped = PlannedSession(day: "2026-11-10", kind: .conditioning, title: "Conditioning", status: .skipped, startMinutes: 18 * 60 + 35)
        let pick = SessionSuggestions.likelyPlan(for: evening, among: [morning, untimed, rest, otherDay, skipped, night], calendar: cal)
        XCTAssertEqual(pick?.id, night.id)
        // With no timed entry near, an untimed one (six hours away by rule) beats one twelve hours away.
        let pickUntimed = SessionSuggestions.likelyPlan(for: evening, among: [morning, untimed], calendar: cal)
        XCTAssertEqual(pickUntimed?.id, untimed.id)
        XCTAssertNil(SessionSuggestions.likelyPlan(for: evening, among: [rest, otherDay], calendar: cal))
        XCTAssertEqual(SessionSuggestions.sport(for: night.kind), "HYROX")
        XCTAssertEqual(LSportKind.classify(SessionSuggestions.sport(for: .gymClass)), .conditioning)
        XCTAssertTrue(SessionKind.longRun.matches(LSportKind.classify(SessionSuggestions.sport(for: .longRun))))
    }
}

final class ZoneTimeTests: XCTestCase {
    func testTimeInZonesFromAHeartRateSeries() {
        // Max 200: zones start at 100, 120, 140, 160 and 180.
        let zones = HXZones.fromMaxHR(200)
        let readings: [Double] = [90, 100, 119, 120, 150, 150, 165, 181, 200]
        let points = readings.enumerated().map { LHRPoint(t: Double($0.offset) * 30, bpm: $0.element) }
        let seconds = zones.seconds(from: points, spacing: 30)
        // 90 is under zone 1 and is not counted.
        XCTAssertEqual(seconds, [60, 30, 60, 30, 60])
        XCTAssertEqual(seconds.reduce(0, +), 240)
    }
}
