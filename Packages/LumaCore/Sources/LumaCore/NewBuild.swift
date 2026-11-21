import Foundation

// MARK: - A newer build

/// The newest build named in the public listing that AltStore reads.
public struct ListedBuild: Codable, Equatable, Sendable {
    public var version: String
    public var build: Int
    public var date: String?

    public init(version: String, build: Int, date: String? = nil) {
        self.version = version; self.build = build; self.date = date
    }
}

/// Whether a newer build is out. Luma cannot install anything itself: the most it can do is notice and
/// say how to get it. The listing is one public file; reading it sends nothing about the athlete.
public enum NewBuild {
    public static let listingURL = "https://raw.githubusercontent.com/ALatpate/hyroxlab/main/hyroxlab-source.json"
    /// At most one look a day.
    public static let everyS: Double = 24 * 3600

    /// The first build in the listing, which is the newest.
    public static func listed(from json: String) -> ListedBuild? {
        guard let root = JSONValue.parse(json),
              let app = root["apps"]?.array?.first,
              let first = app["versions"]?.array?.first,
              let version = first["version"]?.string,
              let build = first["buildVersion"]?.int, build > 0 else { return nil }
        return ListedBuild(version: version, build: build, date: first["date"]?.string)
    }

    /// True when a look is due. `lastLookedAt` is seconds since 1970, 0 for never. A clock that has gone
    /// backwards counts as due, so the next look is not parked far in the future.
    public static func due(enabled: Bool, lastLookedAt: Double, now: Double) -> Bool {
        guard enabled else { return false }
        if lastLookedAt <= 0 || now < lastLookedAt { return true }
        return now - lastLookedAt >= everyS
    }

    /// The listed build, when it is newer than the one installed.
    public static func newer(_ listed: ListedBuild?, than installed: Int?) -> ListedBuild? {
        guard let listed, let installed, listed.build > installed else { return nil }
        return listed
    }

    public static func title(_ b: ListedBuild) -> String { "Build \(b.build) is out" }

    /// How to get it, in the order the taps happen.
    public static let howTo = "In AltStore, open My Apps, pull the list down, then tap Update next to Luma."
}
