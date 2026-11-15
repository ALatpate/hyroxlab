import Foundation

/// A stretch of time with heart-rate readings in it and no hole longer than the bridging tolerance.
public struct RecordStretch: Equatable, Sendable {
    /// Unix seconds.
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start; self.end = end
    }

    public var seconds: Double { max(0, end - start) }
}

/// How complete the record behind a night is. A night is only as complete as the heart-rate record it
/// was read from: a night that ends where the record ends has not been seen to end.
public enum NightRecord: Equatable, Sendable {
    /// No night for the day.
    case none
    /// No heart-rate record covers the night (an imported night, or none was read), so it is not judged
    /// and is taken as it is stored. Nothing is known about it either way.
    case unjudged
    /// The record ends with the night and has not been quiet for long: the night may not be over, or
    /// what followed may simply not have arrived yet.
    case stillGoing
    /// An hour or more of the night, or of the time right after the record of it stops, has no readings.
    /// The record stops at `at`; `resumes` is when readings start again, if they do.
    case cutOff(at: Double, resumes: Double?)
    /// Whole: the record covers the night, and no hour or more is missing in it or right after it.
    case complete

    public var isComplete: Bool { self == .complete }

    /// The night's figures describe only part of it, or a night that may not have ended.
    public var isPartial: Bool {
        switch self {
        case .cutOff, .stillGoing: return true
        case .none, .unjudged, .complete: return false
        }
    }
}

/// A night Luma found only part of in the record. Kept on the phone, because the record that shows it
/// is only looked at for a day and a half, while the night goes on counting toward averages for weeks.
public struct NightMark: Codable, Equatable, Sendable {
    /// Wake-day key.
    public var day: String
    /// Where the record stops, unix seconds.
    public var at: Double
    /// Where readings start again, if they did.
    public var resumes: Double?

    public init(day: String, at: Double, resumes: Double?) {
        self.day = day; self.at = at; self.resumes = resumes
    }
}

/// How many nights the recovery baseline has, of the number it needs before the first score.
public struct LCalibration: Equatable, Sendable {
    public var have: Int
    public var need: Int

    public init(have: Int, need: Int) {
        self.have = have; self.need = need
    }
}

/// Why a day has no recovery score. One resolver (`RecordCheck.gap`), so the ring, its caption and the
/// day's call cannot give different reasons, and none of them names a cause that was not established.
public enum RecoveryGap: Equatable, Sendable {
    /// The strap's stored record is being read, or it holds data the phone has not read yet.
    case reading
    /// The baseline a score is measured against is still being learned.
    case calibrating(LCalibration)
    case noNight
    case stillGoing
    case cutOff(at: Double)
    /// A night with a full record and no score, for a reason that is not known here.
    case unscored
}

/// Where the heart-rate record has data and where it does not, and what that means for a night.
public enum RecordCheck {
    /// Readings closer together than this belong to one stretch.
    public static let bridgeSeconds: Double = 5 * 60
    /// A night counts as complete once the record runs this far past its end; a record that ended more
    /// recently than this may simply not have caught up.
    public static let settleSeconds: Double = 15 * 60

    /// Stretches of record from the times of readings, in any order. `spacing` is how long one reading
    /// stands for, so a stretch ends `spacing` after its last reading.
    public static func stretches(readingsAt times: [Double], spacing: Double,
                                 bridge: Double = bridgeSeconds) -> [RecordStretch] {
        let sorted = times.sorted()
        var out: [RecordStretch] = []
        for t in sorted {
            if let last = out.last, t - last.end <= bridge {
                out[out.count - 1].end = max(last.end, t + spacing)
            } else {
                out.append(RecordStretch(start: t, end: t + spacing))
            }
        }
        return out
    }

