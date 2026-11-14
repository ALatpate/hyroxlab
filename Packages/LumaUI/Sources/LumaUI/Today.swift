import SwiftUI
import LumaCore
import LumaKit

/// Today: how recovered you are, what the day is good for, and the day so far.
struct TodayScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var hr: [LHRPoint] = []
    @State private var stress: LStressDay?

    private var a: LumaAnalysis { env.analysis }
    private var dateLine: String { Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) }

    var body: some View {
        LumaTabScreen(title: env.profile.name.isEmpty ? LumaText.greeting() : "\(LumaText.greeting()), \(env.profile.name)",
                      subtitle: dateLine, tone: .recovery) {
            HStack(spacing: 8) {
                StrapChip()
                LumaIconButton(symbol: "person.fill") { router.sheet = .you }
            }
        } content: {
            SwitchedOffNote()
            if a.watch.level >= .watch, a.lastNight?.day == a.today { WatchBanner(watch: a.watch) }
            TodayHero(analysis: a, strainOn21: env.profile.strainOn21)
            CallCard(call: a.call, strain21: a.day?.strain.map(LScale.strain21), on21: env.profile.strainOn21)
            CoachBriefCard()
            Group {
                SuggestedSessionPrompt()
                PlanCard()
            }
            HeartStrip(points: hr)
            TodayVitals(analysis: a, stress: stress)
            FuelGlance()
            CheckInPrompt()
        }
        .task(id: env.days.count) {
            guard let start = LDate.startOfDay(a.today)?.timeIntervalSince1970 else { return }
            hr = await env.source.heartRate(from: start, to: start + 86_400, bucketSeconds: 600)
            stress = await env.source.stress(day: a.today)
        }
    }
}

// MARK: - Header chip

/// Strap state at a glance: a status light and the battery.
struct StrapChip: View {
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let s = live.strap
        Button {
            router.sheet = nil
            router.open(.today, .devices)
        } label: {
            HStack(spacing: 6) {
                Circle().fill(s.connected ? (s.secure ? Luma.volt : Luma.amber) : Luma.smoke).frame(width: 7, height: 7)
                    .shadow(color: s.connected ? Luma.volt.opacity(0.8) : .clear, radius: 4)
                if let b = s.battery {
                    // Dimmed while the strap is away: the figure is then the last one it sent.
                    Text("\(Int(b.rounded()))%").font(LumaFont.numeral(15, .semibold)).foregroundStyle(s.connected ? Luma.frost : Luma.mist)
                    Image(systemName: s.charging ? "battery.100.bolt" : (b > 60 ? "battery.75" : b > 25 ? "battery.50" : "battery.25"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(b <= 20 ? Luma.coral : Luma.mist)
                } else {
                    Text(s.connected ? "Strap" : "Offline").font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Luma.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hero

/// The Lumen with the recovery score, flanked by the day's three headline numbers.
struct TodayHero: View {
    let analysis: LumaAnalysis
    let strainOn21: Bool
    @EnvironmentObject private var router: LumaRouter
    @State private var shown: Double = 0

    private var scored: LDay? { analysis.lastNight?.day == analysis.today ? analysis.lastNight : nil }

    var body: some View {
        let score = scored?.recovery
        let color = Luma.recovery(score)
        VStack(spacing: 6) {
            Button { router.push(.recovery) } label: {
                ZStack {
                    LumaOrb(progress: shown / 100, color: color, partner: score == nil ? Luma.smoke : (score ?? 0) >= 67 ? Luma.mint : color)
                    VStack(spacing: -4) {
                        if score != nil {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                RollingNumber(value: shown) { String(format: "%.0f", $0) }
                                    .font(LumaFont.numeral(92, .heavy))
                                Text("%").font(LumaFont.numeral(30, .bold)).foregroundStyle(Luma.mist)
                            }
                            .foregroundStyle(Luma.frost)
                        } else {
                            Text("–").font(LumaFont.numeral(92, .heavy)).foregroundStyle(Luma.smoke)
                        }
                        Text("Recovery").font(LumaFont.label(12)).foregroundStyle(Luma.mist)
                    }
                }
                .frame(height: 268)
            }
            .buttonStyle(.plain)

            if score == nil {
                Text(analysis.lastNight.map { "Last scored night: \(LumaText.dayTitle($0.day, today: analysis.today).lowercased()), \(Int(($0.recovery ?? 0).rounded()))%" }
                     ?? "No night scored yet. Wear the strap overnight, then sync.")
                    .font(LumaFont.body(13)).foregroundStyle(Luma.mist).multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                heroStat("Strain", value: analysis.day?.strain.map { LScale.shown($0, on21: strainOn21) }, decimals: strainOn21 ? 1 : 0, unit: "", tone: .strain, dest: .strain)
                heroStat("Sleep", value: analysis.sleep.last.flatMap { $0.day == analysis.today ? $0.asleepMin / 60 : nil }, decimals: 1, unit: "h", tone: .sleep, dest: .sleep)
                heroStat("HRV", value: scored?.hrv, decimals: 0, unit: "ms", tone: .hrv, dest: .heart)
            }
            .padding(.top, 4)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.2).delay(0.15)) { shown = score ?? 0 } }
        .onChange(of: score) { _, new in withAnimation(.easeOut(duration: 0.8)) { shown = new ?? 0 } }
    }

    private func heroStat(_ label: String, value: Double?, decimals: Int, unit: String, tone: LumaTone, dest: LumaDest) -> some View {
        Button { router.push(dest) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(tone.color).frame(width: 6, height: 6).shadow(color: tone.color, radius: 3)
                    LumaLabel(label)
                }
                LumaFigure(value: value, decimals: decimals, unit: unit, size: 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(radius: 20))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Carried over

/// After an update from an earlier version of the app: what that version had been left doing on its
/// own (an alarm, a reminder) and this one switched off, because nothing here could manage it.
struct SwitchedOffNote: View {
    @EnvironmentObject private var live: LumaLive

    var body: some View {
        if !live.switchedOff.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.slash.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.sky)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switched off after the update").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                    Text("Luma has no screen yet for alarms and reminders set up in the earlier version, so what was on there has been switched off: \(live.switchedOff.joined(separator: ", ")).")
                        .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { withAnimation(.easeOut(duration: 0.2)) { live.switchedOff = [] } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.mist)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(tint: Luma.sky, radius: 22))
        }
    }
}

/// A pointer on Today to a session the strap saw and nobody recorded. The choice is made on Train.
struct SuggestedSessionPrompt: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        if let s = env.suggestions.first {
            Button { router.tab = .train } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.ink)
                        .frame(width: 40, height: 40).background(Circle().fill(Luma.volt))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Looks like a session").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                        Text(LumaText.line([LumaText.dayTitle(s.day, today: env.today), LumaText.time(s.start),
                                            "\(Int((s.durationS / 60).rounded())) min", "average \(Int(s.avgHR.rounded())) bpm"]))
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text("Review").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.volt)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LumaPanel(tint: Luma.volt.opacity(0.4), radius: 20))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Warning banner

