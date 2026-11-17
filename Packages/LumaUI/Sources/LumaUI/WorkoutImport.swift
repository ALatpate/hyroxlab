import SwiftUI
import LumaCore
import LumaKit

// MARK: - Sessions read from photos

/// A session read from photos, waiting for the athlete to check it.
struct WorkoutDraft: Identifiable {
    let id = UUID()
    var session: LiftSession
    /// Positions (1 is the first) of the photos it was read from.
    var photos: [Int]
}

extension SessionKind {
    /// The kinds a logged session can be: everything but a rest day.
    static let logged: [SessionKind] = SessionKind.allCases.filter { $0 != .rest }
}

/// Add sessions to the training log from photos of the board, the class screen or a tracking app.
/// Luma reads them, sorts each into its kind, and shows what it read to be checked before it is saved.
struct WorkoutPhotoSheet: View {
    let day: String
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [PickedPhoto] = []
    @State private var text = ""
    @State private var drafts: [WorkoutDraft] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        LumaSheet(title: drafts.isEmpty ? "Add workouts" : "Check and save", tone: .run) {
            if drafts.isEmpty { pick } else { review }
        }
        .onAppear {
            // The gallery has no coach to read photos, so it opens on a read made up for it.
            if env.isDemo, LumaLaunch.page == 1, drafts.isEmpty { drafts = WorkoutPhotoSheet.demoDrafts() }
            if env.isDemo, LumaLaunch.page == 2, drafts.isEmpty { drafts = [WorkoutPhotoSheet.blank(day: day)] }
            if env.isDemo, LumaLaunch.page == 3 { busy = true }
        }
    }

    // MARK: Pick

    @ViewBuilder
    private var pick: some View {
        LumaLabel("Photos of your workouts (up to \(CoachEngine.maxPhotos))")
        PhotoStrip(photos: $photos, size: 76)
        LumaField(title: photos.isEmpty ? "Or type it: “5x5 back squat at 100, then 4 rounds of…”" : "Add detail (optional): “squats were at 100 kg”",
                  text: $text, axis: .vertical)
        LumaNote("The board, the class screen, a page of your gym's app or your tracking app: several sessions at once is fine. Luma sorts each one by type and lists its movements and sets. It files them under \(LumaText.dayTitle(day, today: env.today).lowercased()) unless a photo shows another day.")
        if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
        Button {
            Task { await read() }
        } label: {
            if busy { HStack(spacing: 10) { ProgressView().tint(Luma.ink); Text("Reading") } } else { Label("Read my workouts", systemImage: "sparkles") }
        }
        .buttonStyle(LumaPrimaryButtonStyle())
        .disabled(busy || (photos.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty))
        // While the photos are read: the shape of what is coming.
        if busy { ReadingRows(caption: photos.count > 1 ? "Reading \(photos.count) photos" : "Reading your workout") }
        if !env.coach.hasKey {
            LumaNote("Reading workouts uses the coach. Connect your key in the Coach tab, or enter the workout by hand below.")
        }
        Button("Enter a workout by hand") { drafts = [WorkoutPhotoSheet.blank(day: day)] }
            .buttonStyle(LumaSecondaryButtonStyle())
    }

    /// An empty session for the athlete to fill in: nothing read, nothing assumed.
    static func blank(day: String, now: Date = Date()) -> WorkoutDraft {
        let noon = LDate.startOfDay(day)?.addingTimeInterval(12 * 3600) ?? now
        let start = LDate.key(now) == day ? now : noon
        return WorkoutDraft(session: LiftSession(start: start, title: "Workout", kind: .strength, source: "hand"), photos: [])
    }

    private func read() async {
        guard env.coach.hasKey else { error = "Connect your key in the Coach tab to read workouts from photos."; return }
        busy = true; error = nil
        do {
            let found = try await env.coach.readWorkouts(text: text, photos: photos.map { $0.data }, day: day)
            let count = photos.count
            drafts = found.map { item in
                var numbers: [Int] = item.photos.filter { $0 <= count }
                // One workout and no word on which photos it came from: it came from all of them.
                if numbers.isEmpty, found.count == 1, count > 0 { numbers = Array(1...count) }
                return WorkoutDraft(session: item.session, photos: numbers)
            }
        } catch let e {
            error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }
        busy = false
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        LumaNote(reviewLine)
        ForEach(drafts) { d in
            WorkoutDraftCard(draft: binding(d), thumbnails: thumbnails(d)) {
                drafts.removeAll { $0.id == d.id }
            }
        }
        Button(drafts.count == 1 ? "Save this workout" : "Save \(drafts.count) workouts") { save() }
            .buttonStyle(LumaPrimaryButtonStyle())
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)
        Button(byHand ? "Back" : "Back to the photos") { drafts = [] }.buttonStyle(LumaSecondaryButtonStyle())
    }

    /// There is something to save: a workout with nothing in it is not one.
    private var canSave: Bool { drafts.contains { WorkoutPhotoSheet.holdsSomething($0.session) } }

    /// Every draft was started by hand, so there was no reading to check.
    private var byHand: Bool { drafts.allSatisfy { $0.session.source == "hand" } }

    /// What was found and what is still wanted. A weight the photo or the note gave is already filled
    /// in; an exercise that is normally loaded and came without one is asked for.
    private var reviewLine: String {
        if byHand { return "Name the workout, pick its type and add its exercises." }
        let missing = drafts.reduce(0) { $0 + $1.session.exercises.filter { $0.needsLoad }.count }
        let found = drafts.count == 1 ? "Luma read one workout." : "Luma read \(drafts.count) workouts."
        switch missing {
        case 0: return found + " Check each exercise and its weight, then save."
        case 1: return found + " One exercise came without a weight: type what you used in its box, or leave it empty."
        default: return found + " \(missing) exercises came without a weight: type what you used in their boxes, or leave them empty."
        }
    }

    static func holdsSomething(_ s: LiftSession) -> Bool { !s.exercises.isEmpty || !(s.asWritten ?? "").isEmpty }

    /// A draft is reached by its id, never by its place in the list, so leaving one out cannot leave a
    /// field writing to a place that is no longer there.
    private func binding(_ d: WorkoutDraft) -> Binding<WorkoutDraft> {
        Binding(get: { drafts.first { $0.id == d.id } ?? d },
                set: { new in if let i = drafts.firstIndex(where: { $0.id == d.id }) { drafts[i] = new } })
    }

    private func thumbnails(_ d: WorkoutDraft) -> [UIImage] {
        d.photos.compactMap { i in photos.indices.contains(i - 1) ? photos[i - 1].thumbnail : nil }
    }

    private func save() {
        // Each photo is stored once, however many sessions were read from it.
        var stored: [Int: String] = [:]
        for d in drafts where WorkoutPhotoSheet.holdsSomething(d.session) {
            var s = d.session
            let names: [String] = d.photos.compactMap { i in
                guard photos.indices.contains(i - 1) else { return nil }
                if let name = stored[i] { return name }
                let name = env.savePhoto(photos[i - 1].data)
                stored[i] = name
                return name
            }
            s.photos = names.isEmpty ? nil : names
            s.exercises = s.exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            env.save(s)
        }
        LumaHaptics.success()
        dismiss()
    }

    static func demoDrafts() -> [WorkoutDraft] {
        let all = LumaDemoContent.lifts()
        var out: [WorkoutDraft] = []
        if var lower = all.first(where: { $0.kind == .strength && $0.title.hasPrefix("Lower") }) {
            lower.source = "photo"
            // A board shows the sets, not the loads: the second lift has none until the athlete adds them.
            if lower.exercises.count > 1 { for i in lower.exercises[1].sets.indices { lower.exercises[1].sets[i].kg = 0 } }
            // A tracking app shows a weight for each set: the first lift climbs to its top set.
            if let first = lower.exercises.first, first.sets.count == 4 {
                let ramp: [Double] = [100, 105, 110, 114]
                for i in first.sets.indices { lower.exercises[0].sets[i].kg = ramp[i] }
            }
            out.append(WorkoutDraft(session: lower, photos: [1]))
        }
        if let race = all.first(where: { $0.kind == .hyrox }) { out.append(WorkoutDraft(session: race, photos: [2])) }
        return out
    }
}

