#if os(iOS)
import SwiftUI
import Combine
import WidgetKit
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
        env = LumaEnv(source: source, live: live, secrets: LumaKeychain())
        env.device = self
        env.recorder = recorder
        Self.settleEarlierShell()
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

        // Widgets and the Lock Screen card.
        env.onGlanceChange = { [weak self] in self?.publishGlance() }
        recorder.onChange = { [weak self] in self?.liveActivity?.refresh() }
        liveActivity?.decorate = { [weak self] state in self?.decorate(&state) }

        refreshStrap()
        refreshHealth()
        follow(model.deviceRegistry)
    }

    /// Called when the app comes to the front.
    func becameActive() {
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
    }

    // MARK: Widgets and the Lock Screen

    private func publishGlance() {
        let glance = env.glance()
        lastGlance = glance
        if LumaGlanceStore.save(glance) { WidgetCenter.shared.reloadAllTimelines() }
        liveActivity?.refresh()
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
