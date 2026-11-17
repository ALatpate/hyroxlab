import SwiftUI
import LumaCore
import LumaKit

// MARK: - You

struct YouSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = env.profile
        LumaSheet(title: p.name.isEmpty ? "You" : p.name, tone: .recovery) {
            HStack(spacing: 0) {
                fact("\(p.age())", "years")
                fact(String(format: "%.0f", p.weightKg), "kg")
                fact("\(Int(p.resolvedMaxHR()))", "max bpm")
                fact("\(env.analysis.dayCount)", "days of data")
            }
            .padding(.vertical, 14).background(LumaPanel(radius: 20))
            LumaGroup {
                row("person.fill", Luma.frost, "Profile", "Body, heart-rate zones, race goal", .profile)
                row("dot.radiowaves.left.and.right", live.strap.connected ? Luma.volt : Luma.amber, "Strap", live.strap.name.map { "\($0) · \(live.strap.statusText)" } ?? live.strap.statusText, .devices)
                row("face.smiling.inverse", Luma.volt, env.extras.name, "Your companion, on the Lock Screen and here", .buddy)
                row("calendar.badge.checkmark", Luma.aqua, "Weekly review", "The week written up, and the ones before", .reviews)
                row("bell.fill", Luma.amber, "Reminders", "Worked out from your own numbers", .reminders)
                row("gearshape.fill", Luma.frost, "Settings", "Cues, Lock Screen, data", .settings)
                row("info.circle.fill", Luma.frost, "About Luma", "Privacy, licences, what the numbers mean", .about)
            }
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.tab = .coach; router.sheet = .coachSetup }
            } label: { Label("Coach settings", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(LumaFont.numeral(26)).foregroundStyle(Luma.frost)
            LumaLabel(label)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ subtitle: String, _ dest: LumaDest) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { router.open(.today, dest) }
        } label: { LumaRow(symbol: symbol, symbolColor: color, title: title, subtitle: subtitle, chevron: true) }
            .buttonStyle(.plain)
    }
}

// MARK: - Profile

struct ProfileScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var fiveKMinutes = 25.0
    @State private var fiveKSeconds = 0.0
    @State private var hasRace = false
    @State private var raceDate = Date().addingTimeInterval(60 * 86_400)

    var body: some View {
        LumaDetailScreen(title: "Profile", tone: .recovery) {
            ProfileFields()
            LumaSection(title: "Heart rate")
            optionalNumber("Maximum heart rate", "Leave off to use the age estimate (\(Int((208 - 0.7 * Double(env.profile.age())).rounded())) bpm). Set it if you have seen higher in an all-out effort.",
                           value: $env.profile.maxHR, fallback: env.profile.resolvedMaxHR(), range: 120...230)
            optionalNumber("Threshold heart rate", "If you know your lactate-threshold heart rate, zones are built from it instead.",
                           value: $env.profile.lthr, fallback: (env.profile.resolvedMaxHR() * 0.88).rounded(), range: 100...220)
            LumaSection(title: "Running and racing")
            LumaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("Current 5 km time")
                    HStack(spacing: 10) {
                        NumberField(label: "min", value: $fiveKMinutes)
                        NumberField(label: "sec", value: $fiveKSeconds)
                    }
                    LumaNote("Sets your training paces for intervals and race targets.")
                }
            }
            LumaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    LumaLabel("HYROX format you train for")
                    LumaSegmented(selection: $env.profile.format, options: RaceFormat.allCases.map { ($0, shortFormat($0)) }, tint: Luma.volt)
                    Toggle(isOn: $hasRace) { Text("I have a race booked").font(LumaFont.body(15)).foregroundStyle(Luma.frost) }.tint(Luma.volt)
                    if hasRace {
                        LumaField(title: "Race name", text: $env.profile.raceName)
                        DatePicker("Race day", selection: $raceDate, in: Date()..., displayedComponents: [.date]).font(LumaFont.body(15)).foregroundStyle(Luma.frost).colorScheme(.dark)
                    }
                }
            }
            LumaSection(title: "For the coach")
            LumaField(title: "Where you train", text: $env.profile.gym)
            LumaField(title: "Your goals, in your own words", text: $env.profile.goals, axis: .vertical)
            LumaSection(title: "Sleep")
            optionalNumber("Fixed sleep need (hours)", "Leave off and Luma estimates your need each night from strain and sleep debt.",
                           value: $env.profile.sleepNeedHours, fallback: 8, range: 5...11, step: 0.25, decimals: 2)
        }
        .onAppear {
            if let t = env.profile.fiveKSeconds { fiveKMinutes = Double(Int(t) / 60); fiveKSeconds = Double(Int(t) % 60) }
            hasRace = env.profile.raceDate != nil
            if let d = env.profile.raceDate { raceDate = d }
        }
        .onChange(of: fiveKMinutes) { _, _ in saveFiveK() }
        .onChange(of: fiveKSeconds) { _, _ in saveFiveK() }
        .onChange(of: hasRace) { _, on in env.profile.raceDate = on ? raceDate : nil }
        .onChange(of: raceDate) { _, d in if hasRace { env.profile.raceDate = d } }
    }

    private func saveFiveK() {
        let t = fiveKMinutes * 60 + fiveKSeconds
        env.profile.fiveKSeconds = t >= 700 ? t : nil
    }

    private func shortFormat(_ f: RaceFormat) -> String {
        switch f {
        case .openSingles: return "Open"
        case .proSingles: return "Pro"
        case .doubles: return "Doubles"
        case .relay: return "Relay"
        }
    }

    private func optionalNumber(_ title: String, _ note: String, value: Binding<Double?>, fallback: Double, range: ClosedRange<Double>,
                                step: Double = 1, decimals: Int = 0) -> some View {
        LumaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? fallback : nil })) {
                    Text(title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                }
                .tint(Luma.volt)
                if let v = value.wrappedValue {
                    Stepper(value: Binding(get: { v }, set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }), step: step) {
                        Text(String(format: "%.\(decimals)f", v)).font(LumaFont.numeral(30)).foregroundStyle(Luma.frost)
                    }
                }
                LumaNote(note)
            }
        }
    }
}

