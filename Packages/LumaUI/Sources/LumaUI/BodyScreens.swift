import SwiftUI
import LumaCore
import LumaKit

// MARK: - Weight, real burn, sweat rate

/// The weight log read as a trend, what the athlete really burns worked out from it and the food log,
/// and their own sweat rate.
struct BodyScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let weight = env.next.weight
        LumaDetailScreen(title: "Weight and energy", tone: .fuel) {
            WeightHero(read: weight)
            Button { router.sheet = .weighIn } label: {
                Label("Add a weigh-in", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
            if weight.points.count >= 2 { WeightChart(read: weight) }

            LumaSection(title: "What you really burn")
            EnergyCard(read: env.next.energy)

            LumaSection(title: "Your sweat rate", action: "Add a test") { router.sheet = .sweatTest }
            SweatCard()

            if !env.weights.isEmpty {
                LumaSection(title: "Weigh-ins")
                LumaGroup {
                    ForEach(env.weights.sorted { $0.at > $1.at }.prefix(12)) { w in
                        LumaRow(symbol: nil, title: LumaText.kg(w.kg) + " kg",
                                subtitle: w.at.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) {
                            Button { env.deleteWeight(w.id) } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke).frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete this weigh-in")
                        }
                    }
                }
            }
        }
    }
}

private struct WeightHero: View {
    let read: WeightRead

    var body: some View {
        LumaCard(tint: Luma.mint.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 8) {
                LumaLabel("Weight trend")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    LumaFigure(value: read.current, decimals: 1, unit: "kg", size: 56)
                    if let change = read.change28 {
                        DeltaBadge(delta: change, decimals: 1, unit: " kg", higherIsBetter: nil, suffix: "in four weeks")
                    }
                }
                if read.weighIns == 0 {
                    LumaNote("Nothing logged yet. Weigh in on waking, a few mornings a week. Luma smooths the readings, because one weigh-in is water, food and the hour as much as it is you.")
                } else if read.current == nil, let latest = read.latest {
                    LumaNote("The last weigh-in was \(LumaText.shortDay(latest.day)), too long ago to say what you weigh today.")
                } else {
                    LumaNote("Smoothed over your last weigh-ins. This is the weight every other figure in Luma is worked from: energy, protein, strength for your size.")
                }
            }
        }
    }
}

private struct WeightChart: View {
    let read: WeightRead

    var body: some View {
        let points = Array(read.points.suffix(90))
        let all = points.flatMap { [$0.kg, Optional($0.trend)].compactMap { $0 } }
        let lo = (all.min() ?? 0) - 0.4, hi = (all.max() ?? 1) + 0.4
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    key("Trend", Luma.mint)
                    key("Weigh-ins", Luma.mist)
                }
                LumaLineChart(series: [
                    LumaLineChart.Series(id: "weigh-ins", values: points.map { $0.kg }, color: Luma.mist.opacity(0.75), width: 1.4, gaps: true),
                    LumaLineChart.Series(id: "trend", values: points.map { Optional($0.trend) }, color: Luma.mint),
                ], labels: points.map { LumaText.shortDay($0.day) }, yRange: lo...hi, height: 180, format: { String(format: "%.1f", $0) })
            }
        }
    }

    private func key(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(LumaFont.body(12, .medium)).foregroundStyle(Luma.mist)
        }
    }
}

private struct EnergyCard: View {
    let read: EnergyRead

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                if let burn = read.burn, let low = read.low, let high = read.high, let intake = read.intake {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(LFormat.grouped(burn)).font(LumaFont.numeral(48, .heavy)).foregroundStyle(Luma.frost)
                        Text("kcal a day").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                    }
                    Text("Most likely between \(LFormat.grouped(low)) and \(LFormat.grouped(high)).").font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                    StatGrid {
                        StatCell(label: "Eaten", value: LFormat.grouped(intake), unit: "kcal", note: "average of \(read.loggedDays) logged days")
                        StatCell(label: "Weight", value: String(format: "%+.2f", read.kgPerWeek ?? 0), unit: "kg / wk", note: "from \(read.weighIns) weigh-ins")
                    }
                    if let notice = read.shortfall {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Luma.amber)
                            Text(notice).font(LumaFont.body(13.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LumaNote("Worked out from what you logged eating and how your weight moved over \(read.window) days. Food you did not log makes the real figure higher than this one.")
                } else {
                    Text("No estimate yet").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    LumaNote((read.missing ?? "Needs a food log and weigh-ins over the same four weeks.")
                             + " Then Luma can replace the formula with what your own log and scale say you burn.")
                    if let intake = read.intake {
                        Text("So far: \(LFormat.grouped(intake)) kcal a day eaten, over \(read.loggedDays) logged days.")
                            .font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                    }
                }
            }
        }
    }
}

private struct SweatCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let tests = env.sweatTests.sorted { $0.day > $1.day }
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                if let rate = env.next.sweatRate {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.1f", rate / 1000)).font(LumaFont.numeral(48, .heavy)).foregroundStyle(Luma.frost)
                        Text("litres an hour").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                    }
                    LumaNote("The middle of your last \(min(3, tests.compactMap { $0.mlPerHour }.count)) tests. Your water target on training days is now built from this, in place of a standard \(Int(SweatModel.standardMlPerHour)) ml an hour.")
                } else {
                    Text("Not measured yet").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    LumaNote("Weigh yourself just before and just after one session, and note what you drank during it. The weight that went, plus what you drank, is what you sweated. Until then your water target uses a standard \(Int(SweatModel.standardMlPerHour)) ml an hour.")
                }
                ForEach(tests.prefix(4)) { t in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LumaText.shortDay(t.day)).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                            Text("\(Int(t.minutes)) min · \(LumaText.kg(t.beforeKg)) to \(LumaText.kg(t.afterKg)) kg · drank \(Int(t.drankMl)) ml")
                                .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                        }
                        Spacer(minLength: 6)
                        Text(t.mlPerHour.map { String(format: "%.1f L/h", $0 / 1000) } ?? "not usable")
                            .font(LumaFont.body(13, .semibold)).foregroundStyle(t.mlPerHour == nil ? Luma.smoke : Luma.frost)
                        Button { env.deleteSweatTest(t.id) } label: {
                            Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke).frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete this test")
                    }
                }
            }
        }
    }
}

