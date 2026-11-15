#if os(iOS)
import Foundation
import WhoopProtocol
import WhoopStore
import StrandAnalytics
import StrandDesign
import LumaCore
import LumaUI

/// Reads the strap's data for Luma's interface. Everything comes through `Repository`, the same
/// reads the scoring pipeline itself uses, so Luma shows the recovery, strain and sleep that were
/// computed on this phone rather than a second calculation of them.
@MainActor
final class LumaRepoSource: LumaDataSource {
    private let repo: Repository
    /// The stored rows behind the sessions last handed to the interface, keyed by `LWorkout.id`, so an
    /// edit or a delete can name the exact row it replaces.
    private var rows: [String: WorkoutRow] = [:]
    /// The state of the strap link, supplied by the bridge, for the data check.
    var linkFacts: (() -> [LFact])?

    init(repo: Repository) { self.repo = repo }

    /// Efficiency is stored as a fraction by the strap pipeline and as a percentage by imports.
    private static func percent(_ v: Double?) -> Double? { v.map { $0 <= 1 ? $0 * 100 : $0 } }

    // MARK: Days

    func loadDays() async -> [LDay] {
        let days = repo.days
        guard !days.isEmpty else { return [] }
        let rest = await repo.exploreSeries(key: "sleep_performance", source: Repository.whoopSource)
        let restByDay = Dictionary(rest.map { ($0.day, $0.value) }, uniquingKeysWith: { _, last in last })
        let imported = repo.importedSleep
        return days.map { d in
            // A skin-temperature "deviation" of 20 °C or more is an imported absolute reading.
            let deviation = d.skinTempDevC.flatMap { $0 < 20 ? $0 : nil }
            let absolute = d.skinTempC ?? d.skinTempDevC.flatMap { $0 >= 20 ? $0 : nil }
            return LDay(day: d.day, sleepMin: d.totalSleepMin, sleepEfficiency: Self.percent(d.efficiency), deepMin: d.deepMin,
                        remMin: d.remMin, lightMin: d.lightMin, disturbances: d.disturbances, restingHR: d.restingHr.map { Double($0) },
                        hrv: d.avgHrv, sdnn: d.avgSdnn, recovery: d.recovery, strain: d.strain, workouts: d.exerciseCount,
                        spo2: d.spo2Pct, skinTempDev: deviation, skinTemp: absolute, respRate: d.respRateBpm, steps: d.steps,
                        activeKcal: d.activeKcalEst, sleepScore: restByDay[d.day], sleepNeedMin: imported[d.day]?.needMin)
        }
    }

    // MARK: Sleep

