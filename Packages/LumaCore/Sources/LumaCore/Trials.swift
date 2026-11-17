import Foundation

// MARK: - Supplement trials

/// A fair test of one supplement on one athlete: blocks of days on it and blocks off it, in pairs, the
/// order inside each pair drawn at random when the trial is set up. Taking something every day leaves
/// nothing to compare, and the days it happens to be missed are rarely ordinary days; a planned order
/// is what makes the two sides comparable. (Repeated on/off pairs in random order, with the first days
/// after each switch left out, is how single-person trials are run.)
public struct SupplementTrial: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// The supplement, by the name it is logged under.
    public var supplement: String
    public var outcome: LMetric
    public var blockDays: Int
    /// Days at the start of each block that are not counted, while the last block wears off.
    public var washoutDays: Int
    public var startDay: String
    /// One entry per block: true where the supplement is taken. Blocks come in on/off pairs.
    public var order: [Bool]
    /// Set when the trial is ended early; days after it are not part of it.
    public var stoppedDay: String?

    public init(id: UUID = UUID(), supplement: String, outcome: LMetric, blockDays: Int, washoutDays: Int, startDay: String,
                order: [Bool], stoppedDay: String? = nil) {
        self.id = id; self.supplement = supplement; self.outcome = outcome
        self.blockDays = max(3, blockDays); self.washoutDays = max(0, min(washoutDays, max(3, blockDays) - 2))
        self.startDay = startDay; self.order = order; self.stoppedDay = stoppedDay
    }

    /// What a trial can watch: figures the strap gives for every night.
    public static let outcomes: [LMetric] = [.deepMin, .sleepHours, .hrv, .restingHR, .recovery]

    /// A new trial: `rounds` pairs of blocks, each pair in an order drawn from `rng`.
    public static func plan<G: RandomNumberGenerator>(supplement: String, outcome: LMetric, blockDays: Int = 7, rounds: Int = 3,
                                                       washoutDays: Int = 2, startDay: String, using rng: inout G) -> SupplementTrial {
        var order: [Bool] = []
        for _ in 0..<max(1, rounds) {
            let onFirst = Bool.random(using: &rng)
            order += [onFirst, !onFirst]
        }
        return SupplementTrial(supplement: supplement, outcome: outcome, blockDays: blockDays, washoutDays: washoutDays,
                               startDay: startDay, order: order)
    }

    public var rounds: Int { order.count / 2 }
    public var totalDays: Int { order.count * blockDays }

    public func lastDay(calendar: Calendar = LDate.calendar) -> String {
        let planned = LDate.adding(totalDays - 1, to: startDay, calendar: calendar)
        return stoppedDay.map { min($0, planned) } ?? planned
    }

    /// Where a day falls in the trial.
    public struct Position: Equatable, Sendable {
        /// 0-based block, and the 1-based round it belongs to.
        public let block: Int
        public let round: Int
        public let on: Bool
        /// 1-based day within the block.
        public let dayInBlock: Int
        /// Past the block's first days, so the night after it is compared.
        public let counted: Bool
        public let daysLeftInBlock: Int
    }

    /// Nil before the trial starts and after it ends.
    public func position(on day: String, calendar: Calendar = LDate.calendar) -> Position? {
        let offset = LDate.daysBetween(startDay, day, calendar: calendar)
        guard offset >= 0, offset < totalDays, day <= lastDay(calendar: calendar) else { return nil }
        let block = offset / blockDays
        let inBlock = offset % blockDays + 1
        return Position(block: block, round: block / 2 + 1, on: order[block], dayInBlock: inBlock, counted: inBlock > washoutDays,
                        daysLeftInBlock: blockDays - inBlock)
    }

    public func isRunning(on day: String, calendar: Calendar = LDate.calendar) -> Bool { position(on: day, calendar: calendar) != nil }

    /// What to do today, in a line.
    public func instruction(on day: String, calendar: Calendar = LDate.calendar) -> String? {
        guard let p = position(on: day, calendar: calendar) else { return nil }
        let left = p.daysLeftInBlock == 0 ? "last day of this block" : "\(p.daysLeftInBlock) more day\(p.daysLeftInBlock == 1 ? "" : "s") in this block"
        return p.on ? "On block: take \(supplement) today (\(left))." : "Off block: skip \(supplement) today (\(left))."
    }
}

/// What a trial shows so far.
public struct TrialRead: Equatable, Sendable {
    public enum Verdict: String, Sendable { case tooEarly, unclear, higher, lower }

    public let nOn: Int
    public let nOff: Int
    public let meanOn: Double?
    public let meanOff: Double?
    /// On minus off, in the outcome's units, with the range it most likely lies in (90%).
    public let delta: Double?
    public let low: Double?
    public let high: Double?
    public let verdict: Verdict
    /// Counted days on which the plan was followed, and days it was not (left out of the comparison).
    public let followed: Int
    public let broken: Int
    public let roundsDone: Int
    public let finished: Bool
    public let sentence: String

