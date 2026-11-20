import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - What a widget shows, moment by moment

/// The companion at one instant, as a widget draws it.
public struct BuddyFrame: Equatable, Sendable {
    public var date: Date
    public var kind: BuddyKind
    /// Which still of the mood (`GlimmRig.pose`): 0 is the mood's own pose, 1 to 3 its small
    /// variations, 10 and 11 the two steps of the answer to a tap.
    public var beat: Int
    public var title: String
    public var line: String
    /// 0…1; negative when there is no recovery score.
    public var energy: Double
    /// What Glimm is wearing, as the app chose it; empty for the everyday look.
    public var outfit: String

    public init(date: Date, kind: BuddyKind, beat: Int = 0, title: String, line: String, energy: Double = -1, outfit: String = "") {
        self.date = date; self.kind = kind; self.beat = beat; self.title = title; self.line = line; self.energy = energy; self.outfit = outfit
    }
}

/// Turns the companion's schedule into the frames a widget's timeline is made of. iOS draws a widget
/// from a list of dated pictures and animates the change from one to the next, so the companion moves
/// in three ways: when its state changes, when it shifts its weight every few minutes, and when it is
/// tapped. Nothing here decides a state; those come from the app, in the glance.
public enum BuddyTimeline {
    /// How often a resting companion shifts a little.
    public static let shiftEvery: TimeInterval = 300
    /// How long after a tap its reaction is still worth playing.
    public static let pokeWindow: TimeInterval = 4

    /// The stills it moves through, one per shift: its own pose, then one of the mood's small variations.
    static let beats = [0, 1, 0, 2, 0, 3]

    private static func beat(at date: Date) -> Int {
        let slot = whole((date.timeIntervalSince1970 / shiftEvery).rounded(.down))
        return beats[((slot % beats.count) + beats.count) % beats.count]
    }

    /// The frame for one instant.
    public static func frame(_ buddy: LumaGlance.Buddy?, at date: Date, beat: Int? = nil) -> BuddyFrame {
        guard let moment = buddy?.moment(at: date), let kind = BuddyKind(rawValue: moment.kind) else {
            return BuddyFrame(date: date, kind: .waiting, beat: beat ?? 0, title: "Waiting", line: "Open Luma to bring today's numbers in.")
        }
        return BuddyFrame(date: date, kind: kind, beat: beat ?? BuddyTimeline.beat(at: date), title: moment.title, line: moment.line,
                          energy: moment.energy, outfit: moment.outfit ?? "")
    }

    /// Frames from `now` for the next `hours`: every change of state, a shift of weight every few
    /// minutes, and, straight after a tap, a hop and a wave.
    public static func frames(_ buddy: LumaGlance.Buddy?, from now: Date, poke: Date? = nil, hours: Double = 3) -> [BuddyFrame] {
        let end = now.addingTimeInterval(hours * 3600)
        var times: Set<Date> = []
        for m in buddy?.moments ?? [] where m.at > now && m.at <= end { times.insert(m.at) }
        var mark = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / shiftEvery).rounded(.down) * shiftEvery + shiftEvery)
        while mark <= end {
            times.insert(mark)
            mark = mark.addingTimeInterval(shiftEvery)
        }
        var out: [BuddyFrame] = []
        if let poke, now.timeIntervalSince(poke) >= 0, now.timeIntervalSince(poke) < pokeWindow {
            // A second or more apart. Nothing documents how close two pictures of a widget may be and
            // still be shown one after the other, so the reaction does not depend on less.
            out.append(frame(buddy, at: now, beat: 10))
            out.append(frame(buddy, at: now.addingTimeInterval(1), beat: 11))
            out.append(frame(buddy, at: now.addingTimeInterval(2.2)))
        } else {
            out.append(frame(buddy, at: now))
        }
        for t in times.sorted() where t > (out.last?.date ?? now) { out.append(frame(buddy, at: t)) }
        return out
    }
}

// MARK: - Widget views

public extension GlimmFigure {
    /// The figure for a widget frame: still, in the pose and the clothes the frame names.
    init(frame: BuddyFrame, ink: GlimmInk) {
        self.init(kind: frame.kind, outfit: frame.outfit, ink: ink, beat: frame.beat, energy: frame.energy < 0 ? 0.5 : frame.energy)
    }
}

/// The companion as a widget: alone in the round Lock Screen slot, beside its state in the wide one,
/// above it on the Home Screen. `figure` is the drawn companion, which the widget extension wraps in
/// a button so that a tap reaches it.
public struct LumaBuddyWidgetView<Figure: View>: View {
    let frame: BuddyFrame
    let name: String
    let family: LumaWidgetFamily
    let figure: Figure

    public init(frame: BuddyFrame, name: String, family: LumaWidgetFamily, @ViewBuilder figure: () -> Figure) {
        self.frame = frame; self.name = name; self.family = family; self.figure = figure()
    }

    public var body: some View {
        layout
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name): \(frame.title). \(frame.line)")
    }

    @ViewBuilder
    private var layout: some View {
        switch family {
        case .circular:
            // Drawn a little over-size and set low, so the face fills the circle and the feet meet its edge.
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                figure
                    .frame(width: side * 0.97, height: side * 1.16)
                    .offset(y: side * 0.07)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(Circle())
            }
        case .rectangular:
            HStack(spacing: 8) {
                figure.frame(width: 54, height: 65)
                VStack(alignment: .leading, spacing: 1) {
                    Text(frame.title).font(LumaFont.heading(13.5)).lineLimit(1).minimumScaleFactor(0.8)
                    // Three lines: the slot is narrow beside the figure, and a line cut short would drop the
                    // figure it exists to give.
                    Text(frame.line).font(.system(size: 11, weight: .medium)).opacity(0.8).lineLimit(3).minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .inline:
            Text("\(name): \(frame.title)")
        case .small:
            VStack(spacing: 2) {
                figure.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(frame.title).font(LumaFont.heading(14)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
                Text(frame.line).font(LumaFont.body(10.5)).foregroundStyle(Luma.mist).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
        case .medium, .large:
            HStack(spacing: 14) {
                figure.frame(width: 104).frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(LumaFont.label(10)).foregroundStyle(Luma.mist)
                    Text(frame.title).font(LumaFont.heading(19)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
                    Text(frame.line).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

public extension LumaBuddyWidgetView where Figure == GlimmFigure {
    /// The widget with the figure alone, for previews and the design gallery.
    init(frame: BuddyFrame, name: String, family: LumaWidgetFamily) {
        let lock = family == .circular || family == .rectangular || family == .inline
        self.init(frame: frame, name: name, family: family) {
            GlimmFigure(frame: frame, ink: lock ? .mono : .color)
        }
    }
}
