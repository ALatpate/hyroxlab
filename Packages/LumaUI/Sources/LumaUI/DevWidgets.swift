import SwiftUI
import LumaCore
import LumaKit

/// Development only: lays the widget and Lock Screen designs out at their real sizes so the
/// screenshot harness can photograph them. Reached through the `dev.*` launch routes, never from the app.
struct DevWidgetsScreen: View {
    let page: Int

    private let glance = LumaGlance.sample

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1B2A4A), Color(hex: 0x0A0E1A)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    switch page {
                    case 0: lockScreen
                    case 1: homeA
                    case 3: buddySheet
                    case 4: buddyBuilds
                    default: homeB
                    }
                }
                .padding(.vertical, 12)
                .offset(y: -LumaLaunch.scrollOffset)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Lock Screen

    private var live: LumaLiveState {
        LumaLiveState(bpm: 64, lastBpm: 64, lastAt: Date(), zone: 1, connected: true, recovery: 74, strainText: "9.4", sleepScore: 82)
    }

    @ViewBuilder
    private var lockScreen: some View {
        HStack(spacing: 14) {
            accessory(72, 72) { LumaTodayWidgetView(glance: glance, family: .circular) }
            accessory(160, 72) { LumaTodayWidgetView(glance: glance, family: .rectangular) }
            accessory(72, 72) { LumaFuelWidgetView(glance: glance, family: .circular) }
        }
        HStack(spacing: 14) {
            accessory(160, 72) { LumaFuelWidgetView(glance: glance, family: .rectangular) }
            accessory(160, 72) { LumaPlanWidgetView(glance: glance, family: .rectangular) }
        }
        accessory(340, 72) { LumaBriefWidgetView(glance: glance, family: .rectangular) }
        card { LumaLiveCard(state: live) }
        card {
            LumaLiveCard(state: LumaLiveState(bpm: nil, lastBpm: 71, lastAt: Date().addingTimeInterval(-190), zone: 1, connected: true,
                                             recovery: 74, strainText: "9.4", sleepScore: 82))
        }
        card {
            LumaLiveCard(state: LumaLiveState(bpm: 158, lastBpm: 158, lastAt: Date(), zone: 4, connected: true, recovery: 74, strainText: "12.1",
                                             sleepScore: 82, session: "Outdoor run", sessionStart: Date().addingTimeInterval(-1754), distanceKm: 5.42))
        }
        card { LumaLiveCard(state: LumaLiveState(connected: false)) }
        card { LumaSyncCard(status: "Syncing history", detail: "38 blocks so far", startedAt: Date().addingTimeInterval(-95), finished: false, failed: false) }
        island
    }

    private var island: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                LumaIslandHeart(state: live)
                Spacer()
                LumaIslandBpm(state: live)
            }
            .padding(.horizontal, 14).frame(width: 190, height: 37).background(Capsule().fill(Color.black))
            VStack(spacing: 8) {
                HStack {
                    LumaIslandLeading(state: live)
                    Spacer()
                    LumaIslandTrailing(state: live)
                }
                LumaIslandBottom(state: live)
            }
            .padding(16).frame(width: 360).background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
        }
    }

    private func accessory<V: View>(_ w: CGFloat, _ h: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .foregroundStyle(.white)
            .frame(width: w - 8, height: h - 8)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: w == h ? h / 2 : 14, style: .continuous).fill(Color.white.opacity(0.16)))
    }

    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: 366)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var demoTrace: [Double] {
        (0..<90).map { (i: Int) -> Double in
            let wave: Double = 14 * sin(Double(i) / 9)
            return 58 + wave + Double(i % 7)
        }
    }

    private var demoStress: [(hour: Int, level: Double?)] {
        (6..<20).map { (h: Int) -> (hour: Int, level: Double?) in
            let level: Double? = h < 18 ? 0.4 + 1.3 * abs(sin(Double(h) / 2.3)) : nil
            return (hour: h, level: level)
        }
    }

    // MARK: The companion

    private static let mid = BuddyShape(levels: [2.6, 2.4, 2.8, 2.2, 2.5, 3.2])
    private static let big = BuddyShape(levels: [4.6, 4.4, 4.5, 4.7, 4.2, 4.8])

    private func frame(_ kind: BuddyKind, _ title: String, _ line: String, beat: Int = 0) -> BuddyFrame {
        BuddyFrame(date: Date(), kind: kind, beat: beat, title: title, line: line, energy: 0.72)
    }

    private func lockBuddy(_ kind: BuddyKind, _ title: String, _ line: String = "", wide: Bool = false, beat: Int = 0,
                           shape: BuddyShape = DevWidgetsScreen.mid) -> some View {
        accessory(wide ? 160 : 72, 72) {
            LumaBuddyWidgetView(frame: frame(kind, title, line, beat: beat), name: "Glim", family: wide ? .rectangular : .circular, shape: shape)
        }
    }

    /// The companion as the Lock Screen and Home Screen widgets draw it.
    @ViewBuilder
    private var buddySheet: some View {
        HStack(spacing: 12) {
            lockBuddy(.charged, "Charged")
            lockBuddy(.steady, "Steady")
            lockBuddy(.drained, "Drained")
            lockBuddy(.sleeping, "Asleep")
        }
        HStack(spacing: 12) {
            lockBuddy(.training, "In session")
            lockBuddy(.celebrating, "New best")
            lockBuddy(.thirsty, "Thirsty")
            lockBuddy(.waiting, "No score yet")
        }
        HStack(spacing: 12) {
            lockBuddy(.charged, "Charged", "Recovery 72%. Good to push today.", wide: true)
            lockBuddy(.sleepy, "Winding down", "Lights out by 22:40 covers tonight's sleep.", wide: true)
        }
        HStack(spacing: 12) {
            lockBuddy(.thirsty, "Thirsty", "1.0 of 2.9 L so far.", wide: true)
            lockBuddy(.unwell, "Run down", "Several signals are off together.", wide: true)
        }
        // A tap: the two steps of its answer, then back.
        HStack(spacing: 12) {
            lockBuddy(.steady, "Steady", beat: 0)
            lockBuddy(.steady, "Steady", beat: 10)
            lockBuddy(.steady, "Steady", beat: 11)
            lockBuddy(.steady, "Steady", beat: 2)
        }
        HStack(spacing: 22) {
            widget(158, 158) {
                LumaBuddyWidgetView(frame: frame(.charged, "Charged", "Recovery 72%. Good to push today."), name: "Glim", family: .small,
                                    shape: DevWidgetsScreen.mid)
            }
            widget(158, 158, tint: Luma.coral) {
                LumaBuddyWidgetView(frame: frame(.drained, "Drained", "Recovery 28%. Keep it easy."), name: "Glim", family: .small,
                                    shape: DevWidgetsScreen.big, spark: Luma.coral)
            }
        }
        widget(338, 158) {
            LumaBuddyWidgetView(frame: frame(.celebrating, "New best", "Back squat: est. max 133 kg."), name: "Glim", family: .medium,
                                shape: DevWidgetsScreen.big)
        }
    }

    /// Every state at three builds: the plain one, a middling one and a strong one.
    @ViewBuilder
    private var buddyBuilds: some View {
        ForEach([BuddyShape.plain, DevWidgetsScreen.mid, DevWidgetsScreen.big].indices, id: \.self) { i in
            let shape = [BuddyShape.plain, DevWidgetsScreen.mid, DevWidgetsScreen.big][i]
            Text(["Plain build", "Middling levels", "Strong all round"][i]).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
            BuddyMoodGrid(shape: shape).padding(.horizontal, 16)
        }
    }

    // MARK: Home Screen

    private func widget<V: View>(_ w: CGFloat, _ h: CGFloat, tint: Color = Luma.volt, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .padding(16)
            .frame(width: w, height: h)
            .background(GlanceBackdrop(tint: tint))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var homeA: some View {
        HStack(spacing: 22) {
            widget(158, 158) { LumaTodayWidgetView(glance: glance, family: .small) }
            widget(158, 158, tint: Luma.mint) { LumaFuelWidgetView(glance: glance, family: .small) }
        }
        widget(338, 158) { LumaTodayWidgetView(glance: glance, family: .medium) }
        widget(338, 354) { LumaTodayWidgetView(glance: glance, family: .large) }
    }

    @ViewBuilder
    private var homeB: some View {
        widget(338, 158, tint: Luma.coral) {
            LumaHeartWidgetView(bpm: 62, at: Date().addingTimeInterval(-70), values: demoTrace, resting: 52)
        }
        widget(338, 158, tint: Luma.aqua) { LumaBriefWidgetView(glance: glance, family: .medium) }
        HStack(spacing: 22) {
            widget(158, 158) { LumaPlanWidgetView(glance: glance, family: .small) }
            widget(158, 158) { LumaTodayWidgetView(glance: nil, family: .small) }
        }
        widget(338, 158, tint: Luma.amber) {
            LumaStressWidgetView(hours: demoStress)
        }
        widget(338, 158, tint: Luma.mint) { LumaFuelWidgetView(glance: glance, family: .medium) }
    }
}
