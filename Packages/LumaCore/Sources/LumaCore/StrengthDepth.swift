import Foundation

// MARK: - Deeper strength

/// The heaviest load done for at least a number of reps.
public struct RepBest: Equatable, Sendable, Identifiable {
    public var id: Int { reps }
    public let reps: Int
    public let kg: Double
    public let day: String
}

/// One day a lift was done.
public struct LiftDay: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let sessionID: UUID
    public let sets: Int
    /// The day's heaviest set as it was logged: "5 × 100 kg".
    public let top: String
    public let e1RM: Double?
}

/// Everything logged for one lift.
public struct LiftHistory: Equatable, Sendable {
    public let name: String
    /// Newest first.
    public let days: [LiftDay]
    public let bests: [RepBest]
    public let progress: LiftProgress?
    /// The lift moves the body's own weight, so its loads are what was added to it.
    public let bodyweight: Bool
    /// Said when the lift has not moved in six weeks.
    public let stall: String?
}

public struct StalledLift: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let sessions: Int
    public let text: String
}

/// A muscle's sets week by week, oldest first; the last entry is the seven days ending today.
public struct MuscleWeeks: Equatable, Sendable, Identifiable {
    public var id: String { muscle.rawValue }
    public let muscle: Muscle
    public let sets: [Double]

    public var mean: Double { sets.isEmpty ? 0 : sets.reduce(0, +) / Double(sets.count) }
}

public enum StrengthDepth {
    public static let repMarks = [1, 3, 5, 8]
    /// A lift is called stalled only when it has been trained this often in the six weeks it did not move.
    public static let stallSessions = 3

    /// The heaviest load done for at least 1, 3, 5 and 8 reps. For a lift that moves the body's own
    /// weight the load is what was added, and a set with nothing added counts as zero.
    public static func repBests(_ name: String, sessions: [LiftSession]) -> [RepBest] {
        let own = ExerciseLibrary.match(name)?.bodyweight ?? false
        var best: [Int: (kg: Double, day: String)] = [:]
        for s in sessions.sorted(by: { $0.start < $1.start }) {
            for e in s.exercises where e.name == name {
                for set in e.sets where set.done && set.reps > 0 && (own || set.kg > 0) {
                    for mark in repMarks where set.reps >= mark {
                        if set.kg > (best[mark]?.kg ?? -1) { best[mark] = (set.kg, s.day) }
                    }
                }
            }
        }
        return repMarks.compactMap { m in best[m].map { RepBest(reps: m, kg: $0.kg, day: $0.day) } }
    }

    public static func history(_ name: String, sessions: [LiftSession], progress: TrainingProgress, bodyKg: Double, today: String,
                               calendar: Calendar = LDate.calendar) -> LiftHistory {
        let own = ExerciseLibrary.match(name)?.bodyweight ?? false
        var byDay: [String: LiftDay] = [:]
        for s in sessions {
            for e in s.exercises where e.name == name {
                let done = e.sets.filter { $0.done && $0.hasContent }
                guard !done.isEmpty else { continue }
                let heaviest = done.max { ($0.kg, $0.reps) < ($1.kg, $1.reps) }
                let estimate = LiftMath.best(e, bodyKg: bodyKg)
                let day = LiftDay(day: s.day, sessionID: s.id, sets: done.count, top: heaviest?.text ?? "", e1RM: estimate)
                // Two sessions on one day: keep the one with the better estimate.
                if let old = byDay[s.day], (old.e1RM ?? 0) >= (estimate ?? 0) { continue }
                byDay[s.day] = day
            }
        }
        let lift = progress.lifts.first { $0.name == name }
        let stall = stalled(progress, sessions: sessions, today: today, calendar: calendar).first { $0.name == name }?.text
        return LiftHistory(name: name, days: byDay.values.sorted { $0.day > $1.day }, bests: repBests(name, sessions: sessions),
                           progress: lift, bodyweight: own, stall: stall)
    }

