import SwiftUI
import LumaCore
import LumaKit

// MARK: - Wording

/// Wording that names clock times, kept in one place so every screen that says why there is no score,
/// or how much of a night was recorded, says it in the same words. The reasons themselves are resolved
/// in LumaCore (`RecordCheck`); nothing here decides anything.
enum LumaWords {
    /// One line under an empty recovery ring.
    static func gapLine(_ gap: RecoveryGap?) -> String {
        switch gap {
        case .reading: return "Reading last night from your strap."
        case .calibrating(let c): return "Recovery starts after \(c.need) recorded nights. You have \(c.have)."
        case .noNight: return "No night recorded."
        case .stillGoing: return "Last night is still being recorded."
        case .cutOff(let at): return "Last night's record stops at \(LumaText.time(at)), so it has no score."
        case .unscored, .none: return "Last night has no recovery score."
        }
    }

    /// A word or two for the middle of an empty ring.
    static func gapLabel(_ gap: RecoveryGap?) -> String {
        switch gap {
        case .reading: return "Reading"
        case .calibrating: return "Learning"
        case .noNight: return "No night"
        case .stillGoing: return "Recording"
        case .cutOff: return "Part night"
        case .unscored, .none: return "No score"
        }
    }

    /// What goes under a night figure the record does not fully back.
    static func nightNote(_ night: NightRecord) -> String? {
        switch night {
        case .cutOff(let at, _): return "to \(LumaText.time(at))"
        case .stillGoing: return "so far"
        case .none, .unjudged, .complete: return nil
        }
    }

    /// A sentence saying how much of a night the record holds; nil for a whole one.
    static func nightSentence(_ night: NightRecord) -> String? {
        switch night {
        case .cutOff(let at, let resumes):
            if let resumes {
                return "The record of this night stops at \(LumaText.time(at)) and starts again at \(LumaText.time(resumes))."
            }
            return "The record of this night stops at \(LumaText.time(at))."
        case .stillGoing: return "This night is still being recorded."
        case .none, .unjudged, .complete: return nil
        }
    }
}

// MARK: - The notice

/// The one thing about the state of the data worth knowing now. It is resolved once (`LumaEnv.dataNotice`),
/// so every screen that carries this card says the same thing.
struct DataNoticeCard: View {
    /// Whether a notice about a hole offers the way to the data check. Off on the data check itself.
    var linksToRecord = true
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    /// The start of the hole whose notice was closed. Its figures stay marked wherever they show.
    @AppStorage("luma.notice.hole.closed") private var closedHole: Double = 0
    /// A strap takes a few seconds to connect after launch. "Not connected" is worth saying only once
    /// it has had that chance.
    @State private var settled = false

    private struct Content {
        var symbol: String
        var tint: Color
        var title: String
        var text: String
        var action: String? = nil
        var run: (() -> Void)? = nil
        var close: (() -> Void)? = nil
        var busy = false
    }

