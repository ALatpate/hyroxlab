import SwiftUI
import LumaCore
import LumaKit

// MARK: - Shared pieces

/// How firmly a pattern stands, as a pill.
struct PatternPill: View {
    let strength: PatternStrength

    var body: some View {
        switch strength {
        case .clear: LumaPill(text: "Clear", color: Luma.mint)
        case .early: LumaPill(text: "Early signal", color: Luma.amber)
        case .none: LumaPill(text: "No pattern", color: Luma.mist)
        }
    }
}

/// The mornings that followed each range of an amount: one bar a range, with how many days it stands on.
struct BinBars: View {
    let bins: [DoseBin]
    let metric: LMetric
    let color: Color

    var body: some View {
        let top = bins.compactMap { $0.mean }.max() ?? 1
        VStack(spacing: 9) {
            ForEach(bins) { bin in
                HStack(spacing: 10) {
                    Text(bin.label).font(LumaFont.body(12.5, .medium)).foregroundStyle(Luma.mist).frame(width: 104, alignment: .leading)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let mean = bin.mean {
                        LumaBar(value: mean, total: max(top, 1e-9) * 1.05, color: color, height: 10)
                        Text(metric.format(mean)).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                            .frame(width: 44, alignment: .trailing)
                    } else {
                        Capsule().fill(Color.white.opacity(0.05)).frame(height: 10)
                        Text("–").font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.smoke).frame(width: 44, alignment: .trailing)
                    }
                    Text("\(bin.n) d").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke).frame(width: 34, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An effect and the range it most likely lies in, on a line with zero in the middle.
struct RangeMeter: View {
    let effect: Double
    let low: Double
    let high: Double
    /// The largest value the line has to hold, either side of zero.
    let span: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let unit = span > 0 ? w / 2 / CGFloat(span) : 0
            let mid = w / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07)).frame(height: 6)
                Rectangle().fill(Luma.lineStrong).frame(width: 1, height: 14).offset(x: mid)
                Capsule().fill(color.opacity(0.35))
                    .frame(width: max(4, CGFloat(high - low) * unit), height: 6)
                    .offset(x: mid + CGFloat(low) * unit)
                Circle().fill(color).frame(width: 12, height: 12).overlay(Circle().stroke(Luma.night, lineWidth: 2))
                    .offset(x: mid + CGFloat(effect) * unit - 6)
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - How much and how late

/// Caffeine, alcohol, the last meal and bedtime, each set against the morning after it across the
/// athlete's own days.
struct DoseScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let read = env.next.dose
        let shown = read.findings.filter { $0.strength != .none }
        let quiet = read.findings.filter { $0.strength == .none }
        LumaDetailScreen(title: "How much and how late", tone: .sleep) {
            LumaNote("What you logged on a day, set against the morning after it. These are patterns in your own days. They show what goes together, not what causes what.")
            if read.loggedDays < DoseModel.minimumDays {
                LumaCard {
                    LumaEmpty(symbol: "chart.dots.scatter", title: "Not enough days yet",
                              message: "This needs \(DoseModel.minimumDays) days with a food log. You have \(read.loggedDays). Log caffeine and drinks with the time they were taken.")
                }
            } else {
                ForEach(read.cutoffs) { cut in CutoffCard(cut: cut) }
                if shown.isEmpty && read.cutoffs.isEmpty {
                    LumaCard {
                        LumaEmpty(symbol: "equal.circle", title: "Nothing stands out",
                                  message: "Across \(read.loggedDays) logged days, none of these goes with a different morning. That is a finding too.")
                    }
                }
                ForEach(shown) { f in DoseCard(finding: f) }
                if !quiet.isEmpty {
                    LumaSection(title: "Checked, with no pattern")
                    LumaCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(quiet) { f in
                                Text("\(f.title) and \(f.outcome.phrase) (\(f.n) days)").font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                            }
                        }
                    }
                }
                LumaNote("Read from \(read.loggedDays) days with a food log. Several things are checked at once, so a pattern is called clear only when it survives a correction for that.")
            }
        }
    }
}

private struct CutoffCard: View {
    let cut: DoseCutoff

    var body: some View {
        LumaCard(tint: Luma.dusk.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LumaLabel("Your caffeine cut-off")
                    Spacer()
                    LumaPill(text: cut.firm ? "Clear" : "Early signal", color: cut.firm ? Luma.mint : Luma.amber)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(cut.clock).font(LumaFont.numeral(52, .heavy)).foregroundStyle(Luma.frost)
                    Text(cut.outcome.title.lowercased()).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                }
                LumaNote(cut.sentence)
            }
        }
    }
}

