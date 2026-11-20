import SwiftUI
import LumaCore
import LumaKit

// MARK: - Luma Doctor
//
// A weekly check of the athlete's own numbers against their own usual range (`Doctor`, LumaCore).
// The screens say what moved and by how much. They do not say why, and they name no illness.

extension DoctorLevel {
    var color: Color {
        switch self {
        case .noData: return Luma.smoke
        case .steady: return Luma.mint
        case .watch: return Luma.amber
        case .outside: return Luma.coral
        }
    }

    var symbol: String {
        switch self {
        case .noData: return "questionmark.circle"
        case .steady: return "checkmark.circle.fill"
        case .watch: return "eye.fill"
        case .outside: return "exclamationmark.triangle.fill"
        }
    }
}

enum DoctorWords {
    /// "Sun 15 to Sat 21 Nov".
    static func week(_ report: DoctorReport) -> String {
        guard let a = LDate.date(report.weekStart), let b = LDate.date(report.weekEnd) else { return report.weekEnd }
        return a.formatted(.dateTime.weekday(.abbreviated).day()) + " to " + b.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func nights(_ report: DoctorReport) -> String {
        "\(report.nights) of 7 nights had a reading"
    }
}

/// The card on the Recovery screen: the last check in a line, and the way in.
struct DoctorCard: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        Button { router.push(.doctor) } label: {
            LumaCard(tint: (env.doctorLatest?.level ?? .noData) >= .watch ? env.doctorLatest?.level.color : nil) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Luma.aqua)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Luma.aqua.opacity(0.13)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Luma Doctor").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        if let report = env.doctorLatest {
                            HStack(spacing: 6) {
                                Image(systemName: report.level.symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(report.level.color)
                                Text(report.headline).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("Week of \(DoctorWords.week(report))").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                        } else {
                            Text("Checks your week against your own usual range every Sunday. The first check runs as soon as there is a week of data.")
                                .font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke).padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The Doctor's own screen: the check on show, the written read, each thing looked at, and the log.
struct DoctorScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    /// The check on show; nil for the newest.
    @State private var chosen: String?

    private var report: DoctorReport? {
        chosen.flatMap { id in env.doctorReports.first { $0.id == id } } ?? env.doctorLatest
    }

    var body: some View {
        LumaDetailScreen(title: "Luma Doctor", tone: .hrv) {
            LumaNote("Every Sunday Luma checks the week against your own usual range and keeps the result here. It is not a doctor and it cannot diagnose: it tells you what moved, and by how much. If something stays outside your range, or you feel unwell, see a doctor.")
            if let report {
                summary(report)
                read(report)
                LumaSection(title: "What was checked")
                ForEach(report.findings.sorted { $0.level > $1.level }) { finding in
                    DoctorFindingCard(finding: finding)
                }
            } else {
                LumaCard {
                    LumaEmpty(symbol: "stethoscope", title: "No check yet",
                              message: "The weekly check runs on Sunday once Luma holds a week of your data. You can run one now on what is there.",
                              action: "Run a check now") { env.runDoctorNow() }
                }
            }
            if env.doctorReports.count > 1 {
                LumaSection(title: "Log")
                LumaGroup {
                    ForEach(env.doctorReports) { past in
                        Button {
                            LumaHaptics.select()
                            chosen = past.id
                        } label: {
                            LumaRow(symbol: past.level.symbol, symbolColor: past.level.color,
                                    title: "Week of \(DoctorWords.week(past))" + (past.scheduled ? "" : " · asked for"),
                                    subtitle: past.headline) {
                                if past.id == report?.id { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.volt) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            LumaSection(title: "When it runs")
            LumaGroup {
                HStack {
                    Text("Next weekly check").font(LumaFont.body(15)).foregroundStyle(Luma.frost)
                    Spacer()
                    Text(DoctorSchedule.next(after: Date()).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(LumaFont.body(14, .medium)).foregroundStyle(Luma.mist)
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                Toggle(isOn: notify) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tell me when it is done").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("One notification each Sunday with the result in a line.").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                }
                .tint(Luma.volt)
                .padding(.vertical, 11).padding(.horizontal, 16)
            }
            LumaNote("iOS does not let an app wake itself at an exact minute. The check is due at 00:00 on Sunday and runs the first time Luma is running after that, which is usually at once, because the strap keeps Luma running in the background.")
            Button("Run a check now") {
                LumaHaptics.tap()
                chosen = nil
                env.runDoctorNow()
            }
            .buttonStyle(LumaSecondaryButtonStyle())
        }
    }

    /// Which model writes the read, and that the coach's own setting has no say in it.
    private var strongestNote: String {
        let now = env.coach.doctorModelName.map { " (now " + $0 + ")" } ?? ""
        return "The read is always written by the most capable model your key reaches" + now + ", whatever the coach is set to."
    }

    /// The switch asks iOS for leave the first time it is turned on, and stays off if leave is refused.
    private var notify: Binding<Bool> {
        Binding(get: { env.extras.doctorNotify }, set: { on in
            guard on else { env.extras.doctorNotify = false; return }
            Task {
                let allowed = await env.requestNotifications?() ?? true
                env.extras.doctorNotify = allowed
            }
        })
    }

    private func summary(_ report: DoctorReport) -> some View {
        LumaCard(tint: report.level >= .watch ? report.level.color.opacity(0.7) : Luma.mint.opacity(0.4)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: report.level.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(report.level.color)
                    LumaLabel("Week of \(DoctorWords.week(report))" + (report.scheduled ? "" : " · asked for"))
                }
                Text(report.headline).font(LumaFont.title(24)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                Text("\(DoctorWords.nights(report)). Checked \(report.ranAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).")
                    .font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The written read, or why there is none.
    @ViewBuilder
    private func read(_ report: DoctorReport) -> some View {
        LumaSection(title: "The read")
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                if let text = report.read {
                    Text(text).font(LumaFont.body(15)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.aqua)
                        Text("Written by \(report.readModel ?? "Claude") from the figures below. Not medical advice.")
                            .font(LumaFont.body(12)).foregroundStyle(Luma.smoke).fixedSize(horizontal: false, vertical: true)
                    }
                } else if env.doctorWriting {
                    ReadingRows(caption: "Writing the read", rows: 3)
                } else if !env.coach.hasKey {
                    LumaNote("The check itself runs on this phone. Connect your Anthropic key and the strongest Claude model your key reaches will also write a short read of each check.")
                    Button("Connect your key") { router.sheet = .coachSetup }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                } else if !env.profile.shareHealthWithCoach {
                    LumaNote("The check itself runs on this phone. A written read means sending these figures to Anthropic with your key, so it is only done while “Share my health data with the coach” is on.")
                    Button("Turn sharing on") { env.profile.shareHealthWithCoach = true; env.writeDoctorRead(for: report.id, asked: true) }
                        .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                } else {
                    LumaNote(report.readNote ?? "No read has been written for this check yet.")
                    Button("Write it now") { env.writeDoctorRead(for: report.id, asked: true) }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
                if report.read != nil || env.doctorCanWrite {
                    Text(strongestNote).font(LumaFont.body(12)).foregroundStyle(Luma.smoke).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One thing the check looked at: its figure, what is usual, what was seen, and four weeks of it.
struct DoctorFindingCard: View {
    let finding: DoctorFinding

    var body: some View {
        LumaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(finding.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                    Spacer(minLength: 6)
                    LumaPill(text: finding.level.title, color: finding.level.color, symbol: finding.level.symbol)
                }
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(finding.figure).font(LumaFont.numeral(26)).foregroundStyle(finding.level == .noData ? Luma.smoke : Luma.frost)
                    if let usual = finding.usual {
                        Text(usual).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(finding.line).font(LumaFont.body(14)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                if finding.series.compactMap({ $0 }).count >= 4 {
                    DoctorSpark(series: finding.series, color: finding.level.color)
                        .frame(height: 34)
                        .accessibilityHidden(true)
                    HStack {
                        Text("4 weeks ago").font(LumaFont.label(10)).foregroundStyle(Luma.smoke)
                        Spacer()
                        Text("this week").font(LumaFont.label(10)).foregroundStyle(Luma.smoke)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Four weeks of one reading as a line, the week checked set apart. A day with no reading is a
/// break in the line, not a stroke across it.
struct DoctorSpark: View {
    let series: [Double?]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let values = series.compactMap { $0 }
            let low = values.min() ?? 0, high = values.max() ?? 1
            let span = max(high - low, 0.0001)
            let n = max(series.count - 1, 1)
            let weekFrom = max(series.count - 7, 0)
            let point: (Int, Double) -> CGPoint = { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(n), y: geo.size.height * (1 - CGFloat((v - low) / span)) * 0.86 + geo.size.height * 0.07)
            }
            ZStack(alignment: .topLeading) {
                // The week checked, as a band behind the line.
                Rectangle().fill(color.opacity(0.08))
                    .frame(width: geo.size.width * CGFloat(series.count - weekFrom - 1) / CGFloat(n) + 4)
                    .offset(x: geo.size.width * CGFloat(weekFrom) / CGFloat(n) - 2)
                Path { path in
                    var drawing = false
                    for (i, value) in series.enumerated() {
                        guard let value else { drawing = false; continue }
                        let p = point(i, value)
                        if drawing { path.addLine(to: p) } else { path.move(to: p); drawing = true }
                    }
                }
                .stroke(Luma.mist.opacity(0.75), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                ForEach(Array(series.enumerated()), id: \.offset) { i, value in
                    if let value, i >= weekFrom {
                        Circle().fill(color).frame(width: 5, height: 5).position(point(i, value))
                    }
                }
            }
        }
    }
}