/// One session as read, open to correction: its name, its kind, its day, and the load of each movement.
struct WorkoutDraftCard: View {
    @Binding var draft: WorkoutDraft
    let thumbnails: [UIImage]
    let onRemove: () -> Void
    @EnvironmentObject private var env: LumaEnv
    @State private var showWritten = false
    /// The kind the session was read as, fixed when the card appears so the row does not reshuffle under a tap.
    @State private var sorted: SessionKind = .strength
    @State private var adding = false

    var body: some View {
        LumaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(Array(thumbnails.prefix(3).enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    Spacer(minLength: 4)
                    Button(action: onRemove) {
                        Label("Leave out", systemImage: "xmark").font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.mist)
                    }
                    .buttonStyle(.plain)
                }
                LumaField(title: "Name", text: $draft.session.title)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        // The kind it was sorted into leads the row, so it is in view without scrolling.
                        ForEach([sorted] + SessionKind.logged.filter { $0 != sorted }) { k in
                            LumaChip(title: k.title, symbol: k.sport.symbol, isOn: draft.session.resolvedKind == k) { draft.session.kind = k }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack {
                    Text("Day").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                    Spacer()
                    DatePicker("", selection: $draft.session.start, in: ...Date(), displayedComponents: [.date]).labelsHidden().colorScheme(.dark)
                }
                LumaDivider()
                if draft.session.exercises.isEmpty && !(draft.session.asWritten ?? "").isEmpty {
                    LumaNote("No exercises could be listed. The workout is kept as it was written; add its exercises below.")
                }
                ForEach(draft.session.exercises) { e in
                    MovementEditRow(exercise: movement(e), last: LiftMath.lastLoad(e.name, in: env.lifts)) {
                        draft.session.exercises.removeAll { $0.id == e.id }
                    }
                }
                if adding {
                    ExerciseAddForm(history: env.lifts) { new in
                        draft.session.exercises.append(new)
                        adding = false
                    } onCancel: { adding = false }
                } else {
                    Button { adding = true } label: {
                        Label("Add an exercise", systemImage: "plus").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.volt)
                    }
                    .buttonStyle(.plain)
                }
                if let written = draft.session.asWritten, !written.isEmpty {
                    Button { withAnimation(LumaMotion.quick) { showWritten.toggle() } } label: {
                        Label(showWritten ? "Hide what was written" : "Show what was written", systemImage: showWritten ? "chevron.up" : "chevron.down")
                            .font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.mist)
                    }
                    .buttonStyle(.plain)
                    if showWritten {
                        Text(written).font(LumaFont.body(13)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            sorted = draft.session.resolvedKind
            // A workout started by hand has nothing in it yet: open on the form that fills it.
            if draft.session.exercises.isEmpty && (draft.session.asWritten ?? "").isEmpty { adding = true }
        }
    }
}

extension WorkoutDraftCard {
    /// A movement is reached by its id, for the same reason a draft is.
    fileprivate func movement(_ e: LiftExercise) -> Binding<LiftExercise> {
        Binding(get: { draft.session.exercises.first { $0.id == e.id } ?? e },
                set: { new in
                    if let i = draft.session.exercises.firstIndex(where: { $0.id == e.id }) { draft.session.exercises[i] = new }
                })
    }
}

/// A box for a weight in kg. Outlined when a weight is wanted and none has been typed, so an empty
/// box reads as a question.
struct LoadField: View {
    @Binding var text: String
    var hint: String = "–"
    var wanted: Bool = false
    let label: String

