import SwiftUI

/// What the Lock Screen card and the Dynamic Island show. Built by the widget extension from the
/// activity's content state, so these views stay free of ActivityKit and can be laid out in the app.
public struct LumaLiveState: Equatable, Sendable {
    /// The current reading, or nil when the strap is not delivering one right now.
    public var bpm: Int?
    /// The most recent reading the strap delivered and when, kept so the card never goes blank.
    public var lastBpm: Int?
    public var lastAt: Date?
    /// Heart-rate zone 1…5 of the reading shown.
    public var zone: Int?
    public var connected: Bool
    public var recovery: Int?
    public var strainText: String?
    public var sleepScore: Int?
    /// A session being recorded: its name, and a start date such that now − start is the moving time.
    public var session: String?
    public var sessionStart: Date?
    /// Moving time while the session is paused (the clock stands still).
    public var pausedElapsed: TimeInterval?
    public var distanceKm: Double?

    public init(bpm: Int? = nil, lastBpm: Int? = nil, lastAt: Date? = nil, zone: Int? = nil, connected: Bool = true, recovery: Int? = nil,
                strainText: String? = nil, sleepScore: Int? = nil, session: String? = nil, sessionStart: Date? = nil,
                pausedElapsed: TimeInterval? = nil, distanceKm: Double? = nil) {
        self.bpm = bpm; self.lastBpm = lastBpm; self.lastAt = lastAt; self.zone = zone; self.connected = connected
        self.recovery = recovery; self.strainText = strainText; self.sleepScore = sleepScore; self.session = session
        self.sessionStart = sessionStart; self.pausedElapsed = pausedElapsed; self.distanceKm = distanceKm
    }

    /// The number to draw: the live reading, else the last one the strap delivered.
    public var shownBpm: Int? { bpm ?? lastBpm }
    public var isLive: Bool { bpm != nil }
    public var hasSession: Bool { session != nil }

    var zoneColor: Color { zone.map { Luma.zone($0) } ?? Luma.coral }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The moving time of a session: a system-driven clock while it runs, a still figure while paused.
struct LiveSessionClock: View {
    let state: LumaLiveState
    var size: CGFloat

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(LumaLiveState.clock(paused)).font(LumaFont.numeral(size)).foregroundStyle(Luma.amber)
        } else if let start = state.sessionStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .font(LumaFont.numeral(size)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing)
        }
    }
}

/// The line under the heart rate: live, how old the last reading is, or what is missing.
struct LiveStatusLine: View {
    let state: LumaLiveState
    var size: CGFloat = 11.5

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(state.isLive ? Luma.volt : (state.lastAt == nil ? Luma.smoke : Luma.amber)).frame(width: 6, height: 6)
            if state.isLive {
                Text(state.zone.map { "Zone \($0)" } ?? "Live").foregroundStyle(state.zone == nil ? Luma.mist : state.zoneColor)
            } else if let at = state.lastAt {
                Text("Last reading \(Text(at, style: .relative)) ago").foregroundStyle(Luma.mist)
            } else {
                Text(state.connected ? "Waiting for a reading" : "Strap not connected").foregroundStyle(Luma.mist)
            }
        }
        .font(LumaFont.body(size, .medium))
        .lineLimit(1)
    }
}

/// The Lock Screen card: heart rate on the left; on the right the day's three scores, or the clock
/// and distance of a session being recorded.
public struct LumaLiveCard: View {
    let state: LumaLiveState

    public init(state: LumaLiveState) { self.state = state }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(state.isLive ? state.zoneColor : Luma.smoke)
                    Text(state.session ?? "Heart rate").font(LumaFont.label(10)).foregroundStyle(Luma.mist).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(state.shownBpm.map { "\($0)" } ?? "–").font(LumaFont.numeral(52, .heavy))
                        .foregroundStyle(state.isLive ? Luma.frost : Luma.mist).contentTransition(.numericText())
                    Text("bpm").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist)
                }
                LiveStatusLine(state: state)
            }
            Spacer(minLength: 6)
            if state.hasSession {
                VStack(alignment: .trailing, spacing: 2) {
                    LiveSessionClock(state: state, size: 38).frame(maxWidth: 150, alignment: .trailing)
                    Text(sessionDetail).font(LumaFont.body(12.5, .medium)).foregroundStyle(Luma.mist).lineLimit(1)
                }
            } else {
                HStack(spacing: 14) {
                    ringStat
                    LiveStat(label: "Strain", value: state.strainText, color: Luma.ember)
                    LiveStat(label: "Sleep", value: state.sleepScore.map { "\($0)%" }, color: Luma.dusk)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(LumaLiveBackdrop(color: state.isLive ? state.zoneColor : Luma.smoke))
    }

    private var sessionDetail: String {
        var parts: [String] = []
        if let km = state.distanceKm, km > 0 { parts.append(String(format: "%.2f km", km)) }
        if state.pausedElapsed != nil { parts.append("Paused") }
        if parts.isEmpty, let r = state.recovery { parts.append("Recovery \(r)%") }
        return parts.joined(separator: " · ")
    }

    private var ringStat: some View {
        VStack(spacing: 3) {
            ZStack {
                LumaRing(progress: Double(state.recovery ?? 0) / 100, lineWidth: 4.5,
                         colors: [Luma.recovery(state.recovery.map { Double($0) }).opacity(0.7), Luma.recovery(state.recovery.map { Double($0) })])
                Text(state.recovery.map { "\($0)" } ?? "–").font(LumaFont.numeral(16)).foregroundStyle(state.recovery == nil ? Luma.smoke : Luma.frost)
            }
            .frame(width: 42, height: 42)
            Text("Recovery").font(LumaFont.label(8)).foregroundStyle(Luma.mist)
        }
    }
}

