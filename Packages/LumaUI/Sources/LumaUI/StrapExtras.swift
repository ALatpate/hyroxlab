import SwiftUI
import Combine
import LumaCore
import LumaKit

// MARK: - A newer build

extension LumaEnv {
    /// The build number of this copy of the app.
    var installedBuild: Int? { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) } }

    /// Looks at the public listing for a newer build: once a day, only when switched on (or asked for
    /// by hand), and never from the gallery. It reads one public file and sends nothing about the athlete.
    func lookForNewerBuild(force: Bool = false) {
        guard !isDemo, storesReady else { return }
        // What the last look found stands until the next one, so the note is there after a restart too.
        let known = extras.newBuildListed.map { ListedBuild(version: "", build: $0) }
        let shown = NewBuild.newer(known, than: installedBuild)
        if shown != newerBuild { newerBuild = shown }
        let now = Date().timeIntervalSince1970
        guard !lookingForBuild, let url = URL(string: NewBuild.listingURL) else { return }
        if !force {
            guard NewBuild.due(enabled: extras.newBuild, lastLookedAt: extras.newBuildLookedAt, now: now) else { return }
            // A look that failed is tried again, at most every half hour.
            guard now - buildLookTriedAt >= 1800 else { return }
        }
        lookingForBuild = true
        buildLookTriedAt = now
        Task { [weak self] in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let data = try? await URLSession.shared.data(for: request).0
            guard let self else { return }
            self.lookingForBuild = false
            guard let data, let text = String(data: data, encoding: .utf8), let listed = NewBuild.listed(from: text) else {
                if force { self.buildLookSaid = "The listing could not be read. Check the connection and try again." }
                return
            }
            var e = self.extras
            e.newBuildLookedAt = Date().timeIntervalSince1970
            e.newBuildListed = listed.build
            self.extras = e
            let newer = NewBuild.newer(listed, than: self.installedBuild)
            self.newerBuild = newer
            if force { self.buildLookSaid = newer.map { NewBuild.title($0) + "." } ?? "This is the newest build." }
        }
    }

    /// Switches the daily look on or off; either way the offer of it has been answered.
    func setNewBuildNotice(_ on: Bool) {
        var e = extras
        e.newBuild = on
        e.newBuildAsked = true
        extras = e
        if on { lookForNewerBuild() }
    }

    /// Keeps a breathing sitting, newest first, a few dozen at most.
    func keep(_ outcome: BreathOutcome) {
        breaths = Array(([outcome] + breaths).prefix(40))
    }
}

