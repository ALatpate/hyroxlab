import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import LumaKit

/// The widget extension entry point: Luma's Home Screen and Lock Screen widgets, the heart-rate
/// Live Activity and the strap-sync Live Activity. The designs live in LumaKit; this file only
/// connects them to WidgetKit and ActivityKit and to what the app publishes into the App Group.
///
/// Widget kinds are the ones earlier builds shipped, so widgets already placed on a Home Screen or
/// Lock Screen pick up the new design instead of disappearing.
@main
struct LumaWidgetBundle: WidgetBundle {
    init() { LumaGlanceStore.suiteName = WidgetSnapshot.suiteName }

    var body: some Widget {
        LumaTodayWidget()
        LumaLiveActivity()
        LumaFuelWidget()
        LumaPlanWidget()
        LumaBriefWidget()
        LumaHeartWidget()
        LumaStressWidget()
        LumaSyncActivity()
        LumaBuddyWidget()
    }
}

// MARK: - Plumbing

extension WidgetFamily {
    var luma: LumaWidgetFamily {
        switch self {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge, .systemExtraLarge: return .large
        case .accessoryCircular: return .circular
        case .accessoryRectangular: return .rectangular
        case .accessoryInline: return .inline
        @unknown default: return .small
        }
    }

    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

/// Gives a LumaKit widget view its family, its background and where a tap leads.
struct GlanceHost<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    var tint: Color = Luma.volt
    let route: String
    @ViewBuilder var content: (LumaWidgetFamily) -> Content

    var body: some View {
        ZStack {
            if family == .accessoryCircular { AccessoryWidgetBackground() }
            content(family.luma)
        }
        .containerBackground(for: .widget) {
            if !family.isAccessory { GlanceBackdrop(tint: tint) }
        }
        .widgetURL(URL(string: "noop://luma/" + route))
    }
}

struct GlanceEntry: TimelineEntry {
    let date: Date
    let glance: LumaGlance?
    /// Whether the stored figures belong to the training day this entry is shown on.
    let current: Bool
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: Date(), glance: .sample, current: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(context.isPreview ? GlanceEntry(date: Date(), glance: .sample, current: true) : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let now = Date()
        // A second entry at the 04:00 rollover, when last night's scores stop being today's: the widget
        // then withholds them by itself, without the app having to run.
        let rollover = LumaGlance.nextRollover(after: now).addingTimeInterval(1)
        let refresh = min(rollover.addingTimeInterval(60), now.addingTimeInterval(30 * 60))
        completion(Timeline(entries: [entry(at: now), entry(at: rollover)], policy: .after(refresh)))
    }