    /// Seconds of record in each of the `hours` clock hours ending with the hour that contains `end`,
    /// oldest first. `hourStart` is the unix time each hour begins.
    public static func hourly(_ stretches: [RecordStretch], endingAt end: Double, hours: Int) -> [(hourStart: Double, seconds: Double)] {
        let lastHour: Double = (end / 3600).rounded(.down) * 3600
        var out: [(hourStart: Double, seconds: Double)] = []
        for i in stride(from: hours - 1, through: 0, by: -1) {
            let from: Double = lastHour - Double(i) * 3600
            let to: Double = min(from + 3600, end)
            var seconds: Double = 0
            for s in stretches where s.end > from && s.start < to {
                seconds += max(0, min(s.end, to) - max(s.start, from))
            }
            out.append((hourStart: from, seconds: seconds))
        }
        return out
    }

    /// Where the slot grid for readings from `from` begins. Readings arrive in buckets that start on
    /// whole multiples of the step, so the grid does too: the bucket that holds `from` starts a little
    /// before it and is the first slot.
    public static func slotStart(_ from: Double, step: Double) -> Double {
        step > 0 ? (from / step).rounded(.down) * step : from
    }

    /// Readings laid out on evenly spaced slots from `from` up to `to`, nil where nothing was recorded,
    /// so a chart leaves missing time empty instead of joining the line across it. Slot `i` begins at
    /// `slotStart(from, step:) + i * step`.
    public static func slots(_ points: [LHRPoint], from: Double, to: Double, step: Double) -> [Double?] {
        guard step > 0, to > from else { return [] }
        let origin: Double = slotStart(from, step: step)
        let count: Int = Int(((to - origin) / step).rounded(.up))
        var out = [Double?](repeating: nil, count: count)
        for p in points {
            let i: Int = Int(((p.t - origin) / step).rounded(.down))
            if i >= 0 && i < count { out[i] = p.bpm }
        }
        return out
    }

    /// Holes in the record between `from` and `to` that are at least `minimum` seconds long, oldest first.
    public static func gaps(_ stretches: [RecordStretch], from: Double, to: Double, minimum: Double) -> [RecordStretch] {
        var out: [RecordStretch] = []
        var cursor: Double = from
        for s in stretches.sorted(by: { $0.start < $1.start }) where s.end > from && s.start < to {
            if s.start - cursor >= minimum { out.append(RecordStretch(start: cursor, end: s.start)) }
            cursor = max(cursor, s.end)
        }
        if to - cursor >= minimum { out.append(RecordStretch(start: cursor, end: to)) }
        return out
    }

    /// Missing readings add up to a missing part of the night once they reach this. Anything shorter (a
    /// dropped link, a walk away from the phone after waking) is tolerated: at most that much is unseen.
    public static let holeSeconds: Double = 60 * 60
    /// The shortest hole the data check lists.
    public static let listedHoleSeconds: Double = 20 * 60

    /// How complete the record behind a night from `start` to `end` is. `now` is the moment the record
    /// was read, not the wall clock: a record read a while ago says nothing about the time since.
    public static func night(start: Double, end: Double, stretches: [RecordStretch], now: Double) -> NightRecord {
        let sorted = stretches.sorted { $0.start < $1.start }
        let inside = sorted.filter { $0.end > start && $0.start < end }
        // Nothing of this night is in the record (an imported night): not judged.
        guard let last = inside.last else { return .unjudged }
        // A hole inside the night, up to where the record itself ends.
        if let hole = gaps(inside, from: start, to: min(end, last.end), minimum: holeSeconds).first {
            return .cutOff(at: hole.start, resumes: hole.end)
        }
        // Then the end of the record against the end of the night.
        let recordEnd: Double = last.end
        if recordEnd - end >= settleSeconds { return .complete }
        // The record stops with the night, so its end was not observed. How long nothing followed decides.
        if let resumes = sorted.first(where: { $0.start > recordEnd })?.start {
            return resumes - recordEnd >= holeSeconds ? .cutOff(at: recordEnd, resumes: resumes) : .complete
        }
        return now - recordEnd >= holeSeconds ? .cutOff(at: recordEnd, resumes: nil) : .stillGoing
    }