/// On Today: a newer build is out, with how to get it; or, once, the offer to look for one each day.
struct NewBuildNote: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if let build = env.newerBuild {
            note(symbol: "arrow.down.circle.fill", title: NewBuild.title(build), text: NewBuild.howTo) { EmptyView() }
        } else if !env.extras.newBuildAsked, !env.isDemo {
            note(symbol: "arrow.down.circle", title: "Hear about new builds?",
                 text: "Luma can look once a day for a newer build and say so here. It reads one public file; nothing about you is sent.") {
                HStack(spacing: 10) {
                    Button("Yes, look daily") { env.setNewBuildNotice(true) }.buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    Button("No") { env.setNewBuildNotice(false) }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    private func note<Actions: View>(symbol: String, title: String, text: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(Luma.volt)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                Text(text).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LumaPanel(tint: Luma.volt, radius: 22))
    }
}

/// On the About screen: the daily look for a newer build, and a look asked for now.
struct NewBuildCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("New builds").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                if let build = env.newerBuild {
                    Text(NewBuild.title(build)).font(LumaFont.title(22)).foregroundStyle(Luma.volt)
                    LumaNote(NewBuild.howTo)
                }
                Toggle(isOn: Binding(get: { env.extras.newBuild }, set: { env.setNewBuildNotice($0) })) {
                    Text("Look for a new build once a day").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                }
                .tint(Luma.volt)
                LumaNote("Luma cannot update itself: AltStore does that. With this on, Luma reads one public file a day and says on Today when a newer build is listed. Nothing about you is sent.")
                HStack(spacing: 12) {
                    Button("Look now") {
                        env.buildLookSaid = nil
                        env.lookForNewerBuild(force: true)
                    }
                    .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                    if let said = env.buildLookSaid {
                        Text(said).font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Wake alarm

/// The strap's wake alarm: one wake time, the days it goes off on, and what will happen when it is
/// next due. Everything said about the alarm comes from the one reading the app keeps (`LumaLive.alarm`).
struct AlarmScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @State private var time = Date()
    @State private var days: Set<Int> = []

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        let a = live.alarm
        LumaDetailScreen(title: "Wake alarm", tone: .sleep) {
            LumaCard(tint: a.willGoOff ? Luma.dusk.opacity(0.6) : nil) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: Binding(get: { a.on }, set: { turn($0) })) {
                        Text("Wake me").font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    }
                    .tint(Luma.volt)
                    HStack {
                        Text("Wake time").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                        Spacer()
                        DatePicker("Wake time", selection: $time, displayedComponents: [.hourAndMinute]).labelsHidden().colorScheme(.dark)
                    }
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = days.contains(d)
                            Button {
                                LumaHaptics.select()
                                if on { days.remove(d) } else { days.insert(d) }
                            } label: {
                                Text(dayNames[d - 1]).font(LumaFont.body(13, .semibold)).foregroundStyle(on ? Luma.ink : Luma.frost)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? Luma.volt : Color.white.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LumaNote(days.isEmpty || days.count == 7 ? "Every day. Pick days to wake only on those." : "Only on the days picked.")
                }
            }
            outcome(a)
            if a.strapIsTrial { trial(a) }
            LumaNote("The phone's part is one notification with its usual sound, and a Focus that silences notifications silences it too. Keep another alarm for anything you cannot miss.")
        }
        .onAppear {
            // By the clock, not by seconds from midnight: on a day the clocks change those differ.
            time = Calendar.current.date(bySettingHour: a.minutes / 60, minute: a.minutes % 60, second: 0, of: Date()) ?? Date()
            days = a.weekdays
        }
        .onChange(of: time) { _, _ in push() }
        .onChange(of: days) { _, _ in push() }
    }

    private var minutes: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 7) * 60 + (c.minute ?? 0)
    }

    /// All seven days picked is the same as none: every day.
    private var chosenDays: Set<Int> { days.count == 7 ? [] : days }

    private func turn(_ on: Bool) {
        LumaHaptics.select()
        let wake = minutes, onDays = chosenDays
        Task {
            // The phone's own notification is half of the alarm, so leave to show one is asked for first.
            if on { _ = await env.requestNotifications?() }
            env.device?.setAlarm(on: on, minutes: wake, weekdays: onDays)
        }
    }

    /// Sends a changed time or days on, and only a change: opening the screen sends nothing.
    private func push() {
        let a = live.alarm
        guard minutes != a.minutes || chosenDays != a.weekdays else { return }
        env.device?.setAlarm(on: a.on, minutes: minutes, weekdays: chosenDays)
    }

    @ViewBuilder
    private func outcome(_ a: LumaAlarmState) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("What will happen")
                if !a.on {
                    Text("The alarm is off.").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                } else if let next = a.next {
                    if a.willGoOff {
                        Text(next.formatted(.dateTime.weekday(.wide).hour().minute())).font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                    } else {
                        Text("Nothing is set to go off").font(LumaFont.heading(17)).foregroundStyle(Luma.amber)
                    }
                    happens("waveform", a.strap == .told, strapLine(a))
                    happens("bell.fill", a.phoneWillNotify,
                            a.phoneWillNotify ? "This phone shows a notification, titled Smart alarm." : "No notification: notifications are off for Luma in the phone's Settings.")
                } else {
                    Text("No day is picked for it to go off on.").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
                }
                if let old = a.strapStillSet {
                    LumaNote("The strap could not be reached when its alarm was taken off, so it may still buzz at \(old.formatted(.dateTime.weekday(.abbreviated).hour().minute())). It is told to stop when it next connects.")
                }
            }
        }
    }

    /// The strap's part, said as what the app did: that the strap was told is known, that it buzzes is not.
    private func strapLine(_ a: LumaAlarmState) -> String {
        switch a.strap {
        case .told:
            return a.strapIsTrial ? "The strap has been told to buzz then. On this strap that is a trial, so it may not."
                                  : "The strap has been told to buzz then, and can do so with the phone asleep or Luma closed."
        case .waiting: return "The strap has not been told this time yet. It is told when it is connected with Luma running."
        case .notAsked: return "The strap is not asked to buzz: on this strap its own alarm is a trial, and the trial is off."
        case .none: return "No strap is paired, so nothing buzzes on the wrist."
        }
    }

    private func happens(_ symbol: String, _ will: Bool, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(will ? Luma.volt : Luma.smoke).frame(width: 20)
            Text(text).font(LumaFont.body(14.5)).foregroundStyle(will ? Luma.frost : Luma.mist).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func trial(_ a: LumaAlarmState) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { a.trialOn }, set: { env.device?.setAlarmTrial($0) })) {
                    Text("Try the strap's own alarm").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                }
                .tint(Luma.volt)
                LumaNote("On a WHOOP 5.0 or MG the strap's own alarm is still a trial: wakes have been reported, and it is not known to work every time. With this on, Luma tells the strap the wake time; the notification on the phone comes either way.")
            }
        }
    }
}

