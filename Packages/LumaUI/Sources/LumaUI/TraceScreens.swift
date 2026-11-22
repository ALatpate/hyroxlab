import SwiftUI
import LumaCore
import LumaKit

// MARK: - A trace from the clasp: the trial
//
// A WHOOP MG can send the signal between the electrodes in its clasp. This screen asks for one reading
// of it, keeps the trace, and counts its beats (`LumaCore/ECGTrace.swift`). It is a trial: the strap
// layer has the commands and nobody has shown them to work on a strap from here.
//
// What it is not is said on the screen and held to in the code. Luma gives no verdict on a trace, looks
// for no rhythm problem, and never shows what the strap's own software concluded about one. Every
// command is sent because the athlete tapped for it and then confirmed it.

extension LumaEnv {
    /// A trace has ended: what arrived is read and kept, newest first. Called by the app.
    public func takeTrace(_ packets: [ECGPacket], wristHeartRate: Int?) {
        let read = ECGReader.read(id: UUID().uuidString, takenAt: Date(), packets: packets, wristHeartRate: wristHeartRate)
        traces = Array(([read] + traces).prefix(12))
    }

    func forgetTrace(_ id: String) { traces.removeAll { $0.id == id } }
}

enum TraceWords {
    static let what = "Your WHOOP MG has two electrodes in its clasp. Held with a finger and thumb of your other hand, they pick up your heartbeat itself, which gives a heart rate counted beat by beat."
    static let trial = "A trial. Luma sends the strap the commands that start and stop a reading. Nobody has yet shown from here that they work on this strap's software, so a reading may come back empty."
    static let not = "This is a recording of a signal, not a check of your heart. Luma does not look for rhythm problems, cannot tell you whether a trace is as it should be, and shows nothing the strap's own software concluded. If you are worried about your heart, see a doctor."
    static let hold = "Sit still, arm resting. Hold the clasp between a finger and thumb of your other hand and keep holding until it ends: about 40 seconds, a minute at most."
    static let variation = "How much the time from one beat to the next changed during this reading. It is not the overnight HRV figure, which is taken while you sleep."
}

