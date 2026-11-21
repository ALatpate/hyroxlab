#if os(iOS)
import SwiftUI
import Combine
import WidgetKit
import ActivityKit
import UIKit
import UserNotifications
import WhoopProtocol
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
    /// The companion as the Lock Screen card carries it, and the minute it was worked out in: the card
    /// is refreshed with every reading, and the companion's state changes with the minute at most.
    private var glimmTag: (minute: Int, tag: String)?
    /// A changed wake time waiting to be passed to the strap layer (see `applyAlarm`).
    private var alarmApply: Task<Void, Never>?
    /// Whether iOS will show a notification for Luma, as last read. Half of the alarm's reading.
    private var phoneNotifies = false
    /// The strap layer's heart-rate broadcaster, alive only while the phone is on the air.
    private var broadcaster: HrBroadcaster?
    private var broadcastBag: Set<AnyCancellable> = []
    /// Which packet of beat intervals was last passed on, so each is passed on once.
    private var beatCursor = RRPacketCursor()
    /// The strap layer's store of raw-motion recordings, opened when first needed.
    private var motionStore: RawDataSessionStore?
    /// The recording being made, if any.
    private var motionSession: String?

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
        // What iOS reports about the app stopping is kept on the phone, for the data check.
        LumaCrashLog.shared.start()
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

    /// The earlier shell could act on its own once asked to: a wind-down reminder, strain and
    /// early-warning notifications, haptic check-ins, zone buzzes, a double-tap action. Luma has no
    /// screen for any of them, so one left on would go on buzzing and notifying with nothing in the app
    /// to explain it or stop it. Each one found on is switched off, through the same calls its own
    /// switch used, and the athlete is told which (`LumaLive.switchedOff`). All are off by default, so
    /// for most installs this does nothing, and after the first launch it has nothing left to do.
    ///
    /// The wake alarm is not among them: Luma has a screen for it. What goes is a wake time of its own
    /// for one weekday, which that screen does not show and which would wake at another time than the
    /// one it does show.
    private func retireEarlierAutomations() {
        var off: [String] = []
        let behavior = model.behavior
        if clearDayTimes(), behavior.smartAlarmEnabled {
            // Plans the phone's notification again at the one time, and tells the strap when it connects.
            model.applySmartAlarm()
            off.append("separate wake times for single weekdays")
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
        // Only for someone with no details of their own, never while their details could not be read.
        guard env.storesReady, !env.profile.isSetUp else { return }
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
        // The alarm's reading is taken again with it: its next time moves on once a wake time has passed.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStrap()
                self?.refreshAlarm()
            }
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
            .sink { [weak self] bonded in
                self?.applyCapture()
                if bonded { self?.rearmMotion() }
            }
            .store(in: &bag)
        applyCapture()

        // Beat-to-beat intervals, for the breathing screen. Each packet is passed on once: as soon as it
        // has landed, and at the latest just before the next one takes its place.
        model.live.$rr
            .sink { [weak self] _ in self?.takeBeats() }
            .store(in: &bag)
        model.live.$rrSeq
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.takeBeats() }
            .store(in: &bag)

        // The strap layer tells the strap the wake time once a connection has settled. The alarm's reading
        // is taken a turn later, after it has.
        model.live.$connectSettled.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.linkSettled() }
            .store(in: &bag)

        // The athlete's records could not be read when Luma was started (the phone was locked): read
        // them the moment the phone says its files are open again, and pick up from there.
        NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.env.retryStores() }
            .store(in: &bag)
        env.$storesReady.removeDuplicates().dropFirst().filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.adoptStrapProfileIfNew()
                self?.publishGlance()
            }
            .store(in: &bag)

        // Widgets and the Lock Screen card.
        env.onGlanceChange = { [weak self] in self?.publishGlance() }
        // Reminders and the wake alarm ask iOS for leave the first time one is switched on. The alarm's
        // reading says whether the phone will notify, so the answer is read back before it is drawn.
        env.requestNotifications = { [weak self] in
            let granted = await LumaReminders.requestAuthorization()
            await self?.readNotificationLeave()
            return granted
        }
        // A result that has just come in (Luma Doctor's weekly check), shown at once.
        env.postNotice = { id, title, body in LumaReminders.post(id: id, title: title, body: body) }
        // Something was logged by a shortcut or Siri while the app is running: file it now.
        NotificationCenter.default.publisher(for: LumaQuickIntents.changed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishGlance() }
            .store(in: &bag)
        // A session starting or ending changes the Lock Screen card and the companion's state, and
        // whether the phone is on the air as a heart-rate sensor.
        recorder.onChange = { [weak self] in
            self?.publishGlance()
            self?.applyBroadcast()
        }
        liveActivity?.decorate = { [weak self] state in self?.decorate(&state) }

        refreshStrap()
        refreshHealth()
        follow(model.deviceRegistry)
        refreshAlarm()
        refreshBroadcast()
        Task { [weak self] in await self?.readNotificationLeave() }
    }

    /// Called when the app comes to the front.
    func becameActive() {
        // An icon picked in the earlier shell is no longer shipped; return to Luma's own.
        if UIApplication.shared.alternateIconName != nil {
            UIApplication.shared.setAlternateIconName(nil, completionHandler: nil)
        }
        env.retryStores()
        env.reload()
        refreshStrap()
        publishGlance()
        // The app tells the strap the wake time again each time it comes to the front, straight after
        // this call. The alarm is read once that has happened, with what Settings now says about
        // notifications.
        Task { [weak self] in
            guard let self else { return }
            await self.readNotificationLeave()
            self.refreshAlarm()
        }
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
        refreshAlarm()
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
        // A WHOOP 5.0 or MG repeats a buzz the number of times asked; a 4.0 makes one buzz longer.
        strap.buzzesByCount = device == nil || model.whoop5Detected
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
        let now = LNum.int(Date().timeIntervalSince1970)
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

    func cue() { cue(.two) }

    /// The strap layer's own cue buzz, with its count. On a WHOOP 5.0 or MG the count is the number of
    /// buzzes; on a 4.0 it is the length of one.
    func cue(_ kind: StrapCue) {
        switch kind {
        case .one: model.buzz(loops: 1)
        case .two: model.buzz(loops: 2)
        case .three: model.buzz(loops: 3)
        }
    }

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
        applyBroadcast()
        // A wake time picked a moment before Luma left the screen is passed on now, not after a wait
        // the app may not be given.
        if !on, alarmApply != nil { applyAlarm(settled: true) }
    }

    // MARK: Wake alarm

    /// Luma counts the days of the week from Monday (1) to Sunday (7); the strap layer keeps them as
    /// the calendar does, Sunday (1) to Saturday (7).
    private static func calendarDay(_ day: Int) -> Int { day % 7 + 1 }
    private static func lumaDay(_ day: Int) -> Int { (day + 5) % 7 + 1 }

    /// Stores the wake alarm where the strap layer keeps it and has that layer act on it: it tells the
    /// strap (now, or when the strap next connects) and plans the phone's notification. No command of
    /// Luma's own is sent.
    func setAlarm(on: Bool, minutes: Int, weekdays: Set<Int>) {
        let behavior = model.behavior
        let was = behavior.smartAlarmEnabled
        clearDayTimes()
        let wake = min(max(minutes, 0), 24 * 60 - 1)
        let picked = Set(weekdays.filter { (1...7).contains($0) }.map { Self.calendarDay($0) })
        // All seven days is every day, which the strap layer keeps as no days picked.
        let days: Set<Int> = picked.count == 7 ? [] : picked
        if behavior.smartAlarmMinutes != wake { behavior.smartAlarmMinutes = wake }
        if behavior.smartAlarmWeekdays != days { behavior.smartAlarmWeekdays = days }
        if was != on { behavior.smartAlarmEnabled = on }
        // An alarm that was off and stays off has nothing set anywhere, so nothing is sent for it.
        if was || on { applyAlarm(settled: was != on) }
        refreshAlarm()
        if on { Task { [weak self] in await self?.readNotificationLeave() } }
    }

    /// Switches the trial of the strap's own alarm on a WHOOP 5.0 or MG. The switch is the strap layer's
    /// own for that family, and its one effect in this tree is to let `BLEManager.armStrapAlarm` send
    /// the wake time to such a strap.
    func setAlarmTrial(_ on: Bool) {
        guard model.whoop5Detected, PuffinExperiment.isEnabled != on else { return }
        UserDefaults.standard.set(on, forKey: PuffinExperiment.defaultsKey)
        if model.behavior.smartAlarmEnabled {
            // With the trial off the strap layer no longer sets this strap's alarm, and it leaves one it
            // set earlier in place. That one is taken off.
            if !on { model.ble.disableStrapAlarm() }
            applyAlarm(settled: true)
        }
        refreshAlarm()
    }

    /// Has the strap layer act on the alarm as stored. A switch is acted on at once. A time being
    /// picked changes several times in a second: the strap is told once, when it has settled.
    private func applyAlarm(settled: Bool) {
        alarmApply?.cancel()
        alarmApply = nil
        if settled {
            model.applySmartAlarm()
            return
        }
        alarmApply = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.alarmApply = nil
            self.model.applySmartAlarm()
            self.refreshAlarm()
        }
    }

    /// Luma has one wake time. A time of its own for one weekday, left by the earlier shell, would wake
    /// at another time than the one shown, so those are taken out. True when there were any.
    @discardableResult
    private func clearDayTimes() -> Bool {
        let days = Array(WindDownNudge.perDayWakeOverrides.keys)
        for day in days { WindDownNudge.setWakeOverride(weekday: day, minutes: nil) }
        return !days.isEmpty
    }

    /// A connection has settled, and the strap layer has just acted on the alarm.
    private func linkSettled() {
        // The strap's alarm was taken off while the strap was out of reach, and the alarm is on with the
        // trial off: the strap layer sets nothing on this strap now, so nothing would replace what the
        // strap still holds. It is taken off now that the strap can be reached.
        if model.ble.disarmPending, model.behavior.smartAlarmEnabled, model.whoop5Detected, !PuffinExperiment.isEnabled {
            model.ble.disableStrapAlarm()
        }
        refreshAlarm()
    }

    /// The one reading of the wake alarm, from which every screen that mentions it is drawn. Its time
    /// comes from the function the strap layer itself sets the strap and plans the notification from.
    private func refreshAlarm() {
        let behavior = model.behavior
        var alarm = LumaAlarmState()
        alarm.on = behavior.smartAlarmEnabled
        alarm.minutes = behavior.smartAlarmMinutes
        let days = Set(behavior.smartAlarmWeekdays.filter { (1...7).contains($0) }.map { Self.lumaDay($0) })
        alarm.weekdays = days.count == 7 ? [] : days
        alarm.strapIsTrial = model.whoop5Detected
        alarm.trialOn = PuffinExperiment.isEnabled
        alarm.phoneWillNotify = phoneNotifies
        if alarm.on {
            alarm.next = AppModel.nextSmartAlarmDate(minutes: behavior.smartAlarmMinutes, weekdays: behavior.smartAlarmWeekdays,
                                                     overrides: WindDownNudge.perDayWakeOverrides)
            alarm.strap = strapAlarm(for: alarm.next)
        }
        // An alarm the strap has since been given takes the place of the one it was to drop.
        alarm.strapOwesStop = model.ble.disarmPending && alarm.strap != .told
        if alarm != live.alarm { live.alarm = alarm }
    }

    /// Where the strap stands with a wake time. "Told" is said only on the strap layer's own record of
    /// its last send: that time, to this strap, over a link that could carry it.
    private func strapAlarm(for next: Date?) -> LumaStrapAlarm {
        guard let next, let device = activeDevice, !device.isImportSource,
              DeviceFamily.forRegistryDevice(model: device.model, brand: device.brand) != nil else { return .none }
        if model.whoop5Detected, !PuffinExperiment.isEnabled { return .notAsked }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "alarm.lastArmConnected"),
              defaults.string(forKey: "alarm.lastArmDeviceId") == model.ble.deviceId,
              let sent = defaults.object(forKey: "alarm.lastArmSentEpoch") as? Int,
              sent == LNum.int(next.timeIntervalSince1970) else { return .waiting }
        return .told
    }

    private nonisolated static func notificationsAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                // The strap layer plans the alarm's notification on exactly this condition.
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }

    /// Reads whether iOS will show the alarm's notification, and takes the alarm's reading again if
    /// that has changed.
    private func readNotificationLeave() async {
        let allowed = await Self.notificationsAllowed()
        guard allowed != phoneNotifies else { return }
        phoneNotifies = allowed
        refreshAlarm()
    }

    // MARK: Heart rate for gym equipment

    func setBroadcast(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: HrBroadcaster.defaultsKey)
        applyBroadcast()
    }

    /// Puts the phone on the air as a standard heart-rate sensor, through the strap layer's own
    /// broadcaster: it passes on the heart rate the app already has and writes nothing to the strap.
    /// It runs only while it is switched on and Luma is on screen or recording a session, so a heart
    /// rate is not left readable by whatever is nearby for longer than that.
    private func applyBroadcast() {
        let want = HrBroadcaster.isEnabled && (onScreen || recorder.isRunning)
        if want, broadcaster == nil {
            let made = HrBroadcaster(log: { [weak state = model.live] line in state?.append(log: line) })
            made.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshBroadcast() }
                .store(in: &broadcastBag)
            // A sensor is expected to report about once a second, and a heart rate that holds steady
            // changes nothing to react to: the current figure is passed on each second.
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] _ in self?.feedBroadcast() }
                .store(in: &broadcastBag)
            broadcaster = made
            made.start()
        } else if !want, let running = broadcaster {
            running.stop()
            broadcastBag.removeAll()
            broadcaster = nil
        }
        refreshBroadcast()
    }

    /// The heart rate the strap is sending now, or nothing: a figure is never made up or held over.
    private func feedBroadcast() {
        let state = model.live
        broadcaster?.update(heartRate: state.connected ? (model.bpm ?? state.heartRate) : nil)
    }

    private func refreshBroadcast() {
        var broadcast = LumaBroadcast()
        broadcast.on = HrBroadcaster.isEnabled
        broadcast.advertising = broadcaster?.advertising ?? false
        broadcast.listeners = broadcaster?.subscriberCount ?? 0
        broadcast.note = Self.plain(broadcaster?.statusNote)
        if broadcast != live.broadcast { live.broadcast = broadcast }
    }

    // MARK: Beat intervals

    /// Passes on the latest packet of beat-to-beat intervals, once. The strap layer moves a packet and
    /// its count together, so the two read here always belong to each other.
    private func takeBeats() {
        let state = model.live
        guard beatCursor.isNew(state.rrSeq) else { return }
        let intervals = state.rr.filter { $0 > 0 }.map { Double($0) }
        if !intervals.isEmpty { live.beats.send(intervals) }
    }

    // MARK: Raw motion

    /// The strap layer's store of raw-motion recordings. Luma is its only user in this app, so a
    /// recording found open when the store is first opened was left by a run of the app that ended
    /// mid-session: it is closed where it stands and says so.
    private func motion() -> RawDataSessionStore {
        if let store = motionStore { return store }
        let store = RawDataSessionStore()
        if let open = store.active {
            store.stop()
            store.setComment((open.comment.isEmpty ? "Recording" : open.comment) + " (cut short: Luma stopped while it ran)", sessionId: open.id)
        }
        motionStore = store
        return store
    }

    /// Starts a bounded recording of the strap's raw motion beside a session, through the strap
    /// layer's own collector: its start and stop commands, its files. Only on a strap that is
    /// connected and paired, and only one at a time.
    func startMotion(note: String) -> Bool {
        let state = model.live
        guard motionSession == nil, state.connected, state.bonded else { return false }
        let store = motion()
        guard let session = store.start(deviceId: model.ble.deviceId) else { return false }
        guard model.ble.startGroundTruthRawCapture(sessionId: session.id) else {
            store.stop()
            store.removeMetadata(session.id)
            return false
        }
        store.setComment(note, sessionId: session.id)
        motionSession = session.id
        live.motionRecording = true
        return true
    }

    /// Marks where a part of the session starts, by its name.
    func markMotion(_ text: String) {
        guard let id = motionSession else { return }
        motion().addMarker(sessionId: id, at: Date(), type: "start", text: text)
    }

    func stopMotion() {
        guard motionSession != nil else { return }
        motionSession = nil
        Task { [weak self] in
            guard let self else { return }
            await self.model.ble.stopGroundTruthRawCapture()
            self.motion().stop()
            self.live.motionRecording = false
        }
    }

    /// A link that dropped mid-session stops the strap's motion stream. It is asked for again once the
    /// strap is paired again, as the strap layer's own collector screen does.
    private func rearmMotion() {
        guard let id = motionSession else { return }
        _ = model.ble.startGroundTruthRawCapture(sessionId: id)
    }

    func motionRecordings() async -> [LumaMotionRecording] {
        motion().sessions.compactMap { session in
            guard let end = session.endedAtMs else { return nil }
            return LumaMotionRecording(id: session.id, startedAt: Date(timeIntervalSince1970: Double(session.startedAtMs) / 1000),
                                       seconds: Double(end - session.startedAtMs) / 1000, note: session.comment)
        }
    }

    /// One recording as a zip to share: the strap layer's own export (its description of the session,
    /// the marks, the sensor history it holds for that window, and the motion in 30-minute files) with
    /// a list of what the motion covers.
    func motionFile(_ id: String) async -> URL? {
        let store = motion()
        guard let session = store.sessions.first(where: { $0.id == id }), let end = session.endedAtMs else { return nil }
        let bounds = RawDataCollectorView.fullSecondBounds(fromMs: session.startedAtMs, toMs: end)
        let segments = bounds.map { ImuSessionFileStore.shared.exportSegments(id, from: $0.from, to: $0.to) } ?? []
        var history = Data("stream,unix_s,v1,v2,v3,v4\n".utf8)
        if let bounds { history = await model.ble.groundTruthHistoryCSV(from: bounds.from, to: bounds.to) }
        let hasSensors = !segments.isEmpty || history.split(separator: 0x0A).count > 1
        var entries = store.exportEntries(for: session, sensorAvailable: hasSensors)
        entries.append(.init(name: "history-sensors.csv", data: history))
        let covered: [[String: Any]] = segments.map {
            ["file": $0.name, "start_ts": $0.startTs, "end_ts": $0.endTs, "sample_count": $0.sampleCount]
        }
        let coverage: [String: Any] = ["requested_start_ts": bounds?.from ?? 0, "requested_end_ts": bounds?.to ?? 0,
                                       "sample_rate_hz": ImuSessionFileStore.sampleRate, "segments": covered]
        if let data = try? JSONSerialization.data(withJSONObject: coverage, options: [.prettyPrinted, .sortedKeys]) {
            entries.append(.init(name: "imu-coverage.json", data: data))
        }
        for segment in segments { entries.append(.init(name: "imu/\(segment.name)", data: segment.data)) }
        let name = "luma-motion-\(id)"
        let bundle = entries
        let url = await Task.detached(priority: .userInitiated) { FileExport.zipData(entries: bundle, baseName: name) }.value
        if url != nil { store.markExported(id) }
        return url
    }

    func deleteMotion(_ id: String) async {
        motion().removeMetadata(id)
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
        let maxHR = LNum.int((profile.maxHR ?? 0).rounded())
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
        out.append(LFact(link, "Battery", state.batteryPct.map { "\(LNum.int($0.rounded()))%" } ?? "not reported"))
        out.append(LFact(link, "Firmware", state.strapFirmware ?? "not reported"))
        out.append(LFact(link, "Model", activeDevice?.model ?? "none"))

        let recording = "Recording"
        out.append(LFact(recording, "Stream held open by the setting", yes(PuffinExperiment.keepRealtimeForDataEnabled)))
        out.append(LFact(recording, "Limited to night hours", yes(PuffinExperiment.continuousHrvOvernightOnlyEnabled)))
        out.append(LFact(recording, "Power saving", yes(PuffinExperiment.powerSavingEnabled)))
        out.append(LFact(recording, "Luma on screen", yes(onScreen)))
        out.append(LFact(recording, "A screen or session asking for live heart rate", yes(liveWanters > 0)))

        let alarm = live.alarm
        let wake = "Wake alarm"
        out.append(LFact(wake, "Switched on", yes(alarm.on)))
        out.append(LFact(wake, "Next due", alarm.next.map { stamp($0.timeIntervalSince1970) } ?? "not set"))
        out.append(LFact(wake, "Notifications allowed for Luma", yes(phoneNotifies)))
        out.append(LFact(wake, "Strap of the 5.0 or MG family", yes(model.whoop5Detected)))
        out.append(LFact(wake, "Trial of the strap's own alarm", yes(PuffinExperiment.isEnabled)))
        let defaults = UserDefaults.standard
        let sent = defaults.object(forKey: "alarm.lastArmSentEpoch") as? Int
        out.append(LFact(wake, "Wake time last sent to a strap", sent.map { stamp(Double($0)) } ?? "none sent"))
        out.append(LFact(wake, "That send had a link to travel on", sent == nil ? "none sent" : yes(defaults.bool(forKey: "alarm.lastArmConnected"))))
        out.append(LFact(wake, "A stop still owed to the strap", yes(model.ble.disarmPending)))

        let sharing = "Sharing and motion"
        out.append(LFact(sharing, "Heart rate for gym equipment switched on", yes(HrBroadcaster.isEnabled)))
        out.append(LFact(sharing, "On the air now", yes(broadcaster?.advertising ?? false)))
        out.append(LFact(sharing, "Devices reading it", String(broadcaster?.subscriberCount ?? 0)))
        out.append(LFact(sharing, "Note from the broadcaster", Self.plain(broadcaster?.statusNote) ?? "none"))
        out.append(LFact(sharing, "Motion being recorded", yes(motionSession != nil)))
        out.append(LFact(sharing, "Motion recordings kept", motionStore.map { String($0.sessions.count) } ?? "not opened in this run"))

        let lock = "Lock Screen and widgets"
        out.append(LFact(lock, "Lock Screen card setting", yes(UnitPrefs.liveActivityEnabled())))
        out.append(LFact(lock, "Live Activities allowed in iOS", yes(ActivityAuthorizationInfo().areActivitiesEnabled)))
        out.append(LFact(lock, "Cards on the Lock Screen now", String(Activity<NOOPActivityAttributes>.activities.count)))
        out.append(LFact(lock, "Widget figures last written", lastGlance.map { stamp($0.updated.timeIntervalSince1970) } ?? "not in this run"))
        out.append(contentsOf: LumaCrashLog.shared.facts(stamp: stamp))
        return out
    }

    // MARK: Widgets and the Lock Screen

    private func publishGlance() {
        // With the athlete's records unread, what Luma holds is not theirs: the widgets and the Lock
        // Screen card keep what was last written, and no reminder is planned or cleared.
        guard env.storesReady else { return }
        // First, whatever a widget button or a shortcut logged since the app last ran: the glance about
        // to be written must hold it, or the widget that was tapped would step back.
        env.applyQuickLog()
        let glance = env.glance()
        lastGlance = glance
        glimmTag = nil
        if LumaGlanceStore.save(glance) { WidgetCenter.shared.reloadAllTimelines() }
        liveActivity?.refresh()
        // Reminders are planned from the same numbers. Nothing is planned, or cleared, before the strap
        // data has been read once: an empty plan then would only mean "not known yet".
        if env.loaded { LumaReminders.sync(env.plannedReminders()) }
    }

    /// The day's scores as every other Luma surface shows them, the athlete's own zone for the reading,
    /// and the session being recorded, if any.
    private func decorate(_ state: inout NOOPActivityAttributes.ContentState) {
        guard env.storesReady else {
            // The figures last written for the widgets stand in; no zone is worked out from details
            // that are not the athlete's.
            if let kept = lastGlance ?? LumaGlanceStore.load(), kept.isCurrent() {
                state.recovery = kept.recovery
                state.sleep = kept.sleepScore
                state.strainText = kept.strainText
                // The companion as it was last planned for this hour of the day.
                if let moment = kept.buddy?.moments.last(where: { $0.at <= Date() }) { state.glimm = moment.kind + "~" + (moment.outfit ?? "") }
            }
            return
        }
        let glance = lastGlance ?? env.glance()
        lastGlance = glance
        let current = glance.isCurrent()
        state.recovery = current ? glance.recovery : nil
        state.sleep = current ? glance.sleepScore : nil
        state.strainText = current ? glance.strainText : nil
        if let bpm = state.bpm ?? state.lastBpm { state.zone = env.profile.zones().zone(for: Double(bpm)) }
        let now = Date()
        let minute = LNum.int(now.timeIntervalSince1970 / 60)
        if glimmTag?.minute != minute {
            // Its state and its clothes come from where the companion's own screen takes them.
            glimmTag = (minute, env.glimmTag(now: now))
        }
        state.glimm = glimmTag?.tag
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
        // A link is followed by someone holding an unlocked phone, so the records can be read by now.
        env.retryStores()
        guard env.storesReady else { return }
        env.router.open(link: url.pathComponents.dropFirst().first ?? "today")
    }

    func askCoach(_ question: String) {
        env.retryStores()
        guard env.storesReady else { return }
        env.router.askCoach(question)
    }

    /// A Home Screen quick action (a long press on the app icon).
    func open(_ action: HomeScreenQuickAction) {
        env.retryStores()
        guard env.storesReady else { return }
        switch action {
        case .startWorkout: env.router.open(link: "go")
        case .liveHeartRate: env.router.open(link: "heart")
        case .logJournal: env.router.open(link: "checkin")
        case .breathe: env.router.open(link: "breathing")
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
        let start = LNum.int(workout.start.timeIntervalSince1970), sport = workout.sport
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