/// Name, sex, age and body size: shared by the profile screen and first-run setup.
struct ProfileFields: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaField(title: "First name", text: $env.profile.name)
            LumaSegmented(selection: $env.profile.sex, options: [(Sex.male, "Male"), (.female, "Female")], tint: Luma.frost)
            HStack(spacing: 10) {
                stepper("Born", "\(env.profile.birthYear)", { env.profile.birthYear = max(1930, env.profile.birthYear - 1) }, { env.profile.birthYear = min(2015, env.profile.birthYear + 1) })
                stepper("Height", "\(Int(env.profile.heightCm)) cm", { env.profile.heightCm = max(120, env.profile.heightCm - 1) }, { env.profile.heightCm = min(230, env.profile.heightCm + 1) })
            }
            if let trend = env.next.weight.current {
                // With a weight log, the trend is the weight: it is shown here and changed by weighing in.
                VStack(spacing: 1) {
                    Text(String(format: "%.1f kg", trend)).font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
                    LumaLabel("Body mass, from your weigh-ins")
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(LumaPanel(radius: 18))
                LumaNote("This is the trend of your weigh-ins. Add a weigh-in on the Fuel tab to move it.")
            } else {
                stepper("Body mass", String(format: "%.1f kg", env.profile.weightKg), { env.profile.weightKg = max(35, env.profile.weightKg - 0.5) }, { env.profile.weightKg = min(250, env.profile.weightKg + 0.5) })
            }
            LumaNote("Sex and body size are used for energy targets, training load weighting and official HYROX loads.")
        }
    }

    private func stepper(_ label: String, _ value: String, _ down: @escaping () -> Void, _ up: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: down) { Image(systemName: "minus").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 56) }
            VStack(spacing: 1) {
                Text(value).font(LumaFont.numeral(24)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                LumaLabel(label)
            }
            .frame(maxWidth: .infinity)
            Button(action: up) { Image(systemName: "plus").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 56) }
        }
        .foregroundStyle(Luma.mist)
        .buttonStyle(.plain)
        .background(LumaPanel(radius: 18))
    }
}

// MARK: - Strap

