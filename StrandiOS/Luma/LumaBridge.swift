#if os(iOS)
import SwiftUI
import Combine
import WidgetKit
import ActivityKit
import UIKit
import WhoopStore
import LumaCore
import LumaKit
import LumaUI

/// Connects Luma's interface to the strap, the database and the system. LumaUI knows none of those
/// layers: it sees four small protocols (data source, strap control, session recorder, secrets) and
/// this file implements them over the strap layer the app is built on.
@MainActor
final class LumaBridge: ObservableObject, LumaDeviceControl {
    let env: LumaEnv
    private let model: AppModel
    private let health: HealthKitBridge
    private weak var liveActivity: LiveActivityController?
    private let live: LumaLive
    private let source: LumaRepoSource
    private let recorder: LumaWorkoutRecorder
    private var bag: Set<AnyCancellable> = []
    private var registryBag: Set<AnyCancellable> = []
    /// The latest heart rate the strap delivered and when, kept for `LumaStrap.freshFor` after the
    /// strap layer has cleared its own number (it does so after ten quiet seconds).
    private var lastReading: (bpm: Int, at: Date)?
    private var arrival: Date?
    private var scanning = false
    private var liveWanters = 0
    /// Luma is on screen. While it is, the strap is asked to stream whatever the recording setting.
    private var onScreen = false
    private var ticker: Timer?
    private var lastGlance: LumaGlance?

    init(model: AppModel, health: HealthKitBridge, liveActivity: LiveActivityController) {
        self.model = model
        self.health = health
        self.liveActivity = liveActivity
        let live = LumaLive()
        let source = LumaRepoSource(repo: model.repo)
        let recorder = LumaWorkoutRecorder(model: model)
        self.live = live
        self.source = source
        self.recorder = recorder
        LumaGlanceStore.suiteName = WidgetSnapshot.suiteName
        // Labels and running text follow the text size set in Settings. Widgets do not: they have no room.
        LumaType.followsTextSize = true
        env = LumaEnv(source: source, live: live, secrets: LumaKeychain())
        env.device = self
        env.recorder = recorder
        source.linkFacts = { [weak self] in self?.linkFacts() ?? [] }
        Self.settleEarlierShell()
        retireEarlierAutomations()
        adoptStrapProfileIfNew()
        wire()
    }

    // MARK: Start-up

    /// The shell this app was built on had its own first-run screens, update check, coach and lifting
    /// banner. Luma replaces all of them, so they are marked done or switched off: nothing of theirs
    /// can appear, ask for the network, or post a notification.
    private static func settleEarlierShell() {
        let d = UserDefaults.standard
        d.set(true, forKey: "noop.onboarded")
        d.set(Terms.currentVersion, forKey: "noop.acceptedTermsVersion")
        d.set(AppChangelog.currentVersion, forKey: "noop.lastSeenChangelogVersion")
        d.set(false, forKey: "updates.autoCheck")
        d.set(false, forKey: UnitPrefs.liftLiveActivityKey)
        if CoachBriefScheduler.coachMasterEnabled {
            d.set(false, forKey: "noop.coachEnabled")
            CoachBriefScheduler.applyMasterSwitch(false)
        }
    }

