import SwiftUI
import HYROXCore

/// Start something now. One grid, every session type two taps away.
struct HXGoView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var model: AppModel
    let startRun: (HXSessionKind, PlannedSession?) -> Void
    let startRace: (HXSessionKind, PlannedSession?) -> Void
    @State private var stationPick: Station = .sledPush
    @State private var compromisedPick: Station = .wallBalls
    @State private var showStationPicker = false
    @State private var showCompromisedPicker = false

    private let columns = [GridItem(.flexible(), spacing: HX.gap), GridItem(.flexible(), spacing: HX.gap)]

    var body: some View {
        HXScreen(title: "Go", subtitle: "Strap on. Pick one.") {
            if model.activeWorkout != nil {
                HXCard(tint: HX.warn) {
                    Text("A NOOP workout is already running. Finish it in Live before starting a HYROX Lab session.")
                        .font(HX.body).foregroundStyle(HX.text)
                }
            }
            HXOverline("Run")
            LazyVGrid(columns: columns, spacing: HX.gap) {
                tile("Outdoor run", "figure.run", HX.run, "GPS · map · splits") { startRun(.runOutdoor, nil) }
                tile("Intervals", "repeat", HX.run, "Voice-cued repeats") { startRun(.runIntervals, nil) }
                tile("Treadmill", "figure.run.treadmill", HX.run, "HR + time, distance after") { startRun(.runTreadmill, nil) }
            }
            HXOverline("HYROX")
            LazyVGrid(columns: columns, spacing: HX.gap) {
                tile("Full simulation", "flag.checkered", HX.volt, "8 runs · 8 stations · race mode") { startRace(.fullSimulation, nil) }
                tile("Half · stations 1–4", "flag", HX.volt, "Ski, push, pull, BBJ") { startRace(.halfSimulation(secondHalf: false), nil) }
                tile("Half · stations 5–8", "flag", HX.volt, "Row, carry, lunge, wall balls") { startRace(.halfSimulation(secondHalf: true), nil) }
                tile("Compromised running", "arrow.triangle.2.circlepath", HX.station, "Station → 1 km × 4") { showCompromisedPicker = true }
                tile("Station practice", "dumbbell.fill", HX.station, "Timed sets, one station") { showStationPicker = true }
            }
            HXOverline("Other")
            LazyVGrid(columns: columns, spacing: HX.gap) {
                NavigationLink { LiftLogView() } label: { tileLabel("Lift Log", "list.bullet.rectangle", HX.textDim, "NOOP strength log") }.buttonStyle(.plain)
                NavigationLink { LiveView() } label: { tileLabel("NOOP Live", "waveform.path.ecg", HX.textDim, "Any other workout") }.buttonStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("Which station?", isPresented: $showStationPicker, titleVisibility: .visible) {
            ForEach(Station.allCases) { st in Button(st.title) { startRace(.stationPractice(st), nil) } }
        }
        .confirmationDialog("Compromised running after which station?", isPresented: $showCompromisedPicker, titleVisibility: .visible) {
            ForEach(Station.allCases) { st in Button(st.title) { startRace(.compromisedRunning(st), nil) } }
        }
    }

    private func tile(_ title: String, _ symbol: String, _ color: Color, _ sub: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(title, symbol, color, sub) }.buttonStyle(.plain)
    }

    private func tileLabel(_ title: String, _ symbol: String, _ color: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Spacer(minLength: 0)
            Text(title).font(HX.headline).foregroundStyle(HX.text).multilineTextAlignment(.leading)
            Text(sub).font(HX.caption).foregroundStyle(HX.textDim).lineLimit(2)
        }
        .padding(HX.pad)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HX.radius, style: .continuous).fill(HX.surface))
        .overlay(RoundedRectangle(cornerRadius: HX.radius, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Onboarding

struct HXOnboardingView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var draft = HXProfile()
    @State private var fiveKMin = 25
    @State private var fiveKSec = 0
    @State private var hasRace = false
    @State private var raceDate = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
    @State private var lthrText = ""

    private let weekdayNames = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: 4).tint(HX.volt).padding()
                TabView(selection: $step) {
                    page0.tag(0); page1.tag(1); page2.tag(2); page3.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                Button(step == 3 ? "Start" : "Continue") {
                    if step < 3 { withAnimation { step += 1 } } else { finish() }
                }
                .buttonStyle(HXPrimaryButtonStyle())
                .padding()
            }
            .background(HX.ink.ignoresSafeArea())
            .onAppear { draft = store.profile; fiveKMin = Int(draft.fiveKSeconds) / 60; fiveKSec = Int(draft.fiveKSeconds) % 60; hasRace = draft.raceDate != nil; raceDate = draft.raceDate ?? raceDate; lthrText = draft.lthr.map(String.init) ?? "" }
        }
        .preferredColorScheme(.dark)
    }

    private var page0: some View {
        onboardPage("Which format are you training for?", "You can change this any time; Race Readiness scores every format regardless.") {
            ForEach(RaceFormat.allCases) { f in
                Button { draft.format = f } label: {
                    HStack {
                        Text(f.title).font(HX.body).foregroundStyle(HX.text)
                        Spacer()
                        if draft.format == f { Image(systemName: "checkmark.circle.fill").foregroundStyle(HX.volt) }
                    }
                    .padding().background(RoundedRectangle(cornerRadius: 16).fill(HX.surface))
                }.buttonStyle(.plain)
            }
        }
    }

    private var page1: some View {
        onboardPage("Your 5 km time", "A best guess is fine; every run refines it.") {
            HStack {
                Picker("min", selection: $fiveKMin) { ForEach(15...45, id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.wheel).frame(maxWidth: .infinity)
                Picker("sec", selection: $fiveKSec) { ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d s", $0)).tag($0) } }.pickerStyle(.wheel).frame(maxWidth: .infinity)
            }
            .frame(height: 150)
            HXCard {
                VStack(alignment: .leading, spacing: 6) {
                    HXOverline("Lactate threshold HR (optional)")
                    TextField("e.g. 172", text: $lthrText).keyboardType(.numberPad).font(HX.body).foregroundStyle(HX.text)
                    Text("Leave blank to use zones from your max HR (\(profile.hrMax) bpm in NOOP).").font(HX.caption).foregroundStyle(HX.textDim)
                }
            }
        }
    }

    private var page2: some View {
        onboardPage("Gym class days", "Classes are your strength and station work. Runs and simulations go around them.") {
            HStack(spacing: 8) {
                ForEach(weekdayNames, id: \.0) { wd, name in
                    Button {
                        if draft.classWeekdays.contains(wd) { draft.classWeekdays.remove(wd) } else { draft.classWeekdays.insert(wd) }
                    } label: {
                        Text(name).font(HX.caption.weight(.semibold))
                            .foregroundStyle(draft.classWeekdays.contains(wd) ? HX.ink : HX.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(draft.classWeekdays.contains(wd) ? HX.volt : HX.surface))
                    }.buttonStyle(.plain)
                }
            }
            Stepper("Runs per week: \(draft.runsPerWeek)", value: $draft.runsPerWeek, in: 1...5).foregroundStyle(HX.text)
            HXOverline("Weakest station (optional)")
            Picker("Weakest", selection: Binding(get: { draft.weakestStations.first ?? .sledPush }, set: { draft.weakestStations = [$0] })) {
                ForEach(Station.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(HX.volt)
        }
    }

    private var page3: some View {
        onboardPage("A race on the calendar?", "With a date, the plan builds base → build → peak → taper. Without one, it maintains.") {
            Toggle("I have a race booked", isOn: $hasRace).tint(HX.volt).foregroundStyle(HX.text)
            if hasRace {
                TextField("Race name (e.g. HYROX Dublin)", text: $draft.raceName).font(HX.body).foregroundStyle(HX.text).padding().background(RoundedRectangle(cornerRadius: 14).fill(HX.surface))
                DatePicker("Date", selection: $raceDate, displayedComponents: .date).tint(HX.volt).foregroundStyle(HX.text)
            }
            Toggle("Voice cues on runs", isOn: $draft.voiceCues).tint(HX.volt).foregroundStyle(HX.text)
            Toggle("Auto-pause when stopped", isOn: $draft.autoPause).tint(HX.volt).foregroundStyle(HX.text)
        }
    }

    private func onboardPage<C: View>(_ title: String, _ sub: String, @ViewBuilder content: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(HX.text)
                Text(sub).font(HX.body).foregroundStyle(HX.textDim)
                content()
            }
            .padding(.horizontal, HX.screenPad)
        }
    }

    private func finish() {
        draft.fiveKSeconds = Double(fiveKMin * 60 + fiveKSec)
        draft.lthr = Int(lthrText)
        draft.raceDate = hasRace ? raceDate : nil
        draft.onboarded = true
        store.profile = draft
        store.regeneratePlan()
        dismiss()
    }
}