struct WatchBanner: View {
    let watch: BodyWatch

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16, weight: .bold))
                .foregroundStyle(watch.level == .alert ? Luma.coral : Luma.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(watch.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                Text(watch.detail).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumaPanel(tint: watch.level == .alert ? Luma.coral : Luma.amber, radius: 22))
    }
}

// MARK: - The call

/// What today is good for, with the strain it suggests and how far along the day is.
struct CallCard: View {
    let call: DayCall
    let strain21: Double?
    var on21: Bool = true

    private var targetText: String? {
        guard let t = call.strainTarget else { return nil }
        let lo = Int(LScale.shownFrom21(t.lowerBound, on21: on21).rounded()), hi = Int(LScale.shownFrom21(t.upperBound, on21: on21).rounded())
        return "Aim for strain \(lo)–\(hi)"
    }

    private var color: Color {
        switch call.level {
        case .push: return Luma.volt
        case .build, .steady: return Luma.amber
        case .easy, .rest: return Luma.coral
        case .unknown: return Luma.mist
        }
    }

    var body: some View {
        LumaCard(tint: color.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LumaLabel("Today's call")
                    Spacer()
                    if let targetText { LumaPill(text: targetText, color: color) }
                }
                Text(call.title).font(LumaFont.title(24)).foregroundStyle(Luma.frost)
                Text(call.body).font(LumaFont.body(15)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                if let t = call.strainTarget {
                    StrainTrack(target: t, current: strain21, color: color)
                }
                if !call.reasons.isEmpty {
                    Text(call.reasons.joined(separator: "  ·  ")).font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                }
            }
        }
    }
}

/// The 0–21 strain scale with today's target range lit and a marker for strain so far.
struct StrainTrack: View {
    let target: ClosedRange<Double>
    let current: Double?
    let color: Color
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 8)
                Capsule().fill(color.opacity(0.45))
                    .frame(width: w * CGFloat((target.upperBound - target.lowerBound) / 21), height: 8)
                    .offset(x: w * CGFloat(target.lowerBound / 21))
                if current != nil {
                    Circle().fill(Luma.frost).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Luma.night, lineWidth: 3))
                        .shadow(color: .white.opacity(0.5), radius: 5)
                        .offset(x: max(0, min(w - 14, w * CGFloat(shown / 21) - 7)))
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.3)) { shown = current ?? 0 } }
        .onChange(of: current) { _, new in withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = new ?? 0 } }
    }
}

