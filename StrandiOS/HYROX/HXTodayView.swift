import SwiftUI
import HYROXCore

/// How am I, and what should I do today?
struct HXTodayView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var live: LiveState
    let startRun: (HXSessionKind, PlannedSession?) -> Void
    let startRace: (HXSessionKind, PlannedSession?) -> Void

    var body: some View {
        HXScreen(title: greeting, subtitle: Date().formatted(.dateTime.weekday(.wide).day().month(.wide))) {
            readinessCard
            todaySessionCard
            HStack(spacing: HX.gap) {
                liveHRCard
                strapCard
            }
            raceReadinessCard
            quickLog
        }
        .refreshable { await repo.refresh() }
        .navigationBarHidden(true)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }

    // MARK: Readiness

    private var readinessCard: some View {
        NavigationLink { HXReadinessDetailView() } label: {
            HXCard {
                HStack(spacing: 18) {
                    ZStack {
                        HXRing(value: Double(store.readiness?.score ?? 0) / 100, color: HX.readinessColor(store.readiness?.score ?? 0), lineWidth: 12)
                        VStack(spacing: 0) {
                            Text(store.readiness.map { "\($0.score)" } ?? "—").font(HX.numeral(40))
                                .foregroundStyle(HX.text).contentTransition(.numericText())
                            HXOverline("Ready")
                        }
                    }
                    .frame(width: 118, height: 118)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.readiness?.advice.title ?? "Waiting for strap data")
                            .font(HX.headline).foregroundStyle(HX.text)
                        if let r = store.readiness {
                            ForEach(r.drivers) { d in
                                HStack(spacing: 6) {
                                    Circle().fill(d.points >= 0 ? HX.good : HX.bad).frame(width: 6, height: 6)
                                    Text(d.label).font(HX.caption).foregroundStyle(HX.textDim)
                                }
                            }
                            if r.confidence < 0.6 {
                                Text("Low confidence — more nights needed").font(HX.caption).foregroundStyle(HX.warn)
                            }
                        } else {
                            Text("Wear the strap tonight; readiness appears after the first sync.")
                                .font(HX.caption).foregroundStyle(HX.textDim)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Today's session

    @ViewBuilder private var todaySessionCard: some View {
        if let p = store.todayPlanned() {
            HXCard(tint: p.type == .rest ? nil : HX.volt) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HXOverline("Today's session", color: HX.volt)
                        Spacer()
                        if p.completedSessionID != nil { HXPill(text: "Done", color: HX.good) }
                    }
                    Text(p.title).font(HX.title).foregroundStyle(HX.text)
                    if !p.purpose.isEmpty { Text(p.purpose).font(HX.body).foregroundStyle(HX.textDim) }
                    if !p.detail.isEmpty { Text(p.detail).font(HX.caption).foregroundStyle(HX.textDim) }
                    HStack(spacing: 10) {
                        if let pace = p.targetPaceSPerKm { HXPill(text: "\(HXFormat.pace(pace)) /km", color: HX.run) }
                        if let z = p.targetZone { HXPill(text: "Zone \(z)", color: HX.zone(z)) }
                        if p.durationMin > 0 { HXPill(text: "\(p.durationMin) min") }
                    }
                    if p.completedSessionID == nil, let kind = startKind(for: p) {
                        Button(p.type.isRun ? "Start run" : "Start session") {
                            if kind.isRun { startRun(kind, p) } else { startRace(kind, p) }
                        }
                        .buttonStyle(HXPrimaryButtonStyle())
                        .padding(.top, 4)
                    } else if p.type == .gymClass, p.completedSessionID == nil {
                        NavigationLink { HXCoachCaptureView(mode: .workout) } label: { Text("Log the class from a photo") }
                            .buttonStyle(HXGhostButtonStyle())
                    }
                }
            }
        }
    }

    private func startKind(for p: PlannedSession) -> HXSessionKind? {
        switch p.type {
        case .easyRun, .thresholdRun, .longRun: return .runOutdoor
        case .intervalRun: return .runIntervals
        case .compromisedRun: return .compromisedRunning(store.profile.weakestStations.first ?? .wallBalls)
        case .fullSimulation: return .fullSimulation
        case .halfSimulation: return .halfSimulation(secondHalf: Calendar.current.component(.weekOfYear, from: Date()) % 2 == 0)
        case .stationPractice: return .stationPractice(store.profile.weakestStations.first ?? .sledPush)
        case .gymClass, .rest: return nil
        }
    }

    // MARK: Live cards

    private var liveHRCard: some View {
        HXCard {
            HXStat(label: "Live HR", value: model.bpm.map(String.init) ?? "—", unit: "bpm",
                   verdict: model.bpm.map { "Zone \(store.zones.zone(for: Double($0)))" } ?? (live.connected ? "No signal" : "Strap off"),
                   color: model.bpm.map { HX.zone(store.zones.zone(for: Double($0))) } ?? HX.textDim, size: 36)
        }
        .onAppear { model.startRealtimeHR() }
        .onDisappear { model.stopRealtimeHR() }
    }

    private var strapCard: some View {
        HXCard {
            HXStat(label: "Strap", value: live.batteryPct.map { "\(Int($0))" } ?? "—", unit: "%",
                   verdict: live.connected ? (live.encryptedBond ? "Bonded · live" : "Connected") : "Not connected",
                   color: (live.batteryPct ?? 100) < 20 ? HX.bad : HX.text, size: 36)
        }
    }

    // MARK: Race readiness

    private var raceReadinessCard: some View {
        NavigationLink { HXRaceReadinessView() } label: {
            HXCard {
                VStack(alignment: .leading, spacing: 10) {
                    HXOverline("Race readiness")
                    ForEach(store.raceReadiness.prefix(2)) { r in
                        HStack {
                            Text(r.format.title).font(HX.body).foregroundStyle(HX.text)
                            Spacer()
                            if let lo = r.predictedLowS, let hi = r.predictedHighS {
                                Text("\(HXFormat.duration(lo))–\(HXFormat.duration(hi))").font(HX.caption.monospacedDigit()).foregroundStyle(HX.textDim)
                            }
                            HXPill(text: r.verdict.title, color: verdictColor(r.verdict))
                        }
                    }
                    Text("Tap for every format and what's missing").font(HX.caption).foregroundStyle(HX.textDim)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func verdictColor(_ v: ReadinessVerdict) -> Color {
        switch v { case .ready: return HX.good; case .close: return HX.warn; case .notYet: return HX.textDim }
    }

    // MARK: Quick log

    private var quickLog: some View {
        HStack(spacing: HX.gap) {
            quickButton("Water", "drop.fill") { Task { await repo.logHydration(amountMl: 250) } }
            quickButton("Coffee", "cup.and.saucer.fill") { CaffeineLogStore.shared.log(at: Date(), mg: 80) }
            NavigationLink { HXCoachCaptureView(mode: .meal) } label: { quickLabel("Meal", "camera.fill") }
                .buttonStyle(.plain)
        }
    }

    private func quickButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { quickLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func quickLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(HX.volt)
            Text(title).font(HX.caption).foregroundStyle(HX.textDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(HX.surface))
    }
}

// MARK: - Readiness detail

struct HXReadinessDetailView: View {
    @EnvironmentObject private var store: HXStore
    var body: some View {
        HXScreen(title: "Readiness", subtitle: "How today's number is built") {
            if let r = store.readiness, let i = store.readinessInputs {
                HXCard {
                    HStack(spacing: 18) {
                        HXRing(value: Double(r.score) / 100, color: HX.readinessColor(r.score), lineWidth: 12)
                            .frame(width: 100, height: 100)
                            .overlay(Text("\(r.score)").font(HX.numeral(34)).foregroundStyle(HX.text))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(r.advice.title).font(HX.headline).foregroundStyle(HX.text)
                            Text(String(format: "Confidence %.0f%%", r.confidence * 100)).font(HX.caption).foregroundStyle(HX.textDim)
                        }
                    }
                }
                HXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HXOverline("Drivers")
                        ForEach(r.drivers) { d in
                            HStack {
                                Text(d.label).font(HX.body).foregroundStyle(HX.text)
                                Spacer()
                                Text(String(format: "%+.0f", d.points)).font(HX.body.monospacedDigit()).foregroundStyle(d.points >= 0 ? HX.good : HX.bad)
                            }
                        }
                    }
                }
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HXOverline("Inputs")
                        row("Charge (NOOP)", i.charge.map { "\(Int($0))" })
                        row("HRV today", i.hrvToday.map { "\(Int($0)) ms" })
                        row("HRV baseline", RobustBaseline(history: i.hrvHistory).map { "\(Int($0.median)) ms (n=\($0.count))" } ?? "forming (\(i.hrvHistory.count)/14 nights)")
                        row("Resting HR", i.rhrToday.map { "\(Int($0)) bpm" })
                        row("Sleep", i.sleepHoursLastNight.map { String(format: "%.1f h of %.1f h", $0, i.sleepNeedHours) })
                        let ac = HXTrainingLoad.acuteChronic(dailyLoads: i.dailyLoads)
                        row("Acute : chronic load", ac.ratio.map { String(format: "%.2f", $0) })
                    }
                }
                Text("Readiness is a training-decision aid built from your own baselines. It is not a medical measure.")
                    .font(HX.caption).foregroundStyle(HX.textDim)
            } else {
                HXCard { Text("No readiness yet — it appears after the first synced night.").font(HX.body).foregroundStyle(HX.textDim) }
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(HX.body).foregroundStyle(HX.textDim)
            Spacer()
            Text(value ?? "—").font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
        }
    }
}

