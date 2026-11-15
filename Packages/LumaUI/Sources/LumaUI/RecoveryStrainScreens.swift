import SwiftUI
import LumaCore
import LumaKit

// MARK: - Recovery

struct RecoveryScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let a = env.analysis
        LumaDetailScreen(title: "Recovery", tone: .recovery) {
            if let read = a.recovery {
                RecoveryHero(read: read, today: a.today, gap: a.gap)
                if !read.factors.isEmpty {
                    LumaSection(title: read.score == nil ? "What was measured" : "What is behind it")
                    LumaGroup {
                        ForEach(read.factors) { FactorRow(factor: $0) }
                    }
                    if read.day == a.today, let sentence = LumaWords.nightSentence(a.night) {
                        LumaNote("\(sentence) These figures cover the recorded part only.")
                    }
                    if read.nightsToBaseline > 0 {
                        LumaNote("\(read.nightsToBaseline) more nights until your baselines are established. Until then comparisons are provisional.")
                    }
                }
                if a.watch.level >= .watch || !a.watch.signals.isEmpty {
                    LumaSection(title: "Early-warning check")
                    WatchCard(watch: a.watch)
                }
            } else {
                LumaCard {
                    LumaEmpty(symbol: "bolt.heart", title: "No recovery score yet",
                              message: "Recovery is scored each morning from the night's HRV, resting heart rate and sleep. Wear the strap to bed with Luma running in the background.")
                }
            }
            LumaSection(title: "History")
            MetricHistoryCard(metric: .recovery, style: .bars, barColor: { Luma.recovery($0) })
            WeekdayCard(metric: .recovery)
            let habits = a.effects.filter { $0.outcome == .recovery }.prefix(3)
            if !habits.isEmpty {
                LumaSection(title: "What moves your recovery")
                ForEach(Array(habits)) { EffectCard(finding: $0) }
            }
        }
    }
}

struct RecoveryHero: View {
    let read: RecoveryRead
    let today: String
    /// Why there is no score, when there is none: the same resolved reason Today gives.
    var gap: RecoveryGap? = nil
    @State private var shown: Double = 0

    var body: some View {
        let color = Luma.recovery(read.score)
        VStack(spacing: 10) {
            ZStack {
                LumaOrb(progress: shown / 100, color: color, partner: (read.score ?? 0) >= 67 ? Luma.mint : color)
                VStack(spacing: -4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(read.score.map { String(format: "%.0f", $0) } ?? "–").font(LumaFont.numeral(76, .heavy))
                        if read.score != nil { Text("%").font(LumaFont.numeral(26)).foregroundStyle(Luma.mist) }
                    }
                    .foregroundStyle(Luma.frost)
                    Text(read.band?.title ?? LumaWords.gapLabel(gap)).font(LumaFont.label(12)).foregroundStyle(color)
                }
            }
            .frame(height: 220)
            if read.day != today {
                LumaPill(text: "From \(LumaText.dayTitle(read.day, today: today).lowercased())", color: Luma.amber, symbol: "clock")
            }
            Text(read.headline).font(LumaFont.title(22)).foregroundStyle(Luma.frost).multilineTextAlignment(.center)
            Text(read.detail).font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .onAppear { withAnimation(.easeOut(duration: 1.1).delay(0.1)) { shown = read.score ?? 0 } }
    }
}

/// One input to recovery: its value, what is normal for you, and which way it is pulling.
struct FactorRow: View {
    let factor: RecoveryFactor

    var body: some View {
        let m = factor.metric
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(m.title).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                Text(factor.note).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
            }
            Spacer(minLength: 6)
            EffectMeter(effect: factor.effect)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(m.format(factor.value)).font(LumaFont.numeral(22, .semibold)).foregroundStyle(Luma.frost)
                    Text(m.unit).font(LumaFont.body(11)).foregroundStyle(Luma.mist)
                }
                if let b = factor.baseline, m != .skinTempDev {
                    Text("usual \(m.format(b))").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
    }
}

/// A small centre-zero meter: right of centre helps, left of centre drags.
struct EffectMeter: View {
    let effect: Double
    @State private var shown: Double = 0