struct DevicesScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @State private var scanning = false
    @State private var generation: LumaStrapGeneration = .fiveOrMG

    var body: some View {
        let s = live.strap
        LumaDetailScreen(title: "Strap", tone: .recovery) {
            LumaCard(tint: s.connected ? Luma.volt.opacity(0.4) : nil) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Circle().fill(s.connected ? (s.secure ? Luma.volt : Luma.amber) : Luma.smoke).frame(width: 8, height: 8)
                                LumaLabel(s.statusText, color: s.connected ? Luma.frost : Luma.mist)
                            }
                            Text(s.name ?? "No strap").font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                            if let f = s.firmware { Text("Firmware \(f)").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke) }
                        }
                        Spacer()
                        if let b = s.battery {
                            VStack(alignment: .trailing, spacing: 0) {
                                // Away from the phone the strap reports nothing, so the figure is the last one it sent.
                                Text("\(Int(b.rounded()))%").font(LumaFont.numeral(40))
                                    .foregroundStyle(!s.connected ? Luma.mist : (b <= 20 ? Luma.coral : Luma.frost))
                                Text(!s.connected ? "Battery when last connected" : (s.charging ? "Charging" : "Battery"))
                                    .font(LumaFont.label(10)).foregroundStyle(Luma.mist)
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        info("Heart rate", s.liveHeartRate().map { "\($0) bpm" } ?? "–")
                        info("On wrist", s.connected ? (s.worn ? "Yes" : "No") : "–")
                        info("Last sync", s.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
                    }
                    if let hint = s.hint { Text(hint).font(LumaFont.body(13.5)).foregroundStyle(Luma.amber).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: 8) {
                        LumaQuickAction(symbol: "arrow.triangle.2.circlepath", title: "Sync", tint: Luma.volt) { env.device?.syncNow() }
                        LumaQuickAction(symbol: "bolt.horizontal.fill", title: "Reconnect", tint: Luma.volt) { env.device?.reconnect() }
                        LumaQuickAction(symbol: "waveform", title: "Buzz", tint: Luma.volt) { env.device?.buzz() }
                    }
                }
            }
            if s.connected && !s.secure {
                LumaCard(tint: Luma.amber.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected, but not paired").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        LumaNote("Live heart rate works, but history sync, strap buzzes and double-tap need a secure pairing. Put the strap in pairing mode (on a WHOOP 5.0 or MG: take it off the charger, then tap the band firmly several times until the light blinks blue), then press Reconnect and accept the pairing request.")
                    }
                }
            } else {
                // The same notice Today carries, so the two screens cannot describe the data differently.
                DataNoticeCard()
            }
            LumaSection(title: "Your straps")
            if live.paired.isEmpty {
                LumaCard { Text("No strap has been paired yet.").font(LumaFont.body(14)).foregroundStyle(Luma.mist) }
            } else {
                LumaGroup {
                    ForEach(live.paired) { p in
                        LumaRow(symbol: "dot.radiowaves.left.and.right", symbolColor: p.isActive ? Luma.volt : Luma.smoke, title: p.name, subtitle: p.detail) {
                            if p.isActive {
                                LumaPill(text: "Active", color: Luma.volt)
                            } else {
                                Button("Use") { env.device?.makeActive(p.id) }.font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt).buttonStyle(.plain)
                            }
                            Menu {
                                Button("Forget this strap", role: .destructive) { env.device?.forget(p.id) }
                            } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.mist).frame(width: 30, height: 30) }
                        }
                    }
                }
            }
            LumaSection(title: "Pair a strap")
            LumaNote("Have the strap charged and close by. Luma supports WHOOP 4.0, 5.0 and MG straps directly, without a WHOOP membership.")
            LumaSegmented(selection: $generation, options: LumaStrapGeneration.allCases.map { ($0, $0.title) }, tint: Luma.frost)
                .disabled(scanning)
            Button {
                scanning.toggle()
                if scanning { env.device?.startScan(generation) } else { env.device?.stopScan() }
            } label: {
                if scanning { HStack(spacing: 10) { ProgressView().tint(Luma.frost); Text("Looking for straps… tap to stop") } } else { Text("Look for straps") }
            }
            .buttonStyle(LumaSecondaryButtonStyle())
            if scanning || !live.found.isEmpty {
                LumaGroup {
                    if live.found.isEmpty {
                        LumaRow(symbol: "antenna.radiowaves.left.and.right", symbolColor: Luma.smoke, title: "Nothing found yet",
                                subtitle: "Make sure Bluetooth is on and the strap is not connected to another phone.")
                    }
                    ForEach(live.found) { f in
                        Button {
                            env.device?.stopScan()
                            env.device?.pair(f, generation: generation)
                            scanning = false
                        } label: {
                            LumaRow(symbol: "dot.radiowaves.left.and.right", symbolColor: Luma.volt, title: f.name, subtitle: "Signal \(f.rssi) dBm") {
                                Text("Pair").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HealthAccessCard()
        }
        .onAppear { if let model = live.strap.model, model.contains("4") { generation = .four } }
        .onDisappear { if scanning { env.device?.stopScan() } }
    }

    private func info(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LumaLabel(label)
            Text(value).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthAccessCard: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: "Apple Health")
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "heart.text.square.fill").font(.system(size: 20)).foregroundStyle(Luma.coral)
                        Text(title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                    }
                    LumaNote("Optional. When on, sessions and nightly metrics computed from the strap are written to Apple Health, and steps and body mass can be read from it. Everything stays on this phone.")
                    if live.health == .off || live.health == .denied {
                        Button(live.health == .denied ? "Open Health settings to allow access" : "Connect Apple Health") { Task { await env.device?.connectHealth() } }
                            .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    private var title: String {
        switch live.health {
        case .on: return "Connected"
        case .off: return "Not connected"
        case .denied: return "Access was declined"
        case .unavailable: return "Not available in this build"
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @State private var exportURL: URL?

    var body: some View {
        LumaDetailScreen(title: "Settings", tone: .neutral) {
            LumaSection(title: "During sessions")
            LumaGroup {
                toggle("Spoken cues", "Splits, heart rate and interval changes read out over your music.", $env.profile.voiceCues)
                toggle("A cue every kilometre", "Off: a cue every five minutes instead.", $env.profile.cueEveryKm)
                toggle("Auto-pause outdoor runs", "Pauses when you stop moving and resumes when you set off.", $env.profile.autoPause)
            }
            LumaSection(title: "Display and alerts")
            LumaGroup {
                toggle("Strain on the 0–21 scale", "Off: strain is shown from 0 to 100.", $env.profile.strainOn21)
                toggle("Heart rate on the Lock Screen", "A card with your heart rate and today's numbers. iOS starts it when you open Luma and keeps it for up to eight hours.", $env.profile.lockScreenHeartRate)
                toggle("Strap battery alerts", "A notification when the strap needs charging.",
                       Binding(get: { live.batteryAlerts }, set: { env.device?.setBatteryAlerts($0) }))
                Button { router.push(.reminders) } label: {
                    LumaRow(symbol: "bell.fill", symbolColor: Luma.amber, title: "Reminders",
                            subtitle: "Caffeine cut-off, supplements, protein, bedtime and more", chevron: true)
                }
                .buttonStyle(.plain)
                Button { router.push(.buddy) } label: {
                    LumaRow(symbol: "face.smiling.inverse", symbolColor: Luma.volt, title: env.extras.name,
                            subtitle: "Your companion: its name, and whether it shows on Today", chevron: true)
                }
                .buttonStyle(.plain)
            }
            LumaSection(title: "Recording")
            LumaGroup {
                toggle("Record all the time", "The strap sends heart rate to the phone day and night, so whole nights are recorded and the Lock Screen card stays live. It uses more strap battery, and Luma has to stay open in the background: swiping it away stops the recording. Off: the strap streams only while Luma is on screen or a session is running.", $env.profile.continuousRecording)
                Button { router.push(.dataCheck) } label: {
                    LumaRow(symbol: "waveform.path.ecg.rectangle.fill", symbolColor: Luma.sky, title: "Data check",
                            subtitle: "Where heart rate reached the phone, hour by hour", chevron: true)
                }
                .buttonStyle(.plain)
            }
            LumaSection(title: "Coach")
            LumaGroup {
                toggle("Share my health data with the coach", "Sent to Anthropic with a question when the answer needs it.", $env.profile.shareHealthWithCoach)
                toggle("Morning brief", "A short read of the day on Today, written once each morning.", $env.profile.morningBrief)
                Button { router.sheet = .coachSetup } label: { LumaRow(symbol: "key.fill", symbolColor: Luma.aqua, title: "API key and model", chevron: true) }.buttonStyle(.plain)
            }
            LumaSection(title: "Your data")
            LumaNote("Strap data, sessions, food log and everything else Luma keeps are stored on this phone only.")
            if let url = exportURL {
                ShareLink(item: url) { Label("Export my Luma records", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(LumaSecondaryButtonStyle())
            }
            Button("Clear the coach conversation") { env.coach.newChat() }.buttonStyle(LumaSecondaryButtonStyle())
            Button("Run setup again") { router.cover = .onboarding }.buttonStyle(LumaSecondaryButtonStyle())
        }
        .onAppear { exportURL = env.exportFile() }
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

// MARK: - About

struct AboutScreen: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        LumaDetailScreen(title: "About", tone: .recovery) {
            HStack(spacing: 16) {
                LumaOrb(progress: 0.82, color: Luma.volt, partner: Luma.mint).frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Luma").font(LumaFont.title(34)).foregroundStyle(Luma.frost)
                    Text(env.versionLine).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                }
            }
            section("What the numbers are", "Recovery, strain and sleep are computed on this phone from the strap's heart rate, heart-rate variability, skin temperature and movement. Baselines are your own: Luma compares you with you. Estimates such as VO₂max, sleep need and race predictions are labelled as estimates wherever they appear.")
            section("Not a medical device", "Luma is for training and general wellbeing. It does not diagnose, treat or monitor any condition, and its warning signs are prompts to pay attention, not medical findings. If something feels wrong, see a doctor.")
            section("Privacy", "Everything Luma records stays on this phone. Nothing is uploaded to any Luma server, because there is none. The only data that leaves the phone is what you send to the coach: your messages, photos you attach and, if you turn it on, the health data a question needs, sent to Anthropic with your own API key.")
            section("Open-source licences", "Luma's strap connection, on-device storage and its recovery, strain and sleep scoring are built on the open-source NOOP project (github.com/ryanbr/noop), used under the PolyForm Noncommercial License 1.0.0. This is a personal, non-commercial build. Luma is not affiliated with WHOOP or HYROX. Titles and figures are set in Barlow Condensed by the Barlow Project Authors, used under the SIL Open Font License 1.1.")
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                LumaNote(text)
            }
        }
    }
}

// MARK: - First run

struct OnboardingScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss
    @State private var page = LumaLaunch.page
    @State private var classDays: Set<Int> = [1, 2, 4, 5]
    @State private var runDays: Set<Int> = [6]
    @State private var classTime = Calendar.current.startOfDay(for: Date()).addingTimeInterval(6.5 * 3600)
    @State private var understood = false

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .recovery, strength: 1.3)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(i <= page ? Luma.volt : Color.white.opacity(0.12)).frame(height: 4)
                    }
                }
                .padding(.horizontal, Luma.gutter).padding(.top, 14)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case 0: welcome
                        case 1: about
                        case 2: strap
                        case 3: week
                        default: finish
                        }
                    }
                    .padding(.horizontal, Luma.gutter).padding(.top, 24).padding(.bottom, 30)
                    .offset(y: -LumaLaunch.scrollOffset)
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 12) {
                    if page > 0 { Button("Back") { withAnimation(LumaMotion.snap) { page -= 1 } }.buttonStyle(LumaSecondaryButtonStyle()).frame(width: 110) }
                    Button(page == 4 ? "Open Luma" : "Continue") { next() }.buttonStyle(LumaPrimaryButtonStyle())
                        .disabled(page == 4 && !understood)
                }
                .padding(.horizontal, Luma.gutter).padding(.bottom, 18)
            }
        }
    }

    private func next() {
        if page < 4 { withAnimation(LumaMotion.snap) { page += 1 }; return }
        if !classDays.isEmpty || !runDays.isEmpty, env.routine.isEmpty {
            let c = Calendar.current.dateComponents([.hour, .minute], from: classTime)
            let minutes = (c.hour ?? 6) * 60 + (c.minute ?? 30)
            var slots = classDays.sorted().map { RoutineSlot(weekday: $0, kind: .gymClass, title: "Gym class", startMinutes: minutes) }
            slots += runDays.sorted().map { RoutineSlot(weekday: $0, kind: .easyRun, title: "Run", durationMin: 45) }
            env.setRoutine(slots)
        }
        env.profile.setupVersion = LProfile.currentSetupVersion
        LumaHaptics.success()
        dismiss()
    }

    @ViewBuilder
    private var welcome: some View {
        LumaOrb(progress: 0.86, color: Luma.volt, partner: Luma.mint).frame(height: 240).frame(maxWidth: .infinity)
        Text("Luma").font(LumaFont.title(52)).foregroundStyle(Luma.frost)
        Text("Your strap, read properly. Recovery, sleep and strain each morning; runs and HYROX sessions timed to the second; food and supplements logged from a photo; and a coach that has read all of it.")
            .font(LumaFont.body(17)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var about: some View {
        Text("About you").font(LumaFont.title(30)).foregroundStyle(Luma.frost)
        ProfileFields()
        LumaField(title: "Where you train (optional)", text: $env.profile.gym)
    }

    @ViewBuilder
    private var strap: some View {
        let s = live.strap
        Text("Your strap").font(LumaFont.title(30)).foregroundStyle(Luma.frost)
        LumaCard(tint: s.connected ? Luma.volt.opacity(0.4) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(s.connected ? Luma.volt : Luma.amber).frame(width: 8, height: 8)
                    Text(s.connected ? "\(s.name ?? "Strap") connected" : "No strap connected yet").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                }
                LumaNote(s.connected ? "Wear it day and night. Recovery is scored each morning from the night just gone, and sharpens over the first two weeks as Luma learns your baselines."
                                     : "You can pair a WHOOP 4.0, 5.0 or MG strap now or later from the strap screen. Until one is paired, Luma works as a training and food log.")
                if !s.connected {
                    Button("Open the strap screen") {
                        env.profile.setupVersion = LProfile.currentSetupVersion
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { router.open(.today, .devices) }
                    }
                    .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }

    @ViewBuilder
    private var week: some View {
        Text("Your usual week").font(LumaFont.title(30)).foregroundStyle(Luma.frost)
        LumaNote("Pick the days you normally train. Luma puts them on your calendar and ticks them off as sessions are recorded. You can change this any time.")
        LumaLabel("Gym classes")
        dayPicker($classDays)
        HStack {
            Text("Class usually starts at").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
            Spacer()
            DatePicker("", selection: $classTime, displayedComponents: [.hourAndMinute]).labelsHidden().colorScheme(.dark)
        }
        LumaLabel("Runs")
        dayPicker($runDays)
    }

    private func dayPicker(_ set: Binding<Set<Int>>) -> some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { d in
                let on = set.wrappedValue.contains(d)
                Button {
                    LumaHaptics.select()
                    if on { set.wrappedValue.remove(d) } else { set.wrappedValue.insert(d) }
                } label: {
                    Text(dayNames[d - 1]).font(LumaFont.body(13, .semibold)).foregroundStyle(on ? Luma.ink : Luma.frost)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? Luma.volt : Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var finish: some View {
        Text("Before you start").font(LumaFont.title(30)).foregroundStyle(Luma.frost)
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Stays on your phone", systemImage: "lock.fill").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                LumaNote("Your data is stored on this phone only. The coach is optional and uses your own Anthropic key; you choose whether it can see your health data.")
            }
        }
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Not a medical device", systemImage: "cross.case.fill").font(LumaFont.heading(15)).foregroundStyle(Luma.frost)
                LumaNote("Luma is for training and general wellbeing. It does not diagnose or treat anything. If something feels wrong, see a doctor.")
            }
        }
        Toggle(isOn: $understood) { Text("I understand").font(LumaFont.body(16, .medium)).foregroundStyle(Luma.frost) }.tint(Luma.volt)
            .padding(.horizontal, 4)
        LumaNote("Set up the coach any time from the Coach tab.")
    }
}
