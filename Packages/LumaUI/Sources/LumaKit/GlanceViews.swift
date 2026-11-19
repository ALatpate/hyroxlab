import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The widget shapes Luma draws for. Mapped from WidgetKit's families by the widget extension, so
/// these views can also be laid out in the app (the design gallery) without WidgetKit.
public enum LumaWidgetFamily: Sendable {
    case small, medium, large, circular, rectangular, inline
}

// MARK: - Shared pieces

/// The night field behind Home Screen widgets, with one light spilling in from a corner.
public struct GlanceBackdrop: View {
    var tint: Color

    public init(tint: Color = Luma.volt) { self.tint = tint }

    public var body: some View {
        ZStack {
            Luma.night
            RadialGradient(colors: [tint.opacity(0.22), tint.opacity(0)], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 230)
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0)], startPoint: .top, endPoint: .center)
        }
    }
}

/// The recovery ring with its number: the Lumen, drawn still for a widget.
struct GlanceLumen: View {
    let score: Int?
    var lineWidth: CGFloat = 9
    var numeral: CGFloat = 38
    var caption: Bool = true

    var body: some View {
        let color = Luma.recovery(score.map { Double($0) })
        ZStack {
            Circle().fill(color.opacity(score == nil ? 0 : 0.10)).padding(lineWidth + 3)
            LumaRing(progress: Double(score ?? 0) / 100, lineWidth: lineWidth, colors: [color.opacity(0.7), color])
            VStack(spacing: -1) {
                Text(score.map { "\($0)" } ?? "–").font(LumaFont.numeral(numeral)).foregroundStyle(score == nil ? Luma.smoke : Luma.frost)
                if caption { Text("Recovery").font(LumaFont.label(8)).foregroundStyle(Luma.mist) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct GlanceStat: View {
    let label: String
    let value: String?
    let color: Color
    var size: CGFloat = 19

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(LumaFont.label(8.5)).foregroundStyle(Luma.mist)
            }
            Text(value ?? "–").font(LumaFont.numeral(size)).foregroundStyle(value == nil ? Luma.smoke : Luma.frost)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

struct GlanceProgress: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(color).frame(width: max(height, geo.size.width * min(1, max(0, fraction)))).opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

private func grouped(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private func litres(_ ml: Int) -> String { String(format: "%.1f", Double(ml) / 1000) }

// MARK: - Today

/// Recovery, strain and sleep at a glance, with the day's call and the next session as space allows.
public struct LumaTodayWidgetView: View {
    let glance: LumaGlance?
    let family: LumaWidgetFamily
    /// False when the stored figures belong to an earlier day: scores are then withheld, not shown as today's.
    let current: Bool

    public init(glance: LumaGlance?, family: LumaWidgetFamily, current: Bool = true) {
        self.glance = glance; self.family = family; self.current = current
    }

    private var recovery: Int? { current ? glance?.recovery : nil }
    private var strain: String? { current ? glance?.strainText : nil }
    private var sleep: String? { current ? glance?.sleepScore.map { "\($0)%" } : nil }
    private var hrv: String? { current ? glance?.hrv.map { "\($0)" } : nil }

    private var callLine: String {
        guard let glance else { return "Open Luma to get started" }
        // Figures from an earlier day are withheld. All that is known is that Luma has not written
        // today's yet, so that is all that is said.
        if !current { return "Open Luma to update" }
        return glance.call ?? "Open Luma to update"
    }

    public var body: some View {
        switch family {
        case .small: small
        case .medium: medium
        case .large: large
        case .circular: circular
        case .rectangular: rectangular
        case .inline: inline
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            GlanceLumen(score: recovery, lineWidth: 8, numeral: 34).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                GlanceStat(label: "Strain", value: strain, color: Luma.ember, size: 18)
                Spacer(minLength: 4)
                GlanceStat(label: "Sleep", value: sleep, color: Luma.dusk, size: 18)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            GlanceLumen(score: recovery, lineWidth: 9, numeral: 38)
            VStack(alignment: .leading, spacing: 0) {
                Text(callLine).font(LumaFont.heading(14)).foregroundStyle(Luma.frost).lineLimit(2).minimumScaleFactor(0.75)
                Spacer(minLength: 3)
                sessionLine
                Spacer(minLength: 5)
                HStack(spacing: 12) {
                    GlanceStat(label: "Strain", value: strain, color: Luma.ember)
                    GlanceStat(label: "Sleep", value: sleep, color: Luma.dusk)
                    GlanceStat(label: "HRV", value: hrv, color: Luma.aqua)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var medium: some View { summary }

    @ViewBuilder
    private var sessionLine: some View {
        if let next = glance?.sessions.first(where: { !$0.done }) ?? glance?.sessions.last, current {
            HStack(spacing: 5) {
                Image(systemName: next.done ? "checkmark.circle.fill" : next.symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(next.done ? Luma.volt : Luma.mist)
                Text(next.time.map { "\($0) \(next.title)" } ?? next.title).font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist).lineLimit(1)
            }
        } else {
            Text(glance == nil ? "Wear the strap tonight for a first score" : "Nothing planned today").font(LumaFont.body(12)).foregroundStyle(Luma.smoke).lineLimit(1)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary.frame(height: 112)
            Rectangle().fill(Luma.line).frame(height: 1)
            GlanceWeekBars(week: glance?.week ?? [], day: glance?.day)
                .frame(height: 62)
            Rectangle().fill(Luma.line).frame(height: 1)
            GlanceFuelRows(glance: glance, compact: false)
        }
    }

    private var circular: some View {
        ZStack {
            LumaRing(progress: Double(recovery ?? 0) / 100, lineWidth: 5.5, colors: [.white, .white], track: Color.white.opacity(0.22), glow: false)
            LumaRing(progress: current ? (glance?.strainFraction ?? 0) : 0, lineWidth: 3.5, colors: [.white.opacity(0.75), .white.opacity(0.75)],
                     track: Color.white.opacity(0.14), glow: false)
                .padding(8)
            Text(recovery.map { "\($0)" } ?? "–").font(LumaFont.numeral(20))
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            circular.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1.5) {
                Text("\(Image(systemName: "flame.fill")) \(strain ?? "–")  \(Image(systemName: "moon.fill")) \(sleep ?? "–")")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(callLine).font(.system(size: 12, weight: .medium)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.75)
                Text(rectangularThird).font(.system(size: 12)).opacity(0.65).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    private var rectangularThird: String {
        if current, let next = glance?.sessions.first(where: { !$0.done }) {
            return next.time.map { "\($0) \(next.title)" } ?? next.title
        }
        if let hrv, let rhr = glance?.restingHR { return "HRV \(hrv) · Resting \(rhr)" }
        return "Open Luma to sync"
    }

    private var inline: some View {
        let r = recovery.map { String($0) + "%" } ?? "–"
        let s = strain ?? "–"
        return Text("\(Image(systemName: "bolt.heart.fill")) Recovery \(r) · Strain \(s)")
    }
}

/// Seven days of recovery as bars, today's the brightest.
struct GlanceWeekBars: View {
    let week: [Int?]
    let day: String?

    private var letters: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let end = day.flatMap { key -> Date? in
            let p = key.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) : nil
        } ?? Date()
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { i in
            let d = calendar.date(byAdding: .day, value: i - 6, to: end) ?? end
            return symbols[calendar.component(.weekday, from: d) - 1]
        }
    }

    var body: some View {
        let values: [Int?] = week.count == 7 ? week : Array(repeating: nil, count: 7)
        let names = letters
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let v = values[i]
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(v == nil ? Color.white.opacity(0.08) : Luma.recovery(Double(v ?? 0)).opacity(i == 6 ? 1 : 0.55))
                                .frame(height: max(4, geo.size.height * CGFloat(v ?? 6) / 100))
                        }
                    }
                    Text(names[i]).font(LumaFont.label(8)).foregroundStyle(i == 6 ? Luma.frost : Luma.smoke)
                }
            }
        }
    }
}

// MARK: - Fuel

struct GlanceFuelRows: View {
    let glance: LumaGlance?
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 7 : 8) {
            row("Energy", glance.map { grouped($0.kcal) }, glance.map { "\(grouped($0.kcalTarget)) kcal" }, fraction(glance?.kcal, glance?.kcalTarget), Luma.mint)
            row("Protein", glance.map { "\($0.protein)" }, glance.map { "\($0.proteinTarget) g" }, fraction(glance?.protein, glance?.proteinTarget), Luma.ember)
            row("Water", glance.map { litres($0.waterMl) }, glance.map { "\(litres($0.waterTargetMl)) L" }, fraction(glance?.waterMl, glance?.waterTargetMl), Luma.sky)
        }
    }

    private func fraction(_ value: Int?, _ target: Int?) -> Double {
        guard let value, let target, target > 0 else { return 0 }
        return Double(value) / Double(target)
    }

    private func row(_ label: String, _ value: String?, _ target: String?, _ fraction: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(LumaFont.label(9)).foregroundStyle(Luma.mist)
                Spacer(minLength: 2)
                Text(value ?? "–").font(LumaFont.numeral(compact ? 15 : 16)).foregroundStyle(Luma.frost)
                if let target { Text("/ \(compact ? String(target.split(separator: " ").first ?? "") : target)").font(LumaFont.body(10)).foregroundStyle(Luma.smoke) }
            }
            .lineLimit(1)
            GlanceProgress(fraction: fraction, color: color)
        }
    }
}

/// Energy, protein and water against today's targets.
public struct LumaFuelWidgetView: View {
    let glance: LumaGlance?
    let family: LumaWidgetFamily
    let current: Bool
    /// A control set beside the title on the Home Screen sizes: the widget extension puts the button
    /// that logs a glass of water here.
    let action: AnyView?

