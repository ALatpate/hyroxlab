import SwiftUI
import LumaCore
import LumaKit

// MARK: - Counting from motion: what the app keeps
//
// An experiment (`LumaCore/Motion.swift`). It is off until switched on, shows beside a session and
// changes nothing in it, and has been checked only against made-up motion. Every screen here says so.

extension LumaEnv {
    /// The count kept for one recording.
    func motionRead(_ id: String) -> MotionRead? { motionReads.first { $0.id == id } }

    /// The count kept for the recording that shares the most time with a session, when it shares at
    /// least half of the shorter of the two.
    func motionRead(from start: Date, to end: Date) -> MotionRead? {
        var best: MotionRead?
        var most = 0.0
        for read in motionReads {
            let shared = min(end, read.endedAt).timeIntervalSince(max(start, read.startedAt))
            if shared > most { most = shared; best = read }
        }
        guard let found = best else { return nil }
        return most >= 20 && most >= 0.5 * min(end.timeIntervalSince(start), found.seconds) ? found : nil
    }

    /// What a part with a name that says nothing is taken for, in a recording with this note.
    static func otherKind(note: String) -> MotionKind {
        MotionKind.named(note) == .run || note.lowercased().contains("interval") ? .run : .work
    }

    /// Counts from one recording's motion and keeps what was found. The sums are done away from the
    /// screen: an hour's session is a third of a million readings.
    func countMotion(_ recording: LumaMotionRecording, other: MotionKind) async {
        guard extras.motionCounts, let control = device, !motionReading.contains(recording.id) else { return }
        motionReading.insert(recording.id)
        let seconds = await control.motionSeconds(recording.id)
        let read = await Task.detached(priority: .userInitiated) {
            MotionRead.make(id: recording.id, startedAt: recording.startedAt, seconds: recording.seconds,
                            marks: recording.marks, track: MotionTrack.build(seconds), other: other)
        }.value
        motionReading.remove(recording.id)
        keepCount(read)
    }

    /// Counts from the recording made with a session, when there is one and it has not been counted.
    func countMotion(from start: Date, to end: Date, other: MotionKind) async {
        guard extras.motionCounts, motionRead(from: start, to: end) == nil, let control = device else { return }
        let recordings = await control.motionRecordings()
        var best: LumaMotionRecording?
        var most = 0.0
        for r in recordings {
            let shared = min(end, r.endedAt).timeIntervalSince(max(start, r.startedAt))
            if shared > most { most = shared; best = r }
        }
        guard let found = best, most >= 20, most >= 0.5 * min(end.timeIntervalSince(start), found.seconds) else { return }
        await countMotion(found, other: other)
    }

    /// Keeps a count, newest first. The real numbers entered against an earlier count of the same
    /// recording stay with the parts that are still the same parts.
    func keepCount(_ read: MotionRead) {
        var new = read
        if let old = motionRead(read.id) {
            for i in new.parts.indices {
                let part = new.parts[i]
                if let was = old.parts.first(where: { $0.label == part.label && abs($0.startS - part.startS) < 5 }) {
                    new.parts[i].actual = was.actual
                }
            }
        }
        let rest = motionReads.filter { $0.id != read.id }
        motionReads = Array(([new] + rest).sorted { $0.startedAt > $1.startedAt }.prefix(60))
    }

    /// The athlete's own number for one part: steps a minute for a run, the count for the rest.
    func setActual(_ value: Int?, read id: String, part: Int) {
        guard let r = motionReads.firstIndex(where: { $0.id == id }),
              let p = motionReads[r].parts.firstIndex(where: { $0.id == part }) else { return }
        motionReads[r].parts[p].actual = value
    }
}

