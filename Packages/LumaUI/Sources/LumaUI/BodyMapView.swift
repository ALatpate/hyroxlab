import SwiftUI
import LumaCore
import LumaKit

// MARK: - The figure

extension Path {
    /// The closed smooth curve through an outline's points, placed in a view.
    init(outline: [BodyPoint], scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        self.init()
        let curve = BodyMap.curve(outline)
        func place(_ p: BodyPoint) -> CGPoint { CGPoint(x: dx + CGFloat(p.x) * scale, y: dy + CGFloat(p.y) * scale) }
        move(to: place(curve.start))
        for s in curve.segments { addCurve(to: place(s.end), control1: place(s.control1), control2: place(s.control2)) }
        closeSubpath()
    }
}

/// One side of the body, each muscle area filled with the colour it is given. An area given no
/// colour has nothing to show: it is drawn as a dashed outline, so "not measured" never reads as "low".
struct BodyFigure: View {
    let side: BodySide
    let tint: (Muscle) -> Color?
    /// What the figure shows for a muscle, in words, for someone who cannot see its colours.
    let describe: (Muscle) -> String
    var selected: Muscle? = nil
    var onSelect: ((Muscle) -> Void)? = nil

    private struct Area {
        let muscle: Muscle
        let path: Path
    }

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = min(geo.size.width / CGFloat(BodyMap.width), geo.size.height / CGFloat(BodyMap.height))
            let dx: CGFloat = (geo.size.width - CGFloat(BodyMap.width) * scale) / 2
            let dy: CGFloat = (geo.size.height - CGFloat(BodyMap.height) * scale) / 2
            let base: [Path] = BodyMap.silhouette.map { Path(outline: $0, scale: scale, dx: dx, dy: dy) }
            let areas: [Area] = BodyMap.regions(side).flatMap { region in
                region.outlines.map { Area(muscle: region.muscle, path: Path(outline: $0, scale: scale, dx: dx, dy: dy)) }
            }
            Canvas { context, _ in
                for p in base { context.fill(p, with: .color(Luma.smoke.opacity(0.32))) }
                for a in areas {
                    if let color = tint(a.muscle) {
                        context.fill(a.path, with: .color(color))
                    } else {
                        context.stroke(a.path, with: .color(Luma.mist.opacity(0.7)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                    }
                }
                for a in areas where a.muscle == selected {
                    context.stroke(a.path, with: .color(Luma.frost), lineWidth: 1.8)
                }
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap in
                if let m = BodyFigure.hit(tap.location, in: areas.map { ($0.muscle, $0.path) }) { onSelect?(m) }
            })
        }
        .aspectRatio(CGFloat(BodyMap.width / BodyMap.height), contentMode: .fit)
        .accessibilityLabel("\(side.title) of the body")
        .accessibilityChildren {
            ForEach(BodyMap.muscles(on: side)) { m in
                Button(describe(m)) { onSelect?(m) }
            }
        }
    }

    /// The muscle under a tap. Small areas are hard to hit, so a near miss counts: the tap is tried
    /// again a little way off in each direction.
    static func hit(_ point: CGPoint, in areas: [(Muscle, Path)]) -> Muscle? {
        if let exact = areas.last(where: { $0.1.contains(point) }) { return exact.0 }
        let steps: [CGFloat] = [6, 12]
        let directions: [CGPoint] = [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1),
                                     CGPoint(x: 0.7, y: 0.7), CGPoint(x: -0.7, y: 0.7), CGPoint(x: 0.7, y: -0.7), CGPoint(x: -0.7, y: -0.7)]
        for r in steps {
            for d in directions {
                let near = CGPoint(x: point.x + d.x * r, y: point.y + d.y * r)
                if let found = areas.last(where: { $0.1.contains(near) }) { return found.0 }
            }
        }
        return nil
    }
}

// MARK: - What the figure shows

/// What the body map is coloured by.
enum BodyMode: String, CaseIterable {
    case strength, progress, work

    var title: String {
        switch self {
        case .strength: return "Strength"
        case .progress: return "Progress"
        case .work: return "Work"
        }
    }

