import Foundation

// MARK: - Baselines

/// Personal baselines for the nightly signals, computed from the nights strictly before `day`.
public struct LBaselines: Equatable, Sendable {
    public var hrv: LBaseline?
    public var restingHR: LBaseline?
    public var respRate: LBaseline?
    public var skinTemp: LBaseline?
    public var sleepMin: LBaseline?
    public var recovery: LBaseline?
    public var strain: LBaseline?
    /// Scored nights available before `day`.
    public var nights: Int

    public static func compute(days: [LDay], before day: String) -> LBaselines {
        let past = days.filter { $0.day < day }
        func base(_ f: (LDay) -> Double?) -> LBaseline? { LBaseline(past.compactMap(f)) }
        return LBaselines(hrv: base { $0.hrv }, restingHR: base { $0.restingHR }, respRate: base { $0.respRate },
                          skinTemp: base { $0.skinTempDev }, sleepMin: base { $0.sleepMin },
                          recovery: base { $0.recovery }, strain: base { $0.strain },
                          nights: past.filter { $0.hasNight }.count)
    }

    public func baseline(for metric: LMetric) -> LBaseline? {
        switch metric {
        case .hrv: return hrv
        case .restingHR: return restingHR
        case .respRate: return respRate
        case .skinTempDev: return skinTemp
        case .recovery: return recovery
        default: return nil
        }
    }
}

// MARK: - Recovery

public enum RecoveryBand: String, Codable, Sendable {
    case low, moderate, high

    public static func of(_ score: Double) -> RecoveryBand { score >= 67 ? .high : (score >= 34 ? .moderate : .low) }

    public var title: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }
}

/// One signal behind the recovery score, compared with the personal baseline.
public struct RecoveryFactor: Equatable, Sendable, Identifiable {
    public var id: String { metric.rawValue }
    public let metric: LMetric
    public let value: Double
    public let baseline: Double?
    /// Standardised distance from baseline, signed so that positive HELPS recovery.
    public let effect: Double
    public let note: String

    public var direction: Int { effect > 0.5 ? 1 : (effect < -0.5 ? -1 : 0) }
}

public struct RecoveryRead: Equatable, Sendable {
    public let day: String
    public let score: Double?
    public let band: RecoveryBand?
    public let factors: [RecoveryFactor]
    public let headline: String
    public let detail: String
    /// Nights still needed before baselines are established (0 when ready).
    public let nightsToBaseline: Int
}