    public init(glance: LumaGlance?, family: LumaWidgetFamily, current: Bool = true, action: AnyView? = nil) {
        self.glance = glance; self.family = family; self.current = current; self.action = action
    }

    /// Yesterday's intake is not today's: after the rollover the log reads empty until something is logged.
    private var shown: LumaGlance? {
        guard var g = glance else { return nil }
        if !current { g.kcal = 0; g.protein = 0; g.waterMl = 0 }
        return g
    }

    public var body: some View {
        switch family {
        case .small:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Fuel").font(LumaFont.heading(13)).foregroundStyle(Luma.frost)
                    Spacer(minLength: 0)
                    if let action { action }
                }
                Spacer(minLength: 0)
                GlanceFuelRows(glance: shown, compact: true)
            }
        case .medium, .large:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fuel").font(LumaFont.heading(13)).foregroundStyle(Luma.frost)
                    if let action { action.padding(.top, 4) }
                    Spacer(minLength: 0)
                    Text(shown.map { grouped(max(0, $0.kcalTarget - $0.kcal)) } ?? "–").font(LumaFont.numeral(42)).foregroundStyle(Luma.frost)
                    Text("kcal to go").font(LumaFont.label(9)).foregroundStyle(Luma.mist)
                }
                .fixedSize(horizontal: true, vertical: false)
                GlanceFuelRows(glance: shown, compact: false)
            }
        case .circular:
            ZStack {
                LumaRing(progress: shown.map { $0.proteinTarget > 0 ? Double($0.protein) / Double($0.proteinTarget) : 0 } ?? 0, lineWidth: 5.5,
                         colors: [.white, .white], track: Color.white.opacity(0.22), glow: false)
                VStack(spacing: -2) {
                    Text(shown.map { "\($0.protein)" } ?? "–").font(LumaFont.numeral(19))
                    Text("g protein").font(.system(size: 7.5, weight: .medium))
                }
            }
            .widgetAccentable()
        case .rectangular:
            VStack(alignment: .leading, spacing: 4) {
                line("Energy", shown.map { "\(grouped($0.kcal)) / \(grouped($0.kcalTarget))" }, shown.map { $0.kcalTarget > 0 ? Double($0.kcal) / Double($0.kcalTarget) : 0 })
                line("Protein", shown.map { "\($0.protein) / \($0.proteinTarget) g" }, shown.map { $0.proteinTarget > 0 ? Double($0.protein) / Double($0.proteinTarget) : 0 })
                line("Water", shown.map { "\(litres($0.waterMl)) / \(litres($0.waterTargetMl)) L" }, shown.map { $0.waterTargetMl > 0 ? Double($0.waterMl) / Double($0.waterTargetMl) : 0 })
            }
        case .inline:
            Text("\(Image(systemName: "fork.knife")) \(inlineText)")
        }
    }

    private var inlineText: String {
        guard let g = shown else { return "No food logged" }
        return grouped(g.kcal) + " kcal · " + String(g.protein) + " g protein"
    }

    private func line(_ label: String, _ value: String?, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 2)
                Text(value ?? "–").font(.system(size: 11, weight: .medium)).monospacedDigit().opacity(0.8)
            }
            .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule().fill(Color.white).frame(width: max(3, geo.size.width * min(1, max(0, fraction ?? 0))))
                }
            }
            .frame(height: 3)
            .widgetAccentable()
        }
    }
}