    var body: some View {
        let clamped = min(2.5, max(-2.5, shown))
        let color: Color = effect > 0.5 ? Luma.volt : (effect < -0.5 ? Luma.coral : Luma.smoke)
        ZStack {
            Capsule().fill(Color.white.opacity(0.08)).frame(width: 56, height: 6)
            Rectangle().fill(Luma.smoke).frame(width: 1.5, height: 12)
            Capsule().fill(color)
                .frame(width: max(3, CGFloat(abs(clamped)) / 2.5 * 28), height: 6)
                .offset(x: CGFloat(clamped) / 2.5 * 14)
        }
        .frame(width: 56, height: 14)
        .onAppear { withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) { shown = effect } }
    }
}

struct WatchCard: View {
    let watch: BodyWatch

    var body: some View {
        LumaCard(tint: watch.level == .clear ? nil : (watch.level == .alert ? Luma.coral : Luma.amber)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: watch.level == .clear ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(watch.level == .clear ? Luma.mint : (watch.level == .alert ? Luma.coral : Luma.amber))
                    Text(watch.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                }
                LumaNote(watch.detail)
                ForEach(watch.signals) { s in
                    HStack {
                        Circle().fill(s.flagged ? Luma.coral : Luma.mint).frame(width: 7, height: 7)
                        Text(s.metric.title).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                        Spacer()
                        Text(s.text.replacingOccurrences(of: s.metric.title + " ", with: "")).font(LumaFont.numeral(17, .semibold))
                            .foregroundStyle(s.flagged ? Luma.coral : Luma.mist)
                    }
                }
                Text("A pattern check, not a diagnosis.").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
            }
        }
    }
}

/// Mean of a metric by weekday, to show the shape of the week.
struct WeekdayCard: View {
    let metric: LMetric
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let means = EffectModel.weekdayMeans(metric, days: Array(env.days.suffix(84)))
        if means.count >= 5 {
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    LumaLabel("\(metric.title) by weekday · last 12 weeks")
                    LumaBarChart(bars: (1...7).map { wd in
                        let v = means[wd]?.mean
                        return LumaBarChart.Bar(id: wd, value: v, color: metric == .recovery ? Luma.recovery(v) : metric.tone.color,
                                                label: ["M", "T", "W", "T", "F", "S", "S"][wd - 1])
                    }, height: 140, format: { metric.format($0) })
                }
            }
        }
    }
}

/// A habit's measured effect: the two group means side by side and the sentence that explains them.
struct EffectCard: View {
    let finding: EffectFinding

    var body: some View {
        let helps = finding.helps
        let color: Color = helps == nil ? Luma.mist : (helps == true ? Luma.mint : Luma.coral)
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(finding.factor).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    Spacer()
                    LumaPill(text: finding.reliable ? "Reliable" : "Early signal", color: finding.reliable ? Luma.mint : Luma.amber)
                }
                CompareBars(aLabel: "After", a: finding.withMean, bLabel: "Otherwise", b: finding.withoutMean,
                            metric: finding.outcome, color: color)
                LumaNote(finding.sentence)
            }
        }
    }
}

/// Two values as horizontal bars on a shared scale.
struct CompareBars: View {
    let aLabel: String
    let a: Double
    let bLabel: String
    let b: Double
    let metric: LMetric
    let color: Color

    var body: some View {
        let top = max(a, b, 1e-9)
        VStack(spacing: 8) {
            row(aLabel, a, top, color)
            row(bLabel, b, top, Luma.mist)
        }
    }

    private func row(_ label: String, _ v: Double, _ top: Double, _ c: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist).frame(width: 74, alignment: .leading)
            LumaBar(value: v, total: top * 1.05, color: c, height: 10)
            Text("\(metric.format(v)) \(metric.unit)").font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                .frame(width: 70, alignment: .trailing)
        }
    }
}

// MARK: - Strain