    /// The earlier shell could act on its own once asked to: a wake alarm, a wind-down reminder, strain
    /// and early-warning notifications, haptic check-ins, zone buzzes, a double-tap action. Luma has no
    /// screen for any of them, so one left on would go on buzzing and notifying with nothing in the app
    /// to explain it or stop it. Each one found on is switched off, through the same calls its own
    /// switch used, and the athlete is told which (`LumaLive.switchedOff`). All are off by default, so
    /// for most installs this does nothing, and after the first launch it has nothing left to do.
    private func retireEarlierAutomations() {
        var off: [String] = []
        let behavior = model.behavior
        if behavior.smartAlarmEnabled {
            behavior.smartAlarmEnabled = false
            // Disarms the strap (now, or as soon as it next connects) and removes the backup notification.
            model.applySmartAlarm()
            off.append("the wake alarm")
        }
        if WindDownNudge.isEnabled {
            WindDownNudge.setEnabled(false)
            off.append("the wind-down reminder")
        }
        if behavior.strainTargetNudge {
            behavior.strainTargetNudge = false
            off.append("the strain target notification")
        }
        if behavior.illnessWatch {
            behavior.illnessWatch = false
            off.append("the early-warning notification")
        }
        if behavior.stressCheckIn {
            behavior.stressCheckIn = false
            behavior.stressAutoNudge = false
            off.append("stress check-ins")
        }
        if behavior.zoneCoaching {
            behavior.zoneCoaching = false
            off.append("zone buzzes")
        }
        if behavior.doubleTapAction != .none {
            behavior.doubleTapAction = .none
            off.append("the double-tap action")
        }
        if !off.isEmpty { live.switchedOff = off }
    }

    /// Before Luma's own setup has run, start from what the strap layer already knows about the
    /// athlete, so nothing has to be typed twice.
    private func adoptStrapProfileIfNew() {
        guard !env.profile.isSetUp else { return }
        var p = env.profile
        let known = model.profile
        p.sex = known.sex == "female" ? .female : .male
        p.weightKg = known.weightKg
        p.heightCm = known.heightCm
        p.birthYear = Calendar.current.component(.year, from: known.dateOfBirth)
        if known.hrMaxOverride > 0 { p.maxHR = Double(known.hrMaxOverride) }
        env.profile = p
    }

    private func wire() {
        let model = self.model

        // Strap data: reload Luma's view of it whenever the stored data actually changes.
        model.repo.$refreshSeq.dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.env.reload() }
            .store(in: &bag)