public enum RecoveryModel {
    /// Explains the day's recovery score from its inputs. The score itself comes from the strap
    /// pipeline; this never produces a second, competing number.
    /// `partial`: only part of the night behind the day was recorded. Its figures are then listed as
    /// they were measured and set against nothing: a part of a night is not comparable with whole ones.
    public static func read(day d: LDay, baselines b: LBaselines, gap: RecoveryGap? = nil, partial: Bool = false) -> RecoveryRead {
        var factors: [RecoveryFactor] = []

        if let v = d.hrv {
            let z = b.hrv?.z(v)
            let pct = b.hrv?.percent(v)
            let note: String
            if let z, let pct {
                note = abs(z) < 0.5 ? "In your normal range" : "\(LFormat.signed(pct))% vs your baseline"
            } else { note = "Baseline still building" }
            factors.append(RecoveryFactor(metric: .hrv, value: v, baseline: b.hrv?.center, effect: z ?? 0, note: note))
        }
        if let v = d.restingHR {
            let z = b.restingHR?.z(v)
            let note: String
            if let z, let c = b.restingHR?.center {
                note = abs(z) < 0.5 ? "In your normal range" : "\(LFormat.signed(v - c)) bpm vs your baseline"
            } else { note = "Baseline still building" }
            factors.append(RecoveryFactor(metric: .restingHR, value: v, baseline: b.restingHR?.center, effect: -(z ?? 0), note: note))
        }
        if let v = d.sleepMin {
            let need = d.sleepNeedMin ?? SleepModel.defaultNeedMin
            let ratio = v / need
            // 100 % of need is neutral-to-good; each 10 % short is roughly one standard step.
            let effect = LStat.clamp((ratio - 0.92) / 0.1, -3, 2)
            let note = ratio >= 1 ? "Met your sleep need" : "\(Int(((1 - ratio) * 100).rounded()))% short of your need"
            factors.append(RecoveryFactor(metric: .sleepHours, value: v / 60, baseline: need / 60, effect: effect, note: note))
        }
        if let v = d.respRate {
            let z = b.respRate?.z(v)
            let note: String
            if let z, let c = b.respRate?.center {
                note = abs(z) < 1 ? "In your normal range" : "\(LFormat.signed(v - c, decimals: 1)) vs your baseline"
            } else { note = "Baseline still building" }
            factors.append(RecoveryFactor(metric: .respRate, value: v, baseline: b.respRate?.center, effect: -abs(z ?? 0) * (abs(z ?? 0) < 1 ? 0 : 1), note: note))
        }
        if let v = d.skinTempDev, abs(v) < 20 {
            let effect = abs(v) < 0.5 ? 0 : -abs(v) / 0.4
            let note = abs(v) < 0.5 ? "In your normal range" : "\(LFormat.signed(v, decimals: 1))°C from baseline"
            factors.append(RecoveryFactor(metric: .skinTempDev, value: v, baseline: 0, effect: effect, note: note))
        }

        if partial {
            factors = factors.map { RecoveryFactor(metric: $0.metric, value: $0.value, baseline: nil, effect: 0, note: "From the recorded part") }
        }

        let band = d.recovery.map(RecoveryBand.of)
        let toBaseline = max(0, LBaseline.established - b.nights)
        // Only a clear departure from baseline is named as the reason; small wobbles are not.
        let worst = factors.filter { $0.effect <= -1 }.sorted { $0.effect < $1.effect }.first
        let best = factors.filter { $0.effect >= 1 }.sorted { $0.effect > $1.effect }.first

        let headline: String
        let detail: String
        switch band {
        case .high?:
            headline = "Recovered and ready"
            detail = best.map { "\($0.metric.title) is leading the way: \($0.note.prefix(1).lowercased() + $0.note.dropFirst())." } ?? "Your overnight signals are at or above baseline."
        case .moderate?:
            headline = "Partly recovered"
            detail = worst.map { "\($0.metric.title) is holding you back: \($0.note.prefix(1).lowercased() + $0.note.dropFirst())." } ?? "No single signal stands out; several sit a little under your baseline."
        case .low?:
            headline = "Running low"
            detail = worst.map { "\($0.metric.title) is the main drag: \($0.note.prefix(1).lowercased() + $0.note.dropFirst())." } ?? "Several overnight signals are below baseline."
        case nil:
            // The reason is resolved once (`RecordCheck.gap`) and worded once (`DayCall.waiting`).
            let words = DayCall.waiting(gap)
            headline = words.title
            detail = words.body
        }
        return RecoveryRead(day: d.day, score: d.recovery, band: band, factors: factors, headline: headline, detail: detail,
                            nightsToBaseline: toBaseline)
    }
}

// MARK: - Sleep

/// One night as Luma presents it: the main sleep plus any naps that day, with need, debt and score.
public struct SleepNight: Equatable, Sendable, Identifiable {
    public var id: String { day }
    public let day: String
    public let main: LSleep?
    public let naps: [LSleep]
    public let asleepMin: Double
    public let inBedMin: Double
    public let efficiency: Double?
    public let deepMin: Double?
    public let remMin: Double?
    public let lightMin: Double?
    public let awakeMin: Double?
    public let awakenings: Int?
    public let needMin: Double
    /// Accumulated shortfall going into this night, minutes.
    public let debtMin: Double
    public let score: Double?
    /// Minutes relative to local midnight of the wake day (negative: before midnight).
    public let bedtime: Double?
    public let wake: Double?
    public let napMin: Double
    /// Only part of this night is in the record (`NightRecord`): its figures cover the recorded part, it
    /// has no score, and it is left out of sleep debt, averages and the usual bed and wake times.
    public var partial: Bool = false

    public var restorativePct: Double? {
        guard let deepMin, let remMin, asleepMin > 0 else { return nil }
        return (deepMin + remMin) / asleepMin * 100
    }
    public var needMetPct: Double { needMin > 0 ? (asleepMin + napMin) / needMin * 100 : 0 }
}

public struct SleepSummary: Equatable, Sendable {
    /// Oldest first.
    public let nights: [SleepNight]
    public let last: SleepNight?
    public let avg7Min: Double?
    public let avg30Min: Double?
    public let debtMin: Double
    /// 0–100: how regular bed and wake times have been over the last week.
    public let consistency: Double?
    public let typicalBedtime: Double?
    public let typicalWake: Double?
    /// Weekend-vs-weekday shift of the sleep midpoint, minutes.
    public let socialJetlagMin: Double?
    public let tonightNeedMin: Double
    /// Recommended lights-out tonight, minutes relative to midnight (negative: before midnight).
    public let recommendedBedtime: Double?
}

