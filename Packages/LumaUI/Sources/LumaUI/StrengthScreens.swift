import SwiftUI
import Combine
import LumaCore
import LumaKit

// MARK: - Strength log

struct StrengthScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let sessions = env.lifts.sorted { $0.start > $1.start }
        let records = LiftMath.records(env.lifts).sorted { $0.value.e1RM > $1.value.e1RM }
        LumaDetailScreen(title: "Strength", tone: .strain) {
            Button { router.cover = .lift } label: { Label("Start a strength session", systemImage: "dumbbell.fill").frame(maxWidth: .infinity) }
                .buttonStyle(LumaPrimaryButtonStyle())
            if sessions.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "dumbbell", title: "No strength sessions yet",
                              message: "Log sets and loads as you lift. Luma keeps your best lifts and prefills your last numbers next time.")
                }
            } else {
                volumeCard(sessions)
                LumaSection(title: "Best lifts")
                LumaGroup {
                    ForEach(records.prefix(12), id: \.key) { name, rec in
                        LumaRow(symbol: "trophy.fill", symbolColor: Luma.amber, title: name, subtitle: "Set \(LumaText.shortDay(rec.day))") {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.0f", rec.e1RM)).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                                Text("kg est. 1RM").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                            }
                        }
                    }
                }
                LumaSection(title: "Sessions")
                LumaGroup {
                    ForEach(sessions) { s in
                        Button { router.push(.lift(s.id)) } label: {
                            LumaRow(symbol: "dumbbell.fill", symbolColor: Luma.ember, title: s.title,
                                    subtitle: "\(LumaText.shortDay(s.day)) · \(s.exercises.count) exercises · \(s.doneSets) sets", chevron: true) {
                                Text(LFormat.grouped(s.volumeKg)).font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                                Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func volumeCard(_ sessions: [LiftSession]) -> some View {
        let recent = Array(sessions.prefix(12).reversed())
        return LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("Volume per session (kg lifted)")
                LumaBarChart(bars: recent.enumerated().map { i, s in
                    LumaBarChart.Bar(id: i, value: s.volumeKg, color: Luma.ember, label: LumaText.shortDay(s.day))
                }, height: 140, format: { LFormat.grouped($0) })
            }
        }
    }
}

struct LiftDetailScreen: View {
    let id: UUID
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LumaDetailScreen(title: "Strength session", tone: .strain) {
            if let s = env.lifts.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.title).font(LumaFont.title(26)).foregroundStyle(Luma.frost)
                    Text(s.start.formatted(date: .complete, time: .shortened)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                }
                StatGrid {
                    StatCell(label: "Volume", value: LFormat.grouped(s.volumeKg), unit: "kg")
                    StatCell(label: "Sets", value: "\(s.doneSets)")
                }
                ForEach(s.exercises) { e in
                    LumaCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(e.name).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                                Spacer()
                                if let best = e.bestE1RM { Text(String(format: "est. 1RM %.0f kg", best)).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist) }
                            }
                            ForEach(Array(e.sets.filter { $0.done }.enumerated()), id: \.offset) { i, set in
                                HStack {
                                    Text("Set \(i + 1)").font(LumaFont.body(13.5)).foregroundStyle(Luma.smoke).frame(width: 52, alignment: .leading)
                                    Text("\(set.reps)").font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                                    Text("×").foregroundStyle(Luma.smoke)
                                    Text(set.kg == set.kg.rounded() ? String(format: "%.0f", set.kg) : String(format: "%.1f", set.kg)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                                    Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                if !s.note.isEmpty { LumaNote(s.note) }
                Button("Delete this session") {
                    env.delete(s)
                    dismiss()
                }
                .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Live strength session

/// Logging a strength session as it happens: tick sets off, adjust reps and load, rest timer between.
struct LiftLiveScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var live: LumaLive
    @Environment(\.dismiss) private var dismiss
    @State private var session = LiftSession(title: "Strength")
    @State private var started = Date()
    @State private var now = Date()
    @State private var restUntil: Date?
    @State private var picking = false
    @State private var search = ""
    @State private var confirmStop = false
    @State private var recording = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .strain, strength: 1.1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if session.exercises.isEmpty {
                            LumaCard {
                                LumaEmpty(symbol: "dumbbell", title: "Add your first exercise",
                                          message: "Your last sets for each exercise are filled in for you.", action: "Add exercise") { picking = true }
                            }
                        }
                        ForEach($session.exercises) { $exercise in
                            ExerciseCard(exercise: $exercise, onSetDone: { restUntil = Date().addingTimeInterval(90); LumaHaptics.success() },
                                         onRemove: { session.exercises.removeAll { $0.id == exercise.id } })
                        }
                        if !session.exercises.isEmpty {
                            Button { picking = true } label: { Label("Add exercise", systemImage: "plus").frame(maxWidth: .infinity) }
                                .buttonStyle(LumaSecondaryButtonStyle())
                        }
                    }
                    .padding(.horizontal, Luma.gutter).padding(.top, 8).padding(.bottom, 120)
                    .offset(y: -LumaLaunch.scrollOffset)
                }
                .scrollIndicators(.hidden)
            }
            VStack {
                Spacer()
                Button("Finish session") { finish() }.buttonStyle(LumaPrimaryButtonStyle()).padding(.horizontal, Luma.gutter).padding(.bottom, 18)
                    .disabled(session.doneSets == 0)
            }
        }
        .onReceive(ticker) { now = $0 }
        .onAppear { begin() }
        .sheet(isPresented: $picking) { picker.preferredColorScheme(.dark) }
        .confirmationDialog("Leave this session?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                if recording { env.recorder?.discard() }
                dismiss()
            }
            Button("Keep lifting", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Session name", text: $session.title).font(LumaFont.title(24)).foregroundStyle(Luma.frost)
                Text("\(LumaText.duration(now.timeIntervalSince(started))) · \(session.doneSets) sets · \(LFormat.grouped(session.volumeKg)) kg")
                    .font(LumaFont.body(13)).foregroundStyle(Luma.mist)
            }
            Spacer()
            if let until = restUntil, until > now {
                VStack(spacing: 0) {
                    Text(LumaText.duration(until.timeIntervalSince(now))).font(LumaFont.numeral(26)).foregroundStyle(Luma.volt)
                    LumaLabel("Rest")
                }
                .onTapGesture { restUntil = nil }
            } else if let hr = live.strap.liveHeartRate() {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.coral)
                    Text("\(hr)").font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
                }
            }
            LumaIconButton(symbol: "xmark") { confirmStop = true }
        }
        .padding(.horizontal, Luma.gutter).padding(.top, 14).padding(.bottom, 8)
    }

    private var picker: some View {
        let recent = Array(Set(env.lifts.flatMap { $0.exercises.map { $0.name } })).sorted()
        let all = (recent + LiftMath.catalog.filter { !recent.contains($0) })
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
        return LumaSheet(title: "Add exercise", tone: .strain) {
            LumaField(title: "Search or type a new name", text: $search)
            if !search.isEmpty, !all.contains(where: { $0.caseInsensitiveCompare(search) == .orderedSame }) {
                Button { add(search) } label: { Label("Add “\(search)”", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(LumaSecondaryButtonStyle())
            }
            LumaGroup {
                ForEach(all, id: \.self) { name in
                    Button { add(name) } label: {
                        LumaRow(symbol: nil, title: name, subtitle: lastLine(name)) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Luma.volt)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func lastLine(_ name: String) -> String? {
        let last = LiftMath.lastSets(name, in: env.lifts)
        guard let top = last.max(by: { $0.kg < $1.kg }) else { return nil }
        return "Last time \(last.count) × \(top.reps) at \(Int(top.kg)) kg"
    }

    private func add(_ name: String) {
        let previous = LiftMath.lastSets(name, in: env.lifts)
        let sets = previous.isEmpty ? [LiftSet(reps: 8, kg: 20), LiftSet(reps: 8, kg: 20), LiftSet(reps: 8, kg: 20)]
                                    : previous.map { LiftSet(reps: $0.reps, kg: $0.kg) }
        session.exercises.append(LiftExercise(name: name.trimmingCharacters(in: .whitespaces), sets: sets))
        search = ""
        picking = false
    }

    private func begin() {
        started = Date()
        session.start = started
        if env.isDemo {
            session.title = "Lower body strength"
            session.exercises = [
                LiftExercise(name: "Back squat", sets: [LiftSet(reps: 5, kg: 105, done: true), LiftSet(reps: 5, kg: 105, done: true), LiftSet(reps: 5, kg: 105), LiftSet(reps: 5, kg: 105)]),
                LiftExercise(name: "Romanian deadlift", sets: [LiftSet(reps: 8, kg: 95), LiftSet(reps: 8, kg: 95), LiftSet(reps: 8, kg: 95)]),
            ]
            started = Date().addingTimeInterval(-742)
            restUntil = Date().addingTimeInterval(63)
            return
        }
        recording = env.recorder?.start(sport: "Strength", gps: false) ?? false
        env.device?.setLiveHeartRate(true)
    }

    private func finish() {
        session.end = Date()
        for i in session.exercises.indices { session.exercises[i].sets.removeAll { !$0.done } }
        session.exercises.removeAll { $0.sets.isEmpty }
        env.save(session)
        env.device?.setLiveHeartRate(false)
        let seconds = Date().timeIntervalSince(started)
        Task {
            if recording {
                _ = await env.recorder?.finish()
            } else if !env.isDemo {
                let end = Date().timeIntervalSince1970
                env.saveWorkout(LWorkout(start: end - seconds, end: end, sport: "Strength", source: "manual", notes: session.title))
            }
            env.reload()
        }
        LumaHaptics.success()
        dismiss()
    }
}

/// One exercise in a live session: a row per set with steppers for reps and load.
struct ExerciseCard: View {
    @Binding var exercise: LiftExercise
    let onSetDone: () -> Void
    let onRemove: () -> Void

    var body: some View {
        LumaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(exercise.name).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Spacer()
                    Button(action: onRemove) { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke) }.buttonStyle(.plain)
                }
                ForEach($exercise.sets) { $set in
                    HStack(spacing: 8) {
                        Button {
                            set.done.toggle()
                            if set.done { onSetDone() }
                        } label: {
                            Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.system(size: 26, weight: .medium))
                                .foregroundStyle(set.done ? Luma.volt : Luma.smoke)
                        }
                        .buttonStyle(.plain)
                        stepper(value: Binding(get: { Double(set.reps) }, set: { set.reps = max(1, Int($0)) }), step: 1, unit: "reps", decimals: 0)
                        stepper(value: $set.kg, step: 2.5, unit: "kg", decimals: 1)
                    }
                    .opacity(set.done ? 0.75 : 1)
                }
                HStack(spacing: 16) {
                    Button {
                        let last = exercise.sets.last
                        exercise.sets.append(LiftSet(reps: last?.reps ?? 8, kg: last?.kg ?? 20))
                    } label: { Label("Add set", systemImage: "plus").font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.volt) }
                    if exercise.sets.count > 1 {
                        Button { exercise.sets.removeLast() } label: { Label("Remove last", systemImage: "minus").font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.mist) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepper(value: Binding<Double>, step: Double, unit: String, decimals: Int) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue = max(0, value.wrappedValue - step) } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 40)
            }
            VStack(spacing: -2) {
                Text(value.wrappedValue == value.wrappedValue.rounded() ? String(format: "%.0f", value.wrappedValue) : String(format: "%.\(decimals)f", value.wrappedValue))
                    .font(LumaFont.numeral(22)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                Text(unit).font(LumaFont.label(8.5)).foregroundStyle(Luma.smoke)
            }
            .frame(maxWidth: .infinity)
            Button { value.wrappedValue += step } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).frame(width: 34, height: 40)
            }
        }
        .foregroundStyle(Luma.mist)
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
        .frame(maxWidth: .infinity)
    }
}
