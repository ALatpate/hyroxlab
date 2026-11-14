import SwiftUI
import MapKit
import LumaCore
import LumaKit

// MARK: - Go

/// The start hub behind the centre button: run, race, gym, or log something that already happened.
struct GoSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss
    @State private var station: Station = .sledPush

    var body: some View {
        let today = env.scheduleDays([env.today]).first
        let open = today?.planned.filter { $0.status == .planned && $0.kind != .rest && !(today?.isDone($0) ?? false) } ?? []
        LumaSheet(title: "Start", tone: .run) {
            strapLine
            if !open.isEmpty {
                LumaLabel("Planned today")
                ForEach(open) { p in
                    Button { begin(for: p) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: p.kind.sport.symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Luma.ink)
                                .frame(width: 44, height: 44).background(Circle().fill(Luma.volt))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                                Text("\(p.durationMin) min · \(p.intensity.title)").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                            }
                            Spacer()
                            Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Luma.volt)
                        }
                        .padding(14).background(LumaPanel(tint: Luma.volt.opacity(0.4), radius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            LumaSection(title: "Run")
            HStack(spacing: 10) {
                tile("figure.run", "Outdoor", "GPS, splits, cues") { launch(.run(RunPlan(mode: .free, title: "Run"))) }
                tile("timer", "Intervals", "6 × 1 km") { launch(.run(RunPlan(mode: .intervals, title: "Intervals"))) }
                tile("figure.run.treadmill", "Treadmill", "Time and heart rate") { launch(.run(RunPlan(mode: .treadmill, title: "Treadmill run", sport: "Treadmill run"))) }
            }
            .fixedSize(horizontal: false, vertical: true)
            LumaSection(title: "HYROX")
            HStack(spacing: 10) {
                tile("flag.checkered", "Full race", "8 runs, 8 stations") { launch(.race(.fullSimulation)) }
                tile("1.circle", "First half", "Stations 1–4") { launch(.race(.halfSimulation(secondHalf: false))) }
                tile("2.circle", "Second half", "Stations 5–8") { launch(.race(.halfSimulation(secondHalf: true))) }
            }
            .fixedSize(horizontal: false, vertical: true)
            LumaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    LumaLabel("One station")
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(Station.allCases, id: \.self) { st in
                                LumaChip(title: st.shortTitle, isOn: station == st) { station = st }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    HStack(spacing: 8) {
                        LumaQuickAction(symbol: "repeat", title: "Practice × 4", tint: Luma.volt) { launch(.race(.stationPractice(station))) }
                        LumaQuickAction(symbol: "arrow.triangle.2.circlepath", title: "With 1 km runs", tint: Luma.volt) { launch(.race(.compromisedRunning(station))) }
                    }
                }
            }
            LumaSection(title: "Gym")
            HStack(spacing: 10) {
                tile("dumbbell.fill", "Strength", "Log sets and loads") { launch(.lift) }
                tile("bolt.heart.fill", "Class", "Time, heart rate, strain") { launch(.run(RunPlan(mode: .session, title: "Class", sport: "Conditioning"))) }
                tile("figure.rower", "Other", "Ride, row, anything") { launch(.run(RunPlan(mode: .session, title: "Workout", sport: "Workout"))) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .manualWorkout }
            } label: { Label("Log a session that already happened", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
        }
    }

    private var strapLine: some View {
        let s = live.strap
        return HStack(spacing: 8) {
            Circle().fill(s.connected ? Luma.volt : Luma.amber).frame(width: 7, height: 7)
            Text(s.connected ? (s.liveHeartRate().map { "Strap connected · \($0) bpm" } ?? "Strap connected")
                             : "Strap not connected. The session will have no heart rate or strain.")
                .font(LumaFont.body(13)).foregroundStyle(s.connected ? Luma.mist : Luma.amber)
        }
    }

    private func tile(_ symbol: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Luma.volt)
                Text(title).font(LumaFont.heading(14)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
                Text(subtitle).font(LumaFont.body(11.5)).foregroundStyle(Luma.mist).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(13)
            // Every tile in a row takes the height of the tallest, so a two-line caption does not leave
            // its neighbours short.
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .topLeading)
            .background(LumaPanel(radius: 20))
        }
        .buttonStyle(.plain)
    }

    private func launch(_ cover: LumaCoverDest) {
        LumaHaptics.thud()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.cover = cover }
    }

    private func begin(for p: PlannedSession) {
        switch p.kind {
        case .easyRun, .longRun, .tempoRun: launch(.run(RunPlan(mode: .free, title: p.title, targetPaceSPerKm: p.targetPaceSPerKm)))
        case .intervals: launch(.run(RunPlan(mode: .intervals, title: p.title, targetPaceSPerKm: p.targetPaceSPerKm)))
        case .simulation: launch(.race(.fullSimulation))
        case .strength: launch(.lift)
        case .hyrox: launch(.run(RunPlan(mode: .session, title: p.title, sport: "HYROX")))
        case .gymClass, .conditioning: launch(.run(RunPlan(mode: .session, title: p.title, sport: "Conditioning")))
        case .mobility: launch(.run(RunPlan(mode: .session, title: p.title, sport: "Mobility")))
        case .rest, .other: launch(.run(RunPlan(mode: .session, title: p.title, sport: "Workout")))
        }
    }
}

