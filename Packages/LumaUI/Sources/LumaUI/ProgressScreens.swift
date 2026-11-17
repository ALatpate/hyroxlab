import SwiftUI
import LumaCore
import LumaKit

// MARK: - Progress

/// The Progress face of the Train tab: what the training, food and supplement logs add up to.
struct TrainProgressView: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let p = env.progress
        VStack(alignment: .leading, spacing: 18) {
            if p.sessionsLogged == 0 {
                ProgressEmpty()
            } else {
                BodyMapCard(progress: p, today: env.today)
                ProgressNotes(title: "Strong points", symbol: "bolt.fill", color: Luma.volt, notes: p.strengths,
                              empty: "Log a lift with its load a few times and Luma will grade it against your bodyweight.")
                ProgressNotes(title: "Weak points", symbol: "exclamationmark.triangle.fill", color: Luma.amber, notes: p.weakPoints,
                              empty: "Nothing stands out. Luma looks for a lift graded well below your others, a lift that is slipping, and muscle groups no session has reached in two weeks.")
                LiftProgressList(lifts: p.lifts)
                MuscleWorkCard(muscles: p.muscles)
                LoggedMixCard(mix: p.mix)
            }
            FuelTrainingCard(read: p.fuel)
            SupplementCard(reads: p.supplements)
            HabitEffectsCard(effects: env.analysis.effects)
            LumaQuickAction(symbol: "sparkles", title: "Ask the coach about my progress", tint: Luma.volt) {
                router.askCoach("Look at my progress: lifts, muscles, weak points, how my food and supplements line up with my training. What should I change in the next four weeks?")
            }
        }
    }
}

private struct ProgressEmpty: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        LumaCard(tint: Luma.volt.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nothing logged yet").font(LumaFont.title(22)).foregroundStyle(Luma.frost)
                LumaNote("Progress is built from what you did in each session: the movements, the sets and the loads. Add your sessions from photos of the board or your tracking app, or log a strength session set by set.")
                Button { router.sheet = .workoutPhotos(env.today) } label: {
                    Label("Add from photos", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                }
                .buttonStyle(LumaPrimaryButtonStyle())
                Button { router.cover = .lift } label: { Label("Log a strength session", systemImage: "dumbbell.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(LumaSecondaryButtonStyle())
            }
        }
    }
}

private struct ProgressHeader: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.14)))
            Text(title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
        }
    }
}

struct ProgressNotes: View {
    let title: String
    let symbol: String
    let color: Color
    let notes: [ProgressNote]
    let empty: String

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressHeader(title: title, symbol: symbol, color: color)
                if notes.isEmpty { LumaNote(empty) }
                ForEach(notes) { n in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.title).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        Text(n.detail).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: Lifts

struct LiftProgressList: View {
    let lifts: [LiftProgress]
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        if !lifts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LumaSection(title: "Lifts", action: "Training log") { router.push(.strength) }
                LumaGroup {
                    ForEach(lifts.prefix(8)) { LiftProgressRow(lift: $0) }
                }
                LumaNote("Estimated max, worked out from your sets of 12 reps or fewer. Pull-ups, chin-ups and dips count your bodyweight plus any load added. The level is Luma's own scale of bodyweight multiples for each lift, not a ranking against other people.")
            }
        }
    }
}