        // Live strap state. Stamped as each reading arrives; redrawn at most twice a second.
        model.live.$heartRate
            .sink { [weak self] hr in if hr != nil { self?.arrival = Date() } }
            .store(in: &bag)
        Publishers.Merge3(model.live.objectWillChange.map { _ in () }, model.objectWillChange.map { _ in () },
                          model.ble.objectWillChange.map { _ in () })
            .receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.refreshStrap() }
            .store(in: &bag)
        model.$deviceRegistry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] registry in self?.follow(registry) }
            .store(in: &bag)
        health.$auth
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshHealth() }
            .store(in: &bag)
        // A reading that has stopped arriving must age out of the interface without waiting for another event.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStrap() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        // The athlete's details feed the strap layer's own scoring (zones, energy), so keep them in step.
        env.onProfileChange = { [weak self] profile in self?.mirror(profile) }
        if env.profile.isSetUp { mirror(env.profile) }

        // The strap layer puts its own stored stream preference back on every pairing. Luma's want can be
        // wider than that preference (on screen with "Record all the time" off), so it is applied again
        // after each one. Delivered on the next turn of the run loop, which is after the strap layer's own.
        model.live.$bonded.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyCapture() }
            .store(in: &bag)
        applyCapture()

        // Widgets and the Lock Screen card.
        env.onGlanceChange = { [weak self] in self?.publishGlance() }
        // Reminders ask iOS for leave the first time one is switched on.
        env.requestNotifications = { await LumaReminders.requestAuthorization() }
        // Something was logged by a shortcut or Siri while the app is running: file it now.
        NotificationCenter.default.publisher(for: LumaQuickIntents.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishGlance() }
            .store(in: &bag)
        // A session starting or ending changes the Lock Screen card and the companion's state.
        recorder.onChange = { [weak self] in self?.publishGlance() }
        liveActivity?.decorate = { [weak self] state in self?.decorate(&state) }

        refreshStrap()
        refreshHealth()
        follow(model.deviceRegistry)
    }

    /// Called when the app comes to the front.
    func becameActive() {
        // An icon picked in the earlier shell is no longer shipped; return to Luma's own.
        if UIApplication.shared.alternateIconName != nil {
            UIApplication.shared.setAlternateIconName(nil, completionHandler: nil)
        }
        env.reload()
        refreshStrap()
        publishGlance()
    }

    // MARK: Live state

    private func follow(_ registry: DeviceRegistry?) {
        registryBag.removeAll()
        guard let registry else { live.paired = []; return }
        registry.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPaired() }
            .store(in: &registryBag)
        refreshPaired()
    }

    private func refreshPaired() {
        guard let registry = model.deviceRegistry else { return }
        let paired = registry.devices
            .filter { $0.status != .archived && !$0.isImportSource }
            .map { device in
                LumaPairedStrap(id: device.id, name: device.displayName,
                                detail: device.id == registry.activeDeviceId ? "In use" : "Paired, not in use",
                                isActive: device.id == registry.activeDeviceId)
            }
        if paired != live.paired { live.paired = paired }
        refreshStrap()
    }

    private var activeDevice: PairedDevice? {
        guard let registry = model.deviceRegistry else { return nil }
        return registry.devices.first { $0.id == registry.activeDeviceId && $0.status != .archived }
    }

    private func refreshStrap() {
        let state = model.live
        let now = Date()
        if state.connected, let bpm = model.bpm ?? state.heartRate { lastReading = (bpm, arrival ?? now) }
        if !state.connected { lastReading = nil }
        if let reading = lastReading, now.timeIntervalSince(reading.at) > LumaStrap.freshFor { lastReading = nil }

        var strap = LumaStrap()
        strap.connected = state.connected
        strap.secure = state.encryptedBond
        strap.heartRate = lastReading?.bpm
        strap.heartRateAt = lastReading?.at
        strap.battery = state.batteryPct
        strap.charging = state.charging ?? false
        strap.worn = state.worn
        strap.syncing = state.backfilling
        strap.syncedChunks = state.syncChunksThisSession
        strap.lastSync = state.lastSyncedAt.map { Date(timeIntervalSince1970: $0) }
        // What the strap layer knows about how complete its own read is. Luma states these; it does not
        // re-derive them.
        strap.historyPending = state.historyPendingSync
        strap.historyEmpty = state.historySyncExperimental || state.sustainedEmptyOffload
        strap.needsRestart = state.strapNeedsReboot
        strap.syncError = Self.plain(state.lastSyncError)
        strap.continuous = PuffinExperiment.keepRealtimeForDataEnabled && !PuffinExperiment.continuousHrvOvernightOnlyEnabled
        let device = activeDevice
        strap.name = device?.displayName
        strap.model = device?.model
        strap.firmware = state.strapFirmware
        strap.hint = Self.plain(state.pairingHint ?? state.reconnectGuide)
        if strap != live.strap { live.strap = strap }

        if scanning {
            let found = model.ble.discoveredWhoops
                .sorted { $0.rssi > $1.rssi }
                .map { LumaFoundStrap(id: $0.uuid, name: $0.name, rssi: $0.rssi) }
            if found != live.found { live.found = found }
        }
        if live.batteryAlerts != model.behavior.batteryAlerts { live.batteryAlerts = model.behavior.batteryAlerts }
    }

    /// Guidance written by the strap layer names the project it came from; in Luma it names Luma.
    private static func plain(_ text: String?) -> String? {
        text?.replacingOccurrences(of: "NOOP", with: "Luma")
    }

    private func refreshHealth() {
        let access: LumaHealthAccess
        switch health.auth {
        case .authorized: access = .on
        case .denied: access = .denied
        case .unknown: access = .off
        default: access = .unavailable
        }
        if access != live.health { live.health = access }
    }

    // MARK: Strap control

    func reconnect() { model.scan() }

    func syncNow() { model.ble.syncNow() }

    func startScan(_ generation: LumaStrapGeneration) {
        scanning = true
        live.found = []
        model.presentWhoopScan(model: generation == .four ? .whoop4 : .whoop5mg)
    }

    func stopScan() {
        guard scanning else { return }
        scanning = false
        model.stopWhoopScan()
        // The search takes over the radio; hand it back to the paired strap if the link was dropped for it.
        if !model.live.connected, activeDevice != nil { model.scan() }
    }

    func pair(_ strap: LumaFoundStrap, generation: LumaStrapGeneration) {
        let now = Int(Date().timeIntervalSince1970)
        let label = generation == .four ? "4.0" : "5.0 MG"
        let device = PairedDevice(id: "whoop-\(strap.id)", brand: "WHOOP", model: label, nickname: strap.name.isEmpty ? nil : strap.name,
                                  peripheralId: strap.id, sourceKind: .liveBLE,
                                  capabilities: WhoopLiveCapabilities.metrics(forModel: label), status: .paired,
                                  addedAt: now, lastSeenAt: now)
        model.registerDevice(device, makeActive: true)
        live.found = []
    }

    func makeActive(_ id: String) { model.deviceRegistry?.setActive(id) }

    /// Removes the strap from this phone and keeps everything it recorded.
    func forget(_ id: String) {
        guard let registry = model.deviceRegistry, let device = registry.devices.first(where: { $0.id == id }) else { return }
        model.ble.forgetDevice(device.peripheralId)
        registry.archive(id)
    }

    func buzz() { model.buzzStrapOnce() }

    func cue() { model.buzz(loops: 2) }

    func setLiveHeartRate(_ on: Bool) {
        if on {
            if liveWanters == 0 { model.startRealtimeHR() }
            liveWanters += 1
        } else if liveWanters > 0 {
            liveWanters -= 1
            if liveWanters == 0 { model.stopRealtimeHR() }
        }
    }

    func setOnScreen(_ on: Bool) {
        guard on != onScreen else { return }
        onScreen = on
        applyCapture()
    }

    /// Asks the strap to keep sending heart rate: at all times when the athlete records all the time,
    /// otherwise while Luma is on screen. This is the strap layer's own continuous capture, switched
    /// through its own preference and call: one existing, reversible command (the realtime heart-rate
    /// toggle), no new one. A WHOOP 5.0 or MG that hands over nothing it stored can only be recorded this
    /// way, which is why Luma's setting defaults to on. It costs strap battery, and it has not been
    /// measured on hardware from here.
    ///
    /// The preference is kept where the strap layer reads it, because that layer re-applies it at launch
    /// and on every pairing. Its "night hours only" refinement is the default for a fresh preference and
    /// Luma has no switch for it, so it is set off: Luma's one setting means day and night.
    private func applyCapture() {
        let always = env.profile.continuousRecording
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PuffinExperiment.keepRealtimeForDataKey) as? Bool != always {
            defaults.set(always, forKey: PuffinExperiment.keepRealtimeForDataKey)
        }
        if defaults.object(forKey: PuffinExperiment.continuousHrvOvernightOnlyKey) as? Bool != false {
            defaults.set(false, forKey: PuffinExperiment.continuousHrvOvernightOnlyKey)
        }
        model.ble.setKeepRealtimeForData(always || onScreen)
        refreshStrap()
    }

    func connectHealth() async {
        if health.auth == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            _ = await UIApplication.shared.open(url)
            return
        }
        await health.requestAuthorization()
        refreshHealth()
        if health.auth == .authorized {
            _ = await health.sync()
            await model.repo.refresh()
        }
    }

    func setBatteryAlerts(_ on: Bool) {
        model.behavior.batteryAlerts = on
        if on { BatteryNotifier.requestAuthorization() }
        live.batteryAlerts = on
    }

    // MARK: Profile

    private func mirror(_ profile: LProfile) {
        let known = model.profile
        let sex = profile.sex == .female ? "female" : "male"
        if known.sex != sex { known.sex = sex }
        if known.weightKg != profile.weightKg { known.weightKg = profile.weightKg }
        if known.heightCm != profile.heightCm { known.heightCm = profile.heightCm }
        let maxHR = Int((profile.maxHR ?? 0).rounded())
        if known.hrMaxOverride != maxHR { known.hrMaxOverride = maxHR }
        let calendar = Calendar.current
        if calendar.component(.year, from: known.dateOfBirth) != profile.birthYear,
           let dob = calendar.date(from: DateComponents(year: profile.birthYear, month: 7, day: 1)) {
            known.dateOfBirth = dob
        }
        // One switch for the Lock Screen card, kept where the card's own controller reads it.
        let defaults = UserDefaults.standard
        if UnitPrefs.liveActivityEnabled() != profile.lockScreenHeartRate {
            defaults.set(profile.lockScreenHeartRate, forKey: UnitPrefs.liveActivityKey)
        }
        liveActivity?.refresh()
        applyCapture()
    }

    // MARK: Data check

    /// The state of the strap link and of what feeds the Lock Screen, read at the moment it is asked
    /// for. Readings only: each line is a value the strap layer or iOS holds, with nothing concluded.
    private func linkFacts() -> [LFact] {
        let state = model.live
        let calendar = Calendar.current
        func yes(_ value: Bool) -> String { value ? "yes" : "no" }
        func stamp(_ ts: Double) -> String { RecordReport.stamp(ts, calendar: calendar) }
        var out: [LFact] = []

        let link = "Strap link"
        out.append(LFact(link, "Connected", yes(state.connected)))
        out.append(LFact(link, "Paired securely", yes(state.encryptedBond)))
        out.append(LFact(link, "Ready to hand over what it stored", yes(state.historyReady)))
        out.append(LFact(link, "Being read now", state.backfilling ? "yes, \(state.syncChunksThisSession) parts so far" : "no"))
        out.append(LFact(link, "Holds data not yet read", yes(state.historyPendingSync)))
        out.append(LFact(link, "Handed over nothing in repeated reads", yes(state.historySyncExperimental || state.sustainedEmptyOffload)))
        out.append(LFact(link, "Reads not moving forward", yes(state.strapNeedsReboot)))
        out.append(LFact(link, "Last completed read", state.lastSyncedAt.map { stamp($0) } ?? "never"))
        out.append(LFact(link, "Note from the last read", Self.plain(state.lastSyncError) ?? "none"))
        var range = "not reported"
        if let r = state.strapRange, r.newestUnix > 0 {
            let oldest: String = r.oldestUnix.map { stamp(Double($0)) } ?? "not reported"
            range = oldest + " to " + stamp(Double(r.newestUnix))
        }
        out.append(LFact(link, "The strap's own record runs", range))
        out.append(LFact(link, "Pages waiting at connection", state.pagesBehindAtConnect.map { String($0) } ?? "not reported"))
        let bpm: Int? = model.bpm ?? state.heartRate
        out.append(LFact(link, "Heart rate now", bpm.map { "\($0) bpm" } ?? "none arriving"))
        out.append(LFact(link, "On wrist", yes(state.worn)))
        out.append(LFact(link, "Battery", state.batteryPct.map { "\(Int($0.rounded()))%" } ?? "not reported"))
        out.append(LFact(link, "Firmware", state.strapFirmware ?? "not reported"))
        out.append(LFact(link, "Model", activeDevice?.model ?? "none"))

        let recording = "Recording"
        out.append(LFact(recording, "Stream held open by the setting", yes(PuffinExperiment.keepRealtimeForDataEnabled)))
        out.append(LFact(recording, "Limited to night hours", yes(PuffinExperiment.continuousHrvOvernightOnlyEnabled)))
        out.append(LFact(recording, "Power saving", yes(PuffinExperiment.powerSavingEnabled)))
        out.append(LFact(recording, "Luma on screen", yes(onScreen)))
        out.append(LFact(recording, "A screen or session asking for live heart rate", yes(liveWanters > 0)))

        let lock = "Lock Screen and widgets"
        out.append(LFact(lock, "Lock Screen card setting", yes(UnitPrefs.liveActivityEnabled())))
        out.append(LFact(lock, "Live Activities allowed in iOS", yes(ActivityAuthorizationInfo().areActivitiesEnabled)))
        out.append(LFact(lock, "Cards on the Lock Screen now", String(Activity<NOOPActivityAttributes>.activities.count)))
        out.append(LFact(lock, "Widget figures last written", lastGlance.map { stamp($0.updated.timeIntervalSince1970) } ?? "not in this run"))
        return out
    }

    // MARK: Widgets and the Lock Screen

    private func publishGlance() {
        // First, whatever a widget button or a shortcut logged since the app last ran: the glance about
        // to be written must hold it, or the widget that was tapped would step back.
        env.applyQuickLog()
        let glance = env.glance()
        lastGlance = glance
        if LumaGlanceStore.save(glance) { WidgetCenter.shared.reloadAllTimelines() }
        liveActivity?.refresh()
        // Reminders are planned from the same numbers. Nothing is planned, or cleared, before the strap
        // data has been read once: an empty plan then would only mean "not known yet".
        if env.loaded { LumaReminders.sync(env.plannedReminders()) }
    }

    /// The day's scores as every other Luma surface shows them, the athlete's own zone for the reading,
    /// and the session being recorded, if any.
    private func decorate(_ state: inout NOOPActivityAttributes.ContentState) {
        let glance = lastGlance ?? env.glance()
        lastGlance = glance
        let current = glance.isCurrent()
        state.recovery = current ? glance.recovery : nil
        state.sleep = current ? glance.sleepScore : nil
        state.strainText = current ? glance.strainText : nil
        if let bpm = state.bpm ?? state.lastBpm { state.zone = env.profile.zones().zone(for: Double(bpm)) }
        guard let session = recorder.session else { return }
        state.session = session.title
        if let start = session.movingStart {
            state.sessionStart = start
        } else {
            state.pausedElapsed = recorder.elapsed.rounded()
        }
        if session.usesDistance, recorder.distanceM > 0 {
            // Steps of 50 m: the card follows the run without asking iOS for an update at every stride.
            state.distanceM = (recorder.distanceM / 50).rounded(.down) * 50
        }
    }

    // MARK: Links

    /// Opens what a widget, the Lock Screen card or a shortcut points at.
    func open(_ url: URL) {
        guard url.host == "luma" else { return }
        env.router.open(link: url.pathComponents.dropFirst().first ?? "today")
    }

    func askCoach(_ question: String) { env.router.askCoach(question) }

    /// A Home Screen quick action (a long press on the app icon).
    func open(_ action: HomeScreenQuickAction) {
        switch action {
        case .startWorkout: env.router.open(link: "go")
        case .liveHeartRate: env.router.open(link: "heart")
        case .logJournal: env.router.open(link: "checkin")
        case .breathe: env.router.open(link: "today")
        }
    }
}