public enum SleepModel {
    public static let defaultNeedMin: Double = 465

    /// Sleep need for a night: a base need, plus extra for a hard day, plus a share of the debt carried.
    public static func need(baseMin: Double, priorStrain: Double?, debtMin: Double, napMin: Double = 0) -> Double {
        let strain21 = priorStrain.map(LScale.strain21) ?? 0
        let strainAdd = LStat.clamp((strain21 - 8) * 4.5, 0, 55)
        let debtAdd = LStat.clamp(debtMin * 0.2, 0, 45)
        return max(300, baseMin + strainAdd + debtAdd - napMin)
    }

    /// Minutes relative to local midnight of the wake day; a 23:10 bedtime is −50.
    static func relativeMinutes(_ ts: Double, wakeDay: String, calendar: Calendar) -> Double? {
        guard let midnight = LDate.startOfDay(wakeDay, calendar: calendar) else { return nil }
        return (ts - midnight.timeIntervalSince1970) / 60
    }

    /// The block that is the night on a wake day: the longest one that is not a nap.
    public static func mainBlock(on day: String, sleeps: [LSleep]) -> LSleep? {
        sleeps.filter { $0.day == day && !$0.isNap }.max { $0.inBedMin < $1.inBedMin }
    }

    /// `partial` names the wake days whose night is only partly in the record. Such a night is listed
    /// with what was recorded, and nothing is concluded from it: a night cut short by missing data is
    /// not a short night.
    public static func summarize(days: [LDay], sleeps: [LSleep], baseNeedMin: Double? = nil, partial: Set<String> = [],
                                 today: String, calendar: Calendar = LDate.calendar) -> SleepSummary {
        let base = baseNeedMin ?? defaultNeedMin
        let byDay = Dictionary(grouping: sleeps, by: { $0.day })
        let dayByKey = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(byDay.keys).union(days.filter { $0.sleepMin != nil }.map { $0.day }).sorted()

        var nights: [SleepNight] = []
        var shortfalls: [(day: String, min: Double)] = []
        for key in keys {
            let blocks = (byDay[key] ?? []).sorted { $0.start < $1.start }
            let mainBlock = blocks.filter { !$0.isNap }.max { $0.inBedMin < $1.inBedMin }
            let naps = blocks.filter { $0.isNap }
            let d = dayByKey[key]
            let asleep = d?.sleepMin ?? mainBlock?.asleepMin ?? 0
            guard asleep > 0 else { continue }
            let napMin = naps.reduce(0) { $0 + $1.asleepMin }
            let staged = mainBlock.map { !$0.stages.isEmpty } ?? false
            let deep = d?.deepMin ?? (staged ? mainBlock?.minutes(.deep) : nil)
            let rem = d?.remMin ?? (staged ? mainBlock?.minutes(.rem) : nil)
            let light = d?.lightMin ?? (staged ? mainBlock?.minutes(.light) : nil)
            let awake = staged ? mainBlock?.minutes(.awake) : nil
            let awakenings: Int? = staged ? mainBlock.map { s in s.stages.dropFirst().filter { $0.kind == .awake && $0.minutes >= 1 }.count } : d?.disturbances

            // Debt going into this night: weighted shortfall over the previous seven nights.
            let debt = shortfalls.suffix(7).reversed().enumerated().reduce(0.0) { acc, e in
                let age = LDate.daysBetween(e.element.day, key, calendar: calendar)
                return age >= 1 && age <= 7 ? acc + e.element.min * (1.0 - Double(age - 1) * 0.1) : acc
            }
            let priorStrain = dayByKey[LDate.adding(-1, to: key, calendar: calendar)]?.strain
            let needed = d?.sleepNeedMin ?? need(baseMin: base, priorStrain: priorStrain, debtMin: debt)
            let isPartial = partial.contains(key)
            if !isPartial {
                shortfalls.append((key, max(0, need(baseMin: base, priorStrain: priorStrain, debtMin: 0) - asleep - napMin)))
            }

            let eff = d?.sleepEfficiency ?? mainBlock?.efficiency
            let bed = mainBlock.flatMap { relativeMinutes($0.start, wakeDay: key, calendar: calendar) }
            let wake = mainBlock.flatMap { relativeMinutes($0.end, wakeDay: key, calendar: calendar) }
            let whole: Double? = d?.sleepScore ?? composite(asleep: asleep + napMin, need: needed, efficiency: eff,
                                                            restorativePct: (deep != nil && rem != nil) ? ((deep ?? 0) + (rem ?? 0)) / asleep * 100 : nil)
            let score: Double? = isPartial ? nil : whole
            nights.append(SleepNight(day: key, main: mainBlock, naps: naps, asleepMin: asleep,
                                     inBedMin: mainBlock?.inBedMin ?? asleep / max(0.5, (eff ?? 90) / 100),
                                     efficiency: eff, deepMin: deep, remMin: rem, lightMin: light, awakeMin: awake,
                                     awakenings: awakenings, needMin: needed, debtMin: debt, score: score,
                                     bedtime: bed, wake: wake, napMin: napMin, partial: isPartial))
        }

        // Averages and the usual schedule come from whole nights only.
        let wholeNights = nights.filter { !$0.partial }
        let recent7 = wholeNights.suffix(7), recent30 = wholeNights.suffix(30)
        let beds = recent7.compactMap { $0.bedtime }, wakes = recent7.compactMap { $0.wake }
        var consistency: Double?
        if beds.count >= 4, let sb = LStat.sd(beds), let sw = LStat.sd(wakes) {
            consistency = LStat.clamp(100 * (1 - ((sb + sw) / 2) / 120), 0, 100)
        }
        let typicalBed = LStat.median(wholeNights.suffix(14).compactMap { $0.bedtime })
        let typicalWake = LStat.median(wholeNights.suffix(14).compactMap { $0.wake })

        var jetlag: Double?
        let mids = wholeNights.suffix(28).compactMap { n -> (weekend: Bool, mid: Double)? in
            guard let b = n.bedtime, let w = n.wake else { return nil }
            let wd = LDate.weekday(n.day, calendar: calendar)
            return (wd >= 6, (b + w) / 2)
        }
        let we = mids.filter { $0.weekend }.map { $0.mid }, wk = mids.filter { !$0.weekend }.map { $0.mid }
        if we.count >= 2, wk.count >= 4, let a = LStat.mean(we), let b = LStat.mean(wk) { jetlag = a - b }

        // Tonight: debt as of today, need from today's strain so far.
        let debtNow = shortfalls.suffix(7).reduce(0.0) { acc, e in
            let age = LDate.daysBetween(e.day, today, calendar: calendar)
            return age >= 0 && age <= 6 ? acc + e.min * (1.0 - Double(age) * 0.1) : acc
        }
        let tonightNeed = need(baseMin: base, priorStrain: dayByKey[today]?.strain, debtMin: debtNow)
        var recBed: Double?
        if let w = typicalWake {
            let eff = (LStat.median(recent30.compactMap { $0.efficiency }) ?? 90) / 100
            recBed = w - tonightNeed / LStat.clamp(eff, 0.75, 0.98)
        }
        return SleepSummary(nights: nights, last: nights.last, avg7Min: LStat.mean(recent7.map { $0.asleepMin }),
                            avg30Min: LStat.mean(recent30.map { $0.asleepMin }), debtMin: debtNow, consistency: consistency,
                            typicalBedtime: typicalBed, typicalWake: typicalWake, socialJetlagMin: jetlag,
                            tonightNeedMin: tonightNeed, recommendedBedtime: recBed)
    }