// MARK: - Sheets

/// A stepper around a weight, in tenths of a kilo.
private struct KgStepper: View {
    let title: String
    @Binding var kg: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
            Spacer()
            step("minus", -0.1)
            Text(String(format: "%.1f", kg)).font(LumaFont.numeral(28)).foregroundStyle(Luma.frost).frame(minWidth: 74)
                .contentTransition(.numericText())
            step("plus", 0.1)
        }
        .padding(.vertical, 8).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
    }

    private func step(_ symbol: String, _ by: Double) -> some View {
        Button {
            LumaHaptics.select()
            withAnimation(LumaMotion.quick) { kg = min(250, max(30, ((kg + by) * 10).rounded() / 10)) }
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(Luma.frost)
                .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(by < 0 ? "Less" : "More")
    }
}

struct WeighInSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var kg = 75.0
    @State private var typed = ""
    @State private var at = Date()

    var body: some View {
        LumaSheet(title: "Weigh-in", tone: .fuel) {
            KgStepper(title: "Weight, kg", kg: $kg)
            LumaField(title: "Or type it, e.g. 76.4", text: $typed, keyboard: .decimalPad)
                .onChange(of: typed) { _, new in
                    if let v = Double(new.replacingOccurrences(of: ",", with: ".")), v >= 30, v <= 250 { kg = (v * 10).rounded() / 10 }
                }
            DatePicker("When", selection: $at, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .font(LumaFont.body(15)).foregroundStyle(Luma.frost).tint(Luma.mint)
            LumaNote("On waking, after the toilet and before eating or drinking, is the reading that compares best from day to day.")
            Button("Save weigh-in") {
                env.addWeight(kg, at: at)
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
        }
        .presentationDetents([.medium, .large])
        .onAppear { kg = ((env.next.weight.latest?.kg ?? env.profile.weightKg) * 10).rounded() / 10 }
    }
}

struct SweatTestSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var before = 75.0
    @State private var after = 74.4
    @State private var drank = "500"
    @State private var minutes = "60"

    private var test: SweatTest {
        SweatTest(day: env.today, beforeKg: before, afterKg: after, drankMl: Double(drank) ?? 0, minutes: Double(minutes) ?? 0)
    }

    var body: some View {
        LumaSheet(title: "Sweat test", tone: .fuel) {
            LumaNote("Weigh in the same kit, towelled dry, just before and just after one session. Count everything you drank in between.")
            KgStepper(title: "Before, kg", kg: $before)
            KgStepper(title: "After, kg", kg: $after)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    LumaLabel("Drank, ml")
                    LumaField(title: "500", text: $drank, keyboard: .numberPad)
                }
                VStack(alignment: .leading, spacing: 6) {
                    LumaLabel("Session, minutes")
                    LumaField(title: "60", text: $minutes, keyboard: .numberPad)
                }
            }
            LumaCard {
                VStack(alignment: .leading, spacing: 6) {
                    if let rate = test.mlPerHour {
                        Text(String(format: "%.1f litres an hour", rate / 1000)).font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                        Text(String(format: "You lost %.1f%% of your body weight. Under 2%% is the usual aim.", max(0, test.percentLost)))
                            .font(LumaFont.body(13.5)).foregroundStyle(test.percentLost > 2 ? Luma.amber : Luma.mist)
                    } else {
                        Text("These numbers do not give a usable rate").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        LumaNote("The session needs to be 20 minutes or longer, and the weight after it lower than before by an amount a body can sweat.")
                    }
                }
            }
            Button("Save test") {
                env.addSweatTest(test)
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
            .disabled(test.mlPerHour == nil)
            .opacity(test.mlPerHour == nil ? 0.5 : 1)
        }
        .onAppear {
            let w = ((env.next.weight.latest?.kg ?? env.profile.weightKg) * 10).rounded() / 10
            before = w
            after = ((w - 0.6) * 10).rounded() / 10
        }
    }
}

// MARK: - On the Fuel tab

/// The weight trend and real burn in a line each, leading to their screen.
struct BodyTeaser: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let weight = env.next.weight
        let energy = env.next.energy
        Button { router.push(.body, from: "body") } label: {
            HStack(spacing: 14) {
                Image(systemName: "scalemass.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Luma.mint)
                    .frame(width: 44, height: 44).background(Circle().fill(Luma.mint.opacity(0.13)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weight.current.map { String(format: "%.1f kg trend", $0) } ?? "Weight and real burn")
                        .font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    Text(line(weight, energy)).font(LumaFont.body(13)).foregroundStyle(Luma.mist).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(radius: 22))
        }
        .buttonStyle(.plain)
        .lumaZoomSource("body")
    }

    private func line(_ weight: WeightRead, _ energy: EnergyRead) -> String {
        if weight.weighIns == 0 { return "Log weigh-ins to see your trend and what you really burn in a day." }
        if let burn = energy.burn { return "You burn about \(LFormat.grouped(burn)) kcal a day, from your own log and scale." }
        return energy.missing ?? "Add weigh-ins and food days to work out what you burn."
    }
}
