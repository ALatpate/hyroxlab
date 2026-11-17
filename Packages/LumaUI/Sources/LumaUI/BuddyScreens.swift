import SwiftUI
import LumaCore
import LumaKit

extension BuddyMood {
    var kind: BuddyKind { BuddyKind(rawValue: rawValue) ?? .steady }

    /// The rule behind a state, in a sentence.
    var why: String {
        switch self {
        case .waiting: return "There is no recovery score for today yet, so there is nothing to go by."
        case .training: return "A session is being recorded."
        case .sleeping: return "It is inside your usual night, taken from your last two weeks of bed and wake times."
        case .celebrating: return "A lift's estimated max passed its old best in the last three hours."
        case .worked: return "A session ended in the last 75 minutes."
        case .unwell: return "Your overnight signals have moved away from your normal together. The same read raises the warning on Today."
        case .sleepy: return "It is within 45 minutes of the lights-out that covers tonight's sleep need."
        case .thirsty: return "Water is more than a quarter of the day's target behind where the hour says it should be."
        case .hungry: return "It is past 13:00 and no food has been logged today."
        case .drained: return "Today's recovery is under 34%."
        case .steady: return "Today's recovery is between 34% and 66%."
        case .charged: return "Today's recovery is 67% or more."
        }
    }
}

extension BuddyBuild {
    var shape: BuddyShape { BuddyShape(levels: levels) }
}

// MARK: - The moving figure

/// The companion in the app: breathing, blinking and moving as its state has it, and answering a tap
/// with a hop and a wave. With Reduce Motion on it stands still in the same pose.
struct LiveBuddy: View {
    let look: BuddyLook
    let shape: BuddyShape
    var spark: Color = Luma.volt
    @State private var pokedAt: Date?
    @State private var visible = false

    var body: some View {
        Group {
            if LumaMotion.reduced {
                BuddyFigure(kind: look.mood.kind, shape: shape, style: .color(spark: spark), energy: look.energy ?? 0.5)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                    BuddyFigure(kind: look.mood.kind, shape: shape, style: .color(spark: spark), time: t, energy: look.energy ?? 0.5,
                                poke: poke(at: context.date))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            pokedAt = Date()
            LumaHaptics.tap()
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(look.title). \(look.line)")
        .accessibilityAddTraits(.isImage)
    }

    /// How far through its answer to a tap it is, 0…1; nil once that is over.
    private func poke(at date: Date) -> Double? {
        guard let pokedAt else { return nil }
        let through = date.timeIntervalSince(pokedAt) / 1.15
        return through >= 0 && through <= 1 ? through : nil
    }
}

// MARK: - On Today

/// The companion on Today: the figure with its name and state. The recovery figure and the day's call
/// are already on this screen, so a state that only repeats them is given by its name alone.
struct BuddyStrip: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        if env.extras.buddyOnToday {
            // Looked at again each minute: its state can change with the clock alone.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                strip(env.buddyLook(now: context.date))
            }
        }
    }

    private func strip(_ look: BuddyLook) -> some View {
        let repeats: [BuddyMood] = [.charged, .steady, .drained, .waiting]
        return Button { router.push(.buddy, from: "buddy") } label: {
                HStack(spacing: 14) {
                    LiveBuddy(look: look, shape: env.next.build.shape, spark: Luma.recovery(look.energy.map { $0 * 100 }))
                        .frame(width: 70, height: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel(env.extras.name)
                        Text(look.title).font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                        Text(repeats.contains(look.mood) ? "Tap it. Open to see what it goes by." : look.line)
                            .font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
        .lumaZoomSource("buddy")
    }
}

// MARK: - Its own screen

struct BuddyScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var name = ""

    private var build: BuddyBuild { env.next.build }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            screen(env.buddyLook(now: context.date), now: context.date)
        }
        .onAppear { name = env.extras.buddyName }
        .onDisappear { rename() }
    }

    private func screen(_ look: BuddyLook, now: Date) -> some View {
        let spark = Luma.recovery(look.energy.map { $0 * 100 })
        return LumaDetailScreen(title: env.extras.name, tone: .recovery) {
            VStack(spacing: 6) {
                LiveBuddy(look: look, shape: build.shape, spark: spark)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                Text(look.title).font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                Text(look.line).font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            LumaCard {
                VStack(alignment: .leading, spacing: 8) {
                    LumaLabel("Why it looks like this")
                    Text(look.mood.why).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    LumaNote("It only ever shows what Luma already knows. What is happening now comes first, then how your body is, then what the logs are missing.")
                }
            }

            LumaSection(title: "Its build is yours")
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(build.parts) { part in BuddyPartRow(part: part) }
                    LumaNote(build.measured == 0
                             ? "No graded lift is in your log yet, so it has the plain build. Log lifts and it fills out where you do."
                             : "Each part follows the strength level of the lifts that train it, the same levels the body figure on Train shows. A part no lift measures stays plain. It is never drawn as weak.")
                }
            }

            BuddyDayCard(now: now)

            LumaSection(title: "On your Lock Screen")
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        lockPreview(.circular).frame(width: 76, height: 76)
                        lockPreview(.rectangular).frame(height: 76).frame(maxWidth: .infinity)
                    }
                    LumaNote("Touch and hold the Lock Screen, tap Customise, then the widget row, and pick Luma, then Companion. It changes through the day as your numbers do and shifts a little every few minutes. With the phone unlocked, tap it for a wave.")
                }
            }

            LumaSection(title: "Settings")
            LumaGroup {
                HStack(spacing: 12) {
                    Text("Name").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                    Spacer()
                    TextField("Glim", text: $name)
                        .font(LumaFont.body(15)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                        .frame(maxWidth: 170)
                        .onSubmit { rename() }
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                Toggle(isOn: Binding(get: { env.extras.buddyOnToday }, set: { on in
                    var e = env.extras
                    e.buddyOnToday = on
                    env.extras = e
                })) {
                    Text("Show on Today").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                }
                .tint(Luma.volt)
                .padding(.vertical, 8).padding(.horizontal, 16)
            }

            LumaSection(title: "Every state")
            BuddyMoodGrid(shape: build.shape)
        }
    }

    private func rename() {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        guard trimmed != env.extras.buddyName else { return }
        var e = env.extras
        e.buddyName = trimmed
        env.extras = e
    }

    private func lockPreview(_ family: LumaWidgetFamily) -> some View {
        let frame = BuddyTimeline.frame(env.buddyGlance(now: Date()), at: Date(), beat: 0)
        return LumaBuddyWidgetView(frame: frame, name: env.extras.name, family: family, shape: build.shape)
            .foregroundStyle(.white)
            .padding(family == .circular ? 0 : 10)
            .background {
                if family == .circular { Circle().fill(Color.white.opacity(0.12)) }
                else { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.08)) }
            }
    }
}

