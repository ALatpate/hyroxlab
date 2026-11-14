import SwiftUI
import MapKit
import Charts
import HYROXCore

/// The live run screen: edge-to-edge map, one giant number, a metrics sheet, lap and pause controls.
struct HXRunLiveView: View {
    @ObservedObject var controller: RunSessionController
    @EnvironmentObject private var store: HXStore
    let onClose: () -> Void
    @State private var primary: Primary = .pace
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    enum Primary: CaseIterable { case pace, distance, time, hr }

    var body: some View {
        Group {
            if let s = controller.finished {
                HXRunSummaryView(session: s, samples: controller.samples, laps: controller.laps, onDone: onClose)
            } else {
                live
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { controller.start() }
    }

    private var live: some View {
        ZStack(alignment: .bottom) {
            if controller.isTreadmill {
                HX.ink.ignoresSafeArea()
                treadmillBackdrop
            } else {
                Map(position: $camera) {
                    UserAnnotation()
                    if controller.route.count >= 2 {
                        MapPolyline(coordinates: controller.route).stroke(HX.volt, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                .ignoresSafeArea()
                LinearGradient(colors: [HX.ink.opacity(0.9), .clear, .clear, HX.ink.opacity(0.95)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                header
                Spacer()
                if let flash = controller.lapFlash { lapFlash(flash).transition(.move(edge: .top).combined(with: .opacity)) }
                Spacer()
                metrics
                controls
            }
            .padding(.horizontal, HX.screenPad)
        }
        .animation(.easeOut(duration: 0.25), value: controller.lapFlash)
        .alert("Finish run?", isPresented: $confirmFinish) {
            Button("Finish", role: .destructive) { controller.finish() }
            Button("Keep going", role: .cancel) {}
        }
        .alert("Discard this run?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { controller.discard(); onClose() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(controller.isPaused ? HX.warn : HX.volt).frame(width: 8, height: 8)
                Text(controller.isPaused ? (controller.autoPaused ? "AUTO PAUSED" : "PAUSED") : "RECORDING").font(HX.overline).tracking(1.5).foregroundStyle(HX.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(HX.surface.opacity(0.9)))
            Spacer()
            if let p = controller.phase {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(p.label).font(HX.caption.weight(.semibold)).foregroundStyle(HX.text)
                    ProgressView(value: controller.phaseProgress).tint(HX.volt).frame(width: 90)
                }
            }
        }
        .padding(.top, 8)
    }

    private func lapFlash(_ lap: RunLap) -> some View {
        VStack(spacing: 2) {
            HXOverline("KM \(lap.index)", color: HX.volt)
            Text(HXFormat.pace(lap.paceSPerKm)).font(HX.numeral(56)).foregroundStyle(HX.text)
            if let h = lap.avgHR { Text("\(Int(h)) bpm").font(HX.caption).foregroundStyle(HX.textDim) }
        }
        .padding(24).background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(HX.ink.opacity(0.92)))
    }

    private var metrics: some View {
        VStack(spacing: 10) {
            Button { primary = next(primary) } label: {
                VStack(spacing: 2) {
                    HXOverline(primaryLabel, color: HX.volt)
                    Text(primaryValue).font(HX.numeral(84)).foregroundStyle(HX.text).contentTransition(.numericText())
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
            }.buttonStyle(.plain)
            HStack(spacing: HX.gap) {
                miniStat("Distance", HXFormat.km(controller.distanceM), "km")
                miniStat("Time", HXFormat.duration(controller.elapsedS), nil)
                miniStat("Avg", HXFormat.pace(controller.avgPace), "/km")
                miniStat("HR", controller.hr.map(String.init) ?? "—", controller.hr.map { "z\(controller.zones.zone(for: Double($0)))" })
            }
        }
        .padding(.bottom, 14)
    }

    private func next(_ p: Primary) -> Primary {
        let all = Primary.allCases
        return all[(all.firstIndex(of: p)! + 1) % all.count]
    }

    private var primaryLabel: String {
        switch primary { case .pace: return controller.isTreadmill ? "Elapsed" : "Current pace /km"; case .distance: return "Distance km"; case .time: return "Elapsed"; case .hr: return "Heart rate" }
    }
    private var primaryValue: String {
        switch primary {
        case .pace: return controller.isTreadmill ? HXFormat.duration(controller.elapsedS) : HXFormat.pace(controller.smoothedPace)
        case .distance: return HXFormat.km(controller.distanceM)
        case .time: return HXFormat.duration(controller.elapsedS)
        case .hr: return controller.hr.map(String.init) ?? "—"
        }
    }

    private func miniStat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(spacing: 2) {
            HXOverline(label)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(HX.numeral(22, weight: .bold)).foregroundStyle(HX.text).contentTransition(.numericText())
                if let unit { Text(unit).font(HX.caption).foregroundStyle(HX.textDim) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HX.surface.opacity(0.92)))
    }

    private var controls: some View {
        HStack(spacing: HX.gap) {
            Button { confirmDiscard = true } label: { Image(systemName: "xmark").font(.title3.weight(.bold)).frame(width: 56, height: 56) }
                .foregroundStyle(HX.text).background(Circle().fill(HX.surface))
            Button { controller.togglePause() } label: {
                Label(controller.isPaused ? "Resume" : "Pause", systemImage: controller.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(HXGhostButtonStyle())
            Button { controller.lap() } label: { Image(systemName: "flag.fill").font(.title3.weight(.bold)).frame(width: 56, height: 56) }
                .foregroundStyle(HX.ink).background(Circle().fill(HX.volt))
            Button { confirmFinish = true } label: { Image(systemName: "stop.fill").font(.title3.weight(.bold)).frame(width: 56, height: 56) }
                .foregroundStyle(.white).background(Circle().fill(HX.bad))
        }
        .padding(.bottom, 24)
    }

    private var treadmillBackdrop: some View {
        VStack {
            Spacer()
            Text("Treadmill mode — enter the belt distance when you finish.").font(HX.caption).foregroundStyle(HX.textDim)
            Spacer().frame(height: 300)
        }
    }
}

// MARK: - Summary

struct HXRunSummaryView: View {
    let session: HXSession
    let samples: [RunSample]
    let laps: [RunLap]
    let onDone: () -> Void
    @EnvironmentObject private var store: HXStore
    @State private var manualKm: String = ""

    private var seg: HXSegment? { session.segments.first }
    private var dist: Double { seg?.distanceM ?? 0 }
    private var secs: Double { seg?.durationS ?? 0 }
    private var zoneShares: [HRZoneShare] { RunAnalytics.zoneShares(samples, zones: store.zones) }

    var body: some View {
        HXScreen(title: "Run summary", subtitle: session.startedAt.formatted(date: .abbreviated, time: .shortened)) {
            if session.kind == .runTreadmill, dist == 0 {
                HXCard(tint: HX.warn) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Belt distance (km)").font(HX.headline).foregroundStyle(HX.text)
                        TextField("e.g. 5.0", text: $manualKm).keyboardType(.decimalPad).font(HX.bigNumeral).foregroundStyle(HX.text)
                        Button("Save distance") {
                            if let km = Double(manualKm.replacingOccurrences(of: ",", with: ".")), km > 0 {
                                var s = session
                                s.segments[0].distanceM = km * 1000
                                store.upsert(s)
                            }
                        }.buttonStyle(HXGhostButtonStyle())
                    }
                }
            }
            HXCard {
                HStack(alignment: .top) {
                    HXStat(label: "Distance", value: HXFormat.km(dist), unit: "km", size: 40)
                    Spacer()
                    HXStat(label: "Time", value: HXFormat.duration(secs), size: 40)
                }
                HStack(alignment: .top) {
                    HXStat(label: "Avg pace", value: HXFormat.pace(seg?.paceSPerKm), unit: "/km", size: 28)
                    Spacer()
                    HXStat(label: "Avg HR", value: seg?.hr.map { "\(Int($0.avg))" } ?? "—", unit: "bpm", size: 28)
                    Spacer()
                    HXStat(label: "Max HR", value: seg?.hr.map { "\(Int($0.max))" } ?? "—", unit: "bpm", size: 28)
                }
            }
            if !laps.isEmpty {
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HXOverline("Splits")
                        Chart(laps) { lap in
                            BarMark(x: .value("km", lap.index), y: .value("pace", lap.paceSPerKm))
                                .foregroundStyle(lap.isPartial ? HX.textDim : HX.volt)
                                .cornerRadius(6)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis { AxisMarks { v in AxisValueLabel { if let d = v.as(Double.self) { Text(HXFormat.pace(d)) } } } }
                        .frame(height: 140)
                        ForEach(laps) { lap in
                            HStack {
                                Text(lap.isPartial ? "+\(Int(lap.distanceM)) m" : "km \(lap.index)").font(HX.caption).foregroundStyle(HX.textDim).frame(width: 64, alignment: .leading)
                                Text(HXFormat.pace(lap.paceSPerKm)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
                                Spacer()
                                Text(lap.avgHR.map { "\(Int($0)) bpm" } ?? "—").font(HX.caption.monospacedDigit()).foregroundStyle(HX.textDim)
                            }
                        }
                    }
                }
            }
            HXCard {
                VStack(alignment: .leading, spacing: 8) {
                    HXOverline("Heart-rate zones")
                    HStack(spacing: 4) {
                        ForEach(zoneShares) { z in
                            RoundedRectangle(cornerRadius: 4).fill(HX.zone(z.zone)).frame(width: max(4, 300 * z.fraction), height: 14)
                        }
                    }
                    HStack {
                        ForEach(zoneShares) { z in
                            VStack(spacing: 2) {
                                Text("Z\(z.zone)").font(HX.caption).foregroundStyle(HX.zone(z.zone))
                                Text(HXFormat.duration(z.seconds)).font(HX.caption.monospacedDigit()).foregroundStyle(HX.textDim)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    if let d = RunAnalytics.decouplingPercent(samples) {
                        Text(String(format: "Aerobic decoupling %.1f%% — %@", d, d > 5 ? "second half cost more per beat; this effort was above current aerobic fitness or conditions were hard." : "steady; the pace was sustainable."))
                            .font(HX.caption).foregroundStyle(HX.textDim)
                    }
                }
            }
            let pbs = RunAnalytics.personalBests(samples)
            if !pbs.isEmpty {
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HXOverline("Fastest in this run")
                        ForEach(pbs) { pb in
                            HStack {
                                Text(pb.label).font(HX.body).foregroundStyle(HX.text)
                                Spacer()
                                Text(HXFormat.duration(pb.seconds)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
                                if let best = store.runPBs.first(where: { $0.distanceM == pb.distanceM }), best.seconds >= pb.seconds { HXPill(text: "PB", color: HX.volt) }
                            }
                        }
                        if let r = RunPredictor.range(for: 5000, pbs: store.runPBs) {
                            Text("5 km prediction \(HXFormat.duration(r.low))–\(HXFormat.duration(r.high))").font(HX.caption).foregroundStyle(HX.textDim)
                        }
                    }
                }
            }
            Button("Done") { onDone() }.buttonStyle(HXPrimaryButtonStyle())
        }
    }
}