    private func entry(at date: Date) -> GlanceEntry {
        LumaGlanceStore.suiteName = WidgetSnapshot.suiteName
        let glance = LumaGlanceStore.load()
        return GlanceEntry(date: date, glance: glance, current: glance?.isCurrent(at: date) ?? false)
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [SnapshotEntry(date: now, snapshot: WidgetSnapshot.load())], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Widgets

struct LumaTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NOOPWidget", provider: GlanceProvider()) { entry in
            GlanceHost(tint: Luma.recovery(entry.current ? entry.glance?.recovery.map { Double($0) } : nil), route: "today") { family in
                LumaTodayWidgetView(glance: entry.glance, family: family, current: entry.current)
            }
        }
        .configurationDisplayName("Today")
        .description("Recovery, strain and sleep, with the day's call and your next session.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LumaFuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumaFuelWidget", provider: GlanceProvider()) { entry in
            GlanceHost(tint: Luma.mint, route: "fuel") { family in
                // The button logs a glass of water without opening Luma; the rest of the widget opens the Fuel tab.
                LumaFuelWidgetView(glance: entry.glance, family: family, current: entry.current,
                                   action: AnyView(Button(intent: LogWaterIntent(millilitres: 250)) { GlanceWaterChip(ml: 250) }.buttonStyle(.plain)))
            }
        }
        .configurationDisplayName("Fuel")
        .description("Energy, protein and water against today's targets.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LumaPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HXReadinessWidget", provider: GlanceProvider()) { entry in
            GlanceHost(tint: Luma.volt, route: "train") { family in
                LumaPlanWidgetView(glance: entry.glance, family: family, current: entry.current)
            }
        }
        .configurationDisplayName("Plan")
        .description("Today's sessions and what is first tomorrow.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct LumaBriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CoachBriefWidget", provider: GlanceProvider()) { entry in
            GlanceHost(tint: Luma.aqua, route: "coach") { family in
                LumaBriefWidgetView(glance: entry.glance, family: family, current: entry.current)
            }
        }
        .configurationDisplayName("Coach")
        .description("The coach's read of today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct LumaHeartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeartRateWidget", provider: SnapshotProvider()) { entry in
            GlanceHost(tint: Luma.coral, route: "heart") { _ in
                let series = HrTrace.prune(entry.snapshot?.hrSeries ?? [], nowSec: Int64(entry.date.timeIntervalSince1970))
                let newest = series.last
                LumaHeartWidgetView(bpm: newest?.bpm ?? entry.snapshot?.bpm,
                                    at: newest.map { Date(timeIntervalSince1970: TimeInterval($0.ts)) } ?? entry.snapshot?.updated,
                                    values: series.map { Double($0.bpm) }, resting: entry.snapshot?.restingHr)
            }
        }
        .configurationDisplayName("Heart rate")
        .description("The latest heart rate with the last three hours as a trace.")
        .supportedFamilies([.systemMedium])
    }
}

struct LumaStressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StressWidget", provider: SnapshotProvider()) { entry in
            GlanceHost(tint: Luma.amber, route: "stress") { _ in
                LumaStressWidgetView(hours: LumaStressWidget.hours(entry.snapshot, at: entry.date))
            }
        }
        .configurationDisplayName("Stress")
        .description("Today's stress, hour by hour.")
        .supportedFamilies([.systemMedium])
    }

    static func hours(_ snapshot: WidgetSnapshot?, at date: Date) -> [(hour: Int, level: Double?)] {
        let calendar = Calendar.current
        return (snapshot?.stressCurve(now: date) ?? []).map { point in
            (hour: calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(point.ts))), level: point.level)
        }
    }
}

// MARK: - The companion

struct BuddyEntry: TimelineEntry {
    let date: Date
    let frame: BuddyFrame
    let name: String
}

/// The companion's timeline: its states for the next few hours as the app worked them out, a shift of
/// weight every few minutes, and a hop and a wave straight after a tap. The widget decides nothing.
struct BuddyProvider: TimelineProvider {
    private static let sample = BuddyEntry(date: Date(), frame: BuddyFrame(date: Date(), kind: .charged, title: "Charged",
                                                                           line: "Recovery 74%. Good to push today.", energy: 0.74),
                                           name: "Glimm")

    func placeholder(in context: Context) -> BuddyEntry { BuddyProvider.sample }

    func getSnapshot(in context: Context, completion: @escaping (BuddyEntry) -> Void) {
        completion(context.isPreview ? BuddyProvider.sample : (entries(from: Date()).first ?? BuddyProvider.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BuddyEntry>) -> Void) {
        let now = Date()
        // The app writes a new schedule whenever a number behind it changes; this is the fallback.
        completion(Timeline(entries: entries(from: now), policy: .after(now.addingTimeInterval(150 * 60))))
    }

    private func entries(from now: Date) -> [BuddyEntry] {
        LumaGlanceStore.suiteName = WidgetSnapshot.suiteName
        let buddy = LumaGlanceStore.load()?.buddy
        let name = buddy?.name ?? "Glimm"
        return BuddyTimeline.frames(buddy, from: now, poke: LumaQuickLog.lastPoke).map {
            BuddyEntry(date: $0.date, frame: $0, name: name)
        }
    }
}

struct BuddyWidgetBody: View {
    @Environment(\.widgetFamily) private var family
    let entry: BuddyEntry