    var caption: String {
        switch self {
        case .strength:
            return "Each muscle takes the level of the lift that measures it: your estimated max against your bodyweight, on Luma's scale. Tap a muscle for the lift behind it."
        case .progress:
            return "How that lift's estimated max has moved: the best of the last six weeks against the six before. Tap a muscle for the numbers."
        case .work:
            return "Sets in the last seven days. A set that trains the muscle directly counts 1, one where it assists counts ½. Runs and ergs are not counted."
        }
    }
}

enum BodyColors {
    /// Luma's scale, Starting to Exceptional.
    static func level(_ level: Double) -> Color {
        switch StrengthLevel(level) {
        case .starting: return Luma.smoke
        case .building: return Luma.dusk
        case .solid: return Luma.sky
        case .strong: return Luma.aqua
        case .veryStrong: return Luma.mint
        case .exceptional: return Luma.volt
        }
    }

    static func trend(_ trend: ProgressTrend) -> Color {
        switch trend {
        case .up: return Luma.volt
        case .steady: return Luma.sky
        case .down: return Luma.coral
        }
    }

    static func band(_ band: SetBand) -> Color? {
        switch band {
        case .none: return nil
        case .low: return Luma.ember.opacity(0.32)
        case .middle: return Luma.ember.opacity(0.62)
        case .high: return Luma.ember
        }
    }

    /// The same fact the colour carries, in words.
    static func words(_ state: MuscleState, mode: BodyMode) -> String {
        let name = state.muscle.title
        switch mode {
        case .strength: return name + ": " + (state.level.map { StrengthLevel($0).title } ?? "not measured")
        case .progress: return name + ": " + (state.trend?.title.lowercased() ?? "nothing to compare")
        case .work: return name + ": " + ProgressText.sets(state.weekSets) + " in the last seven days"
        }
    }

    static func tint(_ state: MuscleState, mode: BodyMode) -> Color? {
        switch mode {
        case .strength: return state.level.map { level($0) }
        case .progress: return state.trend.map { trend($0) }
        case .work: return band(state.band)
        }
    }
}

extension ProgressTrend {
    var title: String {
        switch self {
        case .up: return "Climbing"
        case .steady: return "Steady"
        case .down: return "Slipping"
        }
    }

    var symbol: String {
        switch self {
        case .up: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .down: return "arrow.down.right"
        }
    }
}

/// A swatch and its meaning.
struct BodyKey: View {
    let color: Color?
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            if let color {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 11, height: 11)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Luma.smoke, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 11, height: 11)
            }
            Text(text).font(LumaFont.body(11.5)).foregroundStyle(Luma.mist)
        }
    }
}

struct BodyLegend: View {
    let mode: BodyMode

    var body: some View {
        FlowLayout(spacing: 10) {
            switch mode {
            case .strength:
                ForEach(StrengthLevel.allCases, id: \.rawValue) { l in
                    BodyKey(color: BodyColors.level(Double(l.rawValue)), text: l.title)
                }
                BodyKey(color: nil, text: "Not measured")
            case .progress:
                BodyKey(color: BodyColors.trend(.up), text: "Climbing")
                BodyKey(color: BodyColors.trend(.steady), text: "Steady")
                BodyKey(color: BodyColors.trend(.down), text: "Slipping")
                BodyKey(color: nil, text: "Nothing to compare")
            case .work:
                BodyKey(color: BodyColors.band(.high), text: "10 or more sets")
                BodyKey(color: BodyColors.band(.middle), text: "5 to 9")
                BodyKey(color: BodyColors.band(.low), text: "Under 5")
                BodyKey(color: nil, text: "None")
            }
        }
    }
}

// MARK: - The card