struct TraceScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @State private var asking: Ask?
    @State private var shown: String?

    private enum Ask: String, Identifiable {
        case switchOn, left, right, take
        var id: String { rawValue }

        var title: String {
            switch self {
            case .switchOn: return "Switch the trial on?"
            case .left: return "Tell the strap it is on your left wrist?"
            case .right: return "Tell the strap it is on your right wrist?"
            case .take: return "Take a trace now?"
            }
        }

        var message: String {
            switch self {
            case .switchOn: return "Luma will be able to send the strap the commands for a trace. Each one is still sent only when you tap for it. Switching the trial off stops a trace that may be running."
            case .left, .right: return "The strap needs to know before a trace. It may keep this after the app closes; telling it the other wrist is how to change it."
            case .take: return TraceWords.hold
            }
        }

        var confirm: String {
            switch self {
            case .switchOn: return "Switch on"
            case .left: return "Tell it: left"
            case .right: return "Tell it: right"
            case .take: return "Start"
            }
        }
    }

    private var current: ECGRead? { env.traces.first { $0.id == shown } ?? env.traces.first }

    var body: some View {
        let t = live.trace
        LumaDetailScreen(title: "Trace from the clasp", tone: .heart) {
            LumaCard(tint: Luma.amber.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("A trace of your heartbeat").font(LumaFont.heading(18)).foregroundStyle(Luma.frost)
                        Spacer()
                        LumaPill(text: "Trial", color: Luma.amber)
                    }
                    LumaNote(TraceWords.what)
                    LumaNote(TraceWords.trial)
                    Toggle(isOn: Binding(get: { t.on }, set: { on in
                        if on { asking = .switchOn } else { env.device?.setTraceTrial(false) }
                    })) {
                        Text("Try the trace").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                    }
                    .tint(Luma.volt)
                }
            }
            if t.mayStillRun, !t.running {
                LumaCard(tint: Luma.amber.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A trace may still be running on the strap").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        LumaNote("One was started and never seen to stop. It uses the strap's battery while it runs. Stopping needs the strap connected.")
                        Button("Stop it") { env.device?.stopTrace() }.buttonStyle(LumaPrimaryButtonStyle(color: Luma.amber, compact: true))
                    }
                }
            }
            if t.on { controls(t) }
            if !t.answers.isEmpty || t.said != nil { answers(t) }
            if let read = current { result(read) }
            if env.traces.count > 1 { history }
            LumaNote(TraceWords.not)
        }
        .confirmationDialog(asking?.title ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }),
                            titleVisibility: .visible, presenting: asking) { ask in
            Button(ask.confirm) {
                switch ask {
                case .switchOn: env.device?.setTraceTrial(true)
                case .left: env.device?.tellWrist(left: true)
                case .right: env.device?.tellWrist(left: false)
                case .take: env.device?.startTrace()
                }
            }
            Button("Not now", role: .cancel) {}
        } message: { ask in
            Text(ask.message)
        }
    }

    // MARK: Asking for one

    @ViewBuilder
    private func controls(_ t: LumaTraceState) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("First, the wrist")
                HStack(spacing: 10) {
                    Button("Left wrist") { asking = .left }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                    Button("Right wrist") { asking = .right }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
                .disabled(t.running || t.blocked != nil)
                LumaNote(t.wristTold.map { "The strap was told: \($0) wrist. How it answered is below." }
                         ?? "The strap is told which wrist it is on before a trace. Luma has not told it since the app opened.")
            }
        }
        LumaCard(tint: t.running ? Luma.coral.opacity(0.6) : nil) {
            VStack(alignment: .leading, spacing: 12) {
                if let started = t.startedAt {
                    TimelineView(.periodic(from: started, by: 1)) { moment in
                        let seconds = max(0, LNum.int(moment.date.timeIntervalSince(started)))
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(seconds)").font(LumaFont.numeral(54)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                            Text("seconds").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                        }
                    }
                    LumaNote(TraceWords.hold)
                    Button("Stop") { env.device?.stopTrace() }.buttonStyle(LumaSecondaryButtonStyle())
                } else if t.reading {
                    HStack(spacing: 12) {
                        ProgressView().tint(Luma.volt)
                        Text("Reading what arrived").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                    }
                } else {
                    LumaLabel("Then, the trace")
                    LumaNote(TraceWords.hold)
                    Button("Take a trace") { asking = .take }
                        .buttonStyle(LumaPrimaryButtonStyle())
                        .disabled(t.blocked != nil)
                    if let blocked = t.blocked {
                        Text(blocked).font(LumaFont.body(13.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func answers(_ t: LumaTraceState) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 8) {
                LumaLabel("What the strap answered")
                ForEach(Array(t.answers.enumerated()), id: \.offset) { _, line in
                    Text(line).font(LumaFont.body(14)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                }
                if let said = t.said { LumaNote(said) }
                LumaNote("Accepted means the strap took the command, not that a trace followed.")
            }
        }
    }

    // MARK: What came of it

    @ViewBuilder
    private func result(_ read: ECGRead) -> some View {
        LumaSection(title: read.takenAt.formatted(date: .abbreviated, time: .shortened))
        LumaCard {
            VStack(alignment: .leading, spacing: 14) {
                if let rate = read.beatsAMinute {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(rate)").font(LumaFont.numeral(64, .heavy)).foregroundStyle(Luma.frost)
                        Text("beats a minute").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                    }
                    Text(TraceScreen.counted(read)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                    if let variation = read.variationMs {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(LNum.int(variation.rounded())) ms between beats").font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                            LumaNote(TraceWords.variation)
                        }
                    }
                } else if let problem = read.problem {
                    Text("No figure from this trace").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    LumaNote(problem.text)
                }
                ForEach(TraceScreen.facts(read), id: \.self) { fact in
                    Text(fact).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if read.trace.count > 10 {
            LumaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    LumaLabel("The trace")
                    TraceChart(read: read)
                    LumaNote(read.perSecond == nil
                             ? "Drawn reading by reading, because how fast it was read could not be measured. The height has no unit."
                             : "Drag to see all of it. The marks along the top are the beats Luma found. The height has no unit: the strap's numbers are drawn as they came.")
                }
            }
        }
        Button("Remove this trace") { env.forgetTrace(read.id) }
            .font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
    }

    static func counted(_ read: ECGRead) -> String {
        guard let seconds = read.seconds else { return "Counted from \(read.beats) beats." }
        return "Counted from \(read.beats) beats in \(LNum.int(seconds.rounded())) seconds."
    }

    /// The things about a reading that are not its figures: how it was timed, what else read the heart
    /// at the same moment, and what was missing.
    static func facts(_ read: ECGRead) -> [String] {
        var out: [String] = []
        if let pace = read.perSecond {
            let agreed = read.clocksAgree == true ? ", by the phone's clock and the strap's" : ", by the phone's clock"
            out.append("Read \(LNum.int(pace.rounded())) times a second, measured from this trace\(agreed).")
        }
        if let own = read.strapHeartRate, read.heartRate != nil { out.append("The strap's own figure for this trace: \(own).") }
        if let wrist = read.wristHeartRate, read.heartRate != nil { out.append("The wrist's light sensor at the time: \(wrist).") }
        if read.samples > 0, read.contactShare < 0.9 {
            out.append("The strap reported the clasp held for \(LNum.int((read.contactShare * 100).rounded()))% of the reading.")
        }
        if read.lost > 0 { out.append("\(read.lost) piece\(read.lost == 1 ? "" : "s") of the trace did not arrive.") }
        return out
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            LumaSection(title: "Earlier traces")
            LumaGroup {
                ForEach(env.traces) { read in
                    Button { shown = read.id } label: {
                        LumaRow(symbol: "waveform.path.ecg", symbolColor: read.id == current?.id ? Luma.volt : Luma.mist,
                                title: read.takenAt.formatted(date: .abbreviated, time: .shortened),
                                subtitle: read.beatsAMinute.map { "\($0) beats a minute" } ?? "No figure")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The trace, drawn as it came: a line, the beats found marked along the top, and seconds along the
/// bottom where the pace was measured. It scrolls sideways, a second to every forty points.
struct TraceChart: View {
    let read: ECGRead
    private let height: CGFloat = 170

    var body: some View {
        let values = read.trace
        let perPoint = read.perSecond.map { $0 / 40 } ?? 2.5
        let width = max(300, CGFloat(Double(values.count) / perPoint))
        ScrollView(.horizontal) {
            Canvas { context, size in
                guard values.count > 1 else { return }
                let range = TraceChart.range(values)
                let top: CGFloat = 14, bottom: CGFloat = 18
                let plot = size.height - top - bottom
                func x(_ i: Int) -> CGFloat { size.width * CGFloat(i) / CGFloat(values.count - 1) }
                func y(_ v: Int) -> CGFloat {
                    let share = (Double(v) - range.lowerBound) / (range.upperBound - range.lowerBound)
                    return top + plot * CGFloat(1 - min(1, max(0, share)))
                }
                // Seconds, where they are known.
                if let pace = read.perSecond {
                    var second = 0
                    while Double(second) * pace < Double(values.count) {
                        let at = x(LNum.int(Double(second) * pace))
                        var tick = Path()
                        tick.move(to: CGPoint(x: at, y: top))
                        tick.addLine(to: CGPoint(x: at, y: top + plot))
                        context.stroke(tick, with: .color(Luma.line), lineWidth: second % 5 == 0 ? 1 : 0.5)
                        if second % 5 == 0 {
                            context.draw(Text("\(second) s").font(LumaFont.body(10)).foregroundColor(Luma.smoke),
                                         at: CGPoint(x: at + 3, y: size.height - 8), anchor: .leading)
                        }
                        second += 1
                    }
                }
                var line = Path()
                line.move(to: CGPoint(x: x(0), y: y(values[0])))
                for i in 1..<values.count { line.addLine(to: CGPoint(x: x(i), y: y(values[i]))) }
                context.stroke(line, with: .color(Luma.coral), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                for beat in read.beatsAt where beat >= 0 && beat < values.count {
                    var mark = Path()
                    mark.move(to: CGPoint(x: x(beat), y: 2))
                    mark.addLine(to: CGPoint(x: x(beat), y: 10))
                    context.stroke(mark, with: .color(Luma.volt), lineWidth: 2)
                }
            }
            .frame(width: width, height: height)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(read.beatsAMinute.map { "The trace, with \(read.beats) beats marked: \($0) beats a minute." } ?? "The trace.")
    }

    /// The span of heights drawn: nearly all of the trace, with a little room, so that one wild reading
    /// does not flatten the rest.
    static func range(_ values: [Int]) -> ClosedRange<Double> {
        let sorted = values.sorted()
        let low = Double(sorted[sorted.count / 200]), high = Double(sorted[sorted.count - 1 - sorted.count / 200])
        let room = max(1, (high - low) * 0.12)
        return (low - room)...(high + room)
    }
}

// MARK: - The gallery

/// A made-up trace and a made-up count, for the gallery's pictures of these screens. The trace is a
/// drawn heartbeat at a steady rate, read by the same code a real one would be.
enum LumaDemoStrap {
    static func stage(_ env: LumaEnv) {
        var e = env.extras
        e.motion = true
        e.motionCounts = true
        env.extras = e
        env.live.strap.hasClasp = true
        var t = LumaTraceState()
        t.on = true
        t.wristTold = "left"
        t.answers = ["Asking for the trace to be sent: accepted", "Asking the strap to keep its own copy: accepted", "Starting the reading: accepted"]
        env.live.trace = t
        let now = Date()
        env.traces = [ECGReader.read(id: "demo-trace", takenAt: now.addingTimeInterval(-3 * 3600), packets: packets(), wristHeartRate: 59)]
        let started = now.addingTimeInterval(-26 * 3600)
        var read = MotionRead(id: "demo-motion", startedAt: started, seconds: 2710, fromMotion: true)
        let parts: [(MotionKind, Double, Double, Int?, Double?, Double, Int?)] = [
            (.run, 0, 318, 884, 166.8, 1, 168), (.work, 318, 252, 96, 23.1, 0.92, 100), (.rest, 570, 64, nil, nil, 0, nil),
            (.run, 634, 305, 852, 167.6, 1, nil), (.work, 939, 268, 148, 41.5, 0.97, 150), (.rest, 1207, 58, nil, nil, 0, nil),
            (.run, 1265, 322, 890, 165.9, 0.99, nil), (.work, 1587, 296, 61, 15.2, 0.44, 80), (.run, 1883, 331, 908, 164.6, 1, nil),
            (.work, 2214, 240, 118, 30.4, 0.95, nil), (.run, 2454, 256, 712, 166.9, 1, nil),
        ]
        for (i, p) in parts.enumerated() {
            read.parts.append(MotionPart(id: i, label: p.0.title, kind: p.0, startS: p.1, durationS: p.2, count: p.3, perMinute: p.4, steady: p.5, actual: p.6))
        }
        env.motionReads = [read]
    }

    /// A made-up count for one session, so the gallery can show the card on a session's own screen.
    static func stage(_ env: LumaEnv, sessionFrom start: Double, to end: Double) {
        var read = MotionRead(id: "demo-session", startedAt: Date(timeIntervalSince1970: start), seconds: end - start, fromMotion: true)
        let length = end - start
        read.parts = [
            MotionPart(id: 0, label: "Run", kind: .run, startS: 0, durationS: length * 0.46, count: LNum.int(length * 0.46 / 60 * 167), perMinute: 167.2, steady: 1),
            MotionPart(id: 1, label: "Rest", kind: .rest, startS: length * 0.46, durationS: length * 0.06),
            MotionPart(id: 2, label: "Run", kind: .run, startS: length * 0.52, durationS: length * 0.48, count: LNum.int(length * 0.48 / 60 * 169), perMinute: 169.4, steady: 0.98),
        ]
        env.motionReads = [read] + env.motionReads.filter { $0.id != read.id }
    }

    /// Forty seconds of a drawn heartbeat at about 58 a minute, cut into packets as the strap sends them.
    static func packets() -> [ECGPacket] {
        var state: UInt64 = 21
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / 9007199254740992.0 * 2 - 1
        }
        var beats = [0.5]
        while beats[beats.count - 1] < 43 { beats.append(beats[beats.count - 1] + 1.03 + 0.05 * next()) }
        let waves: [(Double, Double, Double)] = [(-0.16, 0.12, 0.025), (-0.026, -0.10, 0.008), (0, 1, 0.012), (0.03, -0.22, 0.010), (0.25, 0.30, 0.04)]
        var samples = [Int](repeating: 0, count: 200)
        var first = 0
        for i in 0..<4000 {
            let t = Double(i) / 100
            while first + 1 < beats.count, beats[first + 1] < t - 0.5 { first += 1 }
            var v = 0.0
            for b in beats[max(0, first - 1)..<min(beats.count, first + 4)] {
                for (at, tall, wide) in waves {
                    let dt = t - b - at
                    if abs(dt) < 5 * wide { v += tall * exp(-0.5 * (dt / wide) * (dt / wide)) }
                }
            }
            samples.append(LNum.int((1400 * v + 160 * sin(2 * Double.pi * 0.22 * t) + 14 * next()).rounded()))
        }
        var out: [ECGPacket] = []
        var k = 0
        while k < samples.count {
            let chunk = Array(samples[k..<min(samples.count, k + 100)])
            let arrived = 1_000_000 + LNum.int(Double(k + chunk.count) * 10 + 45 + 20 * next())
            out.append(ECGPacket(sequence: 40 + out.count, arrivedMs: arrived, strapTime: 7000 + Double(k) / 100, samples: chunk, strapHeartRate: k < 600 ? nil : 58))
            k += 100
        }
        return out
    }
}