struct LiftProgressRow: View {
    let lift: LiftProgress

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lift.name).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                if let level = lift.level {
                    BodyKey(color: BodyColors.level(level), text: levelLine(level))
                } else {
                    Text(lift.current == nil ? "Not lifted in twelve weeks" : "Not graded").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
                }
            }
            Spacer(minLength: 8)
            if lift.points.count >= 2 {
                GappedSparkline(values: lift.points.suffix(12).map { Optional($0.e1RM) }, color: trendColor)
                    .frame(width: 52, height: 22)
            }
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.0f", lift.current ?? lift.allTime)).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                    Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                }
                Text(changeLine).font(LumaFont.body(11.5, .semibold)).foregroundStyle(trendColor)
            }
            .frame(minWidth: 58, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private func levelLine(_ level: Double) -> String {
        let name = StrengthLevel(level).title
        guard let r = lift.ratio else { return name }
        return name + String(format: " · %.1f × bodyweight", r)
    }

    private var trendColor: Color {
        guard let t = lift.trend else { return Luma.mist }
        return BodyColors.trend(t)
    }

    private var changeLine: String {
        guard let c = lift.change, let t = lift.trend else { return lift.current == nil ? "best ever" : "new" }
        if t == .steady { return "steady" }
        return String(format: "%@%.0f%%", c > 0 ? "+" : "−", abs(c) * 100)
    }
}

// MARK: Work by muscle

/// The week's sets for every muscle that had any, most first, with a tick where the athlete's usual week sits.
struct MuscleWorkCard: View {
    let muscles: [MuscleState]

    var body: some View {
        let worked = muscles.filter { $0.weekSets > 0 || ($0.usualSets ?? 0) > 0 }.sorted { $0.weekSets > $1.weekSets }
        let top: Double = max(12, worked.map { max($0.weekSets, $0.usualSets ?? 0) }.max() ?? 12)
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressHeader(title: "Sets by muscle, last 7 days", symbol: "square.stack.3d.up.fill", color: Luma.ember)
                if worked.isEmpty {
                    LumaNote("No sets logged in the last seven days.")
                } else {
                    ForEach(worked) { MuscleWorkRow(state: $0, top: top) }
                    LumaNote("Direct work counts 1, assisting work ½; runs and ergs are not counted. The tick is your weekly average over the four weeks before. Studies that compared weekly sets for a muscle grouped them as under 5, 5 to 9, and 10 or more, and found more growth with more sets, mostly in people new to lifting. Treat it as a guide, not a target.")
                }
            }
        }
    }
}

private struct MuscleWorkRow: View {
    let state: MuscleState
    let top: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(state.muscle.title).font(LumaFont.body(13.5)).foregroundStyle(Luma.frost).frame(width: 92, alignment: .leading)
            GeometryReader { geo in
                let width: CGFloat = geo.size.width
                let filled: CGFloat = width * CGFloat(min(1, state.weekSets / top))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    if state.weekSets > 0 {
                        Capsule().fill(BodyColors.band(state.band) ?? Luma.ember).frame(width: max(8, filled))
                    }
                    if let usual = state.usualSets, usual > 0 {
                        Rectangle().fill(Luma.frost).frame(width: 2, height: 14)
                            .offset(x: min(width - 2, width * CGFloat(usual / top)))
                    }
                }
            }
            .frame(height: 8)
            Text(ProgressText.count(state.weekSets)).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.frost)
                .frame(width: 34, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        var text = "\(state.muscle.title), \(ProgressText.sets(state.weekSets))"
        if let u = state.usualSets { text += ", usually \(ProgressText.count(u))" }
        return text
    }
}

// MARK: Training mix

struct LoggedMixCard: View {
    let mix: [KindCount]

    var body: some View {
        let total = mix.reduce(0) { $0 + $1.count }
        if total > 0 {
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressHeader(title: "Sessions logged, last 4 weeks", symbol: "calendar", color: Luma.volt)
                    FlowLayout(spacing: 8) {
                        ForEach(mix) { m in
                            LumaPill(text: "\(m.count) × \(m.kind.title)", color: m.kind.sport.tone.color, symbol: m.kind.sport.symbol)
                        }
                    }
                }
            }
        }
    }
}

// MARK: Fuel beside training