    /// Whether the difference, if it is one, is in the good direction for the outcome.
    public func helps(_ outcome: LMetric) -> Bool? {
        guard verdict == .higher || verdict == .lower else { return nil }
        return outcome.higherIsBetter.map { $0 == (verdict == .higher) }
    }
}

public enum TrialModel {
    /// Counted nights needed on each side before anything is said.
    public static let minimumEach = 6

    /// Reads a trial against the strap's nights and the supplement log. A day counts when it is past its
    /// block's first days, the plan was followed on it (taken on an on day, not taken on an off day)
    /// and the night after it was measured. The outcome is the figure of the morning after.
    public static func read(_ trial: SupplementTrial, days: [LDay], fuel: [FuelEntry], today: String,
                            calendar: Calendar = LDate.calendar) -> TrialRead {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let taken = TrainingProgress.supplementDays(trial.supplement, fuel: fuel)
        let last = trial.lastDay(calendar: calendar)
        var on: [Double] = [], off: [Double] = []
        var series: [(on: Bool, value: Double)] = []
        var followed = 0, broken = 0
        var day = trial.startDay
        // A day is judged once it is over and its night is in: up to yesterday.
        while day <= last, day < today {
            defer { day = LDate.adding(1, to: day, calendar: calendar) }
            guard let p = trial.position(on: day, calendar: calendar) else { continue }
            let value = byDay[LDate.adding(1, to: day, calendar: calendar)].flatMap { trial.outcome.value($0) }
            if let value { series.append((p.on, value)) }
            guard p.counted else { continue }
            guard taken.contains(day) == p.on else { broken += 1; continue }
            followed += 1
            guard let value else { continue }
            if p.on { on.append(value) } else { off.append(value) }
        }
        let elapsed = max(0, min(LDate.daysBetween(trial.startDay, today, calendar: calendar), trial.totalDays))
        let roundsDone = elapsed / (trial.blockDays * 2)
        let finished = today > last
        let name = trial.supplement
        let what = trial.outcome.phrase

        guard on.count >= minimumEach, off.count >= minimumEach, let test = LStat.welch(on, off) else {
            let text = "\(on.count) counted night\(on.count == 1 ? "" : "s") on \(name) and \(off.count) off so far. A first read needs \(minimumEach) of each."
            return TrialRead(nOn: on.count, nOff: off.count, meanOn: LStat.mean(on), meanOff: LStat.mean(off), delta: nil, low: nil, high: nil,
                             verdict: .tooEarly, followed: followed, broken: broken, roundsDone: roundsDone, finished: finished, sentence: text)
        }
        // Nights follow one another, so they tell less than the same number of unrelated nights would:
        // the range is widened by how closely this outcome follows itself from one night to the next,
        // measured with the difference between the two sides taken out.
        let leftOver = series.map { $0.value - ($0.on ? test.meanA : test.meanB) }
        let rho = LStat.clamp(LStat.serialCorrelation(leftOver) ?? 0, 0, 0.7)
        let sdOn = LStat.sd(on) ?? 0, sdOff = LStat.sd(off) ?? 0
        let se = (sdOn * sdOn / Double(on.count) + sdOff * sdOff / Double(off.count)).squareRoot() * ((1 + rho) / (1 - rho)).squareRoot()
        let df = Double(max(2, on.count + off.count - 2)) * (1 - rho) / (1 + rho)
        let t = LStat.studentTQuantile(0.95, df: max(2, df))
        let low = test.delta - t * se, high = test.delta + t * se
        let verdict: TrialRead.Verdict = low > 0 ? .higher : (high < 0 ? .lower : .unclear)
        // The difference is worded as it reads from the two averages shown with it, so the three agree.
        let shown = trial.outcome.shownDifference(test.meanA, test.meanB)
        let size = trial.outcome.gap(abs(shown))
        let counts = "\(on.count) nights on, \(off.count) off"
        let text: String
        switch verdict {
        case .higher, .lower:
            let dir = verdict == .higher ? "higher" : "lower"
            let a = trial.outcome.format(min(abs(low), abs(high))), b = trial.outcome.gap(max(abs(low), abs(high)))
            let ran = shown == 0 ? "a little \(dir)" : "\(size) \(dir)"
            text = "Your \(what) ran \(ran) on \(name), most likely between \(a) and \(b) (\(counts))."
        default:
            let was = shown == 0 ? "the same on \(name) as off it" : "\(size) \(shown > 0 ? "higher" : "lower") on \(name)"
            let ends = "\(trial.outcome.gap(abs(low))) \(low < 0 ? "lower" : "higher") to \(trial.outcome.gap(abs(high))) \(high < 0 ? "lower" : "higher")"
            text = "Your \(what) was \(was), but it could be anywhere from \(ends). Not clear\(finished ? "" : " yet") (\(counts))."
        }
        return TrialRead(nOn: on.count, nOff: off.count, meanOn: test.meanA, meanOff: test.meanB, delta: test.delta, low: low, high: high,
                         verdict: verdict, followed: followed, broken: broken, roundsDone: roundsDone, finished: finished, sentence: text)
    }
}
