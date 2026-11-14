import SwiftUI
import Charts
import HYROXCore

/// Race mode screen: one segment at a time, one giant timer, one giant button. Double-tap the strap
/// or tap the button to move on.
struct HXRaceModeView: View {
    @ObservedObject var controller: RaceSessionController
    @EnvironmentObject private var store: HXStore
    let onClose: () -> Void
    @State private var confirmDiscard = false
    @State private var confirmFinish = false

    var body: some View {
        Group {
            if let s = controller.finished {
                HXSessionDetailView(session: s, onDone: onClose)
            } else {
                live
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { controller.start() }
    }

    private var live: some View {
        VStack(spacing: 0) {
            // Progress strip: one block per planned segment.
            HStack(spacing: 2) {
                ForEach(controller.plan) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.id < (controller.current?.id ?? 0) ? color(for: p.kind) : (p.id == controller.current?.id ? HX.volt : HX.raised))
                        .frame(height: 6)
                }
            }
            .padding(.horizontal, HX.screenPad).padding(.top, 10)

            HStack {
                Text(controller.kind.title.uppercased()).font(HX.overline).tracking(1.5).foregroundStyle(HX.textDim)
                Spacer()
                Text(HXFormat.duration(controller.elapsedS)).font(HX.numeral(18, weight: .bold)).foregroundStyle(HX.textDim).contentTransition(.numericText())
            }
            .padding(.horizontal, HX.screenPad).padding(.top, 10)

            Spacer()

            if let cur = controller.current {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: cur)).foregroundStyle(color(for: cur.kind))
                        Text(cur.label.uppercased()).font(HX.overline).tracking(2).foregroundStyle(color(for: cur.kind))
                    }
                    if let d = cur.distanceM, cur.kind != .run { Text("\(Int(d)) m\(cur.loadKg.map { $0 > 0 ? " · \(Int($0)) kg" : "" } ?? "")").font(HX.caption).foregroundStyle(HX.textDim) }
                    if let r = cur.reps { Text("\(r) reps\(cur.loadKg.map { " · \(Int($0)) kg" } ?? "")").font(HX.caption).foregroundStyle(HX.textDim) }
                    Text(HXFormat.durationTenths(controller.segmentS)).font(HX.numeral(96)).foregroundStyle(HX.text)
                        .contentTransition(.numericText()).minimumScaleFactor(0.5).lineLimit(1)
                    if let t = controller.currentTargetS {
                        Text("target \(HXFormat.duration(t))").font(HX.caption).foregroundStyle(HX.textDim)
                    }
                    if let ab = controller.aheadBehindS {
                        HXPill(text: ab >= 0 ? "\(HXFormat.signedSeconds(ab)) ahead" : "\(HXFormat.signedSeconds(ab)) behind", color: ab >= 0 ? HX.good : HX.bad)
                    }
                }
                .padding(.horizontal, HX.screenPad)

                if cur.station == .wallBalls {
                    HStack(spacing: 16) {
                        Button { controller.wallBallReps = max(0, controller.wallBallReps - 10) } label: { Image(systemName: "minus").frame(width: 48, height: 48) }
                            .foregroundStyle(HX.text).background(Circle().fill(HX.surface))
                        VStack { Text("\(controller.wallBallReps)").font(HX.numeral(40)).foregroundStyle(HX.text); HXOverline("reps") }
                        Button { controller.wallBallReps += 10 } label: { Image(systemName: "plus").frame(width: 48, height: 48) }
                            .foregroundStyle(HX.ink).background(Circle().fill(HX.volt))
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()

            HStack(spacing: HX.gap) {
                miniStat("HR", controller.hr.map(String.init) ?? "—", controller.hr.map { HX.zone(store.zones.zone(for: Double($0))) } ?? HX.textDim)
                miniStat("Next", controller.next?.label ?? "Finish", HX.textDim)
                miniStat("Done", "\(max(0, controller.recorder.currentIndex))/\(controller.plan.count)", HX.textDim)
            }
            .padding(.horizontal, HX.screenPad)

            Button {
                controller.advance()
            } label: {
                VStack(spacing: 2) {
                    Text(controller.next == nil ? "FINISH" : "NEXT").font(.system(size: 28, weight: .heavy, design: .rounded))
                    Text(controller.next.map { "→ \($0.label)" } ?? "").font(HX.caption)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 26)
            }
            .buttonStyle(HXPrimaryButtonStyle(color: controller.next == nil ? HX.good : HX.volt))
            .padding(.horizontal, HX.screenPad).padding(.top, 12)

            HStack {
                Button("Undo") { controller.undo() }.font(HX.caption).foregroundStyle(HX.textDim)
                Spacer()
                Text("Double-tap the strap to advance").font(HX.caption).foregroundStyle(HX.textDim)
                Spacer()
                Menu {
                    Button("Finish early") { confirmFinish = true }
                    Button("Discard session", role: .destructive) { confirmDiscard = true }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(HX.textDim) }
            }
            .padding(.horizontal, HX.screenPad).padding(.vertical, 14)
        }
        .background(HX.ink.ignoresSafeArea())
        .alert("Finish early?", isPresented: $confirmFinish) {
            Button("Finish", role: .destructive) { controller.finishEarly() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Discard this session?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { controller.discard(); onClose() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func miniStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            HXOverline(label)
            Text(value).font(HX.numeral(20, weight: .bold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(HX.surface))
    }

    private func color(for k: SegmentKind) -> Color {
        switch k { case .run: return HX.run; case .station: return HX.station; case .roxzone: return HX.rox; default: return HX.textDim }
    }
    private func symbol(for p: PlannedSegment) -> String {
        switch p.kind { case .run: return "figure.run"; case .station: return p.station?.symbol ?? "dumbbell"; case .roxzone: return "arrow.right"; case .rest: return "pause"; default: return "circle" }
    }
}

// MARK: - Session detail (race report)

struct HXSessionDetailView: View {
    let session: HXSession
    var onDone: (() -> Void)? = nil
    @EnvironmentObject private var store: HXStore
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private var report: RaceReport { RaceAnalytics.report(session, benchmarks: store.benchmarks, freshPaceSPerKm: store.benchmarks.bestRun1kS?.seconds) }

    var body: some View {
        HXScreen(title: session.kind.title, subtitle: session.startedAt.formatted(date: .abbreviated, time: .shortened)) {
            HXCard(tint: HX.volt) {
                HStack(alignment: .top) {
                    HXStat(label: "Total", value: HXFormat.duration(session.totalS ?? 0), size: 44)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        line("Runs", HXFormat.duration(report.runTotalS), HX.run)
                        line("Stations", HXFormat.duration(report.stationTotalS), HX.station)
                        line("Roxzone", HXFormat.duration(report.roxzoneTotalS), HX.rox)
                    }
                }
            }
            if !report.runs.isEmpty {
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HXOverline("Runs")
                        Chart(report.runs) { r in
                            BarMark(x: .value("run", r.index), y: .value("s", r.seconds)).foregroundStyle(HX.run).cornerRadius(6)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartYAxis { AxisMarks { v in AxisValueLabel { if let d = v.as(Double.self) { Text(HXFormat.duration(d)) } } } }
                        .frame(height: 120)
                        ForEach(report.runs) { r in
                            HStack {
                                Text("Run \(r.index)").font(HX.caption).foregroundStyle(HX.textDim).frame(width: 52, alignment: .leading)
                                Text(HXFormat.duration(r.seconds)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
                                if let d = r.driftVsFirstS, r.index > 1 { Text(HXFormat.signedSeconds(d)).font(HX.caption.monospacedDigit()).foregroundStyle(d > 0 ? HX.bad : HX.good) }
                                Spacer()
                                if let ci = r.compromisedIndex, r.index > 1 { Text(String(format: "×%.2f", ci)).font(HX.caption.monospacedDigit()).foregroundStyle(HX.textDim) }
                                if let h = r.avgHR { Text("\(Int(h))").font(HX.caption.monospacedDigit()).foregroundStyle(HX.textDim).frame(width: 36, alignment: .trailing) }
                            }
                        }
                        HStack(spacing: 14) {
                            if let cv = report.pacingCV { HXPill(text: String(format: "Pacing CV %.1f%%", cv * 100), color: cv < 0.04 ? HX.good : (cv < 0.08 ? HX.warn : HX.bad)) }
                            if let d = report.hrDriftBpm { HXPill(text: String(format: "HR drift %+.0f bpm", d)) }
                            if let c = report.compromisedIndexMean { HXPill(text: String(format: "Compromised ×%.2f", c)) }
                        }
                    }
                }
            }
            if !report.stations.isEmpty {
                HXCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HXOverline("Stations")
                        ForEach(report.stations) { s in
                            HStack {
                                Image(systemName: s.station.symbol).frame(width: 22).foregroundStyle(HX.station)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(s.station.title).font(HX.body).foregroundStyle(HX.text)
                                    Text(stationSubtitle(s)).font(HX.caption).foregroundStyle(HX.textDim)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(HXFormat.duration(s.seconds)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
                                    if let lost = s.lostVsBestS, lost > 0.5 { Text("+\(Int(lost))s vs best").font(HX.caption).foregroundStyle(HX.warn) }
                                    else if s.lostVsBestS != nil { Text("best").font(HX.caption).foregroundStyle(HX.good) }
                                }
                            }
                        }
                    }
                }
            }
            if !session.roxzones.isEmpty {
                HXCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HXOverline("Roxzone")
                        Text("\(HXFormat.duration(report.roxzoneTotalS)) across \(session.roxzones.count) transitions · avg \(HXFormat.duration(report.roxzoneTotalS / Double(max(1, session.roxzones.count))))")
                            .font(HX.body).foregroundStyle(HX.text)
                        Text("Most races lose 4–8 minutes here. Shorter walks between the run lane and the station are free time.").font(HX.caption).foregroundStyle(HX.textDim)
                    }
                }
            }
            if let onDone {
                Button("Done") { onDone() }.buttonStyle(HXPrimaryButtonStyle())
            } else {
                Button("Delete session", role: .destructive) { confirmDelete = true }.font(HX.caption).foregroundStyle(HX.bad)
            }
        }
        .alert("Delete this session?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(session); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func stationSubtitle(_ s: StationRow) -> String {
        var parts: [String] = []
        if let l = s.loadKg, l > 0 { parts.append("\(Int(l)) kg") }
        if let p = s.peakHR { parts.append("peak \(Int(p))") }
        if let h = s.hrrAfterS { parts.append("HRR \(Int(h))") }
        return parts.joined(separator: " · ")
    }

    private func line(_ l: String, _ v: String, _ c: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(l).font(HX.caption).foregroundStyle(HX.textDim)
            Text(v).font(HX.caption.monospacedDigit()).foregroundStyle(HX.text)
        }
    }
}
