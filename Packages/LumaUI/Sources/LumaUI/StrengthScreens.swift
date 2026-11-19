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
        let records = LiftMath.records(env.lifts, bodyKg: env.profile.weightKg).sorted { $0.value.e1RM > $1.value.e1RM }
        LumaDetailScreen(title: "Training log", tone: .strain) {
            Button { router.sheet = .workoutPhotos(env.today) } label: {
                Label("Add workouts from photos or by hand", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
            }
            .buttonStyle(LumaPrimaryButtonStyle(compact: true))
            Button { router.cover = .lift } label: {
                Label("Log a strength session as you lift", systemImage: "dumbbell.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LumaSecondaryButtonStyle(compact: true))
            if sessions.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "dumbbell", title: "Nothing logged yet",
                              message: "Add sessions from photos of the board or your tracking app, or log a strength session set by set. Luma keeps your best lifts and offers your last loads next time.")
                }
            } else {
                // Load lifted is reps times load, so it describes a strength session and nothing else.
                if sessions.contains(where: { StrengthScreen.liftedLoad($0) != nil }) {
                    volumeCard(sessions.filter { StrengthScreen.liftedLoad($0) != nil })
                }
                if !records.isEmpty {
                    LumaSection(title: "Best lifts")
                    LumaGroup {
                        ForEach(records.prefix(12), id: \.key) { name, rec in
                            LumaRow(symbol: "trophy.fill", symbolColor: Luma.amber, title: name, subtitle: "Set \(LumaText.shortDay(rec.day))") {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(String(format: "%.0f", rec.e1RM)).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                                    Text("kg est. max").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                                }
                            }
                        }
                    }
                }
                LumaSection(title: "Sessions")
                LumaGroup {
                    ForEach(sessions) { s in
                        Button { router.push(.lift(s.id)) } label: {
                            LumaRow(symbol: s.resolvedKind.sport.symbol, symbolColor: s.resolvedKind.sport.tone.color, title: s.title,
                                    subtitle: StrengthScreen.rowLine(s), chevron: true) {
                                if let load = StrengthScreen.liftedLoad(s) {
                                    Text(LFormat.grouped(load)).font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                                    Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                                } else {
                                    Text("\(s.doneSets)").font(LumaFont.numeral(18, .semibold)).foregroundStyle(Luma.frost)
                                    Text("sets").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// The load lifted in a strength session; nil for any other kind, where it would count only the
    /// few sets that happen to be reps at a load.
    static func liftedLoad(_ s: LiftSession) -> Double? {
        s.resolvedKind == .strength && s.volumeKg > 0 ? s.volumeKg : nil
    }

    /// "Nov 16 · 4 movements · from a photo"
    static func rowLine(_ s: LiftSession) -> String {
        var parts: [String] = [LumaText.shortDay(s.day), s.exercises.count == 1 ? "1 movement" : "\(s.exercises.count) movements"]
        if s.source == "photo" { parts.append("from a photo") }
        return parts.joined(separator: " · ")
    }

    private func volumeCard(_ sessions: [LiftSession]) -> some View {
        let recent = Array(sessions.prefix(12).reversed())
        return LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel("Load lifted per session (kg)")
                LumaBarChart(bars: recent.enumerated().map { i, s in
                    LumaBarChart.Bar(id: i, value: s.volumeKg, color: Luma.ember, label: LumaText.shortDay(s.day))
                }, height: 140, format: { LFormat.grouped($0) })
            }
        }
    }
}

/// One logged session in full: what it was, every movement and set, the board it was read from.
struct LiftDetailScreen: View {
    let id: UUID
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    /// Adding or correcting the loads after the session was saved.
    @State private var editing = false
    @State private var adding = false

    var body: some View {
        LumaDetailScreen(title: env.lifts.first(where: { $0.id == id })?.resolvedKind.title ?? "Session", tone: .strain) {
            if let s = env.lifts.first(where: { $0.id == id }) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(LumaFont.title(26)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                        Text(heading(s)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                    }
                    Spacer(minLength: 6)
                    Button(editing ? "Done" : "Edit") { withAnimation(LumaMotion.quick) { editing.toggle(); adding = false } }
                        .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
                if editing {
                    LumaNote("Type the weight you used for an exercise and it is set for all its sets, or give each set its own. Weights are what Luma works your estimated max and strength level from.")
                }
                StatGrid {
                    StatCell(label: "Movements", value: "\(s.exercises.count)")
                    StatCell(label: "Sets", value: "\(s.doneSets)")
                    if let load = StrengthScreen.liftedLoad(s) { StatCell(label: "Load lifted", value: LFormat.grouped(load), unit: "kg") }
                    if let m = s.minutes { StatCell(label: "Length", value: "\(LNum.int(m.rounded()))", unit: "min") }
                }
                ForEach(s.exercises) { e in
                    LumaCard(padding: 16) {
                        if editing {
                            MovementEditRow(exercise: movement(s, e), last: LiftMath.lastLoad(e.name, in: env.lifts.filter { $0.id != s.id })) {
                                var changed = s
                                changed.exercises.removeAll { $0.id == e.id }
                                env.save(changed)
                            }
                        } else {
                            LiftExerciseDetail(exercise: e, bodyKg: env.profile.weightKg)
                        }
                    }
                }
                if editing { addExercise(s) }
                if let written = s.asWritten, !written.isEmpty {
                    LumaSection(title: "As it was written")
                    LumaCard(padding: 16) {
                        Text(written).font(LumaFont.body(14)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                photos(s)
                if !s.note.isEmpty { LumaNote(s.note) }
                Button("Delete this session") {
                    env.delete(s)
                    dismiss()
                }
                .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity)
            }
        }
    }

    /// Type in an exercise the session is missing.
    @ViewBuilder
    private func addExercise(_ s: LiftSession) -> some View {
        if adding {
            LumaCard(padding: 16) {
                ExerciseAddForm(history: env.lifts) { new in
                    var changed = s
                    changed.exercises.append(new)
                    env.save(changed)
                    adding = false
                } onCancel: { adding = false }
            }
        } else {
            Button { adding = true } label: { Label("Add an exercise", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle(compact: true))
        }
    }

    /// A movement of the stored session, reached by its id and written straight back to the log.
    private func movement(_ s: LiftSession, _ e: LiftExercise) -> Binding<LiftExercise> {
        Binding(get: { env.lifts.first { $0.id == s.id }?.exercises.first { $0.id == e.id } ?? e },
                set: { new in
                    guard var session = env.lifts.first(where: { $0.id == s.id }),
                          let i = session.exercises.firstIndex(where: { $0.id == e.id }) else { return }
                    session.exercises[i] = new
                    env.save(session)
                })
    }

    private func heading(_ s: LiftSession) -> String {
        let when = s.source == "live" || s.source == nil ? s.start.formatted(date: .complete, time: .shortened)
                                                          : s.start.formatted(date: .complete, time: .omitted)
        switch s.source {
        case "photo": return when + " · read from a photo"
        case "coach": return when + " · logged by the coach"
        default: return when
        }
    }

    @ViewBuilder
    private func photos(_ s: LiftSession) -> some View {
        let images: [UIImage] = (s.photos ?? []).compactMap { env.photoData($0) }.compactMap { UIImage(data: $0) }
        if !images.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// One movement of a logged session: its sets as they were counted, and the max they point to.
struct LiftExerciseDetail: View {
    let exercise: LiftExercise
    let bodyKg: Double

    var body: some View {
        let done = exercise.sets.filter { $0.done && $0.hasContent }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                Spacer()
                if let best = LiftMath.best(exercise, bodyKg: bodyKg) {
                    Text(String(format: "est. max %.0f kg", best)).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                }
            }
            if let note = exercise.note, !note.isEmpty {
                Text(note).font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            }
            if done.isEmpty {
                Text("No sets listed").font(LumaFont.body(13.5)).foregroundStyle(Luma.smoke)
            }
            ForEach(Array(done.enumerated()), id: \.offset) { i, set in
                HStack {
                    Text("Set \(i + 1)").font(LumaFont.body(13.5)).foregroundStyle(Luma.smoke).frame(width: 52, alignment: .leading)
                    Text(set.text).font(LumaFont.numeral(19, .semibold)).foregroundStyle(Luma.frost)
                    Spacer()
                }
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
    @State private var session = LiftSession(title: "Strength", kind: .strength, source: "live")
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
                        // Each card reaches its exercise by id: a card bound by position stops the app
                        // when its exercise is removed while the card is still on screen.
                        ForEach(session.exercises) { exercise in
                            ExerciseCard(exercise: $session.exercises.element(exercise),
                                         onSetDone: { restUntil = Date().addingTimeInterval(90); LumaHaptics.success() },
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
                .scrollDismissesKeyboard(.immediately)
            }
            .lumaKeyboardRoom()
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
        guard !last.isEmpty else { return nil }
        return "Last time " + LiftExercise(name: name, sets: last).setsText
    }

    private func add(_ name: String) {
        session.exercises.append(LiftExercise.toDo(name: name, previous: LiftMath.lastSets(name, in: env.lifts)))
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
                // A machine counted in metres, with no load to step.
                LiftExercise.toDo(name: "SkiErg", previous: []),
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

/// One exercise in a live session: a row per set, with a stepper for what the set counts and, for
/// a movement done against a load, one for the load. A SkiErg, a rower or a bike is stepped in
/// metres and has no load.
struct ExerciseCard: View {
    @Binding var exercise: LiftExercise
    let onSetDone: () -> Void
    let onRemove: () -> Void

    private var measure: SetMeasure { exercise.measure }
    private var takesLoad: Bool { ExerciseLibrary.match(exercise.name)?.resistance ?? true }

    var body: some View {
        LumaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(exercise.name).font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Spacer()
                    Button(action: onRemove) {
                        Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke)
                            .frame(width: 36, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(exercise.name)")
                }
                // Each row reaches its set by id, for the same reason each card reaches its exercise by id.
                ForEach(exercise.sets) { row in
                    SetStepRow(set: $exercise.sets.element(row), measure: measure, takesLoad: takesLoad, onDone: onSetDone)
                }
                HStack(spacing: 16) {
                    Button {
                        let last = exercise.sets.last
                        var next = LiftSet(reps: 0, kg: takesLoad ? (last?.kg ?? 20) : 0)
                        let amount = last?.amount(measure) ?? 0
                        next.setAmount(amount > 0 ? amount : LiftExercise.startAmount(measure, loaded: takesLoad), measure)
                        exercise.sets.append(next)
                    } label: { Label("Add set", systemImage: "plus").font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.volt) }
                    if exercise.sets.count > 1 {
                        Button {
                            if !exercise.sets.isEmpty { exercise.sets.removeLast() }
                        } label: { Label("Remove last", systemImage: "minus").font(LumaFont.body(13.5, .semibold)).foregroundStyle(Luma.mist) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One set of a live session: a tick, what the set counts, and its load when the movement has one.
private struct SetStepRow: View {
    @Binding var set: LiftSet
    let measure: SetMeasure
    let takesLoad: Bool
    let onDone: () -> Void

    var body: some View {
        let step = LiftExercise.step(measure, loaded: takesLoad)
        HStack(spacing: 8) {
            Button {
                set.done.toggle()
                if set.done { onDone() }
            } label: {
                // The tick is drawn as the set is ticked off.
                LumaTick(on: set.done, size: 28, color: Luma.volt).frame(width: 34, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.done ? "Set done" : "Mark set done")
            LumaValueStepper(value: Binding(get: { set.amount(measure) }, set: { set.setAmount($0, measure) }),
                             step: step, floor: step, unit: unit, text: amountText)
            if takesLoad {
                LumaValueStepper(value: $set.kg, step: 2.5, floor: 0, unit: "kg", text: LumaText.kg(set.kg))
            }
        }
        .opacity(set.done ? 0.75 : 1)
    }

    private var unit: String {
        switch measure {
        case .reps: return "reps"
        case .meters: return "m"
        case .seconds: return "min"
        case .calories: return "cal"
        }
    }

    private var amountText: String {
        let text = AmountText.text(set.amount(measure), measure)
        return text.isEmpty ? "–" : text
    }
}

/// A figure with a minus on one side and a plus on the other.
struct LumaValueStepper: View {
    @Binding var value: Double
    let step: Double
    var floor: Double = 0
    let unit: String
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            LumaStepButton(symbol: "minus", width: 36, height: 44, label: "Less \(unit)") { value = max(floor, value - step) }
            VStack(spacing: -2) {
                Text(text).font(LumaFont.numeral(22)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(LumaFont.label(8.5)).foregroundStyle(Luma.smoke)
            }
            .frame(maxWidth: .infinity)
            LumaStepButton(symbol: "plus", width: 36, height: 44, label: "More \(unit)") { value += step }
        }
        .foregroundStyle(Luma.mist)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.06)))
        .frame(maxWidth: .infinity)
    }
}