// MARK: - Live run / session

struct RunLiveScreen: View {
    let plan: RunPlan
    @EnvironmentObject private var env: LumaEnv

    var body: some View { RunLiveBody(env: env, plan: plan) }
}

private struct RunLiveBody: View {
    @StateObject private var c: RunController
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false
    @State private var treadmillKm = 0.0
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    init(env: LumaEnv, plan: RunPlan) {
        _c = StateObject(wrappedValue: RunController(env: env, plan: plan))
    }

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .run, strength: 1.2)
            if let result = c.result {
                RunSummaryView(result: result, zones: c.zones) { dismiss() }
            } else if !c.started {
                ready
            } else {
                running
            }
        }
        .onAppear { if env.isDemo { c.start() } }
        .confirmationDialog("End this session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Finish and save") { c.finish(treadmillKm: treadmillKm > 0 ? treadmillKm : nil) }
            Button("Discard", role: .destructive) { c.discard(); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            HStack {
                Spacer()
                LumaIconButton(symbol: "xmark") { dismiss() }
            }
            Spacer()
            Image(systemName: c.isRun ? "figure.run" : "bolt.heart.fill").font(.system(size: 54, weight: .semibold)).foregroundStyle(Luma.volt)
            Text(c.plan.title).font(LumaFont.title(34)).foregroundStyle(Luma.frost)
            Text(readyLine).font(LumaFont.body(15)).foregroundStyle(Luma.mist).multilineTextAlignment(.center).padding(.horizontal, 30)
            if let f = c.failed { Text(f).font(LumaFont.body(14)).foregroundStyle(Luma.coral).multilineTextAlignment(.center).padding(.horizontal, 30) }
            Spacer()
            Button("Start") { c.start() }.buttonStyle(LumaPrimaryButtonStyle()).padding(.horizontal, 24)
            Text(c.usesGPS ? "Start outdoors with a clear view of the sky for the best distance." : "Heart rate and strain come from the strap.")
                .font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
        }
        .padding(.vertical, 18).padding(.horizontal, Luma.gutter)
    }

    private var readyLine: String {
        switch c.plan.mode {
        case .free: return "GPS distance and route, a split every kilometre, and spoken cues."
        case .intervals: return "10 min warm-up, \(c.plan.intervalCount) × \(Int(c.plan.intervalMeters)) m with \(Int(c.plan.restSeconds)) s recoveries, 10 min cool-down. The strap buzzes at each change."
        case .treadmill: return "Time and heart rate are recorded. Enter the treadmill's distance when you finish."
        case .session: return "Time, heart rate and strain are recorded for the whole session."
        }
    }

    private var running: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.plan.title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Text(c.paused ? (c.autoPaused ? "Auto-paused" : "Paused") : "Recording").font(LumaFont.label(11))
                        .foregroundStyle(c.paused ? Luma.amber : Luma.volt)
                }
                Spacer()
                if let hr = c.hr {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.zone(c.zones.zone(for: Double(hr))))
                        Text("\(hr)").font(LumaFont.numeral(26)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                        Text("Z\(c.zones.zone(for: Double(hr)))").font(LumaFont.label(11)).foregroundStyle(Luma.zone(c.zones.zone(for: Double(hr))))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            .padding(.horizontal, Luma.gutter).padding(.top, 10)

            if c.usesGPS {
                Map(position: $camera) {
                    if c.route.count >= 2 {
                        MapPolyline(coordinates: c.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                            .stroke(Luma.volt, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
                .padding(.horizontal, Luma.gutter).padding(.top, 12)
                .onChange(of: c.route.count) { _, _ in
                    if env.isDemo, c.route.count >= 2 {
                        let lats = c.route.map { $0.lat }, lons = c.route.map { $0.lon }
                        let centre = CLLocationCoordinate2D(latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2, longitude: ((lons.min() ?? 0) + (lons.max() ?? 0)) / 2)
                        camera = .region(MKCoordinateRegion(center: centre, latitudinalMeters: 2600, longitudinalMeters: 2600))
                    }
                }
            }

            Spacer(minLength: 8)
            if c.isRun {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(LumaText.km(c.distanceM)).font(LumaFont.numeral(112, .heavy)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("km").font(LumaFont.heading(20)).foregroundStyle(Luma.mist)
                }
            } else {
                Text(LumaText.duration(c.elapsed)).font(LumaFont.numeral(112, .heavy)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            HStack(spacing: 0) {
                if c.isRun { metric("Time", LumaText.duration(c.elapsed)) }
                if c.usesGPS { metric("Pace", LumaText.pace(c.pace), "/km") }
                if c.isRun { metric("Average", LumaText.pace(c.avgPace), "/km") }
                if !c.isRun { metric("Heart rate", c.hr.map { "\($0)" } ?? "–", "bpm") }
                if !c.isRun { metric("Zone", c.hr.map { "Z\(c.zones.zone(for: Double($0)))" } ?? "–") }
            }
            .padding(.horizontal, Luma.gutter).padding(.top, 4)

            if let p = c.phase {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(p.label).font(LumaFont.heading(17)).foregroundStyle(p.isWork ? Luma.volt : Luma.frost)
                        Spacer()
                        if let t = p.targetPace { Text("Target \(LumaText.pace(t)) /km").font(LumaFont.body(13.5, .medium)).foregroundStyle(Luma.mist) }
                    }
                    LumaBar(value: c.phaseProgress, total: 1, color: p.isWork ? Luma.volt : Luma.sky, height: 8)
                    Text(c.phaseRemaining).font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                }
                .padding(14).background(LumaPanel(radius: 20)).padding(.horizontal, Luma.gutter).padding(.top, 12)
            } else if let lap = c.lapFlash ?? c.laps.last {
                HStack {
                    Text("Split \(lap.index)").font(LumaFont.label(12)).foregroundStyle(c.lapFlash != nil ? Luma.volt : Luma.mist)
                    Spacer()
                    Text("\(LumaText.pace(lap.paceSPerKm)) /km").font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
                    if let hr = lap.avgHR { Text("\(Int(hr)) bpm").font(LumaFont.body(13)).foregroundStyle(Luma.mist) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(LumaPanel(tint: c.lapFlash != nil ? Luma.volt : nil, radius: 18))
                .padding(.horizontal, Luma.gutter).padding(.top, 12)
            }
            if c.plan.mode == .treadmill {
                HStack {
                    Text("Treadmill distance").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    Spacer()
                    NumberField(label: "km", value: $treadmillKm).frame(width: 100)
                }
                .padding(.horizontal, Luma.gutter).padding(.top, 10)
            }
            Spacer(minLength: 10)
            HStack(spacing: 18) {
                if c.usesGPS {
                    roundButton("flag.fill", "Split", Luma.raised, Luma.frost) { c.lap() }
                }
                Button { c.togglePause() } label: {
                    Image(systemName: c.paused ? "play.fill" : "pause.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Luma.ink)
                        .frame(width: 92, height: 92).background(Circle().fill(Luma.volt)).shadow(color: Luma.volt.opacity(0.45), radius: 18)
                }
                .buttonStyle(.plain)
                roundButton("stop.fill", "Finish", Luma.raised, Luma.coral) { confirmStop = true }
            }
            .padding(.bottom, 26)
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String = "") -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(LumaFont.numeral(34)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                if !unit.isEmpty { Text(unit).font(LumaFont.body(11)).foregroundStyle(Luma.mist) }
            }
            LumaLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private func roundButton(_ symbol: String, _ label: String, _ fill: Color, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 62, height: 62).background(Circle().fill(fill)).overlay(Circle().strokeBorder(Luma.line, lineWidth: 1))
                Text(label).font(LumaFont.label(10)).foregroundStyle(Luma.mist)
            }
        }
        .buttonStyle(.plain)
    }
}

/// What a finished run or session looked like: the headline numbers, the route, splits and zones.
struct RunSummaryView: View {
    let result: RunResult
    let zones: HXZones
    let onDone: () -> Void
    @EnvironmentObject private var router: LumaRouter
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    LumaLabel("Saved", color: Luma.volt)
                    Text(result.title).font(LumaFont.title(30)).foregroundStyle(Luma.frost)
                }
                .padding(.top, 20)
                if result.route.count >= 2 {
                    LumaRouteTrace(coords: result.route).frame(height: 230).background(LumaPanel())
                }
                if result.distanceM > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(LumaText.km(result.distanceM)).font(LumaFont.numeral(96, .heavy)).foregroundStyle(Luma.frost)
                        Text("km").font(LumaFont.heading(20)).foregroundStyle(Luma.mist)
                    }
                }
                StatGrid {
                    StatCell(label: "Time", value: LumaText.duration(result.seconds))
                    if result.distanceM > 0 {
                        StatCell(label: "Average pace", value: LumaText.pace(result.seconds / (result.distanceM / 1000)), unit: "/km")
                    }
                    StatCell(label: "Average heart rate", value: result.avgHR.map { String(format: "%.0f", $0) } ?? "–", unit: "bpm")
                    StatCell(label: "Highest heart rate", value: result.maxHR.map { String(format: "%.0f", $0) } ?? "–", unit: "bpm")
                    if let s = result.workout?.strain { StatCell(label: "Strain", value: LScale.text(s, on21: env.profile.strainOn21)) }
                    if let k = result.workout?.kcal { StatCell(label: "Energy", value: LFormat.grouped(k), unit: "kcal") }
                }
                if !result.newBests.isEmpty {
                    LumaCard(tint: Luma.volt) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("New personal best", systemImage: "trophy.fill").font(LumaFont.heading(16)).foregroundStyle(Luma.volt)
                            ForEach(result.newBests) { pb in
                                HStack {
                                    Text(pb.label).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                    Spacer()
                                    Text(LumaText.duration(pb.seconds)).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                                }
                            }
                        }
                    }
                }
                SplitsCard(laps: result.laps)
                RunZonesCard(samples: result.samples, zones: zones)
                if let d = RunAnalytics.decouplingPercent(result.samples) {
                    LumaCard {
                        VStack(alignment: .leading, spacing: 6) {
                            LumaLabel("Aerobic decoupling")
                            Text(String(format: "%+.1f%%", d)).font(LumaFont.numeral(34)).foregroundStyle(d > 5 ? Luma.amber : Luma.frost)
                            LumaNote(d > 5 ? "Your pace per heartbeat fell in the second half. The run was beyond your current aerobic base, or it was hot or hilly."
                                           : "Pace per heartbeat held from the first half to the second: the effort sat inside your aerobic base.")
                        }
                    }
                }
                Button("Done", action: onDone).buttonStyle(LumaPrimaryButtonStyle())
                Button {
                    onDone()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        router.askCoach("Debrief the session I just finished (\(result.title), \(LumaText.duration(result.seconds))). Look at it in get_workouts for today and tell me what it shows and what to do next.")
                    }
                } label: { Label("Debrief with the coach", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    .buttonStyle(LumaSecondaryButtonStyle())
            }
            .padding(.horizontal, Luma.gutter).padding(.bottom, 40)
            .offset(y: -LumaLaunch.scrollOffset)
        }
        .scrollIndicators(.hidden)
    }
}

