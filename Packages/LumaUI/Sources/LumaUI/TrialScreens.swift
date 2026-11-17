import SwiftUI
import LumaCore
import LumaKit

// MARK: - Supplement trials

extension TrialRead.Verdict {
    var title: String {
        switch self {
        case .tooEarly: return "Too early"
        case .unclear: return "Not clear"
        case .higher: return "Higher on it"
        case .lower: return "Lower on it"
        }
    }
}

/// The list of trials, and the way to start one.
struct TrialsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let open = env.openTrial
        let stack = env.supplements.filter { $0.active }
        LumaDetailScreen(title: "Supplement trials", tone: .fuel) {
            LumaNote("Taking something every day leaves nothing to compare it with. A trial has you take it for a block of days, then leave it for a block, in an order Luma draws at random, and compares the nights. It is the fair way to find out whether it does anything for you.")
            if env.trials.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "testtube.2", title: "No trial yet", message: "Pick one supplement below. One trial runs at a time, so each gets a clean answer.")
                }
            }
            ForEach(env.trials.sorted { $0.startDay > $1.startDay }) { trial in
                Button { router.push(.trial(trial.id)) } label: { TrialSummary(trial: trial, read: env.next.trialReads[trial.id]) }
                    .buttonStyle(.plain)
            }
            LumaSection(title: "Start a trial")
            if open != nil {
                LumaNote("A trial is under way. Finish or stop it before starting another.")
            } else if stack.isEmpty {
                LumaNote("Add what you take to your supplement list first.")
            } else {
                LumaGroup {
                    ForEach(stack) { s in
                        Button { router.sheet = .trialSetup(s.dose.name) } label: {
                            LumaRow(symbol: "pills.fill", symbolColor: Luma.mint, title: s.dose.name, subtitle: "\(s.dose.text) · \(s.timing.title)",
                                    chevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct TrialSummary: View {
    let trial: SupplementTrial
    let read: TrialRead?
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let running = trial.isRunning(on: env.today)
        let waiting = trial.startDay > env.today && trial.stoppedDay == nil
        LumaCard(tint: running ? Luma.mint.opacity(0.4) : nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trial.supplement).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Spacer()
                    LumaPill(text: running ? "Running" : (waiting ? "Starts \(LumaText.shortDay(trial.startDay))" : (read?.verdict.title ?? "Ended")),
                             color: running ? Luma.mint : Luma.mist)
                }
                Text("Against \(trial.outcome.phrase) · \(trial.rounds) rounds of \(trial.blockDays) days on and \(trial.blockDays) off")
                    .font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                if let text = trial.instruction(on: env.today) {
                    Text(text).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                } else if let read, !waiting {
                    Text(read.sentence).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One trial: where it stands, what it shows so far, and the plan block by block.
struct TrialScreen: View {
    let id: UUID
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        LumaDetailScreen(title: "Trial", tone: .fuel) {
            if let trial = env.trials.first(where: { $0.id == id }) {
                let read = env.next.trialReads[trial.id]
                let running = trial.isRunning(on: env.today)
                Text(trial.supplement).font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                if let text = trial.instruction(on: env.today) {
                    LumaCard(tint: Luma.mint.opacity(0.5)) {
                        VStack(alignment: .leading, spacing: 6) {
                            LumaLabel("Today")
                            Text(text).font(LumaFont.heading(17)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                            LumaNote("Tick it on the Fuel tab on the days you take it. A day that does not follow the plan is left out of the comparison.")
                        }
                    }
                } else if trial.startDay > env.today {
                    LumaCard { LumaNote("Starts \(LumaText.dayTitle(trial.startDay, today: env.today).lowercased()). Luma tells you each day whether it is an on day or an off day.") }
                }
                if let read { TrialResult(trial: trial, read: read) }
                LumaSection(title: "The plan")
                TrialPlan(trial: trial)
                LumaNote("The first \(trial.washoutDays) days of each block are not counted, so the block before has time to wear off. The order of on and off inside each pair was drawn at random when the trial was set up.")
                if running || trial.startDay > env.today {
                    Button("Stop this trial") { env.stopTrial(trial.id) }.buttonStyle(LumaSecondaryButtonStyle())
                }
                Button(confirming ? "Tap again to delete it and its result" : "Delete this trial") {
                    if confirming {
                        env.deleteTrial(trial.id)
                        dismiss()
                    } else {
                        withAnimation(LumaMotion.quick) { confirming = true }
                    }
                }
                .font(LumaFont.body(14, .medium)).foregroundStyle(confirming ? Luma.coral : Luma.mist).buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            } else {
                LumaCard { LumaEmpty(symbol: "testtube.2", title: "This trial is gone", message: "It was deleted.") }
            }
        }
    }
}

private struct TrialResult: View {
    let trial: SupplementTrial
    let read: TrialRead

    var body: some View {
        let helps = read.helps(trial.outcome)
        let color: Color = helps == nil ? Luma.mist : (helps == true ? Luma.mint : Luma.coral)
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LumaLabel(read.finished ? "Result" : "So far")
                    Spacer()
                    LumaPill(text: read.verdict.title, color: read.verdict == .tooEarly || read.verdict == .unclear ? Luma.amber : color)
                }
                if let on = read.meanOn, let off = read.meanOff {
                    CompareBars(aLabel: "On it", a: on, bLabel: "Off it", b: off, metric: trial.outcome, color: color)
                }
                if let delta = read.delta, let low = read.low, let high = read.high {
                    let span = max(abs(low), abs(high), 1e-6)
                    VStack(alignment: .leading, spacing: 6) {
                        RangeMeter(effect: delta, low: low, high: high, span: span, color: color)
                        HStack {
                            Text(trial.outcome.show(low, signed: true)).font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                            Spacer()
                            Text("no difference").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                            Spacer()
                            Text(trial.outcome.show(high, signed: true)).font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                        }
                    }
                }
                Text(read.sentence).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                Text("\(read.nOn) nights on and \(read.nOff) off counted · \(read.followed) days followed the plan, \(read.broken) did not · \(read.roundsDone) of \(trial.rounds) rounds done")
                    .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The blocks in order, each lit for on or left dark for off, with today marked.
private struct TrialPlan: View {
    let trial: SupplementTrial
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let current = trial.position(on: env.today)?.block
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(Array(trial.order.enumerated()), id: \.offset) { i, on in
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(on ? Luma.mint.opacity(i == current ? 1 : 0.55) : Color.white.opacity(i == current ? 0.22 : 0.08))
                                .frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(i == current ? Luma.frost : Color.clear, lineWidth: 1.5))
                            Text(on ? "On" : "Off").font(LumaFont.body(11, .semibold)).foregroundStyle(i == current ? Luma.frost : Luma.smoke)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("\(LumaText.shortDay(trial.startDay)) to \(LumaText.shortDay(trial.lastDay())) · \(trial.totalDays) days")
                    .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trial.order.count) blocks of \(trial.blockDays) days: " + trial.order.map { $0 ? "on" : "off" }.joined(separator: ", "))
    }
}

/// Setting a trial up: what to watch, how long the blocks are, how many rounds.
struct TrialSetupSheet: View {
    let supplement: String
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: LMetric = .deepMin
    @State private var blockDays = 7
    @State private var rounds = 3

    var body: some View {
        LumaSheet(title: "Trial of \(supplement)", tone: .fuel) {
            LumaLabel("What it should change")
            FlowLayout(spacing: 8) {
                ForEach(SupplementTrial.outcomes) { m in
                    LumaChip(title: m.title, isOn: outcome == m, tint: Luma.mint) { outcome = m }
                }
            }
            LumaLabel("Days in each block")
            LumaSegmented(selection: $blockDays, options: [(value: 5, title: "5"), (value: 7, title: "7"), (value: 10, title: "10"), (value: 14, title: "14")],
                          tint: Luma.mint)
            LumaLabel("Rounds, each one block on and one off")
            LumaSegmented(selection: $rounds, options: [(value: 2, title: "2"), (value: 3, title: "3"), (value: 4, title: "4")], tint: Luma.mint)
            LumaCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(blockDays * rounds * 2) days, starting tomorrow").font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    LumaNote("Each day Luma tells you whether to take it or skip it. The first 2 days of every block are left out while the last one wears off, so \((blockDays - 2) * rounds) nights are counted on each side. Something slow to build up or wash out, like creatine, needs the longer blocks.")
                }
            }
            Button("Start the trial") {
                env.startTrial(supplement: supplement, outcome: outcome, blockDays: blockDays, rounds: rounds)
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
        }
    }
}
