import SwiftUI
import Charts
import LumaCore
import WhoopStore

/// What is my body telling me over weeks?
struct HXBodyView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var repo: Repository
    @State private var waterToday: Double = 0
    @State private var showFoodEntry = false

    var body: some View {
        HXScreen(title: "Body", subtitle: "Recovery, load, fuel") {
            trendCards
            loadCard
            nutritionCard
            effectsCard
            HXOverline("NOOP screens")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: HX.gap), GridItem(.flexible(), spacing: HX.gap)], spacing: HX.gap) {
                NavigationLink { TrendsView() } label: { tile("Trends", "chart.line.uptrend.xyaxis") }.buttonStyle(.plain)
                NavigationLink { SleepView() } label: { tile("Sleep", "bed.double.fill") }.buttonStyle(.plain)
                NavigationLink { HealthView() } label: { tile("Health", "heart.text.square.fill") }.buttonStyle(.plain)
                NavigationLink { StressView() } label: { tile("Stress", "bolt.heart.fill") }.buttonStyle(.plain)
                NavigationLink { AppleHealthView() } label: { tile("Apple Health", "heart.fill") }.buttonStyle(.plain)
                NavigationLink { HXLabView() } label: { tile("Lab", "flask.fill") }.buttonStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .task { waterToday = await repo.hydrationTotal(day: Repository.localDayKey(Date())) }
        .sheet(isPresented: $showFoodEntry) { HXFoodEntrySheet().environmentObject(store) }
    }

    // MARK: Trends

    private var last14: [DailyMetric] { Array(repo.days.suffix(14)) }

    private var trendCards: some View {
        HStack(spacing: HX.gap) {
            miniTrend("HRV", last14.map { $0.avgHrv ?? .nan }, unit: "ms", color: HX.good)
            miniTrend("Resting HR", last14.map { $0.restingHr.map { Double($0) } ?? .nan }, unit: "bpm", color: HX.run)
            miniTrend("Charge", last14.map { $0.recovery ?? .nan }, unit: "", color: HX.volt)
        }
    }

    private func miniTrend(_ label: String, _ values: [Double], unit: String, color: Color) -> some View {
        let clean = values.filter { !$0.isNaN }
        return HXCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HXOverline(label)
                Text(clean.last.map { "\(Int($0))" } ?? "—").font(HX.numeral(26, weight: .bold)).foregroundStyle(HX.text)
                Chart(Array(clean.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("d", i), y: .value("v", v)).foregroundStyle(color).interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 34)
                Text(unit.isEmpty ? "14 days" : "\(unit) · 14 d").font(HX.caption).foregroundStyle(HX.textDim)
            }
        }
    }

    // MARK: Load

    private var loadCard: some View {
        let loads = store.dailyLoads
        let ac = HXTrainingLoad.acuteChronic(dailyLoads: loads.map(\.load))
        return HXCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HXOverline("Training load · 28 days")
                    Spacer()
                    if let r = ac.ratio { HXPill(text: String(format: "A:C %.2f", r), color: r > 1.5 ? HX.bad : (r > 1.3 ? HX.warn : HX.good)) }
                }
                Chart {
                    ForEach(Array(loads.enumerated()), id: \.offset) { i, d in
                        BarMark(x: .value("day", i), y: .value("load", d.load)).foregroundStyle(HX.raised).cornerRadius(3)
                    }
                    ForEach(Array(ewma(loads.map(\.load), n: 7).enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("day", i), y: .value("acute", v)).foregroundStyle(HX.volt).interpolationMethod(.monotone)
                    }
                    ForEach(Array(ewma(loads.map(\.load), n: 28).enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("day", i), y: .value("chronic", v)).foregroundStyle(HX.textDim).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 120)
                Text("Bars are NOOP Effort per day. Volt line is the 7-day load, dashed the 28-day. A ratio above 1.3 is a spike; above 1.5, back off.")
                    .font(HX.caption).foregroundStyle(HX.textDim)
            }
        }
    }

    private func ewma(_ xs: [Double], n: Double) -> [Double] {
        let l = 2 / (n + 1); var a = 0.0
        return xs.map { a = l * $0 + (1 - l) * a; return a }
    }

    // MARK: Nutrition

    private var nutritionCard: some View {
        let t = store.nutritionTargets()
        let today = store.todayFood()
        let protein = today.compactMap(\.proteinG).reduce(0, +)
        let kcal = today.compactMap(\.kcal).reduce(0, +)
        return HXCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HXOverline("Fuel today")
                    Spacer()
                    Button { showFoodEntry = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(HX.volt) }
                    NavigationLink { HXCoachCaptureView(mode: .meal) } label: { Image(systemName: "camera.fill").foregroundStyle(HX.volt) }
                }
                bar("Protein", protein, t.proteinG, "g", HX.good)
                bar("Energy", kcal, t.kcal, "kcal", HX.warn)
                bar("Water", waterToday, t.waterMl, "ml", HX.run)
                if today.isEmpty {
                    Text("Nothing logged yet — unlogged is not zero. Targets: \(Int(t.proteinG)) g protein, \(Int(t.kcal)) kcal for today's load.")
                        .font(HX.caption).foregroundStyle(HX.textDim)
                } else {
                    ForEach(today) { f in
                        HStack {
                            Text(f.title).font(HX.caption).foregroundStyle(HX.text)
                            HXPill(text: f.provenance.rawValue, color: f.provenance == .measured ? HX.good : (f.provenance == .reviewed ? HX.warn : HX.textDim))
                            Spacer()
                            Text([f.kcal.map { "\(Int($0)) kcal" }, f.proteinG.map { "\(Int($0)) g P" }].compactMap { $0 }.joined(separator: " · ")).font(HX.caption).foregroundStyle(HX.textDim)
                        }
                    }
                }
            }
        }
    }

    private func bar(_ label: String, _ value: Double, _ target: Double, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(HX.caption).foregroundStyle(HX.textDim)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)").font(HX.caption.monospacedDigit()).foregroundStyle(HX.text)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(HX.raised)
                    Capsule().fill(color).frame(width: g.size.width * min(1, target > 0 ? value / target : 0))
                }
            }.frame(height: 8)
        }
    }

    // MARK: Effects

    private var effectsCard: some View {
        HXCard {
            VStack(alignment: .leading, spacing: 6) {
                HXOverline("Effects")
                Text("Caffeine, alcohol and late sessions versus the next night's HRV and sleep, once there are enough logged days. NOOP computes these in Insights.")
                    .font(HX.caption).foregroundStyle(HX.textDim)
                NavigationLink { InsightsView() } label: {
                    Text("Open Insights").font(HX.caption.weight(.semibold)).foregroundStyle(HX.volt)
                }
            }
        }
    }

    private func tile(_ title: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(HX.textDim)
            Text(title).font(HX.body).foregroundStyle(HX.text)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(HX.textDim)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HX.surface))
    }
}