struct LiveStat: View {
    let label: String
    let value: String?
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value ?? "–").font(LumaFont.numeral(24)).foregroundStyle(value == nil ? Luma.smoke : Luma.frost)
                .frame(height: 42)
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 4, height: 4)
                Text(label).font(LumaFont.label(8)).foregroundStyle(Luma.mist)
            }
        }
        .fixedSize()
    }
}

/// The card's own night field: the zone's colour glowing in from the heart-rate side.
public struct LumaLiveBackdrop: View {
    var color: Color

    public init(color: Color) { self.color = color }

    public var body: some View {
        ZStack {
            Luma.night
            RadialGradient(colors: [color.opacity(0.30), color.opacity(0)], center: UnitPoint(x: 0.0, y: 0.1), startRadius: 0, endRadius: 210)
            LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0)], startPoint: .top, endPoint: .center)
        }
    }
}

// MARK: - Dynamic Island

public struct LumaIslandHeart: View {
    let state: LumaLiveState
    public init(state: LumaLiveState) { self.state = state }
    public var body: some View {
        Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(state.isLive ? state.zoneColor : Luma.smoke)
    }
}

public struct LumaIslandBpm: View {
    let state: LumaLiveState
    public init(state: LumaLiveState) { self.state = state }
    public var body: some View {
        Text(state.shownBpm.map { "\($0)" } ?? "–").font(LumaFont.numeral(17)).foregroundStyle(state.isLive ? Luma.frost : Luma.mist)
            .contentTransition(.numericText())
    }
}

public struct LumaIslandLeading: View {
    let state: LumaLiveState
    public init(state: LumaLiveState) { self.state = state }
    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(state.isLive ? state.zoneColor : Luma.smoke)
            Text(state.shownBpm.map { "\($0)" } ?? "–").font(LumaFont.numeral(34, .heavy)).foregroundStyle(state.isLive ? Luma.frost : Luma.mist)
                .contentTransition(.numericText())
            Text("bpm").font(LumaFont.body(11, .semibold)).foregroundStyle(Luma.mist)
        }
        .padding(.leading, 4)
    }
}

public struct LumaIslandTrailing: View {
    let state: LumaLiveState
    public init(state: LumaLiveState) { self.state = state }
    public var body: some View {
        Group {
            if state.hasSession {
                LiveSessionClock(state: state, size: 28).frame(maxWidth: 110, alignment: .trailing)
            } else {
                HStack(spacing: 6) {
                    ZStack {
                        LumaRing(progress: Double(state.recovery ?? 0) / 100, lineWidth: 3.5,
                                 colors: [Luma.recovery(state.recovery.map { Double($0) })], glow: false)
                        Text(state.recovery.map { "\($0)" } ?? "–").font(LumaFont.numeral(13)).foregroundStyle(Luma.frost)
                    }
                    .frame(width: 34, height: 34)
                }
            }
        }
        .padding(.trailing, 4)
    }
}

public struct LumaIslandBottom: View {
    let state: LumaLiveState
    public init(state: LumaLiveState) { self.state = state }
    public var body: some View {
        HStack(spacing: 10) {
            LiveStatusLine(state: state, size: 12)
            Spacer(minLength: 4)
            if state.hasSession {
                if let km = state.distanceKm, km > 0 {
                    Text(String(format: "%.2f km", km)).font(LumaFont.numeral(16)).foregroundStyle(Luma.frost)
                }
                Text(state.session ?? "").font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist).lineLimit(1)
            } else {
                Text("Strain \(state.strainText ?? "–")").font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist)
                Text("Sleep \(state.sleepScore.map { String($0) + "%" } ?? "–")").font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist)
            }
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Strap sync

/// The Lock Screen card shown while the strap's stored history is being brought in.
public struct LumaSyncCard: View {
    let status: String
    let detail: String?
    let startedAt: Date?
    let finished: Bool
    let failed: Bool

    public init(status: String, detail: String?, startedAt: Date?, finished: Bool, failed: Bool) {
        self.status = status; self.detail = detail; self.startedAt = startedAt; self.finished = finished; self.failed = failed
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: failed ? "exclamationmark.circle.fill" : (finished ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"))
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(failed ? Luma.coral : Luma.volt)
            VStack(alignment: .leading, spacing: 2) {
                Text("Strap sync").font(LumaFont.label(10)).foregroundStyle(Luma.mist)
                Text(status).font(LumaFont.heading(17)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.7)
                if let detail { Text(detail).font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke).lineLimit(1) }
            }
            Spacer(minLength: 6)
            if let startedAt, !finished, !failed {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(LumaFont.numeral(24)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing).frame(maxWidth: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(LumaLiveBackdrop(color: failed ? Luma.coral : Luma.volt))
    }
}