struct FuelTrainingCard: View {
    let read: FuelTrainingRead?

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressHeader(title: "Food against training", symbol: "fork.knife", color: Luma.mint)
                if let r = read {
                    HStack(alignment: .top, spacing: 12) {
                        figure(r.proteinPerKg.map { String(format: "%.1f", $0) } ?? "–", "g protein per kg",
                               String(format: "target %.1f", r.proteinTargetPerKg))
                        figure("\(r.proteinDaysMet)/\(r.loggedDays)", "days at target", "of the days logged")
                        figure("\(r.loggedDays)/\(r.window)", "days logged", "with a full log")
                    }
                    if r.trainingDays > 0 && r.restDays > 0 {
                        LumaDivider()
                        split("Training days", r.trainingDays, r.trainingKcal, r.trainingCarbsPerKg)
                        split("Rest days", r.restDays, r.restKcal, r.restCarbsPerKg)
                    }
                    LumaNote("The 14 days before today. A day counts when it has at least two food entries and 1,000 kcal; the rest are taken as under-logged, not under-eaten.")
                } else {
                    LumaNote("No day in the last two weeks has a full food log (two entries and 1,000 kcal). Log your meals and Luma sets your protein and energy against the days you train.")
                }
            }
        }
    }

    private func figure(_ value: String, _ label: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(LumaFont.numeral(26)).foregroundStyle(Luma.frost)
            Text(label).font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist)
            Text(note).font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func split(_ title: String, _ days: Int, _ kcal: Double?, _ carbs: Double?) -> some View {
        let energy: String = kcal.map { LFormat.grouped($0) + " kcal" } ?? "–"
        let carb: String = carbs.map { String(format: "%.1f g carbs per kg", $0) } ?? "–"
        return HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                Text(days == 1 ? "1 day logged" : "\(days) days logged").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(energy).font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.frost)
                Text(carb).font(LumaFont.body(11.5)).foregroundStyle(Luma.mist)
            }
        }
    }
}

// MARK: Supplements

struct SupplementCard: View {
    let reads: [SupplementRead]

    var body: some View {
        if !reads.isEmpty {
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressHeader(title: "Supplements, last 14 days", symbol: "pills.fill", color: Luma.mint)
                    ForEach(reads) { r in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(r.name).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                                Spacer(minLength: 8)
                                Text(line(r)).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                            }
                            LumaBar(value: Double(r.daysTaken), total: Double(r.window), color: Luma.mint, height: 6)
                        }
                    }
                    LumaNote("Counted from the first day each one was logged, so a new supplement is not marked down for the days before it.")
                }
            }
        }
    }

    private func line(_ r: SupplementRead) -> String {
        var text = "\(r.daysTaken) of \(r.window) days"
        if r.streak >= 2 { text += " · \(r.streak) in a row" }
        return text
    }
}

// MARK: Habits

/// What the logs say about the morning after: the strongest few of the habit effects Luma has found.
struct HabitEffectsCard: View {
    let effects: [EffectFinding]
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                ProgressHeader(title: "What moves your mornings", symbol: "checklist", color: Luma.aqua)
                if effects.isEmpty {
                    LumaNote("Nothing yet. Luma compares the morning after a habit with the mornings without it: alcohol, caffeine after 2 pm, a late meal, a day at your protein target, each supplement. It needs at least four nights with a habit and eight without before it says anything.")
                } else {
                    ForEach(effects.prefix(4)) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: symbol(e)).font(.system(size: 11, weight: .bold)).foregroundStyle(color(e)).frame(width: 16)
                            Text(e.sentence).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LumaNote("These are patterns in your own nights, not proof of cause: a habit may travel with something else that does the work.")
                    Button { router.open(.today, .insights) } label: {
                        Label("All patterns", systemImage: "chevron.right").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.volt)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func symbol(_ e: EffectFinding) -> String {
        switch e.helps {
        case .some(true): return "arrow.up.right"
        case .some(false): return "arrow.down.right"
        case .none: return "arrow.right"
        }
    }

    private func color(_ e: EffectFinding) -> Color {
        switch e.helps {
        case .some(true): return Luma.volt
        case .some(false): return Luma.coral
        case .none: return Luma.mist
        }
    }
}