    /// Fallback sleep score when the strap pipeline has not stored one: how much of the need was met,
    /// how efficiently, and how much of it was deep + REM.
    public static func composite(asleep: Double, need: Double, efficiency: Double?, restorativePct: Double?) -> Double? {
        guard need > 0, asleep > 0 else { return nil }
        let sufficiency = LStat.clamp(asleep / need, 0, 1)
        let eff = efficiency.map { LStat.clamp(($0 - 70) / 25, 0, 1) }
        let rest = restorativePct.map { LStat.clamp($0 / 45, 0, 1) }
        var score = sufficiency * 0.65, weight = 0.65
        if let eff { score += eff * 0.2; weight += 0.2 }
        if let rest { score += rest * 0.15; weight += 0.15 }
        return score / weight * 100
    }

    /// Typical share of sleep per stage for healthy adults, used as the reference band on the stage bars.
    public static func typicalShare(_ kind: LStageKind) -> ClosedRange<Double> {
        switch kind {
        case .deep: return 13...23
        case .rem: return 20...25
        case .light: return 45...60
        case .awake: return 2...8
        }
    }
}

// MARK: - Early-warning signals

public enum WatchLevel: Int, Codable, Sendable, Comparable {
    case clear = 0, watch, alert
    public static func < (a: WatchLevel, b: WatchLevel) -> Bool { a.rawValue < b.rawValue }
}

