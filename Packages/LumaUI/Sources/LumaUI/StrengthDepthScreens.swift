import SwiftUI
import LumaCore
import LumaKit

// MARK: - One lift over time

/// A lift's history: its estimated max day by day, its heaviest load for one, three, five and eight
/// reps, and every session it was logged in.
struct LiftHistoryScreen: View {
    let name: String
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let history = StrengthDepth.history(name, sessions: env.lifts, progress: env.progress, bodyKg: env.profile.weightKg, today: env.today)
        // The history comes newest first; a chart reads left to right from the oldest.
        let points = history.days.reversed().filter { $0.e1RM != nil }
        LumaDetailScreen(title: "Lift", tone: .strain) {
            Text(history.name).font(LumaFont.title(26)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
            if let p = history.progress {
                LumaCard(tint: Luma.ember.opacity(0.4)) {
                    VStack(alignment: .leading, spacing: 8) {
                        LumaLabel(p.current == nil ? "Best estimated max" : "Estimated max now")
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            LumaFigure(value: p.current ?? p.allTime, unit: "kg", size: 56)
                            if let change = p.change, p.trend != .steady {
                                DeltaBadge(delta: change * 100, decimals: 0, unit: "%", higherIsBetter: true, suffix: "in six weeks")
                            }
                        }
                        Text(line(p, bodyweight: history.bodyweight)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let stall = history.stall {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.amber)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stall).font(LumaFont.body(14)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        Button("Ask the coach how to move it") {
                            router.askCoach("My \(history.name) has stalled. Look at my recent sessions for it, my sleep and my food, and suggest how to get it moving over the next four weeks.")
                        }
                        .font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.amber).buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LumaPanel(tint: Luma.amber.opacity(0.4), radius: 22))
            }
            if points.count >= 2 {
                LumaSection(title: "Estimated max over time")
                LumaCard {
                    LumaLineChart(values: points.map { $0.e1RM }, labels: points.map { LumaText.shortDay($0.day) }, color: Luma.ember, height: 170)
                }
            }
            if !history.bests.isEmpty {
                LumaSection(title: "Heaviest for reps")
                StatGrid {
                    ForEach(history.bests) { b in
                        StatCell(label: b.reps == 1 ? "1 rep" : "\(b.reps) reps", value: LumaText.kg(b.kg), unit: history.bodyweight ? "kg added" : "kg",
                                 note: LumaText.shortDay(b.day))
                    }
                }
                LumaNote("The heaviest load you have logged for at least that many reps in one set. These are loads you did, not estimates.")
            }
            if !history.days.isEmpty {
                LumaSection(title: "Sessions")
                LumaGroup {
                    ForEach(Array(history.days.prefix(14))) { d in
                        Button { router.push(.lift(d.sessionID)) } label: {
                            LumaRow(symbol: nil, title: LumaText.dayTitle(d.day, today: env.today),
                                    subtitle: "\(d.sets) set\(d.sets == 1 ? "" : "s") · top \(d.top)", chevron: true) {
                                if let e = d.e1RM {
                                    Text(String(format: "%.0f", e)).font(LumaFont.numeral(19, .semibold)).foregroundStyle(Luma.frost)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if history.days.isEmpty {
                LumaCard { LumaEmpty(symbol: "dumbbell", title: "Nothing logged for this lift", message: "Log it with its load and it will show here.") }
            }
        }
    }

    private func line(_ p: LiftProgress, bodyweight: Bool) -> String {
        var parts: [String] = []
        if let level = p.level { parts.append(StrengthLevel(level).title) }
        if let r = p.ratio { parts.append(String(format: "%.1f × bodyweight", r)) }
        if bodyweight { parts.append("counts your bodyweight") }
        parts.append(String(format: "best ever %.0f kg on %@", p.allTime, LumaText.shortDay(p.allTimeDay)))
        return LumaText.line(parts)
    }
}

// MARK: - On the Progress view

/// Lifts that have been trained regularly and have not moved in twelve weeks.
struct StalledCard: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let stalled = env.next.stalled
        if !stalled.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LumaSection(title: "Stalled lifts")
                LumaGroup {
                    ForEach(stalled.prefix(4)) { s in
                        Button { router.push(.liftHistory(s.name)) } label: {
                            LumaRow(symbol: "pause.fill", symbolColor: Luma.amber, title: s.name, subtitle: s.text, chevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Sets for each muscle week by week, so a week that fell away or doubled shows.
struct WeeklySetsCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let rows = env.next.weeklySets.sorted { $0.mean > $1.mean }.prefix(10)
        if !rows.isEmpty {
            let top = max(1, rows.flatMap { $0.sets }.max() ?? 1)
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.ember)
                        LumaLabel("Sets by muscle, last 8 weeks")
                        Spacer()
                        Text("a week").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                    }
                    ForEach(Array(rows)) { row in
                        HStack(spacing: 10) {
                            Text(row.muscle.title).font(LumaFont.body(13.5)).foregroundStyle(Luma.frost).frame(width: 92, alignment: .leading)
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(Array(row.sets.enumerated()), id: \.offset) { i, v in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(i == row.sets.count - 1 ? Luma.ember : Luma.ember.opacity(0.45))
                                        .frame(height: max(2, 22 * CGFloat(v / top)))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 22, alignment: .bottom)
                            Text(ProgressText.count(row.mean)).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.muscle.title), \(ProgressText.count(row.mean)) sets a week on average")
                    }
                    LumaNote("One bar a week, the newest on the right and brighter. The figure is the weekly average. Counted the same way as the week's sets above.")
                }
            }
        }
    }
}