extension LumaEnv {
    /// What the two experiments last did, as readings, for the Data check: neither has been tried on a
    /// strap from here, so these are what would say how a first real attempt went.
    var experimentFacts: [LFact] {
        var out: [LFact] = []
        func two(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "not measured" }
        let motion = "Counting from motion"
        out.append(LFact(motion, "Recording motion with sessions", extras.motion ? "on" : "off"))
        out.append(LFact(motion, "Counting from it", extras.motionCounts ? "on" : "off"))
        out.append(LFact(motion, "Counts kept", String(motionReads.count)))
        if let last = motionReads.first {
            out.append(LFact(motion, "Last recording counted", last.startedAt.formatted(date: .abbreviated, time: .shortened)))
            out.append(LFact(motion, "Its parts", "\(last.parts.count), \(last.fromMotion ? "found by the motion" : "marked by the session")"))
            out.append(LFact(motion, "How its seconds join (about 1 when they do)", two(last.seamRatio)))
            out.append(LFact(motion, "Why nothing was counted", last.problem ?? "something was"))
        }
        let trace = "Traces read"
        out.append(LFact(trace, "Traces kept", String(traces.count)))
        if let last = traces.first {
            out.append(LFact(trace, "Last trace", last.takenAt.formatted(date: .abbreviated, time: .shortened)))
            out.append(LFact(trace, "Packets, and packets missing", "\(last.packets), \(last.lost)"))
            out.append(LFact(trace, "Readings", String(last.samples)))
            out.append(LFact(trace, "Readings a second, measured", two(last.perSecond)))
            out.append(LFact(trace, "The strap's clock gave the same pace", last.clocksAgree.map { $0 ? "yes" : "no" } ?? "the strap gave no clock"))
            out.append(LFact(trace, "How its packets join (about 1 when they do)", two(last.seamRatio)))
            out.append(LFact(trace, "Beats found", String(last.beats)))
            out.append(LFact(trace, "Why no figure", last.problem?.rawValue ?? "a figure was given"))
        }
        return out
    }
}

/// What every screen that shows a count says about it.
enum MotionWords {
    static let limits = "Counted from the movement of your wrist, by a method checked so far only against made-up movement. Walking about between sets repeats too, and is counted with them. Enter your own number beside a count and Luma keeps score of itself."
    static let split = "This session marked no parts, so Luma split it by the movement alone: running where your wrist shows footfalls at a running pace, rest where it is still, work for everything between. It cannot tell one station from another, or a carry from a station."

    static func when(_ part: MotionPart) -> String {
        LumaText.duration(part.startS) + " for " + LumaText.duration(part.durationS)
    }
}

// MARK: - On a session's own screen

/// What was counted from a session's motion, where it was recorded with motion and counting is on.
/// The session's own figures are its record; this is an estimate beside them, and says so.
struct MotionCard: View {
    let start: Date
    let end: Date
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        if env.extras.motionCounts, let read = env.motionRead(from: start, to: end) {
            let counted = read.parts.filter { $0.said != nil }
            LumaCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        LumaLabel("Counted from wrist motion")
                        Spacer()
                        LumaPill(text: "Experimental", color: Luma.amber)
                    }
                    if let problem = read.problem {
                        LumaNote(problem)
                    } else if counted.isEmpty {
                        LumaNote("Nothing in this session repeated steadily enough to count.")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(counted.prefix(6)) { part in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(part.label).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(part.said ?? "").font(LumaFont.body(14.5)).foregroundStyle(Luma.mist).lineLimit(1)
                                }
                            }
                        }
                        if counted.count > 6 {
                            Text("and \(counted.count - 6) more").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                        }
                        if read.fromMotion { LumaNote("The parts were found by the movement itself, not marked.") }
                    }
                    Button("See the counts, and check them") { router.push(.motion(read.id)) }
                        .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }
}

// MARK: - One recording, counted

struct MotionReadScreen: View {
    let id: String
    @EnvironmentObject private var env: LumaEnv
    @State private var recording: LumaMotionRecording?
    @State private var looked = false