/// A pattern across overnight signals that often shows up before illness, or with heavy fatigue,
/// alcohol or travel. A prompt to take it easy, not a diagnosis.
public struct BodyWatch: Equatable, Sendable {
    public struct Signal: Equatable, Sendable, Identifiable {
        public var id: String { metric.rawValue }
        public let metric: LMetric
        public let value: Double
        public let z: Double
        public let flagged: Bool
        public let text: String
    }
    public let level: WatchLevel
    public let signals: [Signal]
    public let title: String
    public let detail: String
    public var flaggedCount: Int { signals.filter { $0.flagged }.count }

    public static func assess(day d: LDay, baselines b: LBaselines) -> BodyWatch {
        var signals: [Signal] = []
        if let v = d.restingHR, let base = b.restingHR, base.isEstablished {
            let z = base.z(v)
            signals.append(Signal(metric: .restingHR, value: v, z: z, flagged: z >= 2 && v - base.center >= 3,
                                  text: "Resting heart rate \(LFormat.signed(v - base.center)) bpm"))
        }
        if let v = d.hrv, let base = b.hrv, base.isEstablished {
            let z = base.z(v)
            signals.append(Signal(metric: .hrv, value: v, z: z, flagged: z <= -2,
                                  text: "HRV \(LFormat.signed(base.percent(v)))%"))
        }
        if let v = d.respRate, let base = b.respRate, base.isEstablished {
            let z = base.z(v)
            signals.append(Signal(metric: .respRate, value: v, z: z, flagged: z >= 2 && v - base.center >= 0.8,
                                  text: "Respiratory rate \(LFormat.signed(v - base.center, decimals: 1))"))
        }
        if let v = d.skinTempDev, abs(v) < 20 {
            signals.append(Signal(metric: .skinTempDev, value: v, z: v / 0.3, flagged: v >= 0.6,
                                  text: "Skin temperature \(LFormat.signed(v, decimals: 1))°C"))
        }
        let n = signals.filter { $0.flagged }.count
        let level: WatchLevel = n >= 3 ? .alert : (n == 2 ? .watch : .clear)
        let flaggedText = signals.filter { $0.flagged }.map { $0.text.lowercased() }.joined(separator: ", ")
        let title: String, detail: String
        switch level {
        case .alert:
            title = "Your body is under strain"
            detail = "\(n) overnight signals are well outside your range (\(flaggedText)). This pattern often comes before illness, or with heavy fatigue, alcohol or travel. Keep today easy and see how tomorrow reads."
        case .watch:
            title = "Two signals are off"
            detail = "Outside your normal range: \(flaggedText). Worth an easier day if you also feel flat."
        case .clear:
            title = "No warning signs"
            detail = signals.isEmpty ? "Luma needs about two weeks of nights before it can watch for unusual patterns."
                                     : "Overnight signals are inside your normal range."
        }
        return BodyWatch(level: level, signals: signals, title: title, detail: detail)
    }
}

// MARK: - Daily stress proxy

public enum StressModel {
    /// A 0–3 daily stress estimate from how far resting HR and HRV sit from baseline. Used for the
    /// history strip; today's hour-by-hour curve comes from the strap's beat-to-beat data.
    public static func daily(day d: LDay, baselines b: LBaselines) -> Double? {
        guard let rhr = d.restingHR, let hrv = d.hrv, let br = b.restingHR, let bh = b.hrv else { return nil }
        return LStat.clamp(1.2 + 0.45 * (br.z(rhr) - bh.z(hrv)), 0, 3)
    }
}

// MARK: - The day's call

public enum DayCallLevel: String, Codable, Sendable { case push, build, steady, easy, rest, unknown }

/// What today is good for, from recovery, load, sleep debt and warning signs.
public struct DayCall: Equatable, Sendable {
    public let level: DayCallLevel
    public let title: String
    public let body: String
    public let reasons: [String]
    /// Suggested day strain on the 0–21 scale.
    public let strainTarget: ClosedRange<Double>?