struct StrainScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var hr: [LHRPoint] = []

    var body: some View {
        let a = env.analysis
        let on21 = env.profile.strainOn21
        let strain = a.day?.strain.map { LScale.shown($0, on21: on21) }
        let todays = env.workouts.filter { $0.day == a.today }.sorted { $0.start < $1.start }
        // Laid on the clock from the start of the day, so time with no readings shows as a break.
        let grid = TimeGrid(hr, from: LDate.startOfDay(a.today)?.timeIntervalSince1970 ?? (hr.first?.t ?? 0), step: 300)
        LumaDetailScreen(title: "Strain", tone: .strain) {
            StrainHero(strain: strain, top: on21 ? 21 : 100, target: on21 ? a.call.strainTarget : nil)
            if hr.count > 6 {
                LumaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            LumaLabel("Heart rate today")
                            Spacer()
                            if let peak = hr.map({ $0.hi }).max() {
                                Text("Peak \(Int(peak.rounded())) bpm").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist)
                            }
                        }
                        LumaLineChart(values: grid.values, labels: grid.labels, color: Luma.ember, height: 160, gaps: true)
                    }
                }
            }
            LumaSection(title: "Sessions today")
            if todays.isEmpty {
                LumaCard { Text("No sessions recorded today.").font(LumaFont.body(14)).foregroundStyle(Luma.mist) }
            } else {
                LumaGroup {
                    ForEach(todays) { w in
                        Button { router.push(.workout(w.id)) } label: { WorkoutRow(workout: w, on21: on21) }.buttonStyle(.plain)
                    }
                }
            }
            StatGrid {
                StatCell(label: "Steps", value: a.day?.steps.map { LFormat.grouped(Double($0)) } ?? "–")
                StatCell(label: "Active energy", value: a.day?.activeKcal.map { LFormat.grouped($0) } ?? "–", unit: "kcal")
            }
            Button { router.push(.load) } label: { LoadTeaser(load: a.load) }.buttonStyle(.plain)
            LumaSection(title: "History")
            MetricHistoryCard(metric: .strain, style: .bars)
            StrainRecoveryCard()
        }
        .task(id: env.days.count) {
            guard let start = LDate.startOfDay(a.today)?.timeIntervalSince1970 else { return }
            hr = await env.source.heartRate(from: start, to: start + 86_400, bucketSeconds: 300)
        }
    }
}

struct StrainHero: View {
    let strain: Double?
    let top: Double
    let target: ClosedRange<Double>?
    @State private var shown: Double = 0

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                LumaRing(progress: shown / top, lineWidth: 13, colors: [Luma.amber, Luma.ember, Luma.coral])
                VStack(spacing: -2) {
                    Text(strain.map { String(format: top == 21 ? "%.1f" : "%.0f", $0) } ?? "–").font(LumaFont.numeral(48, .heavy)).foregroundStyle(Luma.frost)
                    LumaLabel("of \(Int(top))")
                }
            }
            .frame(width: 140, height: 140)
            VStack(alignment: .leading, spacing: 8) {
                LumaLabel("Day strain")
                Text(band).font(LumaFont.title(22)).foregroundStyle(Luma.frost)
                if let t = target {
                    Text("Today's target is \(Int(t.lowerBound))–\(Int(t.upperBound)).").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    StrainTrack(target: t, current: strain, color: Luma.ember)
                } else {
                    Text("Strain builds with time at higher heart rates.").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear { withAnimation(.easeOut(duration: 1.0).delay(0.1)) { shown = strain ?? 0 } }
        .onChange(of: strain) { _, new in withAnimation(.easeOut(duration: 0.8)) { shown = new ?? 0 } }
    }

    private var band: String {
        guard let s = strain else { return "No data yet" }
        let s21 = top == 21 ? s : LScale.strain21(s)
        return s21 < 7 ? "Light" : s21 < 12 ? "Moderate" : s21 < 16 ? "High" : "All out"
    }
}

/// A session in a list: sport, time, duration and its strain.
struct WorkoutRow: View {
    let workout: LWorkout
    let on21: Bool