    /// Lifts whose best of the last six weeks is within the "steady" margin of the six weeks before,
    /// although they were trained regularly in that time.
    public static func stalled(_ progress: TrainingProgress, sessions: [LiftSession], today: String,
                               calendar: Calendar = LDate.calendar) -> [StalledLift] {
        var out: [StalledLift] = []
        for lift in progress.lifts where lift.trend == .steady {
            let recent = lift.points.filter { LDate.daysBetween($0.day, today, calendar: calendar) < TrainingProgress.trendDays }.count
            guard recent >= stallSessions, let now = lift.recentBest else { continue }
            let text = "\(lift.name) has stayed at about \(Int(now.rounded())) kg estimated max for twelve weeks, over \(recent) sessions in the last six."
            out.append(StalledLift(name: lift.name, sessions: recent, text: text))
        }
        return out.sorted { $0.sessions > $1.sessions }
    }

    /// Sets for each muscle in each of the last `weeks` seven-day spans, counted the one way sets are
    /// counted (`TrainingProgress.sets`). Only muscles that had any.
    public static func weeklySets(sessions: [LiftSession], today: String, weeks: Int = 8,
                                  calendar: Calendar = LDate.calendar) -> [MuscleWeeks] {
        let past = sessions.filter { $0.day <= today }
        let ago: [UUID: Int] = Dictionary(past.map { ($0.id, LDate.daysBetween($0.day, today, calendar: calendar)) }, uniquingKeysWith: { a, _ in a })
        var perWeek: [[Muscle: Double]] = []
        for w in (0..<weeks).reversed() {
            perWeek.append(TrainingProgress.sets(sessions: past, ago: ago, from: w * 7, to: w * 7 + 7))
        }
        return Muscle.allCases.compactMap { m in
            let sets = perWeek.map { $0[m] ?? 0 }
            return sets.contains { $0 > 0 } ? MuscleWeeks(muscle: m, sets: sets) : nil
        }
    }
}

// MARK: - Easing off

/// An offer to make a hard session easier after two low-recovery mornings in a row.
public struct EaseOffer: Equatable, Sendable {
    public let session: PlannedSession
    public let eased: PlannedSession
    public let reason: String
}

public enum EaseOff {
    /// Easing by recovery has shown a small gain in fitness measures and none clear in performance
    /// across the studies that tried it, so this is an offer the athlete can decline, never a rule.
    public static func offer(days: [LDay], today: String, planned: [PlannedSession], settled: Set<UUID>,
                             calendar: Calendar = LDate.calendar) -> EaseOffer? {
        let yesterday = LDate.adding(-1, to: today, calendar: calendar)
        guard let now = days.last(where: { $0.day == today })?.recovery, let before = days.last(where: { $0.day == yesterday })?.recovery,
              RecoveryBand.of(now) == .low, RecoveryBand.of(before) == .low else { return nil }
        let hard = planned.filter { $0.day == today && $0.status == .planned && $0.intensity == .hard && $0.kind != .rest && !settled.contains($0.id) }
            .sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
        guard let session = hard.first else { return nil }
        let reason = "Recovery was \(Int(before.rounded()))% yesterday and \(Int(now.rounded()))% today."
        return EaseOffer(session: session, eased: eased(session), reason: reason)
    }

    /// The easier version of a session: the same slot, shorter and easy. A hard run becomes an easy run;
    /// a class stays the class, done holding back.
    public static func eased(_ p: PlannedSession) -> PlannedSession {
        var e = p
        e.intensity = .easy
        e.durationMin = max(20, Int((Double(p.durationMin) * 0.75 / 5).rounded()) * 5)
        e.targetPaceSPerKm = nil
        let note = "Eased after two low-recovery days: keep it conversational and leave the top sets."
        e.detail = p.detail.isEmpty ? note : note + " " + p.detail
        let hardRuns: [SessionKind] = [.intervals, .tempoRun, .longRun]
        if hardRuns.contains(p.kind) {
            e.kind = .easyRun
            e.title = "Easy run"
        }
        return e
    }
}
