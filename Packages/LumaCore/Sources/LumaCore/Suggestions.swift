import Foundation

/// Sessions the strap saw and nobody recorded: which detected stretches of raised heart rate are worth
/// putting in front of the athlete, and what each one most likely was.
public enum SessionSuggestions {
    /// The shortest stretch worth asking about.
    public static let minimumSeconds: Double = 15 * 60
    /// A stretch that ended more recently than this may not be over yet.
    public static let settleSeconds: Double = 10 * 60
    /// Dismissals older than this are forgotten: the strap record is only searched a few days back.
    public static let rememberSeconds: Double = 30 * 86_400

    /// The stretches to offer, newest first.
    ///
    /// The strap layer's detector asks only for heart rate held thirty beats above resting for twelve
    /// minutes, which a brisk walk to the bus clears. A stretch is offered as a session when it also
    /// reached training intensity: an average of at least 55 % of maximum heart rate, or a peak of at
    /// least 75 %. Stretches already dismissed, overlapping a stored session, shorter than a quarter of
    /// an hour, or so recent they may still be under way are left out.
    public static func open(_ detected: [LSuggestedSession], workouts: [LWorkout], dismissed: Set<String>,
                            maxHR: Double, now: Double) -> [LSuggestedSession] {
        let averageFloor: Double = 0.55 * maxHR
        let peakFloor: Double = 0.75 * maxHR
        let latestEnd: Double = now - settleSeconds
        let kept = detected.filter { (s: LSuggestedSession) -> Bool in
            guard s.durationS >= minimumSeconds, s.end <= latestEnd, !dismissed.contains(s.id) else { return false }
            guard s.avgHR >= averageFloor || s.peakHR >= peakFloor else { return false }
            return !workouts.contains { (w: LWorkout) -> Bool in w.start < s.end && s.start < w.end }
        }
        return kept.sorted { $0.start > $1.start }
    }

    /// Dismissals still worth remembering, given as the ids of the stretches they refer to.
    public static func prune(_ dismissed: Set<String>, now: Double) -> Set<String> {
        let cutoff: Double = now - rememberSeconds
        return dismissed.filter { (id: String) -> Bool in
            guard let end = id.split(separator: ":").last.flatMap({ Double($0) }) else { return false }
            return end >= cutoff
        }
    }

    /// The plan entry a stretch most likely was, from that day's entries still open: the one whose start
    /// time is nearest. Entries without a time count as far away, so a timed entry close by wins.
    public static func likelyPlan(for stretch: LSuggestedSession, among open: [PlannedSession],
                                  calendar: Calendar = LDate.calendar) -> PlannedSession? {
        let day = LDate.key(Date(timeIntervalSince1970: stretch.start), calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: stretch.start))
        let minute: Int = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let candidates = open.filter { $0.day == day && $0.kind != .rest && $0.status == .planned }
        func distance(_ p: PlannedSession) -> Int { p.startMinutes.map { abs($0 - minute) } ?? 6 * 60 }
        return candidates.min { distance($0) < distance($1) }
    }

    /// The sport a kept stretch is stored under when it fulfils a plan entry of this kind.
    public static func sport(for kind: SessionKind) -> String {
        switch kind {
        case .gymClass, .conditioning: return "Conditioning"
        case .strength: return "Strength"
        case .hyrox, .simulation: return "HYROX"
        case .easyRun, .tempoRun, .intervals, .longRun: return "Running"
        case .mobility: return "Mobility"
        case .rest, .other: return "Workout"
        }
    }
}