/// One part of the build: its level on the 0…5 scale and the lifts it is read from.
private struct BuddyPartRow: View {
    let part: BuddyPart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(part.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                Spacer()
                if let level = part.level {
                    Text(String(format: "%.1f", level)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                    Text("of 5").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                } else {
                    Text("Not measured").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                }
            }
            LumaBar(value: part.level ?? 0, total: 5, color: Luma.volt, height: 6)
            Text(part.from.isEmpty ? "No graded lift trains it yet." : "From " + part.from.prefix(3).joined(separator: ", ") + ".")
                .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
        }
    }
}

/// The states still to come today, each from the time it begins.
private struct BuddyDayCard: View {
    @EnvironmentObject private var env: LumaEnv
    let now: Date

    var body: some View {
        let moments = Array(Buddy.schedule(env.buddyFacts(now: now), from: now).dropFirst().prefix(6))
        if !moments.isEmpty {
            LumaSection(title: "The day ahead")
            LumaGroup {
                ForEach(Array(moments.enumerated()), id: \.offset) { _, m in
                    HStack(spacing: 12) {
                        Text(m.at.formatted(date: .omitted, time: .shortened)).font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                            .frame(width: 74, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.look.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                            Text(m.look.line).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 16)
                }
            }
            LumaNote("Worked out from today's numbers as they stand. It changes when they do: a session, a weigh-in, a glass of water.")
        }
    }
}

/// Every state the companion has, side by side, drawn with the athlete's build.
struct BuddyMoodGrid: View {
    let shape: BuddyShape
    var style: BuddyStyle = .color(spark: Luma.volt)

    private static let names: [(BuddyKind, String)] = [
        (.charged, "Charged"), (.steady, "Steady"), (.drained, "Drained"), (.sleeping, "Asleep"), (.sleepy, "Winding down"),
        (.training, "In session"), (.worked, "Session done"), (.celebrating, "New best"), (.unwell, "Run down"), (.thirsty, "Thirsty"),
        (.hungry, "Hungry"), (.waiting, "No score yet"),
    ]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(BuddyMoodGrid.names, id: \.1) { kind, title in
                VStack(spacing: 4) {
                    BuddyFigure(kind: kind, shape: shape, style: style).frame(height: 96)
                    Text(title).font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(LumaPanel(radius: 18))
            }
        }
    }
}
