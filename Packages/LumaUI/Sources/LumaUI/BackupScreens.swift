import SwiftUI
import LumaCore
import LumaKit

/// The copies Luma keeps of what the athlete has logged, and the way back to one of them.
///
/// A day's set is every record as it stood at the end of that day. Going back puts those records in
/// place of what is there now, which is kept first as a set of its own, so going back can be undone.
struct BackupsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var sets: [VaultBackup] = []
    @State private var chosen: VaultBackup?
    @State private var outcome: String?

    /// Days before today: today's set is what is on the phone now.
    private var days: [VaultBackup] { sets.filter { $0.kind == .day && $0.name < env.today } }
    private var others: [VaultBackup] { sets.filter { $0.kind != .day } }

    var body: some View {
        LumaDetailScreen(title: "Copies of your records", tone: .neutral) {
            LumaNote("Whenever something you log is saved, Luma keeps a copy for that day, for two weeks. Going back to a day puts everything you have logged back as it stood at the end of that day. What you have now is kept first, so you can undo it.")
            if let outcome {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Luma.volt)
                    Text(outcome).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LumaPanel(tint: Luma.volt, radius: 18))
            }
            if days.isEmpty && others.isEmpty {
                LumaEmpty(symbol: "clock.arrow.circlepath", title: "No earlier day yet",
                          message: "Copies begin the day this build is installed. From the day after, that day can be gone back to.")
            }
            if !days.isEmpty {
                LumaSection(title: "Days")
                LumaGroup {
                    ForEach(days) { set in row(set) }
                }
            }
            if !others.isEmpty {
                LumaSection(title: "Kept at other moments")
                LumaGroup {
                    ForEach(others) { set in row(set) }
                }
            }
            LumaNote("Copies stay on this phone. Strap data (heart rate, sleep, recovery) is stored separately and is not changed by going back.")
        }
        .onAppear { sets = env.backups }
        .confirmationDialog(chosen.map { Self.prompt($0, today: env.today).title } ?? "",
                            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible) {
            Button(chosen.map { Self.prompt($0, today: env.today).button } ?? "Go back") {
                if let set = chosen { goBack(to: set) }
            }
            Button("Cancel", role: .cancel) { chosen = nil }
        } message: {
            Text(chosen.map { Self.prompt($0, today: env.today).message } ?? "")
        }
    }

    private func row(_ set: VaultBackup) -> some View {
        LumaRow(symbol: Self.symbol(set), symbolColor: set.kind == .day ? Luma.sky : Luma.amber,
                title: Self.title(set, today: env.today), subtitle: Self.detail(set)) {
            Button(set.kind == .beforeRestore ? "Undo" : "Go back") {
                LumaHaptics.tap()
                chosen = set
            }
            .buttonStyle(LumaSecondaryButtonStyle(compact: true))
        }
    }

    private func goBack(to set: VaultBackup) {
        let when = Self.when(set, today: env.today)
        let done = env.restore(set)
        chosen = nil
        sets = env.backups
        if done {
            LumaHaptics.success()
            outcome = set.kind == .day
                ? "Done. Your records are as they stood at the end of \(when). To undo, use the newest set under “Kept at other moments”."
                : "Done. Your records are as they stood \(when). To undo, use the newest set under “Kept at other moments”."
        } else {
            LumaHaptics.warn()
            outcome = "Not all of that set could be put back. Nothing was deleted: what you had is under “Kept at other moments”."
        }
    }

    static func symbol(_ set: VaultBackup) -> String {
        switch set.kind {
        case .day: return "calendar"
        case .beforeRestore: return "arrow.uturn.backward"
        case .beforeChange: return "exclamationmark.triangle"
        case .asFound: return "tray.full"
        }
    }

    /// "yesterday", "Tuesday 17 Nov", and with the time of day for a set kept at a moment.
    static func when(_ set: VaultBackup, today: String) -> String {
        var day = LumaText.dayTitle(set.keptDay, today: today)
        for word in ["Today", "Yesterday", "Tomorrow"] where day == word { day = word.lowercased() }
        return set.keptTime.map { "\(day) at \($0)" } ?? day
    }

    static func title(_ set: VaultBackup, today: String) -> String {
        let when = Self.when(set, today: today)
        switch set.kind {
        case .day: return "End of \(when)"
        case .beforeRestore: return "Before you went back, \(when)"
        case .beforeChange: return "Before a large change, \(when)"
        case .asFound: return "As found, \(when)"
        }
    }

    static func detail(_ set: VaultBackup) -> String {
        let size = LumaVault.sizeText(set.bytes)
        if set.kind == .beforeChange, set.files.count == 1, let only = set.files.first {
            return "\(LumaVault.title(for: only)) · \(size)"
        }
        return "\(set.files.count) \(set.files.count == 1 ? "record" : "records") · \(size)"
    }

    /// What is asked before going back, in words that fit the kind of set.
    static func prompt(_ set: VaultBackup, today: String) -> (title: String, message: String, button: String) {
        let when = Self.when(set, today: today)
        let kept = "What you have now is kept first, so you can undo this."
        switch set.kind {
        case .day:
            return ("Go back to the end of \(when)?", "Everything you have logged goes back to how it stood then. \(kept)", "Go back")
        case .beforeRestore:
            return ("Undo going back?", "Your records return to how they stood \(when), just before you went back. \(kept)", "Undo")
        case .beforeChange:
            let what = set.files.first.map { LumaVault.title(for: $0) } ?? "That record"
            return ("Put this record back?", "\(what) returns to how it stood \(when), before it became much smaller. \(kept)", "Put it back")
        case .asFound:
            return ("Go back to how your records were found?", "Everything you have logged goes back to how it stood \(when), when Luma first kept copies. \(kept)", "Go back")
        }
    }
}