    private var content: Content? {
        // With no strap paired there is nothing to report on; setup covers that.
        guard !live.paired.isEmpty, let notice = env.dataNotice else { return nil }
        switch notice {
        case .offline(let lastSync):
            guard settled else { return nil }
            var text = "Luma is showing what it already had."
            if let lastSync {
                let when = Date(timeIntervalSince1970: lastSync).formatted(.relative(presentation: .named))
                text = "Luma is showing what it had when the strap was last read, \(when)."
            }
            if let note = live.strap.syncError, !note.isEmpty { text = note }
            return Content(symbol: "antenna.radiowaves.left.and.right.slash", tint: Luma.amber, title: "Strap not connected",
                           text: text, action: "Reconnect", run: { env.device?.reconnect() })
        case .notPaired:
            return Content(symbol: "lock.open.fill", tint: Luma.amber, title: "Connected, not paired",
                           text: "Heart rate arrives, but what the strap has stored can't be read until it is paired securely.",
                           action: "Open strap", run: { router.push(.devices) })
        case .needsRestart:
            return Content(symbol: "exclamationmark.arrow.triangle.2.circlepath", tint: Luma.amber, title: "Reads are not moving forward",
                           text: "The strap reports newer data than it is handing over.",
                           action: "Read again", run: { env.device?.syncNow() })
        case .reading(let parts):
            return Content(symbol: "arrow.triangle.2.circlepath", tint: Luma.sky, title: "Reading your strap",
                           text: "What it stored is still arriving (\(parts) parts so far). Today's numbers settle when it finishes.",
                           busy: true)
        case .pending:
            return Content(symbol: "tray.and.arrow.down.fill", tint: Luma.sky, title: "Your strap holds more than Luma has read",
                           text: "Newer data is on the strap and has not reached the phone yet.",
                           action: "Read it now", run: { env.device?.syncNow() })
        case .hole(let from, let to, let lost):
            guard closedHole != from else { return nil }
            var title = "Nothing recorded since \(LumaText.time(from))"
            if let to { title = "Nothing recorded from \(LumaText.time(from)) to \(LumaText.time(to))" }
            var text = "No heart rate reached the phone in that time, so last night is only part of a night. Its figures are marked, and it is left out of sleep debt and averages."
            if lost {
                text += " This strap hands over nothing it stored, so that part can't be brought back."
            } else {
                text += " If the strap still holds it, it arrives with the next read."
            }
            var hole = Content(symbol: "exclamationmark.triangle.fill", tint: Luma.amber, title: title, text: text)
            if linksToRecord {
                hole.action = "See the record"
                hole.run = { router.push(.dataCheck) }
                hole.close = { closedHole = from }
            }
            return hole
        case .notRecording:
            return Content(symbol: "record.circle", tint: Luma.amber, title: "Recording only while Luma is open",
                           text: "This strap hands over nothing it stored, and recording all the time is off. Whatever happens while Luma is closed, nights included, is not recorded.",
                           action: "Open settings", run: { router.push(.settings) })
        case .syncError(let text):
            return Content(symbol: "info.circle.fill", tint: Luma.amber, title: "About the last read of your strap",
                           text: text, action: "Read again", run: { env.device?.syncNow() })
        }
    }

    var body: some View {
        Group {
            if let c = content { card(c) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            settled = true
        }
    }

    private func card(_ c: Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if c.busy {
                ProgressView().controlSize(.small).tint(c.tint).frame(width: 18, height: 18)
            } else {
                Image(systemName: c.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(c.tint).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(c.title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                Text(c.text).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                if let label = c.action, let run = c.run {
                    Button(action: run) {
                        Text(label).font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(c.tint))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5)
                }
            }
            Spacer(minLength: 0)
            if let close = c.close {
                Button { withAnimation(LumaMotion.quick) { close() } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.mist)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumaPanel(tint: c.tint, radius: 22))
    }
}

/// Said above a night only part of which is in the record.
struct NightRecordNote: View {
    let night: NightRecord

    var body: some View {
        if let sentence = LumaWords.nightSentence(night) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Part of a night").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                    Text("\(sentence) Everything below covers the recorded part only, so it has no score and is not set against what you needed.")
                        .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LumaPanel(tint: Luma.amber, radius: 22))
        }
    }
}

// MARK: - Data check

