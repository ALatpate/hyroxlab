import SwiftUI
import LumaCore
import LumaKit

/// One night in detail, with the schedule, debt and history around it.
struct SleepScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var day: String = ""
    @State private var nightHR: [LHRPoint] = []

    private var summary: SleepSummary { env.analysis.sleep }
    private var night: SleepNight? { summary.nights.last { $0.day == day } }

    var body: some View {
        LumaDetailScreen(title: "Sleep", tone: .sleep) {
            if summary.nights.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "moon.zzz.fill", title: "No nights recorded yet",
                              message: "Wear the strap to bed and sync in the morning. Your first night appears here.")
                }
            } else {
                DayStepper(day: $day, earliest: summary.nights.first?.day, today: env.today)
                if let n = night {
                    SleepHero(night: n)
                    if let main = n.main, !main.stages.isEmpty {
                        LumaCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    LumaLabel("Stages")
                                    Spacer()
                                    Text("\(LumaText.time(main.start)) – \(LumaText.time(main.end))").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist)
                                }
                                LumaHypnogram(stages: main.stages).id(n.day)
                                if main.incomplete {
                                    LumaNote("The strap flagged this night's staging as possibly incomplete.")
                                }
                            }
                        }
                    }
                    StageBreakdown(night: n).id("stages-\(n.day)")
                    StatGrid {
                        StatCell(label: "Efficiency", value: n.efficiency.map { String(format: "%.0f", $0) } ?? "–", unit: "%", note: "Asleep while in bed")
                        StatCell(label: "Time in bed", value: LFormat.clock(minutes: n.inBedMin), unit: "h")
                        StatCell(label: "Wake-ups", value: n.awakenings.map { String($0) } ?? "–", note: n.awakeMin.map { "\(Int($0.rounded())) min awake" })
                        StatCell(label: "Restorative", value: n.restorativePct.map { String(format: "%.0f", $0) } ?? "–", unit: "%", note: "Deep + REM share")
                        StatCell(label: "Sleeping heart rate", value: env.day(n.day)?.restingHR.map { String(format: "%.0f", $0) } ?? "–", unit: "bpm")
                        StatCell(label: "HRV", value: env.day(n.day)?.hrv.map { String(format: "%.0f", $0) } ?? "–", unit: "ms")
                    }
                    if nightHR.count > 6 {
                        LumaCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    LumaLabel("Heart rate overnight")
                                    Spacer()
                                    if let low = nightHR.map({ $0.lo }).min() {
                                        Text("Lowest \(Int(low.rounded())) bpm").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist)
                                    }
                                }
                                LumaLineChart(values: nightHR.map { $0.bpm }, labels: nightHR.map { LumaText.time($0.t) }, color: Luma.coral,
                                              height: 150, replay: n.day)
                            }
                        }
                    }
                    if !n.naps.isEmpty {
                        LumaGroup {
                            ForEach(n.naps) { nap in
                                LumaRow(symbol: "moon.zzz.fill", symbolColor: Luma.dusk, title: "Nap",
                                        subtitle: "\(LumaText.time(nap.start)) – \(LumaText.time(nap.end))") {
                                    Text(LFormat.hm(minutes: nap.asleepMin)).font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                                }
                            }
                        }
                    }
                } else {
                    LumaCard {
                        LumaEmpty(symbol: "moon.zzz", title: "No sleep recorded", message: "Nothing was recorded for this night.")
                    }
                }

                LumaSection(title: "Tonight")
                TonightCard(summary: summary)

                LumaSection(title: "Schedule")
                ScheduleCard(summary: summary)

                LumaSection(title: "History")
                MetricHistoryCard(metric: .sleepHours, style: .bars, title: "Time asleep", goal: summary.tonightNeedMin / 60)
                MetricHistoryCard(metric: .deepMin, style: .bars, title: "Deep sleep", color: LStageKind.deep.color)
                MetricHistoryCard(metric: .remMin, style: .bars, title: "REM sleep", color: LStageKind.rem.color)
            }
        }
        .onAppear { if day.isEmpty { day = summary.last?.day ?? env.today } }
        .task(id: day) {
            guard let main = night?.main else { nightHR = []; return }
            nightHR = await env.source.heartRate(from: main.start, to: main.end, bucketSeconds: 300)
        }
    }
}

/// Time asleep against the night's need, with the score ring.
struct SleepHero: View {
    let night: SleepNight
    @State private var shown: Double = 0

    var body: some View {
        let total = night.asleepMin + night.napMin
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                LumaRing(progress: shown / 100, lineWidth: 12, colors: [Luma.sky, Luma.dusk])
                VStack(spacing: -2) {
                    Text(night.score.map { String(format: "%.0f", $0) } ?? "–").font(LumaFont.numeral(44, .heavy)).foregroundStyle(Luma.frost)
                    LumaLabel("Score")
                }
            }
            .frame(width: 128, height: 128)
            VStack(alignment: .leading, spacing: 6) {
                LumaLabel("Time asleep")
                Text(LFormat.hm(minutes: night.asleepMin)).font(LumaFont.numeral(46)).foregroundStyle(Luma.frost)
                Text("\(Int(night.needMetPct.rounded()))% of the \(LFormat.hm(minutes: night.needMin)) you needed")
                    .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                LumaBar(value: total, total: night.needMin, color: Luma.dusk, height: 6)
                if night.napMin > 0 {
                    Text("Includes \(LFormat.hm(minutes: night.napMin)) of naps").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear { withAnimation(.easeOut(duration: 1.0).delay(0.1)) { shown = night.score ?? 0 } }
        .onChange(of: night.day) { _, _ in
            shown = 0
            withAnimation(.easeOut(duration: 0.8)) { shown = night.score ?? 0 }
        }
    }
}

/// Minutes and share per stage, each against the typical range for healthy adults.
struct StageBreakdown: View {
    let night: SleepNight