    /// The same call with a sentence added to what it says.
    func qualified(_ sentence: String) -> DayCall {
        DayCall(level: level, title: title, body: body + " " + sentence, reasons: reasons, strainTarget: strainTarget)
    }

    /// What to say when there is no score to go on, for each reason there might be none. The reason is
    /// resolved once (`RecordCheck.gap`); this only words it.
    static func waiting(_ gap: RecoveryGap?) -> (title: String, body: String) {
        switch gap {
        case .reading:
            return ("Reading last night", "Luma is still reading your strap's record of the night. Go by feel until the score lands.")
        case .calibrating(let c):
            return ("Learning your normal",
                    "Recovery is scored against your own normal, which takes \(c.need) recorded nights to learn. You have \(c.have). Until then, train as planned and go by feel.")
        case .noNight:
            return ("No night recorded", "There is no record of last night. Wear the strap to bed with Luma running in the background. Go by feel today.")
        case .stillGoing:
            return ("Night still being recorded", "Your strap's record of the night ends only minutes ago. Look again shortly.")
        case .cutOff:
            return ("Last night's record is incomplete", "Part of the night never reached the phone, so it can't be scored. Go by feel today and keep the plan flexible.")
        case .unscored, .none:
            return ("No recovery score", "Last night was recorded but has no score. Go by feel and keep the plan flexible.")
        }
    }

    public static func make(recovery: Double?, gap: RecoveryGap? = nil, load: LoadState?, sleepDebtMin: Double, watch: BodyWatch,
                            plannedHard: Bool = false) -> DayCall {
        var reasons: [String] = []
        if watch.level == .alert {
            reasons.append(watch.signals.filter { $0.flagged }.map { $0.text }.joined(separator: " · "))
            return DayCall(level: .rest, title: "Take it easy today",
                           body: "Several overnight signals are off at once. Swap hard work for a walk, mobility or rest, and reassess tomorrow.",
                           reasons: reasons, strainTarget: 0...8)
        }
        guard let r = recovery else {
            let words = waiting(gap)
            return DayCall(level: .unknown, title: words.title, body: words.body, reasons: [], strainTarget: nil)
        }
        reasons.append("Recovery \(Int(r.rounded()))%")
        let acwr = load?.ready == true ? load?.acwr : nil
        if let a = acwr { reasons.append(String(format: "Load ratio %.2f", a)) }
        if sleepDebtMin >= 60 { reasons.append("Sleep debt \(LFormat.hm(minutes: sleepDebtMin))") }
        if watch.level == .watch { reasons.append("Two overnight signals off") }

        let spike = (acwr ?? 1) > 1.5
        let heavyDebt = sleepDebtMin >= 150
        switch RecoveryBand.of(r) {
        case .high:
            if spike {
                return DayCall(level: .build, title: "Ready, but hold the reins",
                               body: "You have recovered well, yet your load has jumped faster than your base. Train with quality, keep the volume where it is.",
                               reasons: reasons, strainTarget: 12...15)
            }
            if watch.level == .watch || heavyDebt {
                return DayCall(level: .build, title: "Good to train, with care",
                               body: "Recovery is high, though not every signal agrees. Do the planned session and stop a rep early rather than a rep late.",
                               reasons: reasons, strainTarget: 12...15)
            }
            return DayCall(level: .push, title: "Green light",
                           body: plannedHard ? "Today can take your hardest work. Hit the planned session with intent."
                                             : "Your body can absorb a hard session today. A good day for race-pace work or a simulation.",
                           reasons: reasons, strainTarget: 14...18)
        case .moderate:
            if heavyDebt || watch.level == .watch || spike {
                return DayCall(level: .easy, title: "Keep it light",
                               body: "You are only partly recovered and carrying extra fatigue. Easy aerobic work or technique is the productive choice.",
                               reasons: reasons, strainTarget: 6...10)
            }
            return DayCall(level: .steady, title: "Steady work",
                           body: "Solid enough for a normal session. Train as planned, and save maximal efforts for a greener day.",
                           reasons: reasons, strainTarget: 10...14)
        case .low:
            return DayCall(level: .easy, title: "Recover today",
                           body: "Your body is asking for less. Zone 2, mobility or a full rest day will do more for race day than forcing a hard one.",
                           reasons: reasons, strainTarget: 0...9)
        }
    }
}