    func loadSleeps(days: Int) async -> [LSleep] {
        let sessions = await repo.allSleepSessions(days: days)
        guard !sessions.isEmpty else { return [] }
        let habitual = await repo.habitualMidsleepSec(days: days)
        var out: [LSleep] = []
        // Grouped and classified exactly as the scoring pipeline does: every block belongs to the local
        // day it ends on; the bridged main-night group is the night, and only blocks outside it are naps.
        for blocks in SleepModel.navDays(navSessions: sessions) {
            guard let anchor = blocks.last else { continue }
            let day = Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(anchor.endTs)))
            let group = SleepView.mainNightGroup(blocks, habitualMidsleepSec: habitual)
            let mainStarts = Set(group.map(\.startTs))
            if let last = group.last {
                let onset = SleepModel.nightOnsetTs(group)
                let fragments = group.filter { $0.effectiveStartTs >= onset }
                var stages: [LStage] = fragments.flatMap { Self.stages($0) }
                for (previous, next) in zip(fragments, fragments.dropFirst()) where next.effectiveStartTs > previous.endTs {
                    stages.append(LStage(start: Double(previous.endTs), end: Double(next.effectiveStartTs), kind: .awake))
                }
                stages.sort { $0.start < $1.start }
                let longest = fragments.max { ($0.endTs - $0.effectiveStartTs) < ($1.endTs - $1.effectiveStartTs) } ?? last
                out.append(LSleep(start: Double(onset), end: Double(last.endTs), day: day, efficiency: Self.efficiency(fragments, stages: stages),
                                  restingHR: longest.restingHr.map { Double($0) }, hrv: longest.avgHrv, stages: stages, isNap: false,
                                  incomplete: fragments.contains { $0.stagingSparse == true }))
            }
            for nap in blocks where !mainStarts.contains(nap.startTs) {
                let stages = Self.stages(nap)
                out.append(LSleep(start: Double(nap.effectiveStartTs), end: Double(nap.endTs), day: day,
                                  efficiency: Self.efficiency([nap], stages: stages), restingHR: nap.restingHr.map { Double($0) },
                                  hrv: nap.avgHrv, stages: stages, isNap: true, incomplete: nap.stagingSparse == true))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    /// A block's stage timeline in unix seconds. Imported nights carry stage totals only, with no
    /// timeline: those return nothing here and keep their stored efficiency.
    private static func stages(_ block: CachedSleepSession) -> [LStage] {
        guard let decoded = SleepView.decodeSegments(block.stagesJSON, sessionStart: block.effectiveStartTs) else { return [] }
        let base = Double(block.effectiveStartTs)
        return decoded.intervals.map { interval in
            let kind: LStageKind
            switch interval.stage {
            case .awake: kind = .awake
            case .light: kind = .light
            case .deep: kind = .deep
            case .rem: kind = .rem
            }
            return LStage(start: base + interval.start, end: base + interval.end, kind: kind)
        }
    }

    private static func efficiency(_ blocks: [CachedSleepSession], stages: [LStage]) -> Double? {
        let total = stages.reduce(0.0) { $0 + $1.minutes }
        if total > 0 {
            let asleep = stages.filter { $0.kind != .awake }.reduce(0.0) { $0 + $1.minutes }
            return asleep / total * 100
        }
        return percent(blocks.first?.efficiency)
    }

    // MARK: Sessions

    func loadWorkouts(days: Int) async -> [LWorkout] {
        let stored = await repo.workoutRows(days: days)
        var byID: [String: WorkoutRow] = [:]
        let out = stored.map { row -> LWorkout in
            let workout = Self.workout(row)
            byID[workout.id] = row
            return workout
        }
        rows = byID
        return out
    }

    static func workout(_ row: WorkoutRow) -> LWorkout {
        let kind = WorkoutSource.classify(row.source)
        return LWorkout(start: Double(row.startTs), end: Double(row.endTs), sport: row.sport, source: row.source, durationS: row.durationS,
                        kcal: row.energyKcal, avgHR: row.avgHr.map { Double($0) }, maxHR: row.maxHr.map { Double($0) }, strain: row.strain,
                        distanceM: row.distanceM, zonePct: WorkoutZones.percents(row.zonesJSON), notes: row.notes,
                        editable: kind == .manual || kind == .detected)
    }

    func saveWorkout(_ workout: LWorkout, replacing old: LWorkout?) async {
        let previous = old.flatMap { rows[$0.id] } ?? rows[workout.id]
        let row = WorkoutRow(startTs: Int(workout.start), endTs: Int(workout.end), sport: workout.sport, source: "manual",
                             durationS: workout.durationS, energyKcal: workout.kcal, avgHr: workout.avgHR.map { Int($0.rounded()) },
                             maxHr: workout.maxHR.map { Int($0.rounded()) }, strain: workout.strain, distanceM: workout.distanceM,
                             zonesJSON: previous?.zonesJSON, notes: workout.notes, steps: previous?.steps)
        await repo.saveManualWorkout(row, replacing: old.flatMap { rows[$0.id] })
        await repo.refresh()
    }

    func deleteWorkout(_ workout: LWorkout) async {
        guard let row = rows[workout.id] else { return }
        await repo.deleteWorkout(row)
        await repo.refresh()
    }

    // MARK: Recovery baseline

    /// How many nights the recovery baseline has of the number it needs, counted exactly as the strap
    /// layer counts them for its own ring; nil once there are enough, or once today has a score.
    func calibration() async -> LCalibration? {
        let history = repo.chargeBaselines?.hrvHistory
        guard let have = RecoveryScorer.calibrationNights(nightlyHrv: history?.values ?? [], dayKeys: history?.dayKeys ?? [],
                                                          hasRecovery: repo.today?.recovery != nil) else { return nil }
        return LCalibration(have: have, need: Baselines.minNightsSeed)
    }

    // MARK: Data check

    /// What is stored on the phone for the last day, as counts, and the sleep blocks as the strap layer
    /// holds them, after the state of the strap link. Read fresh each time; nothing is interpreted.
    func facts() async -> [LFact] {
        var out: [LFact] = linkFacts?() ?? []
        let calendar = Calendar.current
        let now = Int(Date().timeIntervalSince1970)
        let from = now - 86_400
        func count(_ n: Int, cap: Int) -> String { n >= cap ? "\(LFormat.grouped(Double(cap))) or more" : LFormat.grouped(Double(n)) }

        let stored = "Stored on this phone, last 24 hours"
        // One reading a second is 86,400 a day, so these limits are only reached by a duplicate record.
        let hr: [HRSample] = await repo.hrSamples(from: from, to: now, limit: 120_000)
        out.append(LFact(stored, "Heart-rate readings", count(hr.count, cap: 120_000)))
        let newest: Int? = hr.map { $0.ts }.max()
        out.append(LFact(stored, "Newest heart-rate reading", newest.map { RecordReport.stamp(Double($0), calendar: calendar) } ?? "none"))
        let beats = await repo.rrIntervals(from: from, to: now, limit: 200_000)
        out.append(LFact(stored, "Beat-to-beat intervals", count(beats.count, cap: 200_000)))
        let motion = await repo.gravitySamplesUnion(from: from, to: now, limit: 200_000)
        out.append(LFact(stored, "Movement readings", count(motion.count, cap: 200_000)))

        let blocks = "Sleep blocks as the strap layer holds them"
        let sessions = await repo.allSleepSessions(days: 3)
        if sessions.isEmpty { out.append(LFact(blocks, "Last three days", "none")) }
        for (index, block) in sessions.sorted(by: { $0.endTs > $1.endTs }).prefix(6).enumerated() {
            var value: String = RecordReport.stamp(Double(block.effectiveStartTs), calendar: calendar) + " to "
                + RecordReport.stamp(Double(block.endTs), calendar: calendar)
            if block.userEdited { value += ", times set by hand" }
            if block.stagingSparse == true { value += ", staged on sparse movement" }
            out.append(LFact(blocks, "Block \(index + 1)", value))
        }
        return out
    }

    // MARK: Suggested sessions

    /// Stretches of raised heart rate that no stored session covers, found by the strap layer's own
    /// detector over the raw heart-rate record: heart rate held thirty beats above resting for twelve
    /// minutes, short dips tolerated, with every stored session's window excluded. A pure read; the
    /// detector's opt-in prompt in the earlier shell is not involved and nothing is stored here.
    func suggestedSessions(days: Int) async -> [LSuggestedSession] {
        let now = Int(Date().timeIntervalSince1970)
        let from = now - max(1, days) * 86_400
        // One reading a second: three days is about 260,000.
        let samples: [HRSample] = await repo.hrSamples(from: from, to: now, limit: 320_000)
        guard samples.count >= 2 else { return [] }
        let resting: Int? = repo.days.last(where: { $0.restingHr != nil })?.restingHr
        let stored = await repo.workoutRows(days: max(1, days) + 1)
        let saved = stored.map { SavedWorkoutSpan(startSec: $0.startTs, endSec: $0.endTs) }
        let hr: [(ts: Int, bpm: Int)] = samples.map { (ts: $0.ts, bpm: $0.bpm) }
        let found: [DetectedWorkout] = await Task.detached(priority: .utility) {
            AutoWorkoutDetector.detect(hr: hr, restingBpm: resting, savedSpans: saved)
        }.value
        return found.map {
            LSuggestedSession(start: Double($0.startSec), end: Double($0.endSec), avgHR: Double($0.avgBpm), peakHR: Double($0.peakBpm))
        }
    }

    // MARK: Series

    func heartRate(from: Double, to: Double, bucketSeconds: Int) async -> [LHRPoint] {
        guard to > from else { return [] }
        let buckets = await repo.hrBuckets(from: Int(from), to: Int(to), bucketSeconds: max(1, bucketSeconds))
        return buckets.map { LHRPoint(t: Double($0.ts), bpm: $0.bpm, lo: $0.minBpm, hi: $0.maxBpm) }
    }

    func hrvSeries(from: Double, to: Double) async -> [LPoint] {
        guard to > from else { return [] }
        let series = await repo.timelineSeries(metric: .hrv, from: Int(from), to: Int(to))
        return series.points.map { LPoint(t: $0.date.timeIntervalSince1970, v: $0.value) }
    }

    func route(for workout: LWorkout) async -> [LCoord] {
        guard let route = RouteStore.load(startTs: Int(workout.start), sport: workout.sport) else { return [] }
        return RouteMath.decode(route.polyline).map { LCoord(lat: $0.lat, lon: $0.lon) }
    }

    func stress(day: String) async -> LStressDay? {
        let calendar = Calendar.current
        guard let noon = LDate.date(day, calendar: calendar) else { return nil }
        let start = calendar.startOfDay(for: noon)
        let now = Date()
        guard start <= now else { return nil }
        // Today is scored up to this moment; an earlier day up to its last second.
        let until = calendar.isDate(start, inSameDayAs: now) ? now : start.addingTimeInterval(86_399)
        guard let scored = await StressDayCurve.today(repo: repo, now: until, calendar: calendar) else { return nil }
        let hours = scored.result.hours.map { LStressHour(hour: $0.hour, level: $0.level, meanHR: $0.meanHR) }
        guard hours.contains(where: { $0.level != nil }) else { return nil }
        return LStressDay(hours: hours, mean: scored.result.dayMean, highMinutes: scored.result.highStressMinutes)
    }

    func heartRateRecovery(for workout: LWorkout, maxHR: Double) async -> LHRRecovery? {
        guard let result = await repo.workoutHeartRateRecovery(from: Int(workout.start), to: Int(workout.end), maxHR: maxHR,
                                                               source: workout.source), result.hasMeasurement else { return nil }
        return LHRRecovery(endHR: Double(result.endHR), drop1: result.after1Minute.map { Double($0) },
                           drop2: result.after2Minutes.map { Double($0) })
    }
}
#endif