    var body: some View {
        let kind = workout.kind
        HStack(spacing: 13) {
            Image(systemName: kind.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(kind.tone.color)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(kind.tone.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.sport).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                Text(subtitle).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
            }
            Spacer(minLength: 6)
            if let s = workout.strain {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(LScale.text(s, on21: on21)).font(LumaFont.numeral(22, .semibold)).foregroundStyle(Luma.frost)
                    Text("strain").font(LumaFont.body(10.5)).foregroundStyle(Luma.smoke)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts = [LumaText.time(workout.start), LumaText.duration(workout.durationS)]
        if let d = workout.distanceM, d > 200 { parts.append("\(LumaText.km(d)) km") }
        if let hr = workout.avgHR { parts.append("\(Int(hr.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }
}

struct LoadTeaser: View {
    let load: LoadState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Luma.ember)
                .frame(width: 44, height: 44).background(Circle().fill(Luma.ember.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Training load: \(load.status.title.lowercased())").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                Text(load.ready ? String(format: "Load ratio %.2f · fitness %.0f · fatigue %.0f", load.acwr ?? 0, load.today?.fitness ?? 0, load.today?.fatigue ?? 0)
                                : "\(load.historyDays) of \(LoadModel.minimumHistory) days recorded")
                    .font(LumaFont.body(13)).foregroundStyle(Luma.mist)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
        }
        .padding(16)
        .background(LumaPanel(radius: 22))
    }
}

/// Strain and next-morning recovery over two weeks, both as a percentage of their scale.
struct StrainRecoveryCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let strain = env.series(.strain, count: 14)
        let recovery = env.series(.recovery, count: 14)
        if strain.values.compactMap({ $0 }).count >= 4 {
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        LumaLabel("Strain and recovery · 14 days")
                        Spacer()
                        legend("Strain", Luma.ember)
                        legend("Recovery", Luma.volt)
                    }
                    LumaLineChart(series: [
                        LumaLineChart.Series(id: "strain", values: strain.values.map { $0.map { $0 / 21 * 100 } }, color: Luma.ember),
                        LumaLineChart.Series(id: "recovery", values: recovery.values, color: Luma.volt),
                    ], labels: strain.keys.map { LumaText.shortDay($0) }, yRange: 0...100, height: 170, format: { String(format: "%.0f%%", $0) },
                    tickFormat: { String(format: "%.0f", $0) })
                    LumaNote("When strain stays high while recovery falls for several days, you are spending more than you are restoring.")
                }
            }
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(LumaFont.body(12)).foregroundStyle(Luma.mist)
        }
    }
}

// MARK: - Load

struct LoadScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let load = env.analysis.load
        let recent = Array(load.days.suffix(90))
        LumaDetailScreen(title: "Training load", tone: .strain) {
            LumaCard(tint: Luma.ember.opacity(0.6)) {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Status")
                    Text(load.headline).font(LumaFont.title(24)).foregroundStyle(Luma.frost)
                    LumaNote(load.detail)
                    if load.ready {
                        HStack(alignment: .center, spacing: 16) {
                            ZStack {
                                LumaGauge(value: load.acwr, range: 0.4...2.0, bands: [
                                    (0.4...0.8, Luma.sky), (0.8...1.3, Luma.volt), (1.3...1.5, Luma.amber), (1.5...2.0, Luma.coral),
                                ])
                                VStack(spacing: -2) {
                                    Text(load.acwr.map { String(format: "%.2f", $0) } ?? "–").font(LumaFont.numeral(34, .heavy)).foregroundStyle(Luma.frost)
                                    LumaLabel("Load ratio")
                                }
                                .offset(y: 6)
                            }
                            .frame(width: 150, height: 122)
                            VStack(alignment: .leading, spacing: 8) {
                                keyRow(Luma.sky, "Under 0.8", "Fresh, losing fitness if it lasts")
                                keyRow(Luma.volt, "0.8 – 1.3", "Building safely")
                                keyRow(Luma.amber, "1.3 – 1.5", "Overreaching")
                                keyRow(Luma.coral, "Over 1.5", "Spike: higher injury risk")
                            }
                        }
                    }
                }
            }
            StatGrid {
                StatCell(label: "Fitness", value: String(format: "%.0f", load.today?.fitness ?? 0), note: "42-day load")
                StatCell(label: "Fatigue", value: String(format: "%.0f", load.today?.fatigue ?? 0), note: "7-day load")
                StatCell(label: "Form", value: String(format: "%+.0f", load.today?.form ?? 0), note: "Fitness minus fatigue",
                         color: (load.today?.form ?? 0) < -25 ? Luma.coral : Luma.frost)
                StatCell(label: "This week", value: String(format: "%.0f", load.weekLoad),
                         note: load.weekChangePct.map { String(format: "%+.0f%% vs last week", $0) })
            }
            if recent.count >= 14 {
                LumaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            LumaLabel("Fitness and fatigue · 90 days")
                            Spacer()
                        }
                        LumaLineChart(series: [
                            LumaLineChart.Series(id: "fitness", values: recent.map { $0.fitness }, color: Luma.sky, fill: true),
                            LumaLineChart.Series(id: "fatigue", values: recent.map { $0.fatigue }, color: Luma.ember),
                        ], labels: recent.map { LumaText.shortDay($0.day) }, zeroBased: true, height: 190)
                        HStack(spacing: 16) {
                            HStack(spacing: 5) { Circle().fill(Luma.sky).frame(width: 7, height: 7); Text("Fitness").font(LumaFont.body(12)).foregroundStyle(Luma.mist) }
                            HStack(spacing: 5) { Circle().fill(Luma.ember).frame(width: 7, height: 7); Text("Fatigue").font(LumaFont.body(12)).foregroundStyle(Luma.mist) }
                        }
                        LumaNote("Fitness is what months of training have built; fatigue is what the last week has cost. Form is the gap: slightly negative while building, positive when tapering for a race.")
                    }
                }
                WeeklyLoadCard(days: load.days)
            }
            TrainingMixCard()
            if let m = load.monotony {
                LumaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        LumaLabel("Monotony")
                        Text(String(format: "%.1f", m)).font(LumaFont.numeral(38)).foregroundStyle(m > 2 ? Luma.amber : Luma.frost)
                        LumaNote(m > 2 ? "Your days this week look alike. Bigger contrast between hard and easy days lets you absorb more work for the same fatigue."
                                       : "Good contrast between harder and easier days this week.")
                    }
                }
            }
        }
    }

    private func keyRow(_ color: Color, _ range: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text(range).font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.frost)
                Text(text).font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
            }
        }
    }
}