// MARK: - Session recorder

/// A session in progress, recorded by the strap layer's own workout recorder so that heart rate,
/// strain, energy and the GPS route are captured and stored the same way for every kind of session.
@MainActor
final class LumaWorkoutRecorder: LumaRecorder {
    struct Session {
        let title: String
        /// A start such that now − start is the moving time; nil while paused.
        let movingStart: Date?
        let usesDistance: Bool
    }

    private let model: AppModel
    private var gps = false
    private var displaced: (@MainActor () -> Void)?
    private var holdsTap = false
    /// Called when a session starts, pauses, resumes or ends.
    var onChange: (() -> Void)?

    init(model: AppModel) { self.model = model }

    var isRunning: Bool { model.activeWorkout != nil }
    var isPaused: Bool { model.activeWorkout?.isPaused ?? false }
    var elapsed: TimeInterval { model.activeWorkout?.elapsed() ?? 0 }
    var distanceM: Double { gps ? model.gpsRecorder.distanceM : 0 }

    var session: Session? {
        guard let workout = model.activeWorkout else { return nil }
        return Session(title: workout.sport, movingStart: workout.isPaused ? nil : workout.start.addingTimeInterval(workout.pausedDuration),
                       usesDistance: gps)
    }

    func start(sport: String, gps: Bool) -> Bool {
        // One recorder, one session: a session already running (for instance one restored after the
        // app was closed mid-session) has to be finished first.
        guard model.activeWorkout == nil else { return false }
        model.startWorkout(sport: sport)
        self.gps = gps && (WorkoutCatalog.sport(named: sport)?.isDistanceSport ?? false)
        onChange?()
        return model.activeWorkout != nil
    }