/// Where heart rate reached the phone, hour by hour, with the nights and days as stored and the facts
/// the strap layer reports. Everything on it is a reading or a count; nothing is interpreted.
struct DataCheckScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @State private var facts: [LFact] = []

    /// The moment the record on screen was read.
    private var asOf: Double { env.recordReadAt ?? Date().timeIntervalSince1970 }

    /// The readings listed under their own headings: what the strap layer and iOS report, then how
    /// the athlete's own records came off the disk.
    private var shown: [LFact] { facts + env.storeFacts }

    private var ownFacts: [LFact] {
        var out: [LFact] = []
        out.append(LFact("Luma", "Record all the time", env.profile.continuousRecording ? "on" : "off"))
        if let c = env.calibration { out.append(LFact("Luma", "Recovery baseline", "\(c.have) of \(c.need) nights")) }
        out.append(LFact("Luma", "Nights marked part recorded", env.nightMarks.isEmpty ? "none" : env.nightMarks.map { $0.day }.joined(separator: ", ")))
        out.append(contentsOf: env.experimentFacts)
        return out
    }

    private var report: String {
        RecordReport.text(version: env.versionLine, now: asOf, stretches: env.record, night: env.analysis.night, sleeps: env.sleeps,
                          days: env.days, marks: env.nightMarks, facts: ownFacts + shown)
    }

    var body: some View {
        let hours = RecordCheck.hourly(env.record, endingAt: asOf, hours: 24)
        let holes = RecordCheck.gaps(env.record, from: asOf - 24 * 3600, to: asOf, minimum: RecordCheck.listedHoleSeconds)
        let recorded: Double = hours.reduce(0.0) { $0 + $1.seconds }
        LumaDetailScreen(title: "Data check", tone: .neutral) {
            DataNoticeCard(linksToRecord: false)

            LumaSection(title: "Heart rate reaching the phone")
            LumaCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            LumaLabel("Last 24 hours")
                            Text(LFormat.hm(minutes: recorded / 60)).font(LumaFont.numeral(34)).foregroundStyle(Luma.frost)
                        }
                        Spacer()
                        Text("as of \(LumaText.time(asOf))").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mist)
                    }
                    CoverageStrip(hours: hours)
                    if holes.isEmpty {
                        LumaNote("No hole of twenty minutes or more.")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            LumaLabel("Nothing recorded")
                            ForEach(Array(holes.enumerated()), id: \.offset) { _, hole in
                                HStack {
                                    Text(LumaText.span(hole.start, hole.end))
                                        .font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                    Spacer()
                                    Text(LFormat.hm(minutes: hole.seconds / 60)).font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.amber)
                                }
                            }
                        }
                    }
                    LumaNote("Each bar is one hour, the newest on the right. A full bar is sixty minutes of readings. Scores can only be as complete as this record.")
                }
            }

            LumaSection(title: "Last night")
            LumaGroup {
                if let main = env.analysis.sleep.last.flatMap({ $0.day == env.today ? $0.main : nil }) {
                    fact("Stored as", "\(LumaText.time(main.start)) – \(LumaText.time(main.end))")
                } else {
                    fact("Stored as", "No night stored for today")
                }
                fact("Its record", recordLine)
                if let c = env.calibration { fact("Recovery baseline", "\(c.have) of \(c.need) nights") }
            }

            ForEach(sections, id: \.self) { section in
                LumaSection(title: section)
                LumaGroup {
                    ForEach(shown.filter { $0.section == section }) { f in fact(f.label, f.value) }
                    if section == "Your records" {
                        Button { router.push(.backups) } label: {
                            LumaRow(symbol: "clock.arrow.circlepath", symbolColor: Luma.sky, title: "Copies of your records", chevron: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ShareLink(item: report) { Label("Send this report", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
            Button("Read everything again") { env.reload() }.buttonStyle(LumaSecondaryButtonStyle())
            LumaNote("The report is plain text: the times, counts and figures on this screen. It goes only where you send it.")
        }
        .task(id: "\(LNum.int(asOf))|\(live.strap.connected)|\(live.strap.syncing)") { facts = await env.source.facts() }
    }

    /// What is known about the record behind last night. A night nothing covers is said to be that,
    /// not passed off as whole.
    private var recordLine: String {
        switch env.analysis.night {
        case .none: return "–"
        case .unjudged: return "No heart-rate record covers this night, so it is shown as stored."
        case .complete: return "Whole: no hour or more is missing in it or right after it."
        case .cutOff, .stillGoing: return LumaWords.nightSentence(env.analysis.night) ?? "–"
        }
    }

    /// Fact headings in the order they first appear.
    private var sections: [String] {
        var seen: [String] = []
        for f in shown where !seen.contains(f.section) { seen.append(f.section) }
        return seen
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(LumaFont.body(14)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(value).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

/// Twenty-four bars, one an hour, each as tall as the share of that hour with heart-rate readings.
struct CoverageStrip: View {
    let hours: [(hourStart: Double, seconds: Double)]

    private let barHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                    bar(share: min(1, max(0, hour.seconds / 3600)))
                }
            }
            HStack {
                Text(hours.first.map { LumaText.time($0.hourStart) } ?? "")
                Spacer()
                Text(hours.count > 12 ? LumaText.time(hours[hours.count / 2].hourStart) : "")
                Spacer()
                Text("now")
            }
            .font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let withReadings: Int = hours.filter { $0.seconds > 0 }.count
        return "Heart rate recorded in \(withReadings) of the last \(hours.count) hours"
    }

    private func bar(share: Double) -> some View {
        let filled: CGFloat = share > 0 ? max(3, barHeight * CGFloat(share)) : 0
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.white.opacity(0.07))
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(share >= 0.9 ? Luma.volt : Luma.amber)
                .frame(height: filled)
        }
        .frame(maxWidth: .infinity)
        .frame(height: barHeight)
    }
}
