import SwiftUI
import LumaCore
import LumaKit

// MARK: - An official race, typed in or read from its results page
//
// A race that was run with a chip on the ankle is kept beside the sessions recorded here: its
// results page gives eight runs, eight stations, the roxzone total and the finish time, and that is
// what the form asks for. A picture of the page can fill the form in; nothing is kept until the
// athlete has looked at it and said so, and a time the reading did not get is left empty.

/// One time on the form: what is typed, and the seconds it stands for.
private struct SplitBox: View {
    let label: String
    var symbol: String? = nil
    @Binding var seconds: Double?
    @State private var text = ""
    @FocusState private var typing: Bool

    private var unread: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty && seconds == nil }

    var body: some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.volt).frame(width: 22)
            }
            Text(label).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            TextField("m:ss", text: $text, prompt: Text("m:ss").foregroundStyle(Luma.smoke))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(LumaFont.numeral(20, .semibold))
                .foregroundStyle(unread ? Luma.coral : Luma.frost)
                .frame(width: 104)
                .focused($typing)
                .onChange(of: text) { _, typed in
                    // Only what is being typed changes the time: text written in from the time must not write it back.
                    if typing { seconds = SplitText.typedSeconds(typed) }
                }
                .onChange(of: typing) { _, on in
                    // Leaving the box writes the time the way a results page would.
                    if !on, let seconds { text = SplitText.raceClock(seconds) }
                }
        }
        .padding(.vertical, 9).padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { typing = true }
        .onAppear { text = seconds.map { SplitText.raceClock($0) } ?? "" }
        // Filled in from a reading of the page while nobody is typing here.
        .onChange(of: seconds) { _, value in
            if !typing { text = value.map { SplitText.raceClock($0) } ?? "" }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

/// Add an official race, or correct one that was added.
struct RaceEntrySheet: View {
    /// The race being corrected; nil for a new one.
    let editing: UUID?
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss

    @State private var entry = RaceEntry(startedAt: Date(), format: .openSingles, sex: .male)
    @State private var photos: [PickedPhoto] = []
    @State private var busy = false
    @State private var error: String?
    @State private var logToo = true
    @State private var ready = false

    var body: some View {
        LumaSheet(title: editing == nil ? "Add a race" : "Correct the race", tone: .run) {
            if editing == nil { reading }

            LumaField(title: "Race name, e.g. HYROX Dublin", text: $entry.event)
            DatePicker("Race start", selection: $entry.startedAt, in: ...Date()).font(LumaFont.body(15)).foregroundStyle(Luma.frost).colorScheme(.dark)
            FlowLayout(spacing: 8) {
                ForEach(RaceFormat.allCases) { format in
                    LumaChip(title: format.title, isOn: entry.format == format) { entry.format = format }
                }
            }

            LumaSection(title: "Runs")
            LumaGroup {
                ForEach(entry.runs.indices, id: \.self) { i in SplitBox(label: "Run \(i + 1)", symbol: "figure.run", seconds: $entry.runs[i]) }
            }
            LumaSection(title: "Stations")
            LumaGroup {
                ForEach(Array(Station.allCases.enumerated()), id: \.offset) { i, station in
                    SplitBox(label: station.title, symbol: station.symbol, seconds: $entry.stations[i])
                }
            }
            LumaSection(title: "Roxzone and finish")
            LumaGroup {
                SplitBox(label: "Roxzone time", seconds: $entry.roxzoneS)
                SplitBox(label: "Finish time", seconds: $entry.finishS)
            }
            LumaNote("Type a time as 4.35 or 435 for 4:35. The roxzone time or the finish time is enough; with both, Luma checks that the page adds up. A results page gives the roxzone as one total, so it is shared evenly over the 15 transitions.")

            checks

            if editing == nil, !overlaps {
                Toggle(isOn: $logToo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add it to the training log").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("As a HYROX session of that length on the race day, so the week it was in counts it.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Luma.volt)
            }
            Button(editing == nil ? "Save this race" : "Save the correction") { save() }
                .buttonStyle(LumaPrimaryButtonStyle())
                .disabled(!entry.isReady)
                .opacity(entry.isReady ? 1 : 0.45)
        }
        .onAppear(perform: open)
    }

    // MARK: Reading the page

    @ViewBuilder
    private var reading: some View {
        LumaLabel("A picture of your results page")
        PhotoStrip(photos: $photos, size: 76)
        if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
        Button {
            Task { await read() }
        } label: {
            if busy { HStack(spacing: 10) { ProgressView().tint(Luma.frost); Text("Reading") } } else { Label("Read the times from the picture", systemImage: "sparkles") }
        }
        .buttonStyle(LumaSecondaryButtonStyle())
        .disabled(busy || photos.isEmpty)
        if busy { ReadingRows(caption: "Reading your result") }
        LumaNote(env.coach.hasKey
                 ? "A screenshot of the splits page works best. Luma copies the times for you to check, leaves empty any it cannot read, and keeps nothing until you save."
                 : "Reading a picture uses the coach. Connect your key in the Coach tab, or type the times below.")
    }

    private func read() async {
        guard env.coach.hasKey else { error = "Connect your key in the Coach tab to read a results page."; return }
        busy = true
        error = nil
        do {
            var found = try await env.coach.readRace(photos: photos.map { $0.data })
            // What was already typed stays where the page gave nothing.
            if found.event.isEmpty { found.event = entry.event }
            for i in found.runs.indices where found.runs[i] == nil { found.runs[i] = entry.runs[i] }
            for i in found.stations.indices where found.stations[i] == nil { found.stations[i] = entry.stations[i] }
            if found.roxzoneS == nil { found.roxzoneS = entry.roxzoneS }
            if found.finishS == nil { found.finishS = entry.finishS }
            entry = found
        } catch let e {
            error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }
        busy = false
    }

    // MARK: Checking and saving

    /// What is still wanted, or the race as it will be kept.
    @ViewBuilder
    private var checks: some View {
        let problems = entry.problems
        if problems.isEmpty, let total = entry.total, let roxzone = entry.roxzone, let splits = entry.splitsS {
            LumaCard(tint: Luma.volt.opacity(0.5)) {
                VStack(alignment: .leading, spacing: 6) {
                    LumaLabel("It adds up")
                    Text(LumaText.duration(total)).font(LumaFont.numeral(44, .heavy)).foregroundStyle(Luma.frost)
                    Text("Runs and stations \(LumaText.duration(splits)) · roxzone \(LumaText.duration(roxzone))")
                        .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if ready {
            LumaCard {
                VStack(alignment: .leading, spacing: 8) {
                    LumaLabel("Before it can be saved")
                    ForEach(problems, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Luma.amber).frame(width: 5, height: 5).offset(y: -3)
                            Text(line).font(LumaFont.body(14)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A session is already recorded over the time of the race, so it is in the training log.
    private var overlaps: Bool {
        guard let total = entry.total else { return false }
        let start = entry.startedAt.timeIntervalSince1970, end = start + total
        return env.workouts.contains { $0.start < end && $0.end > start }
    }

    private func open() {
        guard !ready else { return }
        ready = true
        if let editing, let session = env.sessions.first(where: { $0.id == editing }), let kept = RaceEntry(session) {
            entry = kept
            return
        }
        // Nine in the morning today until the day is set: a race is not run at the minute it is typed in.
        let nine = LDate.startOfDay(env.today)?.addingTimeInterval(9 * 3600) ?? Date()
        entry = RaceEntry(startedAt: min(nine, Date()), format: env.profile.format, sex: env.profile.sex)
        // The gallery has no page to read, so it opens on a race made up for it.
        if env.isDemo, LumaLaunch.page == 1 { entry = RaceEntrySheet.demoEntry(format: env.profile.format, sex: env.profile.sex) }
        if env.isDemo, LumaLaunch.page == 2 {
            entry = RaceEntrySheet.demoEntry(format: env.profile.format, sex: env.profile.sex)
            entry.runs[2] = nil
            entry.stations[7] = 45
        }
    }

    private func save() {
        guard env.saveRace(entry, replacing: editing, logToo: editing == nil && logToo && !overlaps) != nil else { return }
        LumaHaptics.success()
        dismiss()
    }

    /// A race for the gallery: plausible times that add up.
    static func demoEntry(format: RaceFormat, sex: Sex, now: Date = Date()) -> RaceEntry {
        var e = RaceEntry(event: "HYROX Dublin", startedAt: now.addingTimeInterval(-47 * 86_400), format: format, sex: sex)
        e.runs = [278, 301, 309, 314, 318, 325, 331, 322]
        e.stations = [262, 185, 291, 338, 281, 132, 304, 412]
        e.roxzoneS = 468
        e.finishS = (e.splitsS ?? 0) + 468
        return e
    }
}

// MARK: - Set beside the effort before

/// An effort against the one before it of the same shape: the whole difference, where the most time
/// was won and lost, and every line. The times of this effort are in the cards above; here each line
/// is what it took then and the difference.
struct RaceCompareCard: View {
    let comparison: RaceComparison

    var body: some View {
        let c = comparison
        LumaCard(tint: (c.deltaS <= 0 ? Luma.volt : Luma.amber).opacity(0.45)) {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("Against \(c.thenEvent ?? "last time") · \(c.thenAt.formatted(date: .abbreviated, time: .omitted))")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LumaText.duration(abs(c.deltaS))).font(LumaFont.numeral(44, .heavy)).foregroundStyle(c.deltaS <= 0 ? Luma.volt : Luma.amber)
                    Text(abs(c.deltaS) < 0.5 ? "level" : (c.deltaS < 0 ? "faster" : "slower")).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.mist)
                    Spacer(minLength: 6)
                    Text("then \(LumaText.duration(c.thenTotalS))").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                }
                if !c.won.isEmpty { most("Won most", c.won, Luma.volt) }
                if !c.lost.isEmpty { most("Lost most", c.lost, Luma.amber) }
                Rectangle().fill(Luma.line).frame(height: 1)
                ForEach(c.lines) { line in
                    HStack(spacing: 8) {
                        Text(line.label).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        Text("then \(LumaText.duration(line.thenS))").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                        Text(RaceCompareCard.signed(line.deltaS)).font(LumaFont.numeral(17, .semibold))
                            .foregroundStyle(abs(line.deltaS) < 0.5 ? Luma.mist : (line.deltaS < 0 ? Luma.volt : Luma.amber))
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func most(_ title: String, _ lines: [RaceDelta], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LumaLabel(title)
            Text(lines.map { "\($0.label) \(RaceCompareCard.signed($0.deltaS))" }.joined(separator: ", "))
                .font(LumaFont.body(14.5)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A difference with its sign: quicker is a minus.
    static func signed(_ delta: Double) -> String {
        if abs(delta) < 0.5 { return "level" }
        return (delta < 0 ? "−" : "+") + LumaText.duration(abs(delta))
    }
}

// MARK: - A picture to send

/// An effort as a picture: what it was, when, the finish time, and every run and station. Drawn
/// from the same report its screen shows, so the picture cannot say anything the screen does not.
struct RaceShareCard: View {
    let session: HXSession

    var body: some View {
        let report = RaceAnalytics.report(session)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered").font(.system(size: 13, weight: .bold)).foregroundStyle(Luma.volt)
                Text(session.title).font(LumaFont.heading(17)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(session.format.title)")
                .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).padding(.top, 3)
            Text(report.totalS.map { LumaText.duration($0) } ?? "–").font(LumaFont.numeral(78, .heavy)).foregroundStyle(Luma.frost)
                .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 6)
            HStack(spacing: 0) {
                part("Running", report.runTotalS, Luma.sky)
                part("Stations", report.stationTotalS, Luma.volt)
                part("Roxzone", report.roxzoneTotalS, Luma.amber)
            }
            .padding(.top, 4)
            Rectangle().fill(Luma.line).frame(height: 1).padding(.vertical, 14)
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 7) { ForEach(report.runs) { row("Run \($0.index)", $0.seconds, Luma.sky) } }
                VStack(spacing: 7) { ForEach(Array(report.stations.enumerated()), id: \.offset) { _, st in row(st.station.shortTitle, st.seconds, Luma.volt) } }
            }
            Spacer(minLength: 12)
            Text("Luma").font(LumaFont.heading(13)).foregroundStyle(Luma.smoke).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 360, height: 520, alignment: .topLeading)
        .background(Luma.night)
        .environment(\.colorScheme, .dark)
    }

    private func part(_ label: String, _ seconds: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(label).font(LumaFont.body(11.5)).foregroundStyle(Luma.mist) }
            Text(LumaText.duration(seconds)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ seconds: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(LumaText.duration(seconds)).font(LumaFont.numeral(16, .semibold)).foregroundStyle(Luma.frost)
        }
    }

    /// The card as a picture, three pixels to the point.
    @MainActor
    static func picture(of session: HXSession) -> Image? {
        let renderer = ImageRenderer(content: RaceShareCard(session: session))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// Sends the picture of an effort through the system's share sheet. Nothing leaves the phone unless
/// the athlete picks somewhere to send it.
struct RaceShareButton: View {
    let session: HXSession
    @State private var picture: Image?

    var body: some View {
        Group {
            if let picture {
                ShareLink(item: picture, preview: SharePreview(session.title, image: picture)) {
                    Label("Share this result", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(LumaSecondaryButtonStyle())
            }
        }
        .task(id: session.id) { picture = RaceShareCard.picture(of: session) }
    }
}