    func setPaused(_ paused: Bool) {
        guard let workout = model.activeWorkout, workout.isPaused != paused else { return }
        model.toggleWorkoutPause()
        onChange?()
    }

    func route() -> [LumaRoutePoint] {
        guard gps, let workout = model.activeWorkout, let points = ActiveRouteStore.load() else { return [] }
        let start = workout.start.timeIntervalSince1970
        return points.map { LumaRoutePoint(lat: $0.lat, lon: $0.lon, t: Double($0.tMs) / 1000 - start) }
    }

    func finish() async -> LWorkout? {
        guard let workout = model.activeWorkout else { return nil }
        let start = Int(workout.start.timeIntervalSince1970), sport = workout.sport
        defer { gps = false; onChange?() }
        if AppModel.isTooShortToSave(elapsedSeconds: workout.elapsed()) {
            model.discardWorkout()
            return nil
        }
        model.endWorkout()
        guard model.lastWorkout != nil else { return nil }
        // The row is stored a moment after the session ends. Wait for it, so that a correction made
        // straight afterwards (a treadmill's distance) edits the stored row instead of racing it.
        for _ in 0..<24 {
            let stored = await model.repo.workoutRows(days: 3)
            if let row = stored.first(where: { $0.startTs == start && $0.sport == sport }) { return LumaRepoSource.workout(row) }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return model.lastWorkout.map { LumaRepoSource.workout($0) }
    }

    func discard() {
        model.discardWorkout()
        gps = false
        onChange?()
    }

    /// While a session wants the strap's double tap (to move on to the next race segment), it takes
    /// the place of whatever the tap did before, and hands it back afterwards.
    var onStrapDoubleTap: (() -> Void)? {
        didSet {
            if let handler = onStrapDoubleTap {
                if !holdsTap {
                    displaced = model.strapDoubleTapOverride
                    holdsTap = true
                }
                model.strapDoubleTapOverride = { handler() }
            } else if holdsTap {
                model.strapDoubleTapOverride = displaced
                displaced = nil
                holdsTap = false
            }
        }
    }
}

// MARK: - Secrets

/// The coach's API key, in the phone's keychain. The keychain slot predates Luma and could hold a
/// key for another provider; only an Anthropic key is treated as the coach's.
final class LumaKeychain: LumaSecrets {
    private static let owner = "anthropic"

    func coachKey() -> String? {
        guard let key = AIKeyStore.read(), !key.isEmpty else { return nil }
        if let owner = AIKeyStore.ownerProvider, owner != Self.owner { return nil }
        return key
    }

    func setCoachKey(_ key: String?) {
        if let key, !key.isEmpty {
            AIKeyStore.save(key, owner: Self.owner)
        } else if AIKeyStore.ownerProvider == nil || AIKeyStore.ownerProvider == Self.owner {
            AIKeyStore.clear()
        }
    }
}

// MARK: - Shell

/// The app's one window: Luma.
struct LumaShell: View {
    @EnvironmentObject private var bridge: LumaBridge
    @EnvironmentObject private var quickActions: HomeScreenQuickActionSceneDelegate

    var body: some View {
        LumaRootView(env: bridge.env, launch: LumaLaunch.fromArguments())
            .onChange(of: quickActions.pendingAction, initial: true) { _, action in
                guard let action else { return }
                quickActions.consume(action)
                bridge.open(action)
            }
    }
}
#endif