// MARK: - Plan

/// Today's planned sessions and whether they are done, or a way to add one.
struct PlanCard: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let day = env.scheduleDays([env.today]).first
        let planned = day?.planned.filter { $0.status != .skipped } ?? []
        let extra = day?.unplannedWorkouts ?? []
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LumaLabel("Today's training")
                    Spacer()
                    Button { router.tab = .train } label: {
                        Text("Calendar").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist)
                    }
                    .buttonStyle(.plain)
                }
                if planned.isEmpty && extra.isEmpty {
                    Text("Nothing planned").font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Text("Add a session, or start one now and it will appear here.").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    HStack(spacing: 10) {
                        Button("Add session") { router.sheet = .plan(nil, env.today) }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                        Button("Start now") { router.sheet = .go }.buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    }
                }
                ForEach(planned) { p in
                    let done = day?.isDone(p) ?? false
                    HStack(spacing: 12) {
                        Image(systemName: done ? "checkmark" : p.kind.sport.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(done ? Luma.ink : Luma.frost)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(done ? Luma.volt : Color.white.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                            Text(planLine(p, done: done)).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                        }
                        Spacer(minLength: 6)
                        if !done {
                            Button("Start") { router.sheet = .go }.buttonStyle(LumaPrimaryButtonStyle(compact: true))
                        }
                    }
                }
                ForEach(extra) { w in
                    Button { router.open(.train, .workout(w.id)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: w.kind.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.ink)
                                .frame(width: 40, height: 40).background(Circle().fill(Luma.volt))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.sport).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                                Text("\(LumaText.time(w.start)) · \(LumaText.duration(w.durationS))").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func planLine(_ p: PlannedSession, done: Bool) -> String {
        var parts: [String] = []
        if let m = p.startMinutes { parts.append(LFormat.timeOfDay(minutes: Double(m))) }
        parts.append("\(p.durationMin) min")
        parts.append(done ? "Done" : p.intensity.title)
        return parts.joined(separator: " · ")
    }
}

// MARK: - Heart strip

/// Live heart rate beside the day's trace.
struct HeartStrip: View {
    let points: [LHRPoint]
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @State private var beat = false

    var body: some View {
        let liveHR = live.strap.liveHeartRate()
        Button { router.push(.heart) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.coral)
                            .scaleEffect(beat ? 1.25 : 1)
                        LumaLabel(liveHR == nil ? "Heart rate" : "Live heart rate")
                    }
                    LumaFigure(value: (liveHR ?? live.strap.heartRate).map(Double.init), unit: "bpm", size: 40)
                    if liveHR == nil, let at = live.strap.heartRateAt {
                        Text("Last reading \(at.formatted(.relative(presentation: .named)))").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                    }
                }
                Spacer(minLength: 8)
                if points.count > 3 {
                    LumaSparkline(values: points.map { $0.bpm }, color: Luma.coral)
                        .frame(width: 150, height: 52)
                }
            }
            .padding(18)
            .background(LumaPanel())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { beat = true }
        }
    }
}

// MARK: - Vitals grid

struct TodayVitals: View {
    let analysis: LumaAnalysis
    let stress: LStressDay?
    @EnvironmentObject private var router: LumaRouter