struct WeeklyLoadCard: View {
    let days: [LoadDay]

    var body: some View {
        let weeks = stride(from: 0, to: min(days.count, 84), by: 7).map { offset -> (label: String, total: Double) in
            let end = days.count - offset
            let slice = days[max(0, end - 7)..<end]
            return (LumaText.shortDay(slice.first?.day ?? ""), slice.reduce(0) { $0 + $1.load })
        }.reversed()
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("Weekly load · 12 weeks")
                LumaBarChart(bars: Array(weeks).enumerated().map { i, w in
                    LumaBarChart.Bar(id: i, value: w.total, color: Luma.ember, label: w.label)
                }, height: 160)
            }
        }
    }
}

/// Where the last four weeks of training time went, by sport and by intensity.
struct TrainingMixCard: View {
    @EnvironmentObject private var env: LumaEnv

    private let palette: [Color] = [Luma.volt, Luma.ember, Luma.sky, Luma.dusk, Luma.aqua, Luma.amber, Luma.coral, Luma.mist]

    var body: some View {
        let from = LDate.adding(-27, to: env.today)
        let mix = LoadModel.minutesByKind(workouts: env.workouts, from: from, to: env.today)
        let zones = LoadModel.zoneSeconds(workouts: env.workouts, from: from, to: env.today)
        if !mix.isEmpty {
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    LumaLabel("Training mix · 4 weeks")
                    LumaShareBar(shares: mix.enumerated().map { i, m in
                        LumaShareBar.Share(id: m.kind.rawValue, value: m.minutes, color: palette[i % palette.count])
                    })
                    ForEach(Array(mix.enumerated()), id: \.offset) { i, m in
                        HStack {
                            Circle().fill(palette[i % palette.count]).frame(width: 8, height: 8)
                            Text(m.kind.title).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                            Spacer()
                            Text(LFormat.hm(minutes: m.minutes)).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                        }
                    }
                    if let p = LoadModel.polarization(zones) {
                        LumaDivider()
                        LumaLabel("Intensity split")
                        LumaShareBar(shares: [
                            LumaShareBar.Share(id: "easy", value: p.easy, color: Luma.sky),
                            LumaShareBar.Share(id: "moderate", value: p.moderate, color: Luma.amber),
                            LumaShareBar.Share(id: "hard", value: p.hard, color: Luma.coral),
                        ])
                        Text(String(format: "Easy %.0f%% · moderate %.0f%% · hard %.0f%%", p.easy * 100, p.moderate * 100, p.hard * 100))
                            .font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                        LumaNote(p.moderate > 0.35 ? "A lot of your time sits in the middle zone. Endurance builds best with most work easy and a smaller share properly hard."
                                                   : "Most of your time is easy with a clear hard share: the pattern endurance research favours.")
                    }
                }
            }
        }
    }
}
