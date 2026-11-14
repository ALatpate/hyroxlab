import Foundation

/// Small, dependency-free statistics used across the package.
public enum Stats {
    public static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    public static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// Median absolute deviation, scaled by 1.4826 so it estimates σ for normal data.
    public static func mad(_ xs: [Double]) -> Double? {
        guard let m = median(xs) else { return nil }
        guard let d = median(xs.map { abs($0 - m) }) else { return nil }
        return d * 1.4826
    }

    public static func stdDev(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return v.squareRoot()
    }

    /// Coefficient of variation as a fraction (0.05 = 5 %).
    public static func cv(_ xs: [Double]) -> Double? {
        guard let m = mean(xs), m > 0, let sd = stdDev(xs) else { return nil }
        return sd / m
    }

    /// Pearson r, or nil when either series is constant or too short.
    public static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3, let mx = mean(xs), let my = mean(ys) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in 0..<xs.count {
            let dx = xs[i] - mx, dy = ys[i] - my
            sxy += dx * dy; sxx += dx * dx; syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / (sxx * syy).squareRoot()
    }

    /// Least-squares slope and intercept of y on x.
    public static func linearFit(_ xs: [Double], _ ys: [Double]) -> (slope: Double, intercept: Double)? {
        guard xs.count == ys.count, xs.count >= 2, let mx = mean(xs), let my = mean(ys) else { return nil }
        var sxy = 0.0, sxx = 0.0
        for i in 0..<xs.count { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
        guard sxx > 0 else { return nil }
        let b = sxy / sxx
        return (b, my - b * mx)
    }

    public static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, x)) }
}

/// A robust personal baseline: median and MAD over a trailing window, excluding the current value.
/// Reports `unavailable` below the minimum sample size rather than inventing a figure.
public struct RobustBaseline: Equatable, Sendable {
    public let median: Double
    public let mad: Double
    public let count: Int

    public static let minimumSamples = 14
    public static let window = 60

    /// `history` is oldest → newest and must NOT contain the value being judged.
    public init?(history: [Double]) {
        let tail = Array(history.suffix(Self.window))
        guard tail.count >= Self.minimumSamples, let m = Stats.median(tail), let d = Stats.mad(tail) else { return nil }
        median = m; mad = max(d, 1e-9); count = tail.count
    }

    /// Robust z-score of a value against this baseline.
    public func z(_ value: Double) -> Double { (value - median) / mad }

    /// Percent deviation from the baseline median.
    public func percentDelta(_ value: Double) -> Double { median != 0 ? (value - median) / median * 100 : 0 }
}

// MARK: - Formatting helpers (pure, UI-independent)

public enum Format {
    /// 5:07 for 307 s; 1:02:03 above an hour.
    public static func duration(_ seconds: Double, showHours: Bool? = nil) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if showHours ?? (h > 0) { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    /// Tenths for short splits: 1:04.3
    public static func durationTenths(_ seconds: Double) -> String {
        let whole = Int(seconds)
        let tenths = Int(((seconds - Double(whole)) * 10).rounded())
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, tenths)
    }

    /// 4:52 /km from seconds per km; "—" when unavailable or absurd.
    public static func pace(_ sPerKm: Double?) -> String {
        guard let p = sPerKm, p.isFinite, p > 0, p < 60 * 30 else { return "—" }
        let s = Int(p.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    public static func km(_ metres: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", metres / 1000)
    }

    public static func signedSeconds(_ s: Double) -> String {
        let v = Int(s.rounded())
        return v >= 0 ? "+\(v)s" : "\(v)s"
    }
}