    /// Whether the hole a mark names is still a hole, given the record around it now. A hole fills when
    /// the strap hands over its stored record later.
    public static func stillMissing(_ mark: NightMark, stretches: [RecordStretch]) -> Bool {
        let until: Double = mark.resumes ?? (mark.at + holeSeconds)
        return !gaps(stretches, from: mark.at, to: until, minimum: holeSeconds).isEmpty
    }

    /// Why there is no recovery score, or nil when there is one. Checked in this order: the record is
    /// still arriving; the baseline is still being learned; then what the night's own record says.
    public static func gap(recovery: Double?, night: NightRecord, reading: Bool, calibration: LCalibration?) -> RecoveryGap? {
        guard recovery == nil else { return nil }
        if reading { return .reading }
        if let c = calibration, c.have < c.need { return .calibrating(c) }
        switch night {
        case .none: return .noNight
        case .stillGoing: return .stillGoing
        case .cutOff(let at, _): return .cutOff(at: at)
        case .complete, .unjudged: return .unscored
        }
    }
}

/// The one thing about the state of the data that the athlete most needs to know right now, or nothing
/// when the record is current and whole. Chosen in a fixed order so two screens cannot pick differently.
public enum DataNotice: Equatable, Sendable {
    /// No link to the strap. `lastSync` is when its stored record was last read in full.
    case offline(lastSync: Double?)
    /// Linked without the encrypted pairing: heart rate arrives, the stored record does not.
    case notPaired
    /// The strap holds newer data than it will hand over until it is restarted.
    case needsRestart
    /// The stored record is being read now; `parts` have arrived so far.
    case reading(parts: Int)
    /// The strap holds data the phone has not read, and no read is running.
    case pending
    /// Nothing was recorded from `from` to `to` (nil: nothing since), in or right after last night.
    /// `lost` when the strap hands over no stored record, so nothing can fill the hole later.
    case hole(from: Double, to: Double?, lost: Bool)
    /// The strap hands over none of its stored record and is not being asked to stream all the time, so
    /// whatever happens while Luma is closed is not recorded.
    case notRecording
    /// The last read ended early; the strap layer's own words say why.
    case syncError(String)

    public static func resolve(connected: Bool, secure: Bool, syncing: Bool, parts: Int, pending: Bool, historyEmpty: Bool,
                               continuous: Bool, needsRestart: Bool, syncError: String?, lastSync: Double?,
                               night: NightRecord) -> DataNotice? {
        guard connected else { return .offline(lastSync: lastSync) }
        if !secure { return .notPaired }
        if needsRestart { return .needsRestart }
        // A strap that has handed over nothing in repeated reads is not "being read": the attempts go
        // on in the background and nothing comes of them, so they are not announced each time.
        if !historyEmpty {
            if syncing { return .reading(parts: parts) }
            if pending { return .pending }
        }
        if case .cutOff(let at, let resumes) = night { return .hole(from: at, to: resumes, lost: historyEmpty) }
        if historyEmpty && !continuous { return .notRecording }
        if let error = syncError, !error.isEmpty { return .syncError(error) }
        return nil
    }
}