    var body: some View {
        let asking = wanted && text.isEmpty
        HStack(spacing: 4) {
            TextField("", text: $text, prompt: Text(asking ? "kg?" : hint).foregroundStyle(asking ? Luma.volt : Luma.smoke))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(LumaFont.numeral(18, .semibold))
                .foregroundStyle(Luma.frost)
                .frame(width: 58)
                .accessibilityLabel(label)
            Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(asking ? Luma.volt.opacity(0.7) : Color.clear, lineWidth: 1))
    }

    /// The weight a box holds: nil while it is empty or not a number.
    static func value(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let kg = Double(cleaned), kg >= 0, kg <= 1000 else { return nil }
        return kg
    }
}

/// One movement of a session being checked or corrected: what was logged, and the weight used. One
/// box sets every set alike; "a weight for each set" opens a box per set.
struct MovementEditRow: View {
    @Binding var exercise: LiftExercise
    let last: Double?
    let onRemove: () -> Void
    @State private var load = ""
    @State private var eachSet = false

    private var info: ExerciseInfo? { ExerciseLibrary.match(exercise.name) }
    private var takesLoad: Bool { info?.resistance ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if takesLoad && !eachSet {
                    LoadField(text: $load, hint: hint, wanted: exercise.needsLoad, label: "Weight for \(exercise.name), kilograms")
                }
                Button(action: onRemove) {
                    Image(systemName: "minus.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Luma.smoke).frame(width: 28, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(exercise.name)")
            }
            if eachSet {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { i, set in
                    SetLoadRow(number: i + 1, item: one(set))
                }
            }
            if takesLoad { choices }
        }
        .onAppear {
            load = common.map { LumaText.kg($0) } ?? ""
            // Sets read with different weights open with a box each, so none of them is hidden.
            eachSet = Set(exercise.sets.map { $0.kg }).count > 1
        }
        .onChange(of: load) { _, new in apply(new) }
    }

