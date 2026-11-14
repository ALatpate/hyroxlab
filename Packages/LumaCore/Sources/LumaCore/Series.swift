import Foundation

/// Statistics used across the analytics: robust location and spread, trend tests, group comparisons
/// and multiple-comparison control. Pure functions over plain arrays; nil when there is too little
/// data to say anything.
public enum LStat {
    // MARK: Location and spread

    public static func mean(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }

    public static func median(_ x: [Double]) -> Double? { percentile(x, 0.5) }

    /// Linear-interpolated percentile, p in 0…1.
    public static func percentile(_ x: [Double], _ p: Double) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        let pos = min(1, max(0, p)) * Double(s.count - 1)
        let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
        return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
    }

    /// Sample standard deviation.
    public static func sd(_ x: [Double]) -> Double? {
        guard x.count >= 2, let m = mean(x) else { return nil }
        return (x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)).squareRoot()
    }

    /// Median absolute deviation scaled to be comparable with a standard deviation (×1.4826).
    public static func robustSD(_ x: [Double]) -> Double? {
        guard let m = median(x), let mad = median(x.map { abs($0 - m) }) else { return nil }
        return mad * 1.4826
    }

    public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }

    // MARK: Smoothing

    /// Exponentially weighted moving average with time constant `tau` days (the classic
    /// fitness/fatigue recursion: y += (x − y) / tau), seeded with the first value.
    public static func ewma(_ x: [Double], tau: Double) -> [Double] {
        guard let first = x.first, tau > 0 else { return x }
        var y = first
        return x.map { v in y += (v - y) / tau; return y }
    }

    /// Trailing mean over `window` points; nil until `minCount` real values are in the window.
    public static func rollingMean(_ x: [Double?], window: Int, minCount: Int = 1) -> [Double?] {
        guard window > 0 else { return x }
        return x.indices.map { i in
            let vals = x[max(0, i - window + 1)...i].compactMap { $0 }
            return vals.count >= minCount ? mean(vals) : nil
        }
    }

    // MARK: Trend

    /// Theil–Sen slope (median of pairwise slopes) per index step: robust to outliers.
    public static func theilSen(_ y: [Double]) -> (slope: Double, intercept: Double)? {
        let n = y.count
        guard n >= 3 else { return nil }
        var slopes: [Double] = []
        slopes.reserveCapacity(n * (n - 1) / 2)
        for i in 0..<(n - 1) { for j in (i + 1)..<n { slopes.append((y[j] - y[i]) / Double(j - i)) } }
        guard let slope = median(slopes),
              let intercept = median(y.enumerated().map { $0.element - slope * Double($0.offset) }) else { return nil }
        return (slope, intercept)
    }

    /// Mann–Kendall monotonic-trend test (normal approximation with tie correction).
    public static func mannKendall(_ y: [Double]) -> (tau: Double, z: Double, p: Double)? {
        let n = y.count
        guard n >= 6 else { return nil }
        var s = 0.0
        for i in 0..<(n - 1) { for j in (i + 1)..<n { s += y[j] > y[i] ? 1 : (y[j] < y[i] ? -1 : 0) } }
        var ties: [Double: Int] = [:]
        for v in y { ties[v, default: 0] += 1 }
        let tieTerm = ties.values.reduce(0.0) { $0 + Double($1 * ($1 - 1) * (2 * $1 + 5)) }
        let varS = (Double(n * (n - 1) * (2 * n + 5)) - tieTerm) / 18
        guard varS > 0 else { return (0, 0, 1) }
        let z = s > 0 ? (s - 1) / varS.squareRoot() : (s < 0 ? (s + 1) / varS.squareRoot() : 0)
        let p = 2 * (1 - normalCDF(abs(z)))
        return (s / (Double(n * (n - 1)) / 2), z, p)
    }

    /// Ordinary least squares y = a + b·x with R².
    public static func linearFit(_ x: [Double], _ y: [Double]) -> (slope: Double, intercept: Double, r2: Double)? {
        let n = min(x.count, y.count)
        guard n >= 3, let mx = mean(Array(x.prefix(n))), let my = mean(Array(y.prefix(n))) else { return nil }
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<n { sxx += (x[i] - mx) * (x[i] - mx); sxy += (x[i] - mx) * (y[i] - my); syy += (y[i] - my) * (y[i] - my) }
        guard sxx > 0 else { return nil }
        let b = sxy / sxx
        return (b, my - b * mx, syy > 0 ? (sxy * sxy) / (sxx * syy) : 0)
    }

    // MARK: Association

    public static func pearson(_ x: [Double], _ y: [Double]) -> (r: Double, n: Int, p: Double)? {
        let n = min(x.count, y.count)
        guard n >= 4, let mx = mean(Array(x.prefix(n))), let my = mean(Array(y.prefix(n))) else { return nil }
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<n { sxx += (x[i] - mx) * (x[i] - mx); sxy += (x[i] - mx) * (y[i] - my); syy += (y[i] - my) * (y[i] - my) }
        guard sxx > 0, syy > 0 else { return nil }
        let r = clamp(sxy / (sxx * syy).squareRoot(), -1, 1)
        let df = Double(n - 2)
        let t = abs(r) >= 1 ? Double.infinity : r * (df / (1 - r * r)).squareRoot()
        return (r, n, t.isFinite ? 2 * (1 - studentTCDF(abs(t), df: df)) : 0)
    }

    /// Spearman rank correlation (Pearson on mid-ranks): robust to outliers and monotone curves.
    public static func spearman(_ x: [Double], _ y: [Double]) -> (r: Double, n: Int, p: Double)? {
        let n = min(x.count, y.count)
        return pearson(ranks(Array(x.prefix(n))), ranks(Array(y.prefix(n))))
    }

    static func ranks(_ x: [Double]) -> [Double] {
        let order = x.indices.sorted { x[$0] < x[$1] }
        var r = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, x[order[j + 1]] == x[order[i]] { j += 1 }
            let mid = Double(i + j) / 2 + 1
            for k in i...j { r[order[k]] = mid }
            i = j + 1
        }
        return r
    }

    // MARK: Two groups

    public struct GroupTest: Equatable, Sendable {
        public let meanA: Double
        public let meanB: Double
        /// meanA − meanB.
        public let delta: Double
        /// Hedges' g (small-sample corrected standardized difference).
        public let g: Double
        public let p: Double
        public let nA: Int
        public let nB: Int
    }

    /// Welch's unequal-variance t-test of A against B.
    public static func welch(_ a: [Double], _ b: [Double]) -> GroupTest? {
        guard a.count >= 3, b.count >= 3, let ma = mean(a), let mb = mean(b), let sa = sd(a), let sb = sd(b) else { return nil }
        let na = Double(a.count), nb = Double(b.count)
        let va = sa * sa / na, vb = sb * sb / nb
        let pooled = (((na - 1) * sa * sa + (nb - 1) * sb * sb) / (na + nb - 2)).squareRoot()
        let d = pooled > 0 ? (ma - mb) / pooled : 0
        let g = d * (1 - 3 / (4 * (na + nb) - 9))
        guard va + vb > 0 else { return GroupTest(meanA: ma, meanB: mb, delta: ma - mb, g: 0, p: 1, nA: a.count, nB: b.count) }
        let t = (ma - mb) / (va + vb).squareRoot()
        let df = (va + vb) * (va + vb) / (va * va / (na - 1) + vb * vb / (nb - 1))
        let p = 2 * (1 - studentTCDF(abs(t), df: df))
        return GroupTest(meanA: ma, meanB: mb, delta: ma - mb, g: g, p: p, nA: a.count, nB: b.count)
    }

    /// Benjamini–Hochberg: which hypotheses survive at false-discovery rate `q`.
    public static func benjaminiHochberg(_ p: [Double], q: Double = 0.1) -> [Bool] {
        let m = p.count
        guard m > 0 else { return [] }
        let order = p.indices.sorted { p[$0] < p[$1] }
        var cutoff = -1
        for (rank, idx) in order.enumerated() where p[idx] <= Double(rank + 1) / Double(m) * q { cutoff = rank }
        var keep = [Bool](repeating: false, count: m)
        if cutoff >= 0 { for rank in 0...cutoff { keep[order[rank]] = true } }
        return keep
    }

    // MARK: Distributions

    public static func normalCDF(_ z: Double) -> Double { 0.5 * erfc(-z / 2.0.squareRoot()) }

    /// Student-t CDF via the regularized incomplete beta function.
    public static func studentTCDF(_ t: Double, df: Double) -> Double {
        guard df > 0 else { return .nan }
        let x = df / (df + t * t)
        let tail = 0.5 * incompleteBeta(x, a: df / 2, b: 0.5)
        return t >= 0 ? 1 - tail : tail
    }

    /// Regularized incomplete beta I_x(a, b) (Lentz continued fraction).
    static func incompleteBeta(_ x: Double, a: Double, b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lnBeta = lgamma(a) + lgamma(b) - lgamma(a + b)
        let front = exp(a * log(x) + b * log(1 - x) - lnBeta)
        if x < (a + 1) / (a + b + 2) { return front * betaCF(x, a: a, b: b) / a }
        return 1 - front * betaCF(1 - x, a: b, b: a) / b
    }

    private static func betaCF(_ x: Double, a: Double, b: Double) -> Double {
        let tiny = 1e-300
        var c = 1.0
        var d = 1 - (a + b) * x / (a + 1)
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let mm = Double(m)
            var num = mm * (b - mm) * x / ((a + 2 * mm - 1) * (a + 2 * mm))
            d = 1 + num * d; if abs(d) < tiny { d = tiny }
            c = 1 + num / c; if abs(c) < tiny { c = tiny }
            d = 1 / d; h *= d * c
            num = -(a + mm) * (a + b + mm) * x / ((a + 2 * mm) * (a + 2 * mm + 1))
            d = 1 + num * d; if abs(d) < tiny { d = tiny }
            c = 1 + num / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < 1e-12 { break }
        }
        return h
    }
}