    var body: some View {
        let lock = family.isAccessory
        let spark = Luma.recovery(entry.frame.energy < 0 ? nil : entry.frame.energy * 100)
        ZStack {
            if family == .accessoryCircular { AccessoryWidgetBackground() }
            LumaBuddyWidgetView(frame: entry.frame, name: entry.name, family: family.luma) {
                // A tap on the figure is answered by the figure; a tap anywhere else opens Luma.
                Button(intent: PokeBuddyIntent()) {
                    GlimmFigure(frame: entry.frame, ink: lock ? .mono : .color)
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) {
            if !lock { GlanceBackdrop(tint: spark) }
        }
        .widgetURL(URL(string: "noop://luma/buddy"))
    }
}

struct LumaBuddyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LumaBuddyWidget", provider: BuddyProvider()) { entry in
            BuddyWidgetBody(entry: entry)
        }
        .configurationDisplayName("Companion")
        .description("Glimm, whose state follows your day and who dresses for it. Tap it for a wave.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

// MARK: - Live Activities

extension NOOPActivityAttributes.ContentState {
    /// What the card draws. Once iOS marks the activity stale no reading has arrived for a while, so
    /// the number is shown as the last reading with its age rather than as live.
    func luma(stale: Bool) -> LumaLiveState {
        LumaLiveState(bpm: stale ? nil : bpm, lastBpm: lastBpm ?? bpm, lastAt: lastAt, zone: zone, connected: bonded, recovery: recovery,
                      strainText: strainText ?? effort.map { String($0) }, sleepScore: sleep, session: session, sessionStart: sessionStart,
                      pausedElapsed: pausedElapsed, distanceKm: distanceM.map { $0 / 1000 }, glimm: glimm)
    }
}

struct LumaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NOOPActivityAttributes.self) { context in
            LumaLiveCard(state: context.state.luma(stale: context.isStale))
                .activityBackgroundTint(Luma.night)
                .activitySystemActionForegroundColor(Luma.frost)
                .widgetURL(URL(string: "noop://luma/today"))
        } dynamicIsland: { context in
            let state = context.state.luma(stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { LumaIslandLeading(state: state) }
                DynamicIslandExpandedRegion(.trailing) { LumaIslandTrailing(state: state) }
                DynamicIslandExpandedRegion(.bottom) { LumaIslandBottom(state: state) }
            } compactLeading: {
                LumaIslandHeart(state: state)
            } compactTrailing: {
                LumaIslandBpm(state: state)
            } minimal: {
                LumaIslandBpm(state: state)
            }
            .keylineTint(Luma.volt)
            .widgetURL(URL(string: "noop://luma/today"))
        }
    }
}

struct LumaSyncActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SyncActivityAttributes.self) { context in
            LumaSyncCard(status: context.state.status, detail: context.state.detail, startedAt: context.state.startedAt,
                         finished: context.state.phase == .done, failed: context.state.phase == .interrupted)
                .activityBackgroundTint(Luma.night)
                .activitySystemActionForegroundColor(Luma.frost)
                .widgetURL(URL(string: "noop://luma/strap"))
        } dynamicIsland: { context in
            let active = context.state.phase == .connecting || context.state.phase == .syncing
            let symbol = context.state.phase == .interrupted ? "exclamationmark.circle.fill" : (active ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
            let tint = context.state.phase == .interrupted ? Luma.coral : Luma.volt
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.state.status) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
                        .font(.subheadline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if active {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .font(LumaFont.numeral(17)).multilineTextAlignment(.trailing).frame(maxWidth: 64, alignment: .trailing)
                    }
                }
            } compactLeading: {
                Image(systemName: symbol).foregroundStyle(tint)
            } compactTrailing: {
                Text(context.state.chunks > 0 ? "\(context.state.chunks)" : "…").monospacedDigit()
            } minimal: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
            .widgetURL(URL(string: "noop://luma/strap"))
        }
    }
}