// MARK: - Breathing

/// Drives a breathing sitting: the pace's clock, the cue on the strap at each turn of the breath, and
/// beat-to-beat variation as the strap's intervals arrive.
@MainActor
final class BreathController: ObservableObject {
    private unowned let env: LumaEnv
    @Published private(set) var pace = BreathPace.calm
    @Published private(set) var running = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var moment = BreathPace.calm.moment(at: 0)
    @Published private(set) var hrv: Double?
    @Published private(set) var heartRate: Double?
    @Published private(set) var outcome: BreathOutcome?
    private(set) var length: Double = 300

    private var variation = LiveHRV()
    /// The readings at the end of the first minute, to set the last minute against.
    private var firstHRV: Double?
    private var firstHeartRate: Double?
    private var firstTaken = false
    private var startedAt = Date()
    private var buzz = false
    private var lastPart: BreathPart?
    private var lastSecond = -1
    private var timer: AnyCancellable?
    private var beats: AnyCancellable?

    init(env: LumaEnv) { self.env = env }

    var remaining: Double { max(0, length - elapsed) }

    func start(pace: BreathPace, minutes: Double, buzz: Bool) {
        guard !running else { return }
        self.pace = pace
        self.buzz = buzz
        length = minutes * 60
        startedAt = Date()
        variation = LiveHRV()
        firstHRV = nil; firstHeartRate = nil; firstTaken = false
        lastPart = nil; lastSecond = -1
        hrv = nil; heartRate = nil; outcome = nil
        running = true
        env.device?.setLiveHeartRate(true)
        beats = env.live.beats.sink { [weak self] intervals in
            guard let self, self.running else { return }
            self.variation.add(intervals, at: Date().timeIntervalSince(self.startedAt))
        }
        // The gallery opens part-way through a sitting, with figures to show.
        if env.isDemo {
            startedAt = Date().addingTimeInterval(-97)
            hrv = 61
            heartRate = 58
        }
        timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        guard running else { return }
        let t = Date().timeIntervalSince(startedAt)
        elapsed = t
        let now = pace.moment(at: t)
        if now.part != lastPart {
            lastPart = now.part
            if buzz, let cue = now.part.cue { env.device?.cue(cue) }
        }
        moment = now
        // The figures move once a second, not ten times.
        let second = LNum.int(t)
        if second != lastSecond, !env.isDemo {
            lastSecond = second
            hrv = variation.rmssd
            heartRate = variation.heartRate ?? env.live.strap.liveHeartRate().map { Double($0) }
            if !firstTaken, t >= 60 {
                firstTaken = true
                firstHRV = variation.rmssd
                firstHeartRate = variation.heartRate
            }
        }
        if t >= length { finish() }
    }