private struct DoseCard: View {
    let finding: DoseFinding

    var body: some View {
        let better: Bool? = finding.outcome.higherIsBetter.map { $0 == (finding.perStep > 0) }
        let color: Color = better == nil ? finding.outcome.tone.color : (better == true ? Luma.mint : Luma.coral)
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        Text("against \(finding.outcome.phrase), in \(finding.outcome.unit.isEmpty ? "points" : finding.outcome.unit)")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                    Spacer()
                    PatternPill(strength: finding.strength)
                }
                BinBars(bins: finding.bins, metric: finding.outcome, color: color)
                LumaNote(finding.sentence)
            }
        }
    }
}

// MARK: - What moves recovery

/// One model of the next morning's recovery: every input fitted beside the others, so each effect is
/// what is left when the rest are held level.
struct DriversScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let read = env.next.drivers
        LumaDetailScreen(title: "What moves your recovery", tone: .recovery) {
            LumaNote("Strain, sleep, bedtime and what you logged, fitted together against the next morning's recovery. Fitting them side by side keeps a late night from being blamed for the drink that came with it.")
            if !read.ready || read.effects.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "function", title: "Not enough nights yet",
                              message: "This needs \(DriverModel.minimumNights) scored nights with the day before them. You have \(read.nights).")
                }
            } else {
                if let forecast = read.forecast { ForecastCard(forecast: forecast) }
                let span = max(1, read.effects.map { max(abs($0.low), abs($0.high)) }.max() ?? 1)
                LumaCard {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(read.effects) { e in DriverRow(effect: e, span: span) }
                    }
                }
                LumaNote(footer(read))
            }
        }
    }

    private func footer(_ read: DriverRead) -> String {
        var text = "Fitted on \(read.nights) of your nights"
        if read.loggedNights >= DriverModel.minimumLogged { text += ", \(read.loggedNights) of them with a food log" }
        text += ". The dot is the effect; the band is the range it most likely lies in."
        if let r = read.leftOutR2, r > 0 {
            text += " Tried on nights it was not fitted on, it accounts for about \(Int((r * 100).rounded()))% of how recovery moves from one morning to the next. The rest is everything it cannot see."
        }
        return text
    }
}

private struct ForecastCard: View {
    let forecast: RecoveryForecast

    var body: some View {
        LumaCard(tint: Luma.recovery(forecast.value).opacity(0.6)) {
            VStack(alignment: .leading, spacing: 8) {
                LumaLabel("Tomorrow morning, as today stands")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(forecast.value.rounded()))%").font(LumaFont.numeral(56, .heavy)).foregroundStyle(Luma.frost)
                    Text("likely \(Int(forecast.low.rounded())) to \(Int(forecast.high.rounded()))").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                }
                LumaNote(forecast.basis + " An estimate from your own pattern, not a promise.")
            }
        }
    }
}

private struct DriverRow: View {
    let effect: DriverEffect
    let span: Double

    var body: some View {
        let color: Color = effect.strength == .none ? Luma.mist : (effect.effect >= 0 ? Luma.mint : Luma.coral)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(effect.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                Spacer()
                Text(String(format: "%+.1f", effect.effect)).font(LumaFont.numeral(20)).foregroundStyle(effect.strength == .none ? Luma.mist : Luma.frost)
                PatternPill(strength: effect.strength)
            }
            RangeMeter(effect: effect.effect, low: effect.low, high: effect.high, span: span, color: color)
            Text(effect.sentence).font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - What helps training

/// Weeks the lifts moved, set against the habits that held in those weeks.
struct TrainingHelpCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let read = env.next.help
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: "What goes with your stronger weeks")
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    if !read.ready {
                        LumaNote("Week by week, how your lifts moved against whether you slept enough, ate enough protein and took your supplements. It works on whole weeks, so it needs \(TrainingHelpModel.minimumWeeks) finished weeks with lifts in them. You have \(read.weeks).")
                    } else if read.findings.isEmpty {
                        LumaNote("Across \(read.weeks) weeks, no habit splits your weeks into enough of each kind to compare. Keep logging.")
                    } else {
                        ForEach(read.findings) { f in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(f.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                                    Spacer()
                                    PatternPill(strength: f.strength)
                                }
                                Text(f.sentence).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        LumaNote("From \(read.weeks) finished weeks. Weeks are few, so most of these stay early signals for a long time.")
                    }
                }
            }
        }
    }
}
