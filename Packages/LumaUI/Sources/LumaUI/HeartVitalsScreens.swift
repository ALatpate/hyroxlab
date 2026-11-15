import SwiftUI
import LumaCore
import LumaKit

// MARK: - Heart

struct HeartScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @State private var day: [LHRPoint] = []
    @State private var nightHRV: [LPoint] = []

    var body: some View {
        let a = env.analysis
        let zones = env.profile.zones()
        // Laid on the clock from the start of the day, so time with no readings shows as a break.
        let grid = TimeGrid(day, from: LDate.startOfDay(a.today)?.timeIntervalSince1970 ?? (day.first?.t ?? 0), step: 300)
        LumaDetailScreen(title: "Heart", tone: .heart) {
            LiveHeartHero(strap: live.strap, zones: zones, maxHR: env.profile.resolvedMaxHR())
            if day.count > 6 {
                LumaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        LumaLabel("Today")
                        LumaLineChart(values: grid.values, labels: grid.labels, color: Luma.coral, height: 170, gaps: true)
                        HStack(spacing: 0) {
                            dayStat("Lowest", day.map { $0.lo }.min())
                            dayStat("Average", LStat.mean(day.map { $0.bpm }))
                            dayStat("Highest", day.map { $0.hi }.max())
                        }
                    }
                }
            }
            Group {
                LumaSection(title: "Resting heart rate")
                MetricHistoryCard(metric: .restingHR, style: .line)
                if let t = a.trend(.restingHR) { TrendNote(trend: t) }
            }
            Group {
                LumaSection(title: "Heart rate variability")
                MetricHistoryCard(metric: .hrv, style: .line)
                if let t = a.trend(.hrv) { TrendNote(trend: t) }
                if nightHRV.count > 4 {
                    LumaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            LumaLabel("HRV through last night")
                            LumaLineChart(values: nightHRV.map { $0.v }, labels: nightHRV.map { LumaText.time($0.t) }, color: Luma.aqua, height: 140)
                        }
                    }
                }
                LumaNote("HRV is the beat-to-beat variation in your heart rhythm, measured overnight (RMSSD). Higher than your own baseline usually means your nervous system has recovered; lower means it is still under load. Compare with yourself, not with others.")
            }
            Group {
                LumaSection(title: "Your zones")
                ZoneTable(zones: zones, maxHR: env.profile.resolvedMaxHR(), measured: env.profile.maxHR != nil || env.profile.lthr != nil,
                          observed: a.fitness.observedMaxHR)
            }
        }
        .task(id: env.days.count) {
            guard let start = LDate.startOfDay(a.today)?.timeIntervalSince1970 else { return }
            day = await env.source.heartRate(from: start, to: start + 86_400, bucketSeconds: 300)
            if let main = a.sleep.last?.main { nightHRV = await env.source.hrvSeries(from: main.start, to: main.end) }
        }
        .onAppear { env.device?.setLiveHeartRate(true) }
        .onDisappear { env.device?.setLiveHeartRate(false) }
    }

    private func dayStat(_ label: String, _ v: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LumaLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v.map { String(format: "%.0f", $0) } ?? "–").font(LumaFont.numeral(24, .semibold)).foregroundStyle(Luma.frost)
                Text("bpm").font(LumaFont.body(11)).foregroundStyle(Luma.mist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The current heart rate, large, with a pulse and the zone it sits in. When the strap is not
/// streaming it shows the last reading and says how old it is rather than a blank.
struct LiveHeartHero: View {
    let strap: LumaStrap
    let zones: HXZones
    let maxHR: Double
    @State private var pulse = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let liveHR = strap.liveHeartRate(now: context.date)
            let shown = liveHR ?? strap.heartRate
            let zone = shown.map { zones.zone(for: Double($0)) }
            let color = zone.map { Luma.zone($0) } ?? Luma.coral
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().fill(Luma.coral.opacity(0.16)).frame(width: 112, height: 112).scaleEffect(pulse && liveHR != nil ? 1.14 : 0.94)
                    Circle().fill(Luma.coral.opacity(0.24)).frame(width: 78, height: 78)
                    Image(systemName: "heart.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(Luma.coral)
                        .scaleEffect(pulse && liveHR != nil ? 1.08 : 1)
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(liveHR != nil ? Luma.volt : Luma.smoke).frame(width: 7, height: 7)
                        LumaLabel(liveHR != nil ? "Live" : (strap.connected ? "Waiting for the strap" : "Strap not connected"))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(shown.map { String($0) } ?? "–").font(LumaFont.numeral(84, .heavy)).foregroundStyle(liveHR != nil ? Luma.frost : Luma.mist)
                            .contentTransition(.numericText())
                        Text("bpm").font(LumaFont.body(16, .semibold)).foregroundStyle(Luma.mist)
                    }
                    if liveHR == nil, let at = strap.heartRateAt {
                        Text("Last reading \(at.formatted(.relative(presentation: .named)))").font(LumaFont.body(13)).foregroundStyle(Luma.smoke)
                    } else if let z = zone, let s = shown {
                        Text("Zone \(z) · \(Int((Double(s) / maxHR * 100).rounded()))% of max").font(LumaFont.body(13, .medium)).foregroundStyle(color)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct TrendNote: View {
    let trend: TrendRead

    var body: some View {
        let color: Color = trend.improving == nil ? Luma.mist : (trend.improving == true ? Luma.mint : Luma.amber)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: trend.direction == 0 ? "equal" : (trend.direction > 0 ? "arrow.up.right" : "arrow.down.right"))
                .font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                .frame(width: 26, height: 26).background(Circle().fill(color.opacity(0.14)))
            Text(trend.sentence).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ZoneTable: View {
    let zones: HXZones
    let maxHR: Double
    let measured: Bool
    let observed: Double?

    private let names = ["Recovery", "Aerobic base", "Tempo", "Threshold", "Maximum"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaGroup {
                ForEach((0..<5).reversed(), id: \.self) { i in
                    let lo = Int(zones.bounds[i].rounded())
                    let hi = i < 4 ? Int(zones.bounds[i + 1].rounded()) - 1 : Int(maxHR.rounded())
                    HStack(spacing: 12) {
                        Text("Z\(i + 1)").font(LumaFont.numeral(20, .bold)).foregroundStyle(Luma.zone(i + 1)).frame(width: 30, alignment: .leading)
                        Text(names[i]).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Spacer()
                        Text(i == 0 ? "under \(hi + 1)" : "\(lo)–\(hi)").font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                        Text("bpm").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
            }
            if !measured {
                LumaNote("Zones use an age-based maximum of \(Int(maxHR)) bpm. If you know your real maximum or threshold heart rate, set it in your profile for accurate zones.")
            }
            if let o = observed, o > maxHR + 2 {
                LumaNote("Luma has seen \(Int(o)) bpm in a recent session, above the maximum your zones assume. Consider raising your maximum heart rate in your profile.")
            }
        }
    }
}

// MARK: - Vitals

struct VitalsScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let a = env.analysis
        let night = a.lastNight
        LumaDetailScreen(title: "Vitals", tone: .stress) {
            if let n = night, n.day != a.today {
                LumaPill(text: "Latest night: \(LumaText.dayTitle(n.day, today: a.today).lowercased())", color: Luma.amber, symbol: "clock")
            }
            StatGrid {
                VitalCell(label: "Respiratory rate", value: night?.respRate, decimals: 1, unit: "rpm", baseline: a.baselines.respRate)
                VitalCell(label: "Skin temperature", value: night?.skinTempDev, decimals: 1, unit: "°C", baseline: nil, signed: true,
                          inRange: night?.skinTempDev.map { abs($0) < 0.5 })
                VitalCell(label: "Resting heart rate", value: night?.restingHR, decimals: 0, unit: "bpm", baseline: a.baselines.restingHR)
                VitalCell(label: "HRV", value: night?.hrv, decimals: 0, unit: "ms", baseline: a.baselines.hrv)
            }
            WatchCard(watch: a.watch)

            LumaSection(title: "Respiratory rate")
            MetricHistoryCard(metric: .respRate, style: .line)
            LumaNote("Breaths per minute while asleep. It is one of the steadiest signals the body has, so a rise of a breath or more above your norm is worth noticing.")

            LumaSection(title: "Skin temperature")
            MetricHistoryCard(metric: .skinTempDev, style: .line, goal: 0)
            LumaNote("Shown as the difference from your own baseline. Sustained readings half a degree or more above it often accompany illness, alcohol or a hot room.")

            if env.days.contains(where: { $0.spo2 != nil }) {
                LumaSection(title: "Blood oxygen")
                MetricHistoryCard(metric: .spo2, style: .line)
            } else {
                LumaCard {
                    LumaRow(symbol: "drop.degreesign", symbolColor: Luma.sky, title: "Blood oxygen",
                            subtitle: "This strap does not report a blood-oxygen percentage to Luma, so none is shown.")
                }
            }
        }
    }
}

struct VitalCell: View {
    let label: String
    let value: Double?
    let decimals: Int
    let unit: String
    let baseline: LBaseline?
    var signed: Bool = false
    var inRange: Bool? = nil

    var body: some View {
        let ok: Bool? = inRange ?? value.flatMap { v in baseline.map { abs($0.z(v)) < 2 } }
        VStack(alignment: .leading, spacing: 6) {
            LumaLabel(label)
            LumaFigure(value: value, decimals: decimals, unit: unit, size: 32, signed: signed)
            if let ok {
                HStack(spacing: 5) {
                    Circle().fill(ok ? Luma.mint : Luma.amber).frame(width: 6, height: 6)
                    Text(ok ? "In your range" : "Outside your range").font(LumaFont.body(12, .medium)).foregroundStyle(ok ? Luma.mint : Luma.amber)
                }
            } else {
                Text(value == nil ? "No reading yet" : "Baseline building").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
            }
            if let b = baseline, value != nil {
                Text("Usual \(String(format: "%.\(decimals)f", b.low))–\(String(format: "%.\(decimals)f", b.high))")
                    .font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(LumaPanel(radius: 20))
    }
}

// MARK: - Stress

struct StressScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var stress: LStressDay?

    private func color(_ level: Double) -> Color { level < 1 ? Luma.aqua : (level < 2 ? Luma.amber : Luma.coral) }

    var body: some View {
        let a = env.analysis
        let history = dailyHistory()
        LumaDetailScreen(title: "Stress", tone: .stress) {
            if let s = stress, let mean = s.mean {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        LumaLabel("Today so far")
                        Text(LStressDay.band(mean)).font(LumaFont.numeral(64, .heavy)).foregroundStyle(color(mean))
                        Text(s.highMinutes > 0 ? "\(LFormat.hm(minutes: Double(s.highMinutes))) of high stress" : "No hours of high stress")
                            .font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    }
                    Spacer()
                }
                LumaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        LumaLabel("Hour by hour")
                        LumaBarChart(bars: s.hours.map { h in
                            LumaBarChart.Bar(id: h.hour, value: h.level, color: color(h.level ?? 0), label: "\(h.hour):00")
                        }, yRange: 0...3, height: 170, format: { LStressDay.band($0) }, ticks: [0.5, 1.5, 2.5], axisWidth: 62)
                        LumaNote("Stress is read from heart rate and its variability while you are still. Hours spent training are left out, so a gap is a workout, not calm.")
                    }
                }
            } else {
                LumaCard {
                    LumaEmpty(symbol: "waveform.path.ecg", title: "No stress reading yet today",
                              message: "The curve builds through the day as the strap records your heart rhythm at rest.")
                }
            }
            if history.values.compactMap({ $0 }).count >= 5 {
                LumaSection(title: "Last 30 days")
                LumaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        LumaLabel("Daily stress load")
                        LumaLineChart(values: history.values, labels: history.keys.map { LumaText.shortDay($0) }, color: Luma.amber,
                                      yRange: 0...3, height: 170, format: { LStressDay.band($0) }, ticks: [0.5, 1.5, 2.5], axisWidth: 62)
                        LumaNote("An overnight view: how far your resting heart rate and HRV sat from baseline each morning. Use it to spot stretches where your body stayed switched on.")
                    }
                }
            }
            if let t = a.trend(.hrv) { TrendNote(trend: t) }
        }
        .task(id: env.days.count) { stress = await env.source.stress(day: a.today) }
    }

    private func dailyHistory() -> (keys: [String], values: [Double?]) {
        let keys = LDate.range(ending: env.today, count: 30)
        let byDay = Dictionary(env.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let values: [Double?] = keys.map { key in
            guard let d = byDay[key] else { return nil }
            return StressModel.daily(day: d, baselines: LBaselines.compute(days: env.days, before: key))
        }
        return (keys, values)
    }
}