/// The data check as text, for sending to whoever is helping: where heart rate reached the phone, the
/// nights and days as stored, and the facts the layer under Luma reports. Nothing here is interpreted.
public enum RecordReport {
    /// "02:00" in the calendar's time zone.
    public static func clock(_ ts: Double, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: ts))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "Sun 15 Nov 02:00".
    public static func stamp(_ ts: Double, calendar: Calendar) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let c = calendar.dateComponents([.day, .month, .weekday], from: date)
        let days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let weekday = days[max(0, min(6, (c.weekday ?? 1) - 1))]
        let month = months[max(0, min(11, (c.month ?? 1) - 1))]
        return "\(weekday) \(c.day ?? 0) \(month) \(clock(ts, calendar: calendar))"
    }

    private static func number(_ v: Double?, _ decimals: Int = 0) -> String {
        v.map { String(format: "%.\(decimals)f", $0) } ?? "–"
    }

    public static func nightLine(_ night: NightRecord, calendar: Calendar) -> String {
        switch night {
        case .none: return "no night for today"
        case .stillGoing: return "the record ends with the night; it may not be over"
        case .cutOff(let at, let resumes):
            let tail = resumes.map { ", readings start again at \(clock($0, calendar: calendar))" } ?? ", nothing since"
            return "the record stops at \(clock(at, calendar: calendar))\(tail)"
        case .unjudged: return "no heart-rate record covers the night; it is taken as stored"
        case .complete: return "whole (no hole of an hour or more in it or right after it)"
        }
    }

    public static func text(version: String, now: Double, stretches: [RecordStretch], night: NightRecord, sleeps: [LSleep],
                            days: [LDay], marks: [NightMark], facts: [LFact], calendar: Calendar = LDate.calendar) -> String {
        var out: [String] = ["Luma data check", version, stamp(now, calendar: calendar), ""]

        out.append("Minutes of heart rate that reached the phone, by hour, newest first")
        for hour in RecordCheck.hourly(stretches, endingAt: now, hours: 24).reversed() {
            let minutes: Int = Int((hour.seconds / 60).rounded())
            out.append(stamp(hour.hourStart, calendar: calendar) + "  " + String(minutes))
        }
        out.append("")
        out.append("Holes of 20 minutes or more, last 24 hours")
        let holes = RecordCheck.gaps(stretches, from: now - 24 * 3600, to: now, minimum: RecordCheck.listedHoleSeconds)
        if holes.isEmpty { out.append("none") }
        for hole in holes {
            let from: String = clock(hole.start, calendar: calendar)
            let to: String = clock(hole.end, calendar: calendar)
            let length: String = LFormat.hm(minutes: hole.seconds / 60)
            out.append("\(from) to \(to) (\(length))")
        }
        out.append("")
        out.append("Last night: " + nightLine(night, calendar: calendar))
        out.append("")

        out.append("Sleep as stored, newest first")
        let recent: [LSleep] = Array(sleeps.sorted { $0.start > $1.start }.prefix(8))
        if recent.isEmpty { out.append("none") }
        for s in recent {
            var flags: [String] = []
            if s.isNap { flags.append("nap") }
            if s.incomplete { flags.append("staging flagged incomplete") }
            if !s.isNap, marks.contains(where: { $0.day == s.day }) { flags.append("marked part night") }
            let from: String = clock(s.start, calendar: calendar)
            let to: String = clock(s.end, calendar: calendar)
            let asleep: String = LFormat.hm(minutes: s.asleepMin)
            var line: String = "\(s.day)  \(from) to \(to)  asleep \(asleep)"
            if !flags.isEmpty { line += "  [" + flags.joined(separator: ", ") + "]" }
            out.append(line)
        }
        out.append("")

        out.append("Days as stored, newest first")
        let lastDays: [LDay] = Array(days.sorted { $0.day > $1.day }.prefix(8))
        if lastDays.isEmpty { out.append("none") }
        for d in lastDays {
            let strain: String = number(d.strain.map { LScale.strain21($0) }, 1)
            let steps: String = d.steps.map { String($0) } ?? "–"
            var line: String = "\(d.day)  recovery \(number(d.recovery))  strain \(strain)  sleep \(number(d.sleepMin)) min"
            line += "  resting \(number(d.restingHR))  HRV \(number(d.hrv))  breaths \(number(d.respRate, 1))  steps \(steps)"
            out.append(line)
        }

        var section = ""
        for fact in facts {
            if fact.section != section {
                section = fact.section
                out.append("")
                out.append(section)
            }
            out.append(fact.label + ": " + fact.value)
        }
        return out.joined(separator: "\n")
    }
}
