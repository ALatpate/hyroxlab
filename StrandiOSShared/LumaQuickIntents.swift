import Foundation
import AppIntents
import WidgetKit
import LumaKit

/// Luma's own App Intents: logging without opening the app (a widget button, Siri, a shortcut) and
/// the tap on the companion. Compiled into the app and into the widget extension, as iOS requires of
/// an intent a widget button runs.
///
/// None of these touches the app's records: an intent may run in the widget extension, which cannot
/// reach them. Each queues what was asked in the shared container (`LumaQuickLog`) and the app files
/// it the next time it runs.
enum LumaQuickIntents {
    /// Posted in the process the intent ran in. When that is the app, it files the queue at once.
    static let changed = Notification.Name("luma.quicklog.changed")

    static func queued() {
        NotificationCenter.default.post(name: changed, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func prepare() { LumaGlanceStore.suiteName = WidgetSnapshot.suiteName }
}

/// A tap on the companion in a widget: it hops and waves when the widget is next drawn.
struct PokeBuddyIntent: AppIntent {
    static var title: LocalizedStringResource = "Wave at the Companion"
    static var isDiscoverable = false
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        LumaQuickIntents.prepare()
        LumaQuickLog.poke()
        return .result()
    }
}

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds water to today's log in Luma.")
    static var openAppWhenRun = false

    @Parameter(title: "Millilitres", default: 250, inclusiveRange: (50, 2000))
    var millilitres: Int

    init() {}

    init(millilitres: Int) {
        self.millilitres = millilitres
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LumaQuickIntents.prepare()
        LumaQuickLog.add(LumaQuickLog.Item(kind: .water, amount: Double(millilitres)))
        LumaQuickIntents.queued()
        return .result(dialog: "Logged \(millilitres) ml of water.")
    }
}

struct TickSupplementsIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick My Supplements"
    static var description = IntentDescription("Ticks today's supplements in Luma, leaving out any that a trial has on an off day.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LumaQuickIntents.prepare()
        LumaQuickLog.add(LumaQuickLog.Item(kind: .supplements))
        LumaQuickIntents.queued()
        return .result(dialog: "Today's supplements will be ticked.")
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log My Weight"
    static var description = IntentDescription("Adds a weigh-in to Luma.")
    static var openAppWhenRun = false

    @Parameter(title: "Kilograms", inclusiveRange: (30, 250))
    var kilograms: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LumaQuickIntents.prepare()
        LumaQuickLog.add(LumaQuickLog.Item(kind: .weight, amount: (kilograms * 10).rounded() / 10))
        LumaQuickIntents.queued()
        return .result(dialog: "Logged \(String(format: "%.1f", kilograms)) kg.")
    }
}