/// Kilometre splits as bars (faster is taller) with the table beneath.
struct SplitsCard: View {
    let laps: [RunLap]

    var body: some View {
        if laps.count >= 2 {
            let slowest = laps.map { $0.paceSPerKm }.max() ?? 1
            let fastest = laps.map { $0.paceSPerKm }.min() ?? 0
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Splits")
                    LumaBarChart(bars: laps.map { lap in
                        LumaBarChart.Bar(id: lap.index, value: slowest + 20 - lap.paceSPerKm, color: lap.paceSPerKm == fastest ? Luma.volt : Luma.sky,
                                         label: lap.isPartial ? "+" : "\(lap.index)", dimmed: lap.isPartial)
                    }, height: 120, showAxis: false, format: { LumaText.pace(slowest + 20 - $0) })
                    ForEach(laps) { lap in
                        HStack {
                            Text(lap.isPartial ? String(format: "%.2f km", lap.distanceM / 1000) : "\(lap.index)").font(LumaFont.numeral(17, .semibold))
                                .foregroundStyle(Luma.mist).frame(width: 64, alignment: .leading)
                            Text(LumaText.pace(lap.paceSPerKm)).font(LumaFont.numeral(20)).foregroundStyle(lap.paceSPerKm == fastest ? Luma.volt : Luma.frost)
                            Text("/km").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                            Spacer()
                            if let hr = lap.avgHR { Text("\(Int(hr.rounded())) bpm").font(LumaFont.numeral(16, .medium)).foregroundStyle(Luma.mist) }
                        }
                    }
                }
            }
        }
    }
}

