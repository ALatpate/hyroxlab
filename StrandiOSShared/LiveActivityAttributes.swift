#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity attributes for the heart-rate card on the Lock Screen and in the Dynamic Island.
/// Shared between the app (which starts and updates the activity) and the widget extension (which
/// draws it). The type name is persisted by iOS for running activities, so it stays as it is.
public struct NOOPActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var bpm: Int?
        public var recovery: Int?
        public var bonded: Bool
        // Strain on the stored 0–100 axis. OPTIONAL with a nil default so an activity started by an
        // older build still decodes; the same holds for every field below.
        public var effort: Int?

        /// The most recent reading the strap delivered and when it arrived. Kept when `bpm` goes nil,
        /// so the card can show "last reading, 2 min ago" instead of going blank.
        public var lastBpm: Int?
        public var lastAt: Date?
        /// Heart-rate zone 1…5 of the reading, from the athlete's own zones.
        public var zone: Int?
        /// Strain as the athlete has chosen to see it ("9.4" on the 0–21 scale).
        public var strainText: String?
        public var sleep: Int?
        /// A session being recorded: its name, a start date such that now − start is the moving time,
        /// the moving time while paused, and the distance so far.
        public var session: String?
        public var sessionStart: Date?
        public var pausedElapsed: Double?
        public var distanceM: Double?
        /// The companion on the card: the state it is in and what it is wearing, as the app chose
        /// them ("steady~top|bottom|feet|head|accessory"). Nil from an older build: no companion is drawn.
        public var glimm: String?

        public init(bpm: Int?, recovery: Int?, bonded: Bool, effort: Int? = nil) {
            self.bpm = bpm
            self.recovery = recovery
            self.bonded = bonded
            self.effort = effort
        }
    }

    /// Static title for the session.
    public var title: String

    public init(title: String = "Heart rate") {
        self.title = title
    }
}
#endif
