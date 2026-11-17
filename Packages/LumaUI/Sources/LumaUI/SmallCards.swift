import SwiftUI
import LumaCore
import LumaKit

// MARK: - Food matched to the work

/// The day's food read against the day's training: carbs for the work, protein across the day, and
/// what was eaten before and after the main session.
struct FuelMatchCard: View {
    let day: String
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let read = env.fuelMatch(on: day)
        if !read.checks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LumaSection(title: "Food against the work")
                LumaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            LumaLabel(read.dayClass.title)
                            Spacer()
                            LumaPill(text: read.headline, color: pillColor(read))
                        }
                        ForEach(read.checks) { check in
                            HStack(alignment: .top, spacing: 12) {
                                mark(check.met)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                    Text(check.detail).font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        if day == env.today {
                            LumaNote("Today is still open: a line is only marked short once the day is over.")
                        }
                    }
                }
            }
        }
    }

    private func pillColor(_ read: FuelDayRead) -> Color {
        guard read.usable, read.judged > 0 else { return Luma.mist }
        return read.metCount == read.judged ? Luma.mint : (read.metCount == 0 ? Luma.coral : Luma.amber)
    }

    @ViewBuilder
    private func mark(_ met: Bool?) -> some View {
        switch met {
        case .some(true):
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Luma.mint)
                .accessibilityLabel("Matched")
        case .some(false):
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Luma.amber)
                .accessibilityLabel("Short")
        case .none:
            Image(systemName: "circle.dotted").font(.system(size: 18, weight: .semibold)).foregroundStyle(Luma.smoke)
                .accessibilityLabel("Not judged")
        }
    }
}

// MARK: - Easing off

/// After two low-recovery mornings in a row: an offer to make today's hard session easier. An offer,
/// never a change Luma makes by itself.
struct EaseOfferCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if let offer = env.next.ease {
            LumaCard(tint: Luma.coral.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.right.circle.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Luma.coral)
                        LumaLabel("Ease off today?")
                    }
                    Text("\(offer.session.title): \(offer.eased.durationMin) min, easy").font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                    Text("\(offer.reason) Two low mornings in a row is when easing a hard session is most worth it. It stays your call: the studies that tried this found a small gain, not a large one.")
                        .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button("Keep it as planned") {
                            withAnimation(LumaMotion.quick) { env.declineEase(offer) }
                        }
                        .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                        Button("Ease it") {
                            LumaHaptics.success()
                            withAnimation(LumaMotion.quick) { env.acceptEase(offer) }
                        }
                        .buttonStyle(LumaPrimaryButtonStyle(color: Luma.coral, compact: true))
                    }
                }
            }
        }
    }
}

// MARK: - Reminders

/// Reminders worked out on the phone from the athlete's own numbers. All off until switched on.
struct RemindersScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var denied = false

    var body: some View {
        let on = env.extras.reminderKinds
        let planned = env.plannedReminders()
        LumaDetailScreen(title: "Reminders", tone: .neutral) {
            LumaNote("Each reminder is worked out here, on your iPhone, from your own numbers, and only sent when it applies: a supplement reminder does not come once it is ticked. Nothing is sent to a server.")
            LumaGroup {
                ForEach(ReminderKind.allCases) { kind in
                    Toggle(isOn: Binding(get: { on.contains(kind) }, set: { set(kind, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                            Text(kind.detail).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Luma.volt)
                    .padding(.vertical, 11).padding(.horizontal, 16)
                }
            }
            if denied {
                Text("Notifications are switched off for Luma. Turn them on in the iPhone's Settings, under Notifications, and these will come through.")
                    .font(LumaFont.body(13.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true)
            }
            if !on.isEmpty {
                LumaSection(title: "Coming up")
                if planned.isEmpty {
                    LumaNote("Nothing is due between now and the end of tomorrow.")
                } else {
                    LumaGroup {
                        ForEach(planned) { r in
                            LumaRow(symbol: "bell.fill", symbolColor: Luma.amber, title: r.title,
                                    subtitle: r.at.formatted(.dateTime.weekday(.abbreviated).hour().minute()) + " · " + r.body)
                        }
                    }
                }
            }
            LumaSection(title: "Log without opening Luma")
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    step("drop.fill", Luma.sky, "The Fuel widget has a button that logs 250 ml of water.")
                    step("waveform", Luma.aqua, "Say “Log water in Luma”, “Tick my supplements in Luma” or “Log my weight in Luma” to Siri.")
                    step("square.grid.2x2.fill", Luma.volt, "The same three are in the Shortcuts app, so they can go on the Action button, a Back Tap or a Home Screen icon.")
                    LumaNote("What is logged this way is filed the next time Luma runs, which with the strap connected is within minutes.")
                }
            }
        }
    }

    private func step(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.13)))
            Text(text).font(LumaFont.body(14)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func set(_ kind: ReminderKind, _ on: Bool) {
        env.setReminder(kind, on: on)
        guard on, let ask = env.requestNotifications else { return }
        Task {
            let allowed = await ask()
            denied = !allowed
        }
    }
}