// MARK: - Food entry

struct HXFoodEntrySheet: View {
    @EnvironmentObject private var store: HXStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var measured = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("What did you eat?", text: $title)
                HStack { TextField("kcal", text: $kcal).keyboardType(.numberPad); TextField("protein g", text: $protein).keyboardType(.numberPad) }
                HStack { TextField("carbs g", text: $carbs).keyboardType(.numberPad); TextField("fat g", text: $fat).keyboardType(.numberPad) }
                Toggle("From a label or weighed (measured)", isOn: $measured)
            }
            .navigationTitle("Log food")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.food.append(HXFoodEntry(at: Date(), title: title.isEmpty ? "Meal" : title, kcal: Double(kcal), proteinG: Double(protein),
                                                      carbsG: Double(carbs), fatG: Double(fat), provenance: measured ? .measured : .reviewed, note: nil))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Lab (gated research models)

struct HXLabView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var repo: Repository

    var body: some View {
        HXScreen(title: "Lab", subtitle: "Exploratory models, gated by sample size") {
            proteinRecovery
            HXCard {
                VStack(alignment: .leading, spacing: 6) {
                    HXOverline("Run PBs")
                    if store.runPBs.isEmpty { Text("No GPS runs yet.").font(HX.body).foregroundStyle(HX.textDim) }
                    ForEach(store.runPBs) { pb in
                        HStack { Text(pb.label).font(HX.body).foregroundStyle(HX.text); Spacer(); Text(HXFormat.duration(pb.seconds)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text) }
                    }
                    if let k = RunPredictor.fitExponent(store.runPBs) { Text(String(format: "Personal Riegel exponent %.3f", k)).font(HX.caption).foregroundStyle(HX.textDim) }
                }
            }
            Text("Associations here are exploratory: they do not control for confounding or serial correlation and are never used to change a plan automatically.")
                .font(HX.caption).foregroundStyle(HX.textDim)
        }
    }

    private var proteinRecovery: some View {
        // Day D protein (reviewed/measured only) vs day D+1 Charge, ≥ 21 pairs.
        let cal = Calendar.current
        var byDay: [String: Double] = [:]
        for f in store.food where f.provenance != .estimated {
            let k = Repository.localDayKey(f.at)
            byDay[k, default: 0] += f.proteinG ?? 0
        }
        var xs: [Double] = [], ys: [Double] = []
        for d in repo.days {
            guard let rec = d.recovery, let date = dayDate(d.day), let prev = cal.date(byAdding: .day, value: -1, to: date),
                  let p = byDay[Repository.localDayKey(prev)], p > 0 else { continue }
            xs.append(p); ys.append(rec)
        }
        let r = xs.count >= 21 ? HXStats.pearson(xs, ys) : nil
        return HXCard {
            VStack(alignment: .leading, spacing: 6) {
                HXOverline("Protein → next-day Charge")
                if let r {
                    Text(String(format: "r = %.2f over %d day-pairs (r² %.0f%%)", r, xs.count, r * r * 100)).font(HX.body).foregroundStyle(HX.text)
                    Text("An association, not a cause.").font(HX.caption).foregroundStyle(HX.textDim)
                } else {
                    Text("Needs 21 logged days with protein and a next-day Charge; \(xs.count) so far.").font(HX.body).foregroundStyle(HX.textDim)
                }
            }
        }
    }

    private func dayDate(_ key: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.date(from: key)
    }
}