    /// The last weight is offered, never filled in: it becomes this session's only when tapped.
    @ViewBuilder
    private var choices: some View {
        HStack(spacing: 14) {
            if !eachSet, load.isEmpty, let last {
                Button { load = LumaText.kg(last) } label: {
                    Text("Same as last time: \(LumaText.kg(last)) kg").font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.volt)
                }
                .buttonStyle(.plain)
            }
            if exercise.sets.count > 1 {
                Button {
                    eachSet.toggle()
                    if !eachSet { load = common.map { LumaText.kg($0) } ?? "" }
                } label: {
                    Text(eachSet ? "One weight for all sets" : "Each set its own weight").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One set of the movement, reached by its id.
    private func one(_ set: LiftSet) -> Binding<LiftSet> {
        Binding(get: { exercise.sets.first { $0.id == set.id } ?? set },
                set: { new in if let i = exercise.sets.firstIndex(where: { $0.id == set.id }) { exercise.sets[i] = new } })
    }

    /// The weight all the sets share, when they share one.
    private var common: Double? {
        let loads = Set(exercise.sets.map { $0.kg })
        guard loads.count == 1, let kg = loads.first, kg > 0 else { return nil }
        return kg
    }

    private var hint: String { info?.bodyweight ?? false ? "added" : "–" }

    private var detail: String {
        var parts: [String] = [exercise.sets.isEmpty ? "No sets listed" : exercise.setsText]
        if let n = exercise.note, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }

    /// One weight for the movement: typing it sets every set to it, and clearing it leaves them without
    /// one. The movement is written back once, and only when something changed.
    private func apply(_ text: String) {
        guard !eachSet else { return }
        var changed = exercise
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            // Left alone, sets keep whatever weights were read for them, alike or not.
            guard common != nil else { return }
            for i in changed.sets.indices { changed.sets[i].kg = 0 }
        } else {
            guard let kg = LoadField.value(text) else { return }
            for i in changed.sets.indices { changed.sets[i].kg = kg }
        }
        if changed != exercise { exercise = changed }
    }
}

/// One set and the weight used for it.
private struct SetLoadRow: View {
    let number: Int
    @Binding var item: LiftSet
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Set \(number)").font(LumaFont.body(13)).foregroundStyle(Luma.smoke).frame(width: 46, alignment: .leading)
            Text(item.amountText).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
            Spacer(minLength: 6)
            LoadField(text: $text, label: "Weight for set \(number), kilograms")
        }
        .padding(.trailing, 38)
        .onAppear { text = item.kg > 0 ? LumaText.kg(item.kg) : "" }
        .onChange(of: text) { _, new in
            let empty: Bool = new.trimmingCharacters(in: .whitespaces).isEmpty
            let kg: Double? = empty ? 0 : LoadField.value(new)
            if let kg, kg != item.kg { item.kg = kg }
        }
    }
}