    private var rows: [(kind: LStageKind, minutes: Double)] {
        let all: [(LStageKind, Double?)] = [(.deep, night.deepMin), (.rem, night.remMin), (.light, night.lightMin), (.awake, night.awakeMin)]
        var out: [(kind: LStageKind, minutes: Double)] = []
        for (kind, minutes) in all { if let m = minutes { out.append((kind, m)) } }
        return out
    }

    var body: some View {
        let rows = self.rows
        let asleep = max(1, night.asleepMin)
        if !rows.isEmpty {
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    LumaShareBar(shares: rows.map { LumaShareBar.Share(id: $0.kind.rawValue, value: $0.minutes, color: $0.kind.color) })
                    ForEach(rows, id: \.kind) { row in
                        let pct = row.minutes / asleep * 100
                        let typical = SleepModel.typicalShare(row.kind)
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(row.kind.color).frame(width: 6, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.kind.title).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                                Text("Typical \(Int(typical.lowerBound))–\(Int(typical.upperBound))%").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(LFormat.hm(minutes: row.minutes)).font(LumaFont.numeral(20, .semibold)).foregroundStyle(Luma.frost)
                                Text("\(Int(pct.rounded()))%").font(LumaFont.body(12, .medium))
                                    .foregroundStyle(typical.contains(pct) || (row.kind != .awake && pct > typical.upperBound) ? Luma.mint : Luma.amber)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Tonight's need and when to be in bed to meet it.
struct TonightCard: View {
    let summary: SleepSummary

    var body: some View {
        LumaCard(tint: Luma.dusk.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        LumaLabel("Sleep needed tonight")
                        Text(LFormat.hm(minutes: summary.tonightNeedMin)).font(LumaFont.numeral(42)).foregroundStyle(Luma.frost)
                    }
                    Spacer()
                    if let bed = summary.recommendedBedtime {
                        VStack(alignment: .trailing, spacing: 4) {
                            LumaLabel("Lights out by")
                            Text(LFormat.timeOfDay(minutes: bed)).font(LumaFont.numeral(42)).foregroundStyle(Luma.dusk)
                        }
                    }
                }
                HStack {
                    Text("Sleep debt").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                    Spacer()
                    Text(summary.debtMin < 10 ? "None" : LFormat.hm(minutes: summary.debtMin))
                        .font(LumaFont.numeral(18, .semibold)).foregroundStyle(summary.debtMin >= 90 ? Luma.amber : Luma.frost)
                }
                LumaBar(value: summary.debtMin, total: 240, color: summary.debtMin >= 90 ? Luma.amber : Luma.dusk, height: 6)
                LumaNote(summary.debtMin >= 90
                         ? "You have slept less than you needed this week. Tonight's need includes part of that shortfall and extra for today's strain."
                         : "Need is your base requirement plus extra for today's strain. Bedtime assumes your usual wake time and sleep efficiency.")
            }
        }
    }
}

/// Bed and wake times for the last two weeks as floating bars, with the consistency score.
struct ScheduleCard: View {
    let summary: SleepSummary

    var body: some View {
        let nights = Array(summary.nights.suffix(14)).filter { $0.bedtime != nil && $0.wake != nil }
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel("Consistency")
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(summary.consistency.map { String(format: "%.0f", $0) } ?? "–").font(LumaFont.numeral(40)).foregroundStyle(Luma.frost)
                            Text("%").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        LumaLabel("Usual night")
                        Text("\(summary.typicalBedtime.map { LFormat.timeOfDay(minutes: $0) } ?? "–") – \(summary.typicalWake.map { LFormat.timeOfDay(minutes: $0) } ?? "–")")
                            .font(LumaFont.numeral(22, .semibold)).foregroundStyle(Luma.frost)
                    }
                }
                if nights.count >= 3 {
                    LumaBarChart(bars: nights.enumerated().map { i, n in
                        LumaBarChart.Bar(id: i, value: n.wake, color: Luma.dusk, label: LumaText.weekdayLetter(n.day), low: n.bedtime)
                    }, height: 170, format: { LFormat.timeOfDay(minutes: $0) })
                }
                if let j = summary.socialJetlagMin, abs(j) >= 30 {
                    LumaNote("Your sleep midpoint runs \(LFormat.hm(minutes: abs(j))) \(j > 0 ? "later" : "earlier") at weekends than on weekdays.")
                } else {
                    LumaNote("Each bar runs from lights-out to waking. Level bars mean a steady body clock.")
                }
            }
        }
    }
}