    var body: some View {
        let read = env.motionRead(id)
        LumaDetailScreen(title: "Counted from motion", tone: .run) {
            LumaCard(tint: Luma.amber.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title(read)).font(LumaFont.heading(18)).foregroundStyle(Luma.frost).lineLimit(2)
                        Spacer()
                        LumaPill(text: "Experimental", color: Luma.amber)
                    }
                    if let at = read?.startedAt ?? recording?.startedAt, let seconds = read?.seconds ?? recording?.seconds {
                        Text("\(at.formatted(date: .abbreviated, time: .shortened)) · \(LumaText.duration(seconds))")
                            .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                    }
                    LumaNote(MotionWords.limits)
                }
            }
            if !env.extras.motionCounts {
                LumaCard {
                    Toggle(isOn: Binding(get: { env.extras.motionCounts }, set: { on in var e = env.extras; e.motionCounts = on; env.extras = e })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Count from motion").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                            Text("Off. Switch it on to count from this recording.").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                        }
                    }
                    .tint(Luma.volt)
                }
            } else if let read {
                if let problem = read.problem {
                    LumaCard { LumaNote(problem) }
                } else {
                    if read.fromMotion { LumaNote(MotionWords.split) }
                    LumaGroup {
                        ForEach(read.parts) { part in MotionPartRow(readID: read.id, part: part) }
                    }
                    if let checks = MotionChecks.summary(env.motionReads) {
                        LumaCard {
                            VStack(alignment: .leading, spacing: 6) {
                                LumaLabel("How right it has been")
                                Text(checks.line).font(LumaFont.body(15)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let recording, !env.motionReading.contains(id) {
                    Button("Count again") { Task { await env.countMotion(recording, other: LumaEnv.otherKind(note: recording.note)) } }
                        .buttonStyle(LumaSecondaryButtonStyle())
                }
            } else if env.motionReading.contains(id) || !looked {
                LumaCard {
                    HStack(spacing: 12) {
                        ProgressView().tint(Luma.volt)
                        Text("Counting from the motion").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                    }
                }
            } else {
                LumaCard { LumaEmpty(symbol: "waveform.path", title: "Nothing to count from", message: "This recording is no longer on the phone, or the strap is not set up here.") }
            }
        }
        .task(id: id) {
            let all = await env.device?.motionRecordings() ?? []
            recording = all.first { $0.id == id }
            looked = true
            if let found = recording, env.motionRead(id) == nil {
                await env.countMotion(found, other: LumaEnv.otherKind(note: found.note))
            }
        }
    }

    private func title(_ read: MotionRead?) -> String {
        if let note = recording?.note, !note.isEmpty { return note }
        return read == nil ? "Recording" : "Session"
    }
}

/// One part of a recording: what it was, when, what was counted, and the athlete's own number.
private struct MotionPartRow: View {
    let readID: String
    let part: MotionPart
    @EnvironmentObject private var env: LumaEnv
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.label).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).lineLimit(1)
                    Text(MotionWords.when(part)).font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                }
                Spacer(minLength: 8)
                Text(part.said ?? (part.kind.counts ? "too little recorded" : "not counted"))
                    .font(LumaFont.body(15, part.said == nil ? .regular : .semibold))
                    .foregroundStyle(part.said == nil ? Luma.smoke : Luma.frost)
                    .multilineTextAlignment(.trailing)
            }
            if part.uneven {
                Text("The movement kept a beat for less than half of this part, so this is likely an undercount.")
                    .font(LumaFont.body(12.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true)
            }
            if let figure = part.figure {
                HStack(spacing: 10) {
                    Text(part.kind.byPace ? "Your real steps a minute" : "Your real count").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                    Spacer(minLength: 6)
                    TextField("", text: $typed, prompt: Text("enter").foregroundStyle(Luma.smoke))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                        .frame(width: 72)
                        .padding(.vertical, 7).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                if let actual = part.actual, actual > 0 {
                    let off = LNum.int((abs(Double(figure - actual)) / Double(actual) * 100).rounded())
                    Text(off == 0 ? "Luma had it right." : "Luma said \(figure), you say \(actual): off by \(off)%.")
                        .font(LumaFont.body(12.5)).foregroundStyle(off <= 5 ? Luma.mint : Luma.amber)
                }
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 16)
        .onAppear { typed = part.actual.map { String($0) } ?? "" }
        .onChange(of: typed) { _, text in
            let digits = text.filter { $0.isNumber }
            let value = Int(digits).flatMap { $0 > 0 && $0 < 100_000 ? $0 : nil }
            if value != part.actual { env.setActual(value, read: readID, part: part.id) }
        }
    }
}
