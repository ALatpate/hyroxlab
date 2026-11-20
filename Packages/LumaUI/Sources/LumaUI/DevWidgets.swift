import SwiftUI
import LumaCore
import LumaKit

/// Development only: the picture of an effort as it is sent, at its real size.
private struct DevShareCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if let session = env.sessions.first(where: { $0.isComplete }) {
            RaceShareCard(session: session).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

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
                    case 4: glimmMoods
                    case 5: glimmWear
                    case 6: glimmMotion
                    case 7: DevShareCard()
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
        LumaLiveState(bpm: 64, lastBpm: 64, lastAt: Date(timeIntervalSince1970: 1_795_000_000), zone: 1, connected: true, recovery: 74, strainText: "9.4",
                      sleepScore: 82, glimm: "steady~" + GlimmLook.signature)
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
                                             recovery: 24, strainText: "12.2", sleepScore: 82, glimm: "drained~" + DevWidgetsScreen.cosy))
        }
        card {
            LumaLiveCard(state: LumaLiveState(bpm: 158, lastBpm: 158, lastAt: Date(), zone: 4, connected: true, recovery: 74, strainText: "12.1",
                                             sleepScore: 82, session: "Outdoor run", sessionStart: Date().addingTimeInterval(-1754), distanceKm: 5.42,
                                             glimm: "training~tank:36BFB0:plain|shorts:344968:plain|runners:FF766B:plain|headband:F5D77A:plain|watch:566274:plain"))
        }
        // The widest it gets: three figures of heart rate beside the companion and the day's scores.
        card {
            LumaLiveCard(state: LumaLiveState(bpm: 142, lastBpm: 142, lastAt: Date(timeIntervalSince1970: 1_795_000_080), zone: 3, connected: true, recovery: 100,
                                             strainText: "18.6", sleepScore: 100, glimm: "charged~" + DevWidgetsScreen.party))
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

    private func frame(_ kind: BuddyKind, _ title: String, _ line: String, beat: Int = 0, outfit: String = "") -> BuddyFrame {
        BuddyFrame(date: Date(), kind: kind, beat: beat, title: title, line: line, energy: 0.72, outfit: outfit)
    }

    private func lockBuddy(_ kind: BuddyKind, _ title: String, _ line: String = "", wide: Bool = false, beat: Int = 0) -> some View {
        accessory(wide ? 160 : 72, 72) {
            LumaBuddyWidgetView(frame: frame(kind, title, line, beat: beat), name: "Glimm", family: wide ? .rectangular : .circular)
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
        // A tap: the two steps of its answer, then one of the stills it moves between.
        HStack(spacing: 12) {
            lockBuddy(.steady, "Steady", beat: 0)
            lockBuddy(.steady, "Steady", beat: 10)
            lockBuddy(.steady, "Steady", beat: 11)
            lockBuddy(.steady, "Steady", beat: 2)
        }
        HStack(spacing: 22) {
            widget(158, 158) {
                LumaBuddyWidgetView(frame: frame(.charged, "Charged", "Recovery 72%. Good to push today."), name: "Glimm", family: .small)
            }
            widget(158, 158, tint: Luma.coral) {
                LumaBuddyWidgetView(frame: frame(.drained, "Drained", "Recovery 28%. Keep it easy.", outfit: DevWidgetsScreen.cosy), name: "Glimm", family: .small)
            }
        }
        widget(338, 158) {
            LumaBuddyWidgetView(frame: frame(.celebrating, "New best", "Back squat: est. max 133 kg.", outfit: DevWidgetsScreen.party), name: "Glimm", family: .medium)
        }
    }

    private static let cosy = "hoodie:B5A0EF:stars|sleep:344968:plain|slipper:F4E6C8:plain|-|-"
    private static let party = "varsity:D75C76:plain|jeans:6375E7:plain|high:F5D77A:plain|party:36BFB0:plain|medal:FF766B:plain"

    private func tile<V: View>(_ title: String, width: CGFloat = 112, @ViewBuilder _ figure: () -> V) -> some View {
        VStack(spacing: 2) {
            figure().frame(width: width - 12, height: (width - 12) * 1.2)
            Text(title).font(LumaFont.body(10.5, .medium)).foregroundStyle(Luma.mist).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: width)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func rows<V: View>(_ count: Int, per: Int, @ViewBuilder _ cell: @escaping (Int) -> V) -> some View {
        VStack(spacing: 8) {
            ForEach(0..<((count + per - 1) / per), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<per, id: \.self) { column in
                        let i = row * per + column
                        if i < count { cell(i) } else { Color.clear.frame(width: 1, height: 1) }
                    }
                }
            }
        }
    }

    /// Every mood, drawn both ways: on a canvas as the app draws it, and as the stack of shapes a
    /// widget is given. The two must look the same.
    @ViewBuilder
    private var glimmMoods: some View {
        Text("Every mood, as the app draws it").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
        rows(GlimmLook.moods.count, per: 3) { i in
            tile(GlimmLook.moods[i]) { GlimmFigure(mood: GlimmLook.moods[i], flat: true) }
        }
        Text("The same, as a widget is given it").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
        rows(GlimmLook.moods.count, per: 3) { i in
            tile(GlimmLook.moods[i]) { GlimmFigure(mood: GlimmLook.moods[i]) }
        }
        Text("In light and dark only, for the Lock Screen").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
        rows(6, per: 3) { i in
            tile(GlimmLook.moods[i * 2]) { GlimmFigure(mood: GlimmLook.moods[i * 2], ink: .mono) }
        }
    }

    /// Every cut in the wardrobe, each in a colour of its own.
    @ViewBuilder
    private var glimmWear: some View {
        let colours = GlimmWardrobe.palettes
        ForEach(GlimmSlot.allCases, id: \.self) { slot in
            let cuts = GlimmWardrobe.styles(in: slot)
            Text(slot.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
            rows(cuts.count, per: 4) { i in
                let pattern = slot == .top ? GlimmWardrobe.patterns[i % GlimmWardrobe.patterns.count] : "plain"
                let item = GlimmItem(style: cuts[i].id, palette: colours[(i * 5 + 3) % colours.count].id, pattern: pattern)
                tile(cuts[i].name, width: 84) { GlimmFigure(mood: "steady", outfit: GlimmOutfit.signature.wearing(item).code, flat: true) }
            }
        }
    }

    private func strip(_ title: String, _ make: @escaping (Int) -> GlimmFigure) -> some View {
        VStack(spacing: 4) {
            Text(title).font(LumaFont.heading(14)).foregroundStyle(Luma.frost)
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { i in make(i).frame(width: 46, height: 55) }
            }
        }
    }

    /// Frames of its motion at fixed moments, so a photograph can show what a film would.
    @ViewBuilder
    private var glimmMotion: some View {
        strip("Steady, over six seconds") { GlimmFigure(mood: "steady", time: 40 + Double($0) * 0.8) }
        strip("In session: the run") { GlimmFigure(mood: "focused", time: 40 + Double($0) * 0.1) }
        strip("New best") { GlimmFigure(mood: "celebrating", time: 40 + Double($0) * 0.12) }
        strip("Winding down, over six seconds") { GlimmFigure(mood: "sleepy", time: 60 + Double($0) * 0.8) }
        strip("A wave") { GlimmFigure(mood: "steady", time: 0, play: GlimmAct(name: "wave", phase: Double($0) / 7)) }
        strip("A bow") { GlimmFigure(mood: "proud", time: 0, play: GlimmAct(name: "bow", phase: Double($0) / 7)) }
        strip("A yawn") { GlimmFigure(mood: "sleepy", time: 0, play: GlimmAct(name: "yawn", phase: Double($0) / 7)) }
        strip("A twirl into new clothes") { i in
            GlimmFigure(mood: "steady", outfit: i < 4 ? GlimmLook.signature : DevWidgetsScreen.party, time: 0, play: GlimmAct(name: "twirl", phase: Double(i) / 7))
        }
        strip("The leaf touched") { GlimmFigure(mood: "steady", time: 0, tap: GlimmAct(name: "leaf", phase: Double($0) / 7)) }
        strip("A tickle") { GlimmFigure(mood: "steady", time: 0, tap: GlimmAct(name: "belly", phase: Double($0) / 7)) }
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
            widget(158, 158, tint: Luma.mint) { LumaFuelWidgetView(glance: glance, family: .small, action: AnyView(GlanceWaterChip())) }
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
        widget(338, 158, tint: Luma.mint) { LumaFuelWidgetView(glance: glance, family: .medium, action: AnyView(GlanceWaterChip())) }
    }
}
