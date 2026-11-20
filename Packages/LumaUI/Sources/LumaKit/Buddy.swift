import SwiftUI

// MARK: - The companion's states

/// The states the companion can be in. The raw values are the ones the app's rules give
/// (`BuddyMood` in LumaCore); this target has no dependencies, so it carries its own copy of the names.
/// How each is drawn is Glimm's business: `GlimmLook.mood` names the mood, GlimmRig draws it.
public enum BuddyKind: String, CaseIterable, Sendable {
    case waiting, training, sleeping, celebrating, worked, unwell, sleepy, thirsty, hungry, drained, steady, charged
}
