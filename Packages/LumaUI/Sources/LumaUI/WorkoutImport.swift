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
        if !env.coach.hasKey {
            LumaNote("Reading workouts uses the coach. Connect your key in the Coach tab, or log a strength session set by set from the Training log.")
        }
    }

    private func read() async {
        guard env.coach.hasKey else { error = "Connect your key in the Coach tab to read workouts from photos."; return }
        busy = true; error = nil
        do {
            let found = try await env.coach.readWorkouts(text: text, photos: photos.map { $0.data }, day: day)
            drafts = found.map { WorkoutDraft(session: $0.session, photos: $0.photos.filter { $0 <= photos.count }) }
        } catch let e {
            error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }
        busy = false
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        LumaNote(drafts.count == 1 ? "Luma read one session. Check it, add the loads you used, and save."
                                   : "Luma read \(drafts.count) sessions. Check each one, add the loads you used, and save.")
        ForEach(drafts) { d in
            WorkoutDraftCard(draft: binding(d), thumbnails: thumbnails(d)) {
                drafts.removeAll { $0.id == d.id }
            }
        }
        Button(drafts.count == 1 ? "Save this workout" : "Save \(drafts.count) workouts") { save() }
            .buttonStyle(LumaPrimaryButtonStyle())
        Button("Back to the photos") { drafts = [] }.buttonStyle(LumaSecondaryButtonStyle())
    }

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
        for d in drafts {
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
                if draft.session.exercises.isEmpty {
                    LumaNote("No movements could be listed. The session is kept as it was written.")
                }
                ForEach(draft.session.exercises) { e in
                    MovementEditRow(exercise: movement(e), last: LiftMath.lastLoad(e.name, in: env.lifts)) {
                        draft.session.exercises.removeAll { $0.id == e.id }
                    }
                }
                if let written = draft.session.asWritten, !written.isEmpty {
                    Button { withAnimation(.easeOut(duration: 0.2)) { showWritten.toggle() } } label: {
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
        .onAppear { sorted = draft.session.resolvedKind }
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

/// One movement of a session being checked or corrected: what was logged, and a field for the load used.
struct MovementEditRow: View {
    @Binding var exercise: LiftExercise
    let last: Double?
    let onRemove: () -> Void
    @State private var load = ""

    private var info: ExerciseInfo? { ExerciseLibrary.match(exercise.name) }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                // The last load is offered, never filled in: it becomes this session's only when tapped.
                if load.isEmpty, let last, info?.resistance ?? true {
                    Button { load = LumaText.kg(last) } label: {
                        Text("Same as last time: \(LumaText.kg(last)) kg").font(LumaFont.body(12.5, .semibold)).foregroundStyle(Luma.volt)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 6)
            if info?.resistance ?? true {
                HStack(spacing: 4) {
                    TextField("", text: $load, prompt: Text(hint).foregroundStyle(Luma.smoke))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(LumaFont.numeral(18, .semibold))
                        .foregroundStyle(Luma.frost)
                        .frame(width: 62)
                        .accessibilityLabel("Load for \(exercise.name), kilograms")
                    Text("kg").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            Button(action: onRemove) {
                Image(systemName: "minus.circle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Luma.smoke).frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(exercise.name)")
        }
        .onAppear { load = common.map { LumaText.kg($0) } ?? "" }
        .onChange(of: load) { _, new in apply(new) }
    }

    /// The load all the sets share, when they share one.
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

    /// One load for the movement: typing it sets every set to it, and clearing it leaves them unloaded.
    /// The movement is written back once, and only when something changed.
    private func apply(_ text: String) {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        var changed = exercise
        if cleaned.isEmpty {
            // Left alone, sets keep whatever loads were read for them, alike or not.
            guard common != nil else { return }
            for i in changed.sets.indices { changed.sets[i].kg = 0 }
        } else {
            guard let kg = Double(cleaned), kg >= 0, kg <= 1000 else { return }
            for i in changed.sets.indices { changed.sets[i].kg = kg }
        }
        if changed != exercise { exercise = changed }
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