struct RunZonesCard: View {
    let samples: [RunSample]
    let zones: HXZones

    var body: some View {
        let shares = RunAnalytics.zoneShares(samples, zones: zones)
        if shares.reduce(0, { $0 + $1.seconds }) > 60 {
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Time in zones")
                    LumaZoneBars(seconds: shares.map { $0.seconds }, bounds: zones.bounds)
                }
            }
        }
    }
}

// MARK: - Race mode

struct RaceLiveScreen: View {
    let kind: HXSessionKind
    @EnvironmentObject private var env: LumaEnv

    var body: some View { RaceLiveBody(env: env, kind: kind) }
}

private struct RaceLiveBody: View {
    @StateObject private var c: RaceController
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStop = false

    init(env: LumaEnv, kind: HXSessionKind) {
        _c = StateObject(wrappedValue: RaceController(env: env, kind: kind))
    }

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .run, strength: 1.3)
            if let s = c.finished {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SessionReportView(session: s)
                        Button("Done") { dismiss() }.buttonStyle(LumaPrimaryButtonStyle())
                    }
                    .padding(.horizontal, Luma.gutter).padding(.top, 24).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            } else if !c.started {
                ready
            } else {
                racing
            }
        }
        .onAppear { if env.isDemo { c.start() } }
        .confirmationDialog("End the session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Finish here and save") { c.finishEarly() }
            Button("Discard", role: .destructive) { c.discard(); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(c.kind.title).font(LumaFont.title(28)).foregroundStyle(Luma.frost)
                Spacer()
                LumaIconButton(symbol: "xmark") { dismiss() }
            }
            Text("\(c.plan.filter { $0.kind == .run }.count) runs, \(c.plan.filter { $0.kind == .station }.count) stations. Tap Next, or double-tap the strap, at every change.")
                .font(LumaFont.body(15)).foregroundStyle(Luma.mist)
            ScrollView {
                LumaGroup {
                    ForEach(c.plan.filter { $0.kind == .run || $0.kind == .station }) { p in
                        LumaRow(symbol: p.kind == .run ? "figure.run" : (p.station?.symbol ?? "bolt.fill"), symbolColor: p.kind == .run ? Luma.sky : Luma.volt,
                                title: p.label, subtitle: segmentLine(p))
                    }
                }
            }
            .scrollIndicators(.hidden)
            if !c.canUseStrapTap {
                LumaNote("The strap is not paired securely, so double-tap is unavailable. Use the Next button.")
            }
            Button("Start") { c.start() }.buttonStyle(LumaPrimaryButtonStyle())
        }
        .padding(.horizontal, Luma.gutter).padding(.vertical, 18)
    }

    private func segmentLine(_ p: PlannedSegment) -> String {
        var parts: [String] = []
        if let d = p.distanceM { parts.append(d >= 1000 ? String(format: "%.0f km", d / 1000) : "\(Int(d)) m") }
        if let r = p.reps { parts.append("\(r) reps") }
        if let kg = p.loadKg, kg > 0 { parts.append("\(Int(kg)) kg") }
        return parts.joined(separator: " · ")
    }

    private var racing: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    LumaLabel(c.kind.title)
                    Text("Segment \(c.index + 1) of \(c.plan.count)").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                }
                Spacer()
                if let hr = c.hr {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.coral)
                        Text("\(hr)").font(LumaFont.numeral(26)).foregroundStyle(Luma.frost)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.08)))
                }
                LumaIconButton(symbol: "stop.fill", color: Luma.coral) { confirmStop = true }
            }
            .padding(.horizontal, Luma.gutter).padding(.top, 10)

            RaceProgress(plan: c.plan, index: c.index).padding(.horizontal, Luma.gutter).padding(.top, 12)

            Spacer(minLength: 6)
            Text(LumaText.duration(c.elapsed)).font(LumaFont.numeral(118, .heavy)).foregroundStyle(Luma.frost)
                .minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 12)
            if let d = c.aheadBehind {
                Text("\(LumaText.duration(abs(d))) \(d >= 0 ? "ahead of" : "behind") your target")
                    .font(LumaFont.body(14, .semibold)).foregroundStyle(d >= 0 ? Luma.volt : Luma.amber)
            }
            Spacer(minLength: 6)

            if let cur = c.current {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: cur.kind == .run ? "figure.run" : (cur.station?.symbol ?? "arrow.right")).font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Luma.ink).frame(width: 52, height: 52).background(Circle().fill(Luma.volt))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cur.label).font(LumaFont.title(24)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.7)
                            Text(segmentLine(cur)).font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(LumaText.duration(c.segment)).font(LumaFont.numeral(40)).foregroundStyle(Luma.frost)
                            if let t = c.currentTarget { Text("target \(LumaText.duration(t))").font(LumaFont.body(12)).foregroundStyle(Luma.smoke) }
                        }
                    }
                    if let t = c.currentTarget { LumaBar(value: min(c.segment, t), total: t, color: c.segment > t ? Luma.amber : Luma.volt, height: 6) }
                    if cur.station == .wallBalls {
                        HStack {
                            Text("Wall balls done").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                            Spacer()
                            Stepper(value: $c.wallBallReps, in: 0...200, step: 5) {
                                Text("\(c.wallBallReps)").font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
                            }
                            .fixedSize()
                        }
                    }
                }
                .padding(16).background(LumaPanel(tint: Luma.volt.opacity(0.4))).padding(.horizontal, Luma.gutter)
            }
            if let next = c.next {
                HStack {
                    LumaLabel("Next")
                    Text(next.label).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                    Spacer()
                    Text(segmentLine(next)).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                }
                .padding(.horizontal, Luma.gutter + 4).padding(.top, 12)
            }
            HStack(spacing: 12) {
                Button { c.undo() } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .bold)).foregroundStyle(Luma.frost)
                        .frame(width: 72, height: 84).background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Luma.raised))
                }
                .buttonStyle(.plain)
                .disabled(c.index == 0)
                Button { c.advance() } label: {
                    Text(c.next == nil ? "Finish" : "Next").font(LumaFont.title(30)).foregroundStyle(Luma.ink)
                        .frame(maxWidth: .infinity).frame(height: 84)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Luma.volt))
                        .shadow(color: Luma.volt.opacity(0.45), radius: 18)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Luma.gutter).padding(.top, 14).padding(.bottom, 22)
        }
    }
}

/// The whole race as a row of segments: done, current, to come. Runs are wide, stations taller.
struct RaceProgress: View {
    let plan: [PlannedSegment]
    let index: Int

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(plan.enumerated()), id: \.offset) { i, p in
                let color: Color = i < index ? Luma.volt : (i == index ? Luma.frost : Color.white.opacity(0.14))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(height: p.kind == .station ? 12 : (p.kind == .run ? 7 : 3))
                    .frame(maxWidth: p.kind == .roxzone ? 5 : .infinity)
            }
        }
        .frame(height: 12)
    }
}