    func finish() {
        guard running else { return }
        running = false
        timer?.cancel()
        beats?.cancel()
        env.device?.setLiveHeartRate(false)
        let seconds = min(elapsed, length)
        // Under two minutes there is no first minute to set a last one against.
        guard seconds >= 120, !env.isDemo else { return }
        let result = BreathOutcome(endedAt: Date().timeIntervalSince1970, paceID: pace.id, seconds: seconds, hrvBefore: firstHRV,
                                   hrvAfter: variation.rmssd, heartRateBefore: firstHeartRate, heartRateAfter: variation.heartRate)
        outcome = result
        env.keep(result)
    }
}

struct BreathScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View { BreathBody(env: env) }
}

private struct BreathBody: View {
    @StateObject private var c: BreathController
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @State private var paceID = BreathPace.calm.id
    @State private var minutes = 5.0
    @State private var buzz = true

    init(env: LumaEnv) { _c = StateObject(wrappedValue: BreathController(env: env)) }

    private var pace: BreathPace { BreathPace.all.first { $0.id == paceID } ?? .calm }

    var body: some View {
        LumaDetailScreen(title: "Breathing", tone: .hrv) {
            if c.running { sitting } else { setup }
            if let line = c.outcome?.line, !c.running {
                LumaCard(tint: Luma.aqua.opacity(0.5)) {
                    VStack(alignment: .leading, spacing: 8) {
                        LumaLabel("This sitting")
                        Text(line).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        LumaNote("The first minute against the last. Variation over one minute moves a lot from breath to breath, so read it only within one sitting.")
                    }
                }
            }
            if !c.running, !env.breaths.isEmpty { earlier }
            LumaNote("A way to settle before sleep or an effort. It is not a treatment, and the figures here are not a medical reading.")
        }
        .onAppear { if LumaLaunch.page == 1, !c.running { c.start(pace: .calm, minutes: 5, buzz: false) } }
        .onDisappear { c.finish() }
    }