/// Front and back of the body, coloured by strength, by progress or by the week's work, with the
/// facts behind whichever muscle is tapped.
struct BodyMapCard: View {
    let progress: TrainingProgress
    let today: String
    // The screenshot harness can open the card on another view of the figure, or with a muscle picked.
    @State private var mode: BodyMode = LumaLaunch.page == 1 ? .progress : (LumaLaunch.page == 2 ? .work : .strength)
    @State private var selected: Muscle? = LumaLaunch.page == 3 ? .quads : nil

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 14) {
                LumaSegmented(selection: $mode, options: BodyMode.allCases.map { (value: $0, title: $0.title) }, tint: Luma.frost)
                HStack(alignment: .top, spacing: 6) {
                    figure(.front)
                    figure(.back)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                BodyLegend(mode: mode)
                if let m = selected {
                    MuscleFacts(state: progress.state(m), today: today) { selected = nil }
                } else {
                    LumaNote(mode.caption)
                }
            }
        }
    }

    private func figure(_ side: BodySide) -> some View {
        VStack(spacing: 6) {
            BodyFigure(side: side, tint: { BodyColors.tint(progress.state($0), mode: mode) },
                       describe: { BodyColors.words(progress.state($0), mode: mode) }, selected: selected) { m in
                LumaHaptics.tap()
                selected = selected == m ? nil : m
            }
            LumaLabel(side.title)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Everything Luma knows about one muscle, in words: its level and the lift behind it, how that lift
/// has moved, and the week's work.
struct MuscleFacts: View {
    let state: MuscleState
    let today: String
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(state.muscle.title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                if let level = state.level {
                    LumaPill(text: StrengthLevel(level).title, color: BodyColors.level(level))
                } else {
                    LumaPill(text: "Not measured", color: Luma.smoke)
                }
                Spacer(minLength: 4)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.smoke).frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            fact("scalemass.fill", strengthLine)
            fact("chart.line.uptrend.xyaxis", progressLine)
            fact("square.stack.3d.up.fill", workLine)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func fact(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Luma.mist).frame(width: 16)
            Text(text).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var strengthLine: String {
        if let b = state.basis { return "Read from your \(b.name.lowercased()): \(b.figure)." }
        let gauges = ExerciseLibrary.gauges(of: state.muscle)
        if gauges.isEmpty { return "No lift Luma grades measures this muscle on its own, so it has no level. The Work view shows how much you train it." }
        let names = gauges.prefix(3).map { $0.lowercased() }.joined(separator: ", ")
        return "No graded lift with a load in the last twelve weeks measures it. Logging one of these would: \(names)."
    }

    private var progressLine: String {
        guard let b = state.basis else { return "Nothing to compare yet." }
        guard let change = b.change, let recent = b.recentBest, let before = b.previousBest else {
            return "No figure from the six weeks before to compare with yet."
        }
        let pct = String(format: "%.0f%%", abs(change) * 100)
        let from = String(format: "%.0f", before)
        let to = String(format: "%.0f", recent)
        switch b.trend ?? .steady {
        case .up: return "Up \(pct) in six weeks (\(from) to \(to) kg)."
        case .down: return "Down \(pct) in six weeks (\(from) to \(to) kg)."
        case .steady: return "Steady over six weeks (\(from) to \(to) kg)."
        }
    }

    private var workLine: String {
        var parts: [String] = []
        let week = ProgressText.sets(state.weekSets)
        if let usual = state.usualSets {
            parts.append("\(week) in the last seven days, usually \(ProgressText.count(usual)) a week")
        } else {
            parts.append("\(week) in the last seven days")
        }
        if let last = state.lastDirect { parts.append("last direct work \(LumaText.dayTitle(last, today: today).lowercased())") }
        var text = parts.joined(separator: "; ") + "."
        if !state.movements.isEmpty { text += " Trained by " + state.movements.map { $0.lowercased() }.joined(separator: ", ") + "." }
        return text
    }
}

enum ProgressText {
    /// Sets to the nearest half: "7", "7.5".
    static func count(_ v: Double) -> String {
        let half = (v * 2).rounded() / 2
        return half == half.rounded() ? String(Int(half)) : String(format: "%.1f", half)
    }

    static func sets(_ v: Double) -> String {
        let n = count(v)
        return n == "1" ? "1 set" : "\(n) sets"
    }
}