/// The label of the widget button that logs a glass of water.
public struct GlanceWaterChip: View {
    let ml: Int

    public init(ml: Int = 250) { self.ml = ml }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "plus").font(.system(size: 9, weight: .heavy))
            Text("\(ml) ml").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Luma.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Luma.sky))
        .accessibilityLabel("Log \(ml) millilitres of water")
    }
}

// MARK: - Plan

/// Today's sessions with their state, and what is first tomorrow.
public struct LumaPlanWidgetView: View {
    let glance: LumaGlance?
    let family: LumaWidgetFamily
    let current: Bool

    public init(glance: LumaGlance?, family: LumaWidgetFamily, current: Bool = true) {
        self.glance = glance; self.family = family; self.current = current
    }

    private var sessions: [LumaGlance.Session] { current ? (glance?.sessions ?? []) : [] }

    private func label(_ s: LumaGlance.Session) -> String {
        if let t = s.time { return t + " " + s.title }
        return s.title
    }

    public var body: some View {
        switch family {
        case .rectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Today").font(.system(size: 13, weight: .semibold))
                if sessions.isEmpty {
                    Text("Nothing planned").font(.system(size: 12.5)).opacity(0.75)
                } else {
                    ForEach(sessions.prefix(2)) { s in
                        Text("\(Image(systemName: s.done ? "checkmark.circle.fill" : "circle")) \(label(s))")
                            .font(.system(size: 12.5, weight: .medium)).lineLimit(1).opacity(s.done ? 0.65 : 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Text("\(Image(systemName: "calendar")) \(sessions.first(where: { !$0.done }).map(label) ?? "Nothing left today")")
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today").font(LumaFont.heading(13)).foregroundStyle(Luma.frost)
                    Spacer()
                    if !sessions.isEmpty {
                        Text("\(sessions.filter { $0.done }.count)/\(sessions.count)").font(LumaFont.numeral(15)).foregroundStyle(Luma.mist)
                    }
                }
                if sessions.isEmpty {
                    Spacer(minLength: 0)
                    Text(glance == nil ? "Open Luma to set up your week" : "Nothing planned. A rest day counts.").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                } else {
                    ForEach(sessions.prefix(family == .small ? 2 : 3)) { s in
                        HStack(spacing: 8) {
                            Image(systemName: s.done ? "checkmark" : s.symbol).font(.system(size: 10, weight: .bold))
                                .foregroundStyle(s.done ? Luma.ink : Luma.frost)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(s.done ? Luma.volt : Color.white.opacity(0.10)))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.title).font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.frost).lineLimit(1)
                                if let t = s.time { Text(t).font(LumaFont.numeral(12, .medium)).foregroundStyle(Luma.mist) }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if family != .small, let tomorrow = glance?.tomorrow, current {
                    Text("Tomorrow: \(tomorrow)").font(LumaFont.body(11)).foregroundStyle(Luma.smoke).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Brief

/// The coach's morning brief, or the day's call when no brief has been written.
public struct LumaBriefWidgetView: View {
    let glance: LumaGlance?
    let family: LumaWidgetFamily
    let current: Bool

    public init(glance: LumaGlance?, family: LumaWidgetFamily, current: Bool = true) {
        self.glance = glance; self.family = family; self.current = current
    }

    private var headline: String {
        guard let glance, current else { return "Open Luma to update" }
        return glance.call ?? "Open Luma to update"
    }

    private var text: String {
        guard let glance, current else { return "This widget last heard from Luma on an earlier day." }
        return glance.brief ?? glance.callDetail ?? "Open Luma for today's read."
    }

    public var body: some View {
        switch family {
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(text).font(.system(size: 12)).opacity(0.8).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Text("\(Image(systemName: "sparkles")) \(headline)")
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.aqua)
                    Text("Coach").font(LumaFont.label(10)).foregroundStyle(Luma.mist)
                    Spacer()
                    if let r = current ? glance?.recovery : nil {
                        Text("\(r)%").font(LumaFont.numeral(16)).foregroundStyle(Luma.recovery(Double(r)))
                    }
                }
                Text(headline).font(LumaFont.heading(15)).foregroundStyle(Luma.frost).lineLimit(2).minimumScaleFactor(0.8)
                Text(text).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).lineLimit(family == .large ? 12 : (family == .small ? 4 : 3))
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Heart rate and stress

/// The latest heart rate with the last three hours as a trace.
public struct LumaHeartWidgetView: View {
    let bpm: Int?
    let at: Date?
    let values: [Double]
    let resting: Int?

    public init(bpm: Int?, at: Date?, values: [Double], resting: Int?) {
        self.bpm = bpm; self.at = at; self.values = values; self.resting = resting
    }

    public var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Luma.coral)
                    Text("Heart rate").font(LumaFont.label(9.5)).foregroundStyle(Luma.mist)
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(bpm.map { "\($0)" } ?? "–").font(LumaFont.numeral(50)).foregroundStyle(bpm == nil ? Luma.smoke : Luma.frost)
                    Text("bpm").font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist)
                }
                if let at, bpm != nil {
                    Text("\(Text(at, style: .relative)) ago").font(LumaFont.body(10.5)).foregroundStyle(Luma.smoke).lineLimit(1)
                } else {
                    Text("No reading yet").font(LumaFont.body(10.5)).foregroundStyle(Luma.smoke)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: 4) {
                if values.count >= 3 {
                    LumaSparkline(values: values, color: Luma.coral)
                    HStack(spacing: 8) {
                        Text("3 h").font(LumaFont.label(8.5)).foregroundStyle(Luma.smoke)
                        Spacer()
                        Text("\(whole(values.min() ?? 0))–\(whole(values.max() ?? 0))").font(LumaFont.numeral(12, .medium)).foregroundStyle(Luma.mist)
                        if let resting { Text("resting \(resting)").font(LumaFont.body(10)).foregroundStyle(Luma.smoke) }
                    }
                } else {
                    Spacer(minLength: 0)
                    Text("The trace fills in as the strap streams.").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke).multilineTextAlignment(.trailing)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Today's stress, hour by hour. Levels run 0 (calm) to 3 (high); nil is an hour without a score.
public struct LumaStressWidgetView: View {
    let hours: [(hour: Int, level: Double?)]

    public init(hours: [(hour: Int, level: Double?)]) { self.hours = hours }

    private var latest: Double? { hours.last(where: { $0.level != nil })?.level }

    private func color(_ level: Double) -> Color { level < 1 ? Luma.aqua : (level < 2 ? Luma.amber : Luma.coral) }
    private func word(_ level: Double) -> String { level < 1 ? "Calm" : (level < 2 ? "Moderate" : "High") }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stress").font(LumaFont.label(9.5)).foregroundStyle(Luma.mist)
                Spacer()
                if let latest {
                    Text(word(latest)).font(LumaFont.heading(13)).foregroundStyle(color(latest))
                }
            }
            if hours.contains(where: { $0.level != nil }) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { _, h in
                        GeometryReader { geo in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(h.level.map { color($0) } ?? Color.white.opacity(0.07))
                                    .frame(height: max(3, geo.size.height * CGFloat(min(3, h.level ?? 0.15) / 3)))
                            }
                        }
                    }
                }
                HStack {
                    Text(hours.first.map { String(format: "%02d:00", $0.hour) } ?? "").font(LumaFont.label(8)).foregroundStyle(Luma.smoke)
                    Spacer()
                    Text("now").font(LumaFont.label(8)).foregroundStyle(Luma.smoke)
                }
            } else {
                Spacer(minLength: 0)
                Text("Stress is scored through the day from heart rate and its variability while you are still.")
                    .font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                Spacer(minLength: 0)
            }
        }
    }
}
