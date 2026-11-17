import Foundation

// MARK: - Quantiles, serial correlation and small regressions

extension LStat {
    /// The value a Student's t variable with `df` degrees of freedom stays under with probability `p`.
    public static func studentTQuantile(_ p: Double, df: Double) -> Double {
        guard p > 0, p < 1, df > 0 else { return 0 }
        if p == 0.5 { return 0 }
        if p < 0.5 { return -studentTQuantile(1 - p, df: df) }
        var lo = 0.0, hi = 1.0
        while studentTCDF(hi, df: df) < p, hi < 1e6 { hi *= 2 }
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if studentTCDF(mid, df: df) < p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// How closely a series follows itself one step later: 0 when each value is unrelated to the one
    /// before it, towards 1 when values drift slowly. Nil for a short or constant series.
    public static func serialCorrelation(_ x: [Double]) -> Double? {
        guard x.count >= 6, let m = mean(x) else { return nil }
        var num = 0.0, den = 0.0
        for i in x.indices {
            den += (x[i] - m) * (x[i] - m)
            if i > 0 { num += (x[i] - m) * (x[i - 1] - m) }
        }
        return den > 0 ? num / den : nil
    }

    /// A least-squares fit of one outcome on several inputs.
    public struct Regression: Equatable, Sendable {
        /// The intercept, then one coefficient per input column.
        public let coefficients: [Double]
        public let standardErrors: [Double]
        /// Two-sided p-value of each coefficient.
        public let p: [Double]
        public let n: Int
        public let r2: Double
        /// R² when each row is predicted by a fit that left that row out. It is the honest measure of
        /// how well the fit predicts a night it has not seen, and can be negative.
        public let leftOutR2: Double
        public let residualSD: Double

        public func predict(_ x: [Double]) -> Double {
            var y = coefficients[0]
            for (i, v) in x.enumerated() where i + 1 < coefficients.count { y += coefficients[i + 1] * v }
            return y
        }

        /// The range a coefficient lies in at the given confidence.
        public func interval(_ index: Int, level: Double = 0.9) -> (low: Double, high: Double) {
            let df = Double(max(1, n - coefficients.count))
            let t = LStat.studentTQuantile(0.5 + level / 2, df: df)
            return (coefficients[index] - t * standardErrors[index], coefficients[index] + t * standardErrors[index])
        }
    }

    /// Ordinary least squares of `y` on the columns of `rows` (one row per observation), with an
    /// intercept. Nil when there are too few rows, or the inputs repeat one another.
    public static func regress(y: [Double], rows: [[Double]]) -> Regression? {
        let n = y.count
        guard n == rows.count, let width = rows.first?.count, width >= 1, rows.allSatisfy({ $0.count == width }) else { return nil }
        let k = width + 1
        guard n >= k + 3, let my = mean(y) else { return nil }
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var xty = [Double](repeating: 0, count: k)
        for i in 0..<n {
            let row = [1.0] + rows[i]
            for a in 0..<k {
                xty[a] += row[a] * y[i]
                for b in 0..<k { xtx[a][b] += row[a] * row[b] }
            }
        }
        guard let inv = invert(xtx) else { return nil }
        var beta = [Double](repeating: 0, count: k)
        for a in 0..<k { for b in 0..<k { beta[a] += inv[a][b] * xty[b] } }
        var sse = 0.0, sst = 0.0, press = 0.0
        for i in 0..<n {
            let row = [1.0] + rows[i]
            var fit = 0.0
            for a in 0..<k { fit += beta[a] * row[a] }
            let e = y[i] - fit
            sse += e * e
            sst += (y[i] - my) * (y[i] - my)
            var h = 0.0
            for a in 0..<k { for b in 0..<k { h += row[a] * inv[a][b] * row[b] } }
            let left = 1 - h
            press += left > 1e-9 ? (e / left) * (e / left) : e * e
        }
        guard sst > 0 else { return nil }
        let df = Double(n - k)
        let sigma2 = sse / df
        var se: [Double] = [], ps: [Double] = []
        for a in 0..<k {
            let s = max(0, sigma2 * inv[a][a]).squareRoot()
            se.append(s)
            ps.append(s > 0 ? 2 * (1 - studentTCDF(abs(beta[a] / s), df: df)) : 1)
        }
        return Regression(coefficients: beta, standardErrors: se, p: ps, n: n, r2: 1 - sse / sst, leftOutR2: 1 - press / sst,
                          residualSD: sigma2.squareRoot())
    }

    /// The inverse of a small square matrix (Gauss–Jordan with pivoting); nil when it has none.
    static func invert(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        var a = m
        var inv = (0..<n).map { i in (0..<n).map { $0 == i ? 1.0 : 0.0 } }
        let scale = m.flatMap { $0 }.map { abs($0) }.max() ?? 0
        guard scale > 0 else { return nil }
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<max(col + 1, n) where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > scale * 1e-10 else { return nil }
            if pivot != col { a.swapAt(pivot, col); inv.swapAt(pivot, col) }
            let d = a[col][col]
            for c in 0..<n { a[col][c] /= d; inv[col][c] /= d }
            for r in 0..<n where r != col {
                let f = a[r][col]
                if f == 0 { continue }
                for c in 0..<n { a[r][c] -= f * a[col][c]; inv[r][c] -= f * inv[col][c] }
            }
        }
        return inv
    }
}