// MARK: - Race readiness detail

struct HXRaceReadinessView: View {
    @EnvironmentObject private var store: HXStore
    var body: some View {
        HXScreen(title: "Race readiness", subtitle: "Indicative — the band narrows with every simulation") {
            ForEach(store.raceReadiness) { r in
                HXCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(r.format.title).font(HX.title).foregroundStyle(HX.text)
                            Spacer()
                            HXPill(text: r.verdict.title, color: r.verdict == .ready ? HX.good : (r.verdict == .close ? HX.warn : HX.textDim))
                        }
                        if let lo = r.predictedLowS, let hi = r.predictedHighS {
                            HXStat(label: "Predicted finish", value: "\(HXFormat.duration(lo)) – \(HXFormat.duration(hi))", size: 26)
                        } else {
                            Text("Not enough timed stations to predict a finish yet.").font(HX.body).foregroundStyle(HX.textDim)
                        }
                        ForEach(r.gaps, id: \.self) { g in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(HX.warn)
                                Text(g).font(HX.caption).foregroundStyle(HX.textDim)
                            }
                        }
                        ProgressView(value: r.confidence).tint(HX.volt)
                        Text(String(format: "Data coverage %.0f%%", r.confidence * 100)).font(HX.caption).foregroundStyle(HX.textDim)
                    }
                }
            }
            HXCard {
                VStack(alignment: .leading, spacing: 8) {
                    HXOverline("Your benchmarks")
                    ForEach(Station.allCases) { st in
                        let load = st.loadKg(format: store.profile.format, sex: store.sex)
                        HStack {
                            Image(systemName: st.symbol).frame(width: 22).foregroundStyle(HX.station)
                            Text(st.title).font(HX.body).foregroundStyle(HX.text)
                            Spacer()
                            Text(store.benchmarks.bestStationS(st, loadKg: load).map { HXFormat.duration($0) } ?? "—")
                                .font(HX.body.monospacedDigit()).foregroundStyle(HX.textDim)
                        }
                    }
                    HStack {
                        Image(systemName: "figure.run").frame(width: 22).foregroundStyle(HX.run)
                        Text("Best 1 km").font(HX.body).foregroundStyle(HX.text)
                        Spacer()
                        Text(store.benchmarks.bestRun1kS.map { HXFormat.duration($0.seconds) } ?? "—").font(HX.body.monospacedDigit()).foregroundStyle(HX.textDim)
                    }
                }
            }
        }
    }
}