    @ViewBuilder
    private var setup: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 14) {
                LumaLabel("Pace")
                LumaSegmented(selection: $paceID, options: BreathPace.all.map { ($0.id, $0.title) }, tint: Luma.aqua)
                Text(pace.note).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                LumaLabel("For")
                LumaSegmented(selection: $minutes, options: [(2.0, "2 min"), (5.0, "5 min"), (10.0, "10 min")], tint: Luma.aqua)
                if live.strap.secure {
                    Toggle(isOn: $buzz) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Buzz on the strap").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                            Text("\(live.strap.cueText(.one).capitalizedFirst) to breathe in, \(live.strap.cueText(.two)) to breathe out, so you can do this with your eyes closed.")
                                .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Luma.volt)
                } else {
                    LumaNote("With the strap paired, it can buzz to breathe in and to breathe out.")
                }
            }
        }
        Button("Start") {
            LumaHaptics.thud()
            c.start(pace: pace, minutes: minutes, buzz: buzz && live.strap.secure)
        }
        .buttonStyle(LumaPrimaryButtonStyle())
    }

    @ViewBuilder
    private var sitting: some View {
        let m = c.moment
        ZStack {
            Circle().fill(Luma.aqua.opacity(0.08))
            Circle().strokeBorder(Luma.aqua.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(RadialGradient(colors: [Luma.aqua.opacity(0.55), Luma.aqua.opacity(0.12)], center: .center, startRadius: 0, endRadius: 150))
                .scaleEffect(0.4 + 0.6 * m.fill)
                .animation(LumaMotion.reduced ? nil : .linear(duration: 0.12), value: m.fill)
            VStack(spacing: 0) {
                Text(m.part.title).font(LumaFont.title(30)).foregroundStyle(Luma.frost)
                Text("\(LNum.int(m.remainingS.rounded(.up)))").font(LumaFont.numeral(46)).foregroundStyle(Luma.frost).contentTransition(.numericText())
            }
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        StatGrid {
            StatCell(label: "Heart rate", value: c.heartRate.map { "\(LNum.int($0.rounded()))" } ?? "–", unit: "bpm")
            StatCell(label: "Beat-to-beat variation", value: c.hrv.map { "\(LNum.int($0.rounded()))" } ?? "–", unit: "ms", note: "Over the last minute")
            StatCell(label: "Time left", value: LumaText.duration(c.remaining))
            StatCell(label: "Breaths", value: "\(m.breath)", note: c.pace.title)
        }
        Button("Stop") { c.finish() }.buttonStyle(LumaSecondaryButtonStyle())
    }

    @ViewBuilder
    private var earlier: some View {
        LumaSection(title: "Earlier sittings")
        LumaGroup {
            ForEach(env.breaths.prefix(6)) { b in
                let name = BreathPace.all.first { $0.id == b.paceID }?.title ?? "Breathing"
                LumaRow(symbol: "wind", symbolColor: Luma.aqua,
                        title: "\(name) · \(LNum.int((b.seconds / 60).rounded())) min",
                        subtitle: Date(timeIntervalSince1970: b.endedAt).formatted(date: .abbreviated, time: .shortened) + (b.line.map { ". " + $0 } ?? ""))
            }
        }
    }
}

// MARK: - On the strap screen

/// What the strap can do beyond recording: the wake alarm, breathing, cues by heart rate, sharing heart
/// rate with gym equipment, and the experimental recording of raw motion.
struct StrapExtras: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @State private var recordings: [LumaMotionRecording] = []
    @State private var files: [String: URL] = [:]

    var body: some View {
        let ceiling = ZoneGuard.ceiling(of: env.extras.zoneGuardZone, in: env.profile.zones())
        let comeDown = GoAgain.target(maxHR: env.profile.resolvedMaxHR())
        LumaSection(title: "On the wrist")
        LumaGroup {
            Button { router.push(.alarm) } label: {
                LumaRow(symbol: "alarm.fill", symbolColor: Luma.dusk, title: "Wake alarm", subtitle: alarmLine, chevron: true)
            }
            .buttonStyle(.plain)
            Button { router.push(.breathing) } label: {
                LumaRow(symbol: "wind", symbolColor: Luma.aqua, title: "Breathing", subtitle: "Paced breathing, with a buzz in and out", chevron: true)
            }
            .buttonStyle(.plain)
            toggle("Buzz above a heart-rate zone",
                   "In a steady run or a timed session, not in intervals: \(live.strap.cueText(.three)) when your heart rate has stayed above the zone for eight seconds, \(live.strap.cueText(.two)) when it is back.",
                   Binding(get: { env.extras.zoneGuard }, set: { on in change { $0.zoneGuard = on } }))
            if env.extras.zoneGuard {
                VStack(alignment: .leading, spacing: 8) {
                    LumaSegmented(selection: Binding(get: { env.extras.zoneGuardZone }, set: { zone in change { $0.zoneGuardZone = zone } }),
                                  options: (1...4).map { ($0, "Zone \($0)") }, tint: Luma.volt)
                    if let ceiling {
                        Text("Stay in zone \(env.extras.zoneGuardZone) or under: up to \(LNum.int(ceiling.rounded())) bpm.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 16)
            }
            toggle("Go again by heart rate",
                   "In the rests of an interval run: the buzz to go again comes when your heart rate is back down to \(LNum.int(comeDown)) bpm, in place of a set rest. Never under 15 seconds, never over three minutes.",
                   Binding(get: { env.extras.goAgain }, set: { on in change { $0.goAgain = on } }))
        }
        if !live.strap.secure {
            LumaNote("Buzzes need the strap paired. If the Buzz button above does nothing on your strap, these will do nothing either.")
        }
        LumaSection(title: "Sharing and recording")
        LumaGroup {
            toggle("Share heart rate with gym equipment", broadcastLine,
                   Binding(get: { live.broadcast.on }, set: { env.device?.setBroadcast($0) }))
            toggle("Record motion with sessions",
                   "Experimental. While a session runs, the strap's raw movement is recorded beside it, so that steps, strokes and reps can be counted from it. It uses more strap battery.",
                   Binding(get: { env.extras.motion }, set: { on in change { $0.motion = on } }))
            toggle("Count from motion",
                   "Experimental, and checked so far only against made-up movement. After a session recorded with motion, Luma counts steps a minute, strokes and reps, and splits a session with no parts into runs, work and rest. The counts show beside the session and change nothing in it.",
                   Binding(get: { env.extras.motionCounts }, set: { on in change { $0.motionCounts = on } }))
            ForEach(recordings) { r in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.note.isEmpty ? "Recording" : r.note).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).lineLimit(1)
                        Text("\(r.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(LumaText.duration(r.seconds))")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                    Spacer(minLength: 6)
                    if env.extras.motionCounts {
                        Button("Counts") { router.push(.motion(r.id)) }
                            .font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt).buttonStyle(.plain)
                    }
                    if let url = files[r.id] {
                        ShareLink(item: url) { Text("Share").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt) }
                    } else {
                        Button("Make file") { Task { if let url = await env.device?.motionFile(r.id) { files[r.id] = url } } }
                            .font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt).buttonStyle(.plain)
                    }
                    Menu {
                        Button("Delete this recording", role: .destructive) {
                            Task {
                                await env.device?.deleteMotion(r.id)
                                recordings = await env.device?.motionRecordings() ?? []
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.mist)
                            .frame(width: 30, height: 30).contentShape(Rectangle())
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 16)
            }
        }
        .task(id: live.motionRecording) { recordings = await env.device?.motionRecordings() ?? [] }
        if live.strap.hasClasp {
            LumaSection(title: "From the clasp")
            LumaGroup {
                Button { router.push(.trace) } label: {
                    LumaRow(symbol: "waveform.path.ecg", symbolColor: Luma.coral, title: "Trace from the clasp", subtitle: traceLine, chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var traceLine: String {
        if live.trace.mayStillRun { return "A trace may still be running. Open to stop it." }
        if let last = env.traces.first, let rate = last.beatsAMinute {
            return "A trial. Last: \(rate) beats a minute, \(last.takenAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return live.trace.on ? "A trial, switched on" : "A trial: a heart rate counted beat by beat. Off"
    }

    private var alarmLine: String {
        let a = live.alarm
        guard a.on else { return "Off" }
        guard let next = a.next, a.willGoOff else { return "On, but nothing is set to go off. Open to see why." }
        return "Next: " + next.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var broadcastLine: String {
        let b = live.broadcast
        let what = "Experimental. The phone stands in as a standard heart-rate sensor, so a treadmill, a bike or another app can read your heart rate from it. It is on the air only while Luma is on screen or recording a session, and anything nearby that looks for a heart-rate sensor can read it then."
        guard b.on else { return what }
        if let note = b.note { return note }
        if b.listeners > 0 { return "On the air, read by \(b.listeners) device\(b.listeners == 1 ? "" : "s")." }
        return b.advertising ? "On the air. Look for it under heart-rate sensors on the equipment, with Luma on screen." : "Starting. " + what
    }

    private func change(_ edit: (inout LumaExtras) -> Void) {
        var e = env.extras
        edit(&e)
        env.extras = e
    }

    private func toggle(_ title: String, _ note: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                Text(note).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Luma.volt)
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

extension LumaStrap {
    /// How a cue feels on this strap, in words: a WHOOP 5.0 or MG buzzes once, twice or three times; a
    /// 4.0 buzzes once, for longer.
    func cueText(_ cue: StrapCue) -> String {
        switch cue {
        case .one: return buzzesByCount ? "one buzz" : "a short buzz"
        case .two: return buzzesByCount ? "two buzzes" : "a medium buzz"
        case .three: return buzzesByCount ? "three buzzes" : "a long buzz"
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
