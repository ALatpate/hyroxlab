import Foundation

/// The small blob HYROX Lab shares with its widget: readiness and today's session. Written by the app
/// into the App Group suite WidgetSnapshot already uses; read by HXReadinessWidget. Every field is
/// optional so an older or newer app never breaks the widget.
public struct HXWidgetState: Codable, Equatable {
    public var score: Int?
    public var advice: String?
    public var sessionTitle: String?
    public var sessionPurpose: String?
    public var sessionDone: Bool?
    public var raceDaysLeft: Int?
    public var updated: Date

    public static let storageKey = "hyrox.widget.state"
    public static let kind = "HXReadinessWidget"

    public init(score: Int?, advice: String?, sessionTitle: String?, sessionPurpose: String?, sessionDone: Bool?, raceDaysLeft: Int?, updated: Date) {
        self.score = score; self.advice = advice; self.sessionTitle = sessionTitle; self.sessionPurpose = sessionPurpose
        self.sessionDone = sessionDone; self.raceDaysLeft = raceDaysLeft; self.updated = updated
    }

    public static func load() -> HXWidgetState? {
        guard let d = UserDefaults(suiteName: WidgetSnapshot.suiteName)?.data(forKey: storageKey) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(HXWidgetState.self, from: d)
    }

    public func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(self) else { return }
        UserDefaults(suiteName: WidgetSnapshot.suiteName)?.set(d, forKey: Self.storageKey)
    }
}
