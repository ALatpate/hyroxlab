import SwiftUI
import LumaCore
import LumaKit

// MARK: - Session detail

struct WorkoutScreen: View {
    let id: String
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss
    @State private var hr: [LHRPoint] = []
    @State private var route: [LCoord] = []
    @State private var recovery: LHRRecovery?
    @State private var confirmDelete = false

    private var workout: LWorkout? { env.workouts.first { $0.id == id } }

    var body: some View {
        LumaDetailScreen(title: workout?.kind.title ?? "Session", tone: workout?.kind.tone ?? .run) {
            if let w = workout {
                header(w)
                if route.count >= 2 { LumaRouteTrace(coords: route).frame(height: 240).background(LumaPanel()) }
                stats(w)
                if hr.count > 4 {
                    SessionHeartCard(points: hr, start: w.start, end: w.end, step: Double(Self.bucketSeconds(w)))
                }
                zonesCard(w)
                if let samples = env.runSamples(for: w.id), samples.count > 10 {
                    SplitsCard(laps: RunAnalytics.laps(samples))
                    if let d = RunAnalytics.decouplingPercent(samples) {
                        StatGrid {
                            StatCell(label: "Aerobic decoupling", value: String(format: "%+.1f", d), unit: "%", note: d > 5 ? "Pace per heartbeat faded" : "Held steady",
                                     color: d > 5 ? Luma.amber : Luma.frost)
                            StatCell(label: "Best kilometre", value: LumaText.pace(RunAnalytics.fastest(samples, distanceM: 1000)), unit: "/km")
                        }
                    }
                }
                if let r = recovery {
                    LumaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            LumaLabel("Heart-rate recovery")
                            HStack(spacing: 0) {
                                recoveryStat("At the end", r.endHR, "bpm")
                                recoveryStat("After 1 min", r.drop1.map { -$0 }, "bpm")
                                recoveryStat("After 2 min", r.drop2.map { -$0 }, "bpm")
                            }
                            LumaNote("How fast your heart rate falls once you stop. A bigger drop in the first minute is a sign of better aerobic fitness and recovery.")
                        }
                    }
                }
                if let n = w.notes, !n.isEmpty {
                    LumaCard { VStack(alignment: .leading, spacing: 6) { LumaLabel("Notes"); LumaNote(n) } }
                }
                Button {
                    router.askCoach("Debrief my \(w.sport) session on \(w.day) (\(LumaText.duration(w.durationS))). Pull it with get_workouts and tell me what it shows and what to do next.")
                } label: { Label("Debrief with the coach", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(LumaSecondaryButtonStyle())
                if w.editable {
                    Button("Delete this session") { confirmDelete = true }
                        .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
                }
            } else {
                LumaCard { LumaEmpty(symbol: "questionmark.circle", title: "Session not found", message: "It may have been removed.") }
            }
        }
        .task(id: id) {
            guard let w = workout else { return }
            hr = await env.source.heartRate(from: w.start, to: w.end, bucketSeconds: Self.bucketSeconds(w))
            route = await env.source.route(for: w)
            recovery = await env.source.heartRateRecovery(for: w, maxHR: env.profile.resolvedMaxHR())
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let w = workout { env.deleteWorkout(w) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func header(_ w: LWorkout) -> some View {
        HStack(spacing: 14) {
            Image(systemName: w.kind.symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(Luma.ink)
                .frame(width: 58, height: 58).background(Circle().fill(w.kind.tone.color))
            VStack(alignment: .leading, spacing: 3) {
                Text(w.sport).font(LumaFont.title(26)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(LumaText.dayTitle(w.day, today: env.today)) · \(LumaText.time(w.start)) – \(LumaText.time(w.end))").font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
            }
        }
    }

    private func stats(_ w: LWorkout) -> some View {
        StatGrid {
            StatCell(label: "Duration", value: LumaText.duration(w.durationS))
            if let s = w.strain {
                StatCell(label: "Strain", value: LScale.text(s, on21: env.profile.strainOn21))
            }
            if let d = w.distanceM, d > 100 { StatCell(label: "Distance", value: LumaText.km(d), unit: "km") }
            if let p = w.paceSPerKm, w.kind == .run { StatCell(label: "Average pace", value: LumaText.pace(p), unit: "/km") }
            if let h = w.avgHR { StatCell(label: "Average heart rate", value: String(format: "%.0f", h), unit: "bpm") }
            if let h = w.maxHR { StatCell(label: "Highest heart rate", value: String(format: "%.0f", h), unit: "bpm") }
            if let k = w.kcal { StatCell(label: "Energy", value: LFormat.grouped(k), unit: "kcal") }
        }
    }

    @ViewBuilder
    private func zonesCard(_ w: LWorkout) -> some View {
        if let seconds = zoneSeconds(w) {
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Time in zones")
                    LumaZoneBars(seconds: seconds, bounds: env.profile.zones().bounds)
                }
            }
        }
    }

    /// The spacing of the heart-rate trace: about 120 readings across the session, never finer than 15 s.
    private static func bucketSeconds(_ w: LWorkout) -> Int { max(15, Int(w.durationS / 120)) }

    /// Time in each zone: what was stored with the session or, for one kept or logged after the fact,
    /// what the strap's heart-rate record for that time says.
    private func zoneSeconds(_ w: LWorkout) -> [Double]? {
        if let z = w.zonePct, z.count == 5, z.reduce(0, +) > 1 { return z.map { $0 / 100 * w.durationS } }
        guard hr.count > 4 else { return nil }
        let seconds = env.profile.zones().seconds(from: hr, spacing: Double(Self.bucketSeconds(w)))
        return seconds.reduce(0, +) >= 60 ? seconds : nil
    }

    private func recoveryStat(_ label: String, _ v: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LumaLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v.map { String(format: $0 < 0 ? "%.0f" : "%.0f", $0) } ?? "–").font(LumaFont.numeral(26)).foregroundStyle(Luma.frost)
                Text(unit).font(LumaFont.body(11)).foregroundStyle(Luma.mist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Race report

struct SessionReportScreen: View {
    let id: UUID
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LumaDetailScreen(title: "Race report", tone: .run) {
            if let s = env.sessions.first(where: { $0.id == id }) {
                SessionReportView(session: s)
                Button("Delete this session") {
                    env.delete(s)
                    dismiss()
                }
                .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
            } else {
                LumaCard { LumaEmpty(symbol: "questionmark.circle", title: "Session not found", message: "It may have been removed.") }
            }
        }
    }
}

/// Where the time went in a race-shaped session: totals, every run split and every station.
struct SessionReportView: View {
    let session: HXSession
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let report = RaceAnalytics.report(session, benchmarks: env.benchmarks)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                LumaLabel("\(session.kind.title) · \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                Text(report.totalS.map { LumaText.duration($0) } ?? "In progress").font(LumaFont.numeral(88, .heavy)).foregroundStyle(Luma.frost)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Where the time went")
                    LumaShareBar(shares: [
                        LumaShareBar.Share(id: "run", value: report.runTotalS, color: Luma.sky),
                        LumaShareBar.Share(id: "station", value: report.stationTotalS, color: Luma.volt),
                        LumaShareBar.Share(id: "rox", value: report.roxzoneTotalS, color: Luma.amber),
                    ])
                    HStack(spacing: 0) {
                        part("Running", report.runTotalS, Luma.sky)
                        part("Stations", report.stationTotalS, Luma.volt)
                        part("Roxzone", report.roxzoneTotalS, Luma.amber)
                    }
                }
            }
            if report.runs.count >= 2 {
                let slowest = report.runs.map { $0.seconds }.max() ?? 1
                LumaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            LumaLabel("Run splits")
                            Spacer()
                            if let cv = report.pacingCV { Text(String(format: "Pacing spread %.1f%%", cv * 100)).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist) }
                        }
                        LumaBarChart(bars: report.runs.map { r in
                            LumaBarChart.Bar(id: r.index, value: slowest + 15 - r.seconds, color: Luma.sky, label: "\(r.index)")
                        }, height: 110, showAxis: false, format: { LumaText.duration(slowest + 15 - $0) })
                        ForEach(report.runs) { r in
                            HStack {
                                Text("Run \(r.index)").font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist).frame(width: 60, alignment: .leading)
                                Text(LumaText.duration(r.seconds)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                                Spacer()
                                if let d = r.driftVsFirstS, r.index > 1 {
                                    Text(String(format: "%+.0f s vs run 1", d)).font(LumaFont.body(12.5)).foregroundStyle(d > 12 ? Luma.amber : Luma.mist)
                                }
                                if let hr = r.avgHR { Text("\(Int(hr.rounded()))").font(LumaFont.numeral(16, .medium)).foregroundStyle(Luma.coral).frame(width: 34, alignment: .trailing) }
                            }
                        }
                        if let drift = report.hrDriftBpm {
                            LumaNote(String(format: "Heart rate on the last run was %+.0f bpm against the first.", drift)
                                     + (report.compromisedIndexMean.map { String(format: " Runs after stations averaged %.0f%% slower than your fresh pace.", ($0 - 1) * 100) } ?? ""))
                        }
                    }
                }
            }
            if !report.stations.isEmpty {
                LumaCard {
                    VStack(alignment: .leading, spacing: 12) {
                        LumaLabel("Stations")
                        ForEach(report.stations) { st in
                            HStack(spacing: 12) {
                                Image(systemName: st.station.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Luma.volt)
                                    .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Luma.volt.opacity(0.13)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(st.station.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                    if let kg = st.loadKg, kg > 0 { Text("\(Int(kg)) kg").font(LumaFont.body(12)).foregroundStyle(Luma.smoke) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(LumaText.duration(st.seconds)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                                    if let lost = st.lostVsBestS {
                                        Text(lost <= 0.5 ? "Best" : String(format: "+%.0f s vs best", lost)).font(LumaFont.body(11.5))
                                            .foregroundStyle(lost <= 0.5 ? Luma.volt : Luma.mist)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func part(_ label: String, _ seconds: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 7, height: 7); LumaLabel(label) }
            Text(LumaText.duration(seconds)).font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - HYROX readiness

struct RaceReadinessScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let ready = RaceReadiness.assess(benchmarks: env.benchmarks, sessions: env.sessions, sex: env.profile.sex, personalBests: env.runPBs)
        let sims = env.sessions.filter { $0.kind.isHyrox }
        LumaDetailScreen(title: "HYROX", tone: .run) {
            Text("Which race are you ready for?").font(LumaFont.title(26)).foregroundStyle(Luma.frost)
            LumaNote("An indicative read from your own station benchmarks, simulations and running. It sharpens with every session you record in race mode.")
            ForEach(ready) { r in ReadinessCard(readiness: r) }

            LumaSection(title: "Station benchmarks")
            StationRadarCard()
            LumaGroup {
                ForEach(Station.allCases) { st in
                    let load = st.loadKg(format: env.profile.format, sex: env.profile.sex)
                    let best = env.benchmarks.bestStationS(st, loadKg: load)
                    LumaRow(symbol: st.symbol, symbolColor: best == nil ? Luma.smoke : Luma.volt, title: st.title,
                            subtitle: load > 0 ? st.measure.label + " · \(Int(load)) kg" : st.measure.label) {
                        Text(best.map { LumaText.duration($0) } ?? "Not yet").font(LumaFont.numeral(20)).foregroundStyle(best == nil ? Luma.smoke : Luma.frost)
                    }
                }
            }
            LumaSection(title: "Simulations")
            if sims.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "flag.checkered", title: "No race-mode sessions yet",
                              message: "Run a full or half simulation, or a single station, from the Go button. Every split is timed and feeds the prediction.",
                              action: "Start one") { router.sheet = .go }
                }
            } else {
                LumaGroup {
                    ForEach(sims) { s in
                        Button { router.push(.session(s.id)) } label: {
                            LumaRow(symbol: "flag.checkered", symbolColor: Luma.volt, title: s.kind.title,
                                    subtitle: s.startedAt.formatted(date: .abbreviated, time: .omitted), chevron: true) {
                                Text(s.totalS.map { LumaText.duration($0) } ?? "Unfinished").font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !env.runPBs.isEmpty {
                LumaSection(title: "Running bests")
                LumaGroup {
                    ForEach(env.runPBs) { pb in
                        LumaRow(symbol: "trophy.fill", symbolColor: Luma.amber, title: pb.label, subtitle: "\(LumaText.pace(pb.seconds / (pb.distanceM / 1000))) /km") {
                            Text(LumaText.duration(pb.seconds)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                        }
                    }
                }
            }
        }
    }
}

struct ReadinessCard: View {
    let readiness: FormatReadiness

    private var color: Color {
        switch readiness.verdict {
        case .ready: return Luma.volt
        case .close: return Luma.amber
        case .notYet: return Luma.smoke
        }
    }

    var body: some View {
        LumaCard(tint: readiness.verdict == .notYet ? nil : color.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(readiness.format.title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Spacer()
                    LumaPill(text: readiness.verdict.title, color: color, filled: readiness.verdict == .ready)
                }
                if let lo = readiness.predictedLowS, let hi = readiness.predictedHighS {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(LumaText.duration(lo)) – \(LumaText.duration(hi))").font(LumaFont.numeral(34)).foregroundStyle(Luma.frost)
                        Text("predicted").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                    if let assumption = readiness.assumption {
                        Text(assumption).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Not enough data to predict").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.mist)
                }
                HStack(spacing: 8) {
                    LumaLabel("Evidence")
                    LumaBar(value: readiness.confidence, total: 1, color: color, height: 5)
                    Text("\(Int((readiness.confidence * 100).rounded()))%").font(LumaFont.numeral(15, .semibold)).foregroundStyle(Luma.mist)
                }
                ForEach(readiness.gaps.prefix(3), id: \.self) { gap in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Luma.smoke).frame(width: 4, height: 4).offset(y: -3)
                        Text(gap).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Each station's best against a typical open-division time: further out is faster.
struct StationRadarCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let spokes: [(label: String, value: Double?)] = Station.allCases.map { st in
            let load = st.loadKg(format: env.profile.format, sex: env.profile.sex)
            guard let best = env.benchmarks.bestStationS(st, loadKg: load) else { return (st.shortTitle, nil) }
            // Typical time maps to 0.6 of the radius; 30 % faster reaches the rim.
            return (st.shortTitle, min(1, max(0.15, 0.6 * st.typicalSeconds / best)))
        }
        if spokes.contains(where: { $0.value != nil }) {
            LumaCard {
                VStack(alignment: .leading, spacing: 6) {
                    LumaLabel("Strengths and gaps")
                    LumaRadar(spokes: spokes, color: Luma.volt).frame(height: 250)
                    LumaNote("Further from the centre is faster, measured against a typical open-division time. Dips are where the cheapest minutes are.")
                }
            }
        }
    }
}


/// A session's heart rate on the session's own clock. The line breaks where nothing was recorded, and
/// when the record does not cover the whole session a sentence says how much of it there is: a strap
/// out of the phone's reach leaves a hole, and what is shown for the session describes the rest.
struct SessionHeartCard: View {
    let points: [LHRPoint]
    let start: Double
    let end: Double
    let step: Double

    var body: some View {
        let slots: [Double?] = RecordCheck.slots(points, from: start, to: end, step: step)
        let origin: Double = RecordCheck.slotStart(start, step: step)
        let length: Double = max(0, end - start)
        let missing: Double = min(length, Double(slots.filter { $0 == nil }.count) * step)
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("Heart rate")
                LumaLineChart(values: slots, labels: slots.indices.map { LumaText.duration(max(0, origin + Double($0) * step - start)) },
                              color: Luma.coral, height: 170, gaps: true)
                // Small dropouts are not worth a sentence; a real part of the session is.
                if missing >= 120, missing >= length * 0.05 {
                    LumaNote("Heart rate reached the phone for \(LFormat.hm(minutes: (length - missing) / 60)) of this session's \(LFormat.hm(minutes: length / 60)). Its heart-rate figures cover that part.")
                }
            }
        }
    }
}