/// A personal baseline for one metric: the typical value and the normal day-to-day band, from a
/// trailing window. Uses the median and a robust spread so one bad night does not move it.
public struct LBaseline: Equatable, Sendable {
    public let center: Double
    public let spread: Double
    public let count: Int

    public static let window = 60
    /// Nights needed before a baseline is shown at all, and before it is called established.
    public static let minimum = 5
    public static let established = 14

    public init?(_ history: [Double], window: Int = LBaseline.window, minimum: Int = LBaseline.minimum) {
        let recent = Array(history.suffix(window))
        guard recent.count >= minimum, let c = LStat.median(recent) else { return nil }
        let robust = LStat.robustSD(recent) ?? 0
        // A flat history (identical values) has zero MAD; fall back to the SD, then to 3 % of the level.
        let s = robust > 0 ? robust : (LStat.sd(recent) ?? 0)
        self.center = c
        self.spread = s > 0 ? s : max(abs(c) * 0.03, 0.01)
        self.count = recent.count
    }

    public var isEstablished: Bool { count >= LBaseline.established }
    public var low: Double { center - spread }
    public var high: Double { center + spread }
    public func z(_ v: Double) -> Double { (v - center) / spread }
    public func percent(_ v: Double) -> Double { center != 0 ? (v - center) / abs(center) * 100 : 0 }
}