    private var night: LDay? { analysis.lastNight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: "Body", action: "Trends") { router.push(.trends) }
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                tile("Resting heart rate", night?.restingHR, 0, "bpm", .heart, "heart.fill", baseline: analysis.baselines.restingHR, better: false, dest: .heart)
                tile("Respiratory rate", night?.respRate, 1, "rpm", .stress, "lungs.fill", baseline: analysis.baselines.respRate, better: nil, dest: .vitals)
                tile("Skin temperature", night?.skinTempDev, 1, "°C", .stress, "thermometer.medium", baseline: nil, better: nil, dest: .vitals, signed: true)
                stressTile
                tile("Steps", analysis.day?.steps.map(Double.init), 0, "", .strain, "figure.walk", baseline: nil, better: nil, dest: .strain, grouped: true)
                tile("Active energy", analysis.day?.activeKcal, 0, "kcal", .strain, "flame.fill", baseline: nil, better: nil, dest: .strain, grouped: true)
            }
        }
    }

    private func tile(_ label: String, _ value: Double?, _ decimals: Int, _ unit: String, _ tone: LumaTone, _ symbol: String,
                      baseline: LBaseline?, better: Bool?, dest: LumaDest, signed: Bool = false, grouped: Bool = false) -> some View {
        Button { router.push(dest) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(tone.color)
                    LumaLabel(label)
                    Spacer(minLength: 0)
                }
                LumaFigure(value: value, decimals: decimals, unit: unit, size: 34, signed: signed, grouped: grouped)
                if let value, let baseline {
                    DeltaBadge(delta: value - baseline.center, decimals: decimals, higherIsBetter: better, suffix: "vs usual")
                } else {
                    Text(value == nil ? "No reading yet" : (signed ? "from your baseline" : "today"))
                        .font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
    }

    private var stressTile: some View {
        Button { router.push(.stress) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.amber)
                    LumaLabel("Stress")
                    Spacer(minLength: 0)
                }
                if let mean = stress?.mean {
                    Text(LStressDay.band(mean)).font(LumaFont.numeral(34)).foregroundStyle(Luma.frost)
                    LumaSparkline(values: (stress?.hours ?? []).compactMap { $0.level }, color: Luma.amber, fill: false).frame(height: 16)
                } else {
                    Text("–").font(LumaFont.numeral(34)).foregroundStyle(Luma.smoke)
                    Text("Builds through the day").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fuel glance

struct FuelGlance: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let totals = env.fuelTotals(on: env.today)
        let target = env.fuelTargets(on: env.today)
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: "Fuel", action: "Open") { router.tab = .fuel }
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        LumaFigure(value: totals.kcal, unit: "kcal", size: 38, grouped: true)
                        Spacer()
                        Text("of \(LFormat.grouped(target.kcal)) · \(target.dayClass.title.lowercased())").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                    }
                    LumaBar(value: totals.kcal, total: target.kcal, color: Luma.mint)
                    HStack(spacing: 14) {
                        macro("Protein", totals.proteinG, target.proteinG, Luma.coral)
                        macro("Carbs", totals.carbsG, target.carbsG, Luma.amber)
                        macro("Water", totals.waterMl / 1000, target.waterMl / 1000, Luma.sky, decimals: 1, unit: "L")
                    }
                    HStack(spacing: 8) {
                        LumaQuickAction(symbol: "camera.fill", title: "Photo", tint: Luma.mint) { router.sheet = .fuelAdd(.photo) }
                        LumaQuickAction(symbol: "square.and.pencil", title: "Type", tint: Luma.mint) { router.sheet = .fuelAdd(.meal) }
                        LumaQuickAction(symbol: "drop.fill", title: "250 ml", tint: Luma.sky) { env.logWater(250); LumaHaptics.success() }
                    }
                }
            }
        }
    }

    private func macro(_ label: String, _ value: Double, _ target: Double, _ color: Color, decimals: Int = 0, unit: String = "g") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LumaLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.\(decimals)f", value)).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                Text("/ \(String(format: "%.\(decimals)f", target)) \(unit)").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
            }
            LumaBar(value: value, total: target, color: color, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Check-in

/// The evening check-in: what happened today that might shape tonight and tomorrow.
struct CheckInPrompt: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let existing = env.checkIn(on: env.today)
        Button { router.sheet = .checkIn(env.today) } label: {
            HStack(spacing: 14) {
                Image(systemName: existing == nil ? "square.and.pencil" : "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(existing == nil ? Luma.frost : Luma.volt)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.07)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(existing == nil ? "Log today" : "Today is logged").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    Text(existing.map { $0.tags.isEmpty ? "Nothing unusual noted" : $0.tags.map { $0.title }.joined(separator: ", ") }
                         ?? "Alcohol, late caffeine, sauna… Luma learns what moves your recovery.")
                        .font(LumaFont.body(13)).foregroundStyle(Luma.mist).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
            }
            .padding(16)
            .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coach brief

/// The coach's morning read of the day. Written once a day, and only when the coach is connected
/// and allowed to see health data.
struct CoachBriefCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View { CoachBriefBody(coach: env.coach) }
}

private struct CoachBriefBody: View {
    @ObservedObject var coach: CoachEngine
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    private var enabled: Bool { env.profile.morningBrief && coach.hasKey && env.profile.shareHealthWithCoach }

    var body: some View {
        Group {
            if enabled, let brief = coach.brief, coach.briefDay == env.today {
                LumaCard(tint: Luma.aqua.opacity(0.5)) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.aqua)
                            LumaLabel("Coach's read of today")
                            Spacer()
                            Button {
                                Task { await coach.loadBrief(force: true) }
                            } label: {
                                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke).frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Write the read again")
                        }
                        Text(brief).font(LumaFont.body(15)).foregroundStyle(Luma.frost).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        Button("Talk it through") { router.tab = .coach }
                            .font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.aqua).buttonStyle(.plain)
                    }
                }
            } else if enabled, coach.briefLoading {
                LumaCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(Luma.aqua)
                        Text("Writing this morning's read").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    }
                }
            }
        }
        .task(id: env.analysis.lastNight?.day) { if enabled { await coach.loadBrief() } }
        .onChange(of: coach.brief) { _, _ in env.onGlanceChange?() }
    }
}