/// An exercise typed in by hand: its name, how many sets, what each set counted, and the weight.
struct ExerciseAddForm: View {
    let history: [LiftSession]
    let onAdd: (LiftExercise) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var sets = "3"
    @State private var amount = "10"
    @State private var measure: SetMeasure = .reps
    @State private var load = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LumaField(title: "Exercise, e.g. Back squat", text: $name)
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            LumaChip(title: s, isOn: false) { name = s }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 8) {
                count("Sets", $sets)
                Text("×").font(LumaFont.body(15)).foregroundStyle(Luma.smoke)
                count(measure.title, $amount)
                Spacer(minLength: 4)
                LoadField(text: $load, label: "Weight, kilograms")
            }
            LumaSegmented(selection: $measure, options: SetMeasure.allCases.map { (value: $0, title: $0.title) }, tint: Luma.frost)
            HStack(spacing: 10) {
                Button("Add") { if let exercise = made { onAdd(exercise) } }
                    .buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    .disabled(made == nil)
                Button("Cancel", action: onCancel).buttonStyle(LumaSecondaryButtonStyle(compact: true))
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
    }

    private func count(_ title: String, _ text: Binding<String>) -> some View {
        VStack(spacing: 2) {
            TextField("", text: text, prompt: Text("0").foregroundStyle(Luma.smoke))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(LumaFont.numeral(18, .semibold))
                .foregroundStyle(Luma.frost)
                .frame(width: 54)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                .accessibilityLabel(title)
            Text(title).font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
        }
    }

    /// The exercise as typed so far, or nil while something is missing.
    private var made: LiftExercise? {
        guard let n = Int(sets.trimmingCharacters(in: .whitespaces)),
              let each = Double(amount.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) else { return nil }
        return LiftExercise.typed(name: name, sets: n, amount: each, measure: measure, kg: LoadField.value(load) ?? 0)
    }

    /// Names that fit what has been typed: the athlete's own first, then Luma's list.
    private var suggestions: [String] {
        let typed = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard typed.count >= 2 else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        let own = history.sorted { $0.start > $1.start }.flatMap { $0.exercises.map { $0.name } }
        for candidate in own + LiftMath.catalog + ExerciseLibrary.names {
            let lower = candidate.lowercased()
            guard lower.contains(typed), lower != typed, seen.insert(lower).inserted else { continue }
            out.append(candidate)
            if out.count == 6 { break }
        }
        return out
    }
}

// MARK: - On the calendar

/// A logged session on its day: what it was and the movements in it.
struct LoggedSessionCard: View {
    let session: LiftSession
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let kind = session.resolvedKind
        let shown = session.exercises.prefix(5)
        Button { router.push(.lift(session.id)) } label: {
            LumaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: kind.sport.symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(kind.sport.tone.color)
                            .frame(width: 40, height: 40).background(Circle().fill(kind.sport.tone.color.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                            Text(LoggedSessionCard.line(session)).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke).padding(.top, 4)
                    }
                    ForEach(shown) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(e.name).font(LumaFont.body(13.5)).foregroundStyle(Luma.frost)
                            Spacer(minLength: 6)
                            Text(e.sets.isEmpty ? (e.note ?? "") : e.setsText).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    if session.exercises.count > shown.count {
                        Text("and \(session.exercises.count - shown.count) more").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "HYROX session · 7 movements · from a photo"
    static func line(_ s: LiftSession) -> String {
        var parts: [String] = [s.resolvedKind.title]
        parts.append(s.exercises.count == 1 ? "1 movement" : "\(s.exercises.count) movements")
        switch s.source {
        case "photo": parts.append("from a photo")
        case "coach": parts.append("logged by the coach")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}
