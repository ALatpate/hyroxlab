import SwiftUI
import LumaCore
import LumaKit

// MARK: - Train tab

/// The calendar: what was planned, what was actually done, and the week around it.
struct TrainScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var weekStart: String = ""
    @State private var selected: String = ""

    private var week: String { weekStart.isEmpty ? LDate.weekStart(env.today) : weekStart }
    private var day: String { selected.isEmpty ? env.today : selected }

    var body: some View {
        let keys = (0..<7).map { LDate.adding($0, to: week) }
        let days = env.scheduleDays(keys)
        let current = days.first { $0.day == day } ?? env.scheduleDays([day])[0]
        LumaTabScreen(title: "Train", subtitle: weekTitle(keys), tone: .run) {
            HStack(spacing: 8) {
                LumaIconButton(symbol: "repeat") { router.sheet = .routine }
                LumaIconButton(symbol: "plus") { router.sheet = .plan(nil, day) }
            }
        } content: {
            SuggestedSessions()
            WeekStrip(days: days, selected: day, today: env.today, onSelect: { selected = $0 },
                      onShift: { delta in
                          let next = LDate.adding(delta * 7, to: week)
                          weekStart = next
                          selected = delta == 0 ? env.today : (next == LDate.weekStart(env.today) ? env.today : next)
                      })
            DayAgenda(day: current)
            WeekSummary(days: days)
            if env.routine.isEmpty && env.planned.filter({ $0.status != .removed }).isEmpty {
                LumaCard(tint: Luma.volt.opacity(0.5)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set up your week").font(LumaFont.title(22)).foregroundStyle(Luma.frost)
                        LumaNote("Tell Luma which classes and sessions repeat every week. They appear on the calendar automatically, and everything you record is matched against them.")
                        Button("Add my weekly routine") { router.sheet = .routine }.buttonStyle(LumaPrimaryButtonStyle())
                    }
                }
            }
            HStack(spacing: 8) {
                LumaQuickAction(symbol: "sparkles", title: "Plan my week", tint: Luma.volt) {
                    router.askCoach("Plan my training for the next 7 days. Read my calendar, routine, recovery and load first, work around my standing classes, and put the sessions on my calendar.")
                }
                LumaQuickAction(symbol: "text.magnifyingglass", title: "Review my week", tint: Luma.volt) {
                    router.askCoach("Review my last 7 days: what I planned against what I did, load, recovery and sleep. What went well and what should change next week?")
                }
            }
            LumaSection(title: "More")
            LumaGroup {
                link("clock.arrow.circlepath", "All sessions", "\(env.workouts.count) recorded", .history)
                link("flag.checkered", "HYROX readiness", "Benchmarks, simulations and race prediction", .raceReadiness)
                link("dumbbell.fill", "Strength log", "\(env.lifts.count) sessions, personal records", .strength)
                link("chart.line.uptrend.xyaxis", "Training load", env.analysis.load.status.title, .load)
            }
        }
    }

    private func link(_ symbol: String, _ title: String, _ subtitle: String, _ dest: LumaDest) -> some View {
        Button { router.push(dest) } label: { LumaRow(symbol: symbol, symbolColor: Luma.volt, title: title, subtitle: subtitle, chevron: true) }
            .buttonStyle(.plain)
    }

    private func weekTitle(_ keys: [String]) -> String {
        guard let first = keys.first, let last = keys.last else { return "" }
        if first == LDate.weekStart(env.today) { return "This week" }
        return "\(LumaText.shortDay(first)) – \(LumaText.shortDay(last))"
    }
}

/// Sessions the strap saw and nobody recorded, one at a time, newest first. Each can be kept, as the
/// sport the athlete picks, or dismissed for good. Shows nothing when there are none.
struct SuggestedSessions: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if let stretch = env.suggestions.first {
            SuggestedSessionCard(stretch: stretch, more: env.suggestions.count - 1).id(stretch.id)
        }
    }
}

private struct SuggestedSessionCard: View {
    let stretch: LSuggestedSession
    /// How many more are waiting behind this one.
    let more: Int
    @EnvironmentObject private var env: LumaEnv
    @State private var picked: String?

    private static let sports = ["Conditioning", "Strength", "HYROX", "Running", "Cycling", "Rowing", "Walking", "Mobility"]

    var body: some View {
        let plan = env.likelyPlan(for: stretch)
        let sport = picked ?? plan.map { SessionSuggestions.sport(for: $0.kind) } ?? "Conditioning"
        LumaCard(tint: Luma.volt.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    LumaLabel(more > 0 ? "Looks like a session · \(more) more after this" : "Looks like a session", color: Luma.volt)
                    Text("\(LumaText.dayTitle(stretch.day, today: env.today)), \(LumaText.time(stretch.start)) – \(LumaText.time(stretch.end))")
                        .font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                    Text(LumaText.line(["\(Int((stretch.durationS / 60).rounded())) min", "average \(Int(stretch.avgHR.rounded())) bpm",
                                        "peak \(Int(stretch.peakHR.rounded())) bpm"]))
                        .font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                }
                LumaNote(plan.map { "Your strap recorded this and nothing is logged for it. It fits \($0.title) on your calendar." }
                         ?? "Your strap recorded this and nothing is logged for it. Keep it and it joins your sessions with its heart rate and strain.")
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Self.sports, id: \.self) { name in
                            LumaChip(title: name, symbol: LSportKind.classify(name).symbol, isOn: sport == name) { picked = name }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                HStack(spacing: 10) {
                    Button("Keep as \(sport)") {
                        LumaHaptics.success()
                        withAnimation(.easeOut(duration: 0.2)) { env.keep(stretch, sport: sport) }
                    }
                    .buttonStyle(LumaPrimaryButtonStyle(compact: true))
                    Button("Not a session") { withAnimation(.easeOut(duration: 0.2)) { env.dismiss(stretch) } }
                        .buttonStyle(LumaSecondaryButtonStyle(compact: true))
                }
            }
        }
    }
}

/// Seven days across: the date, and a mark for each session planned (ring) or done (filled).
struct WeekStrip: View {
    let days: [ScheduleDay]
    let selected: String
    let today: String
    let onSelect: (String) -> Void
    /// −1 / +1 to move a week, 0 to return to this week.
    let onShift: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(days) { d in
                    let isSel = d.day == selected
                    Button {
                        LumaHaptics.select()
                        onSelect(d.day)
                    } label: {
                        VStack(spacing: 6) {
                            Text(LumaText.weekdayLetter(d.day)).font(LumaFont.label(10)).foregroundStyle(isSel ? Luma.ink : Luma.smoke)
                            Text(String(Int(d.day.suffix(2)) ?? 0)).font(LumaFont.numeral(22)).foregroundStyle(isSel ? Luma.ink : (d.day == today ? Luma.volt : Luma.frost))
                            HStack(spacing: 3) {
                                let live = d.planned.filter { $0.kind != .rest && $0.status != .skipped }
                                ForEach(live.prefix(3)) { p in
                                    Circle().strokeBorder(isSel ? Luma.ink : Luma.volt, lineWidth: 1.5)
                                        .background(Circle().fill(d.isDone(p) ? (isSel ? Luma.ink : Luma.volt) : Color.clear))
                                        .frame(width: 7, height: 7)
                                }
                                ForEach(d.unplannedWorkouts.prefix(max(0, 3 - live.count))) { _ in
                                    Circle().fill(isSel ? Luma.ink : Luma.volt).frame(width: 7, height: 7)
                                }
                                if live.isEmpty && d.unplannedWorkouts.isEmpty { Circle().fill(Color.clear).frame(width: 7, height: 7) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSel ? Luma.volt : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(d.day == today && !isSel ? Luma.volt.opacity(0.5) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button { onShift(-1) } label: { Label("Earlier", systemImage: "chevron.left").font(LumaFont.body(13, .medium)) }
                Spacer()
                Button { onShift(0) } label: { Text("Today").font(LumaFont.body(13, .semibold)) }
                Spacer()
                Button { onShift(1) } label: {
                    HStack(spacing: 4) { Text("Later"); Image(systemName: "chevron.right") }.font(LumaFont.body(13, .medium))
                }
            }
            .foregroundStyle(Luma.mist)
            .buttonStyle(.plain)
        }
    }
}

/// One day's plan and recordings.
struct DayAgenda: View {
    let day: ScheduleDay
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let planned = day.planned
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: LumaText.dayTitle(day.day, today: env.today), action: "Add") { router.sheet = .plan(nil, day.day) }
            if planned.isEmpty && day.workouts.isEmpty {
                LumaCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.day < env.today ? "Nothing recorded" : "Nothing planned").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        LumaNote(day.day < env.today ? "No session was recorded on this day. If you trained without the strap, log it by hand."
                                                     : "A free day. Add a session, or leave it as rest.")
                        if day.day <= env.today {
                            Button("Log a session by hand") { router.sheet = .manualWorkout }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                        }
                    }
                }
            }
            ForEach(planned) { p in
                PlannedCard(session: p, done: day.isDone(p), workout: day.matches[p.id].flatMap { id in day.workouts.first { $0.id == id } }, isToday: day.day == env.today)
            }
            if !day.unplannedWorkouts.isEmpty {
                LumaGroup {
                    ForEach(day.unplannedWorkouts) { w in
                        Button { router.push(.workout(w.id)) } label: { WorkoutRow(workout: w, on21: env.profile.strainOn21) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct PlannedCard: View {
    let session: PlannedSession
    let done: Bool
    let workout: LWorkout?
    let isToday: Bool
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let skipped = session.status == .skipped
        LumaCard(tint: done ? Luma.volt.opacity(0.35) : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: done ? "checkmark" : session.kind.sport.symbol)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(done ? Luma.ink : Luma.frost)
                        .frame(width: 40, height: 40).background(Circle().fill(done ? Luma.volt : Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(LumaFont.heading(16)).foregroundStyle(skipped ? Luma.smoke : Luma.frost).strikethrough(skipped)
                        Text(line).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                    }
                    Spacer(minLength: 6)
                    Button { router.sheet = .plan(session, session.day) } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Luma.mist).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                }
                if !session.detail.isEmpty && !done {
                    Text(session.detail).font(LumaFont.body(14)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                }
                if let w = workout {
                    Button { router.push(.workout(w.id)) } label: {
                        HStack {
                            Text(recorded(w)).font(LumaFont.body(13.5, .medium)).foregroundStyle(Luma.volt)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.volt)
                        }
                    }
                    .buttonStyle(.plain)
                } else if isToday && !skipped && session.kind != .rest {
                    Button("Start") { router.sheet = .go }.buttonStyle(LumaPrimaryButtonStyle(compact: true))
                }
            }
        }
    }

    private func recorded(_ w: LWorkout) -> String {
        var parts = [w.sport, LumaText.duration(w.durationS)]
        if let s = w.strain { parts.append("strain " + LScale.text(s, on21: env.profile.strainOn21)) }
        return LumaText.line(parts)
    }

    private var line: String {
        var parts: [String] = []
        if let m = session.startMinutes { parts.append(LFormat.timeOfDay(minutes: Double(m))) }
        if session.kind != .rest { parts.append("\(session.durationMin) min"); parts.append(session.intensity.title) }
        if session.origin == .coach { parts.append("From the coach") }
        if session.status == .skipped { parts.append("Skipped") }
        return LumaText.line(parts)
    }
}

/// The selected week in numbers.
struct WeekSummary: View {
    let days: [ScheduleDay]
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let workouts = days.flatMap { $0.workouts }
        let minutes = workouts.reduce(0.0) { $0 + $1.durationS / 60 }
        let adherence = Schedule.adherence(days, through: env.today)
        let km = workouts.filter { $0.kind == .run }.compactMap { $0.distanceM }.reduce(0, +) / 1000
        StatGrid {
            StatCell(label: "Sessions", value: "\(workouts.count)", note: adherence.map { "\($0.done) of \($0.planned) planned done" })
            StatCell(label: "Training time", value: LFormat.clock(minutes: minutes), unit: "h")
            StatCell(label: "Running", value: String(format: "%.1f", km), unit: "km")
            StatCell(label: "Hardest day", value: days.compactMap { env.day($0.day)?.strain }.max().map { LScale.text($0, on21: env.profile.strainOn21) } ?? "–", note: "Peak day strain")
        }
    }
}

// MARK: - Plan editor

struct PlanEditSheet: View {
    let session: PlannedSession?
    let day: String
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PlannedSession(day: "", kind: .gymClass, title: "")
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()

    var body: some View {
        LumaSheet(title: session == nil ? "Add a session" : "Edit session", tone: .run) {
            FlowLayout(spacing: 8) {
                ForEach(SessionKind.allCases) { k in
                    LumaChip(title: k.title, symbol: k.sport.symbol, isOn: draft.kind == k) {
                        let wasDefault = draft.title.isEmpty || draft.title == draft.kind.title
                        draft.kind = k
                        draft.intensity = k.defaultIntensity
                        if wasDefault { draft.title = k.title }
                    }
                }
            }
            LumaField(title: "Title", text: $draft.title)
            HStack {
                DatePicker("Day", selection: $date, displayedComponents: [.date]).labelsHidden().colorScheme(.dark)
                Spacer()
                Toggle("Set a time", isOn: $hasTime).font(LumaFont.body(14)).foregroundStyle(Luma.mist).tint(Luma.volt).fixedSize()
                if hasTime { DatePicker("Time", selection: $time, displayedComponents: [.hourAndMinute]).labelsHidden().colorScheme(.dark) }
            }
            if draft.kind != .rest {
                HStack {
                    LumaLabel("Duration")
                    Spacer()
                    Stepper(value: $draft.durationMin, in: 10...300, step: 5) {
                        Text("\(draft.durationMin) min").font(LumaFont.numeral(22)).foregroundStyle(Luma.frost)
                    }
                    .fixedSize()
                }
                LumaSegmented(selection: $draft.intensity, options: Intensity.allCases.map { ($0, $0.title) }, tint: Luma.frost)
                LumaField(title: "What to do (optional): sets, paces, loads", text: $draft.detail, axis: .vertical)
            }
            Button("Save") {
                draft.day = LDate.key(date)
                if hasTime {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    draft.startMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                } else {
                    draft.startMinutes = nil
                }
                if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = draft.kind.title }
                env.upsert(draft)
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle())
            if session != nil {
                HStack(spacing: 10) {
                    Button(draft.status == .skipped ? "Un-skip" : "Mark skipped") {
                        draft.status = draft.status == .skipped ? .planned : .skipped
                        env.upsert(draft)
                        dismiss()
                    }
                    .buttonStyle(LumaSecondaryButtonStyle())
                    Button(draft.status == .done ? "Not done" : "Mark done") {
                        draft.status = draft.status == .done ? .planned : .done
                        env.upsert(draft)
                        dismiss()
                    }
                    .buttonStyle(LumaSecondaryButtonStyle())
                }
                Button("Remove from calendar") {
                    env.remove(draft)
                    dismiss()
                }
                .font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain).frame(maxWidth: .infinity).padding(.top, 4)
            }
        }
        .onAppear {
            if let s = session {
                draft = s
                hasTime = s.startMinutes != nil
            } else {
                draft = PlannedSession(day: day, kind: .gymClass, title: SessionKind.gymClass.title)
            }
            date = LDate.date(draft.day) ?? Date()
            if let m = draft.startMinutes { time = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(m) * 60) }
        }
    }
}

// MARK: - Weekly routine

struct RoutineSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [RoutineSlot] = []
    @State private var weekday = 1
    @State private var kind: SessionKind = .gymClass
    @State private var title = ""
    @State private var time = Calendar.current.startOfDay(for: Date()).addingTimeInterval(6.5 * 3600)
    @State private var hasTime = true
    @State private var duration = 60

    private let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private func slotLine(_ s: RoutineSlot) -> String {
        var parts = [names[s.weekday - 1]]
        if let m = s.startMinutes { parts.append(LFormat.timeOfDay(minutes: Double(m))) }
        parts.append("\(s.durationMin) min")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LumaSheet(title: "Weekly routine", tone: .run) {
            LumaNote("Sessions that happen every week, such as your coached classes. Luma keeps four weeks of them on the calendar and ticks them off as you record sessions.")
            if slots.isEmpty {
                LumaCard { Text("No standing sessions yet.").font(LumaFont.body(14)).foregroundStyle(Luma.mist) }
            } else {
                LumaGroup {
                    ForEach(slots.sorted { ($0.weekday, $0.startMinutes ?? 0) < ($1.weekday, $1.startMinutes ?? 0) }) { s in
                        LumaRow(symbol: s.kind.sport.symbol, symbolColor: Luma.volt, title: s.title, subtitle: slotLine(s)) {
                            Button { slots.removeAll { $0.id == s.id } } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            LumaSection(title: "Add a standing session")
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { d in
                        LumaChip(title: String(names[d - 1].prefix(3)), isOn: weekday == d) { weekday = d }
                    }
                }
            }
            .scrollIndicators(.hidden)
            FlowLayout(spacing: 8) {
                ForEach([SessionKind.gymClass, .strength, .conditioning, .hyrox, .easyRun, .tempoRun, .intervals, .longRun, .mobility]) { k in
                    LumaChip(title: k.title, isOn: kind == k) {
                        if title.isEmpty || title == kind.title { title = k.title }
                        kind = k
                    }
                }
            }
            LumaField(title: "Name, e.g. Conditioning class", text: $title)
            HStack {
                Toggle("Fixed time", isOn: $hasTime).font(LumaFont.body(14)).foregroundStyle(Luma.mist).tint(Luma.volt).fixedSize()
                Spacer()
                if hasTime { DatePicker("", selection: $time, displayedComponents: [.hourAndMinute]).labelsHidden().colorScheme(.dark) }
            }
            HStack {
                Text("Duration").font(LumaFont.body(14)).foregroundStyle(Luma.mist)
                Spacer()
                Stepper(value: $duration, in: 15...240, step: 5) { Text("\(duration) min").font(LumaFont.numeral(20)).foregroundStyle(Luma.frost) }.fixedSize()
            }
            Button("Add to routine") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                slots.append(RoutineSlot(weekday: weekday, kind: kind, title: title.isEmpty ? kind.title : title,
                                         startMinutes: hasTime ? (c.hour ?? 0) * 60 + (c.minute ?? 0) : nil, durationMin: duration))
                LumaHaptics.tap()
            }
            .buttonStyle(LumaSecondaryButtonStyle())
            Button("Save routine") {
                env.setRoutine(slots)
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle())
        }
        .onAppear { slots = env.routine; title = kind.title }
    }
}

// MARK: - History

struct HistoryScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var filter: LSportKind?

    var body: some View {
        let kinds = Array(Set(env.workouts.map { $0.kind })).sorted { $0.title < $1.title }
        let list = env.workouts.filter { filter == nil || $0.kind == filter }
        let months = Dictionary(grouping: list, by: { String($0.day.prefix(7)) }).sorted { $0.key > $1.key }
        LumaDetailScreen(title: "Sessions", tone: .run) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    LumaChip(title: "All", isOn: filter == nil) { filter = nil }
                    ForEach(kinds, id: \.self) { k in
                        LumaChip(title: k.title, symbol: k.symbol, isOn: filter == k) { filter = k }
                    }
                }
                .padding(.horizontal, Luma.gutter)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -Luma.gutter)
            if list.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "figure.run", title: "No sessions yet", message: "Sessions the strap detects, and everything you start from the Go button, are listed here.",
                              action: "Log one by hand") { router.sheet = .manualWorkout }
                }
            }
            ForEach(months, id: \.key) { month, sessions in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(monthTitle(month)).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        Spacer()
                        Text("\(sessions.count) sessions · \(LFormat.hm(minutes: sessions.reduce(0) { $0 + $1.durationS / 60 }))").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                    }
                    LumaGroup {
                        ForEach(sessions) { w in
                            Button { router.push(.workout(w.id)) } label: { HistoryRow(workout: w, on21: env.profile.strainOn21) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Button { router.sheet = .manualWorkout } label: { Label("Log a session by hand", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
        }
    }

    private func monthTitle(_ key: String) -> String {
        LDate.date(key + "-15").map { $0.formatted(.dateTime.month(.wide).year()) } ?? key
    }
}

struct HistoryRow: View {
    let workout: LWorkout
    let on21: Bool

    var body: some View {
        let kind = workout.kind
        HStack(spacing: 13) {
            VStack(spacing: 0) {
                Text(String(Int(workout.day.suffix(2)) ?? 0)).font(LumaFont.numeral(20)).foregroundStyle(Luma.frost)
                Text(LumaText.weekdayLetter(workout.day)).font(LumaFont.label(9)).foregroundStyle(Luma.smoke)
            }
            .frame(width: 30)
            Image(systemName: kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(kind.tone.color)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(kind.tone.color.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.sport).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                Text(detail).font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
            }
            Spacer(minLength: 6)
            if let s = workout.strain {
                Text(LScale.text(s, on21: on21)).font(LumaFont.numeral(20, .semibold)).foregroundStyle(Luma.frost)
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Luma.smoke)
        }
        .padding(.vertical, 11).padding(.horizontal, 14).contentShape(Rectangle())
    }

    private var detail: String {
        var parts = [LumaText.duration(workout.durationS)]
        if let d = workout.distanceM, d > 200 { parts.append("\(LumaText.km(d)) km") }
        if let p = workout.paceSPerKm, workout.kind == .run { parts.append("\(LumaText.pace(p))/km") }
        if let hr = workout.avgHR { parts.append("\(Int(hr.rounded())) bpm") }
        return LumaText.line(parts)
    }
}

// MARK: - Manual session

struct ManualWorkoutSheet: View {
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var sport = "Conditioning"
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = 60.0
    @State private var km = 0.0
    @State private var hr = 0.0
    @State private var notes = ""

    private let sports = ["Conditioning", "Strength", "HYROX", "Running", "Cycling", "Rowing", "Swimming", "Walking", "Mobility"]

    var body: some View {
        LumaSheet(title: "Log a session", tone: .run) {
            LumaNote("Set when it started and how long it ran. If you were wearing the strap, Luma reads the heart rate, zones and strain for that time from what it recorded; type an average only for a session without it.")
            FlowLayout(spacing: 8) {
                ForEach(sports, id: \.self) { s in
                    LumaChip(title: s, symbol: LSportKind.classify(s).symbol, isOn: sport == s) { sport = s }
                }
            }
            DatePicker("Started", selection: $start, in: ...Date()).font(LumaFont.body(15)).foregroundStyle(Luma.frost).colorScheme(.dark)
            HStack(spacing: 10) {
                NumberField(label: "Minutes", value: $minutes)
                NumberField(label: "Distance km", value: $km)
                NumberField(label: "Avg heart rate", value: $hr)
            }
            LumaField(title: "Notes: what you did", text: $notes, axis: .vertical)
            Button("Save session") {
                let s = start.timeIntervalSince1970
                env.saveWorkout(LWorkout(start: s, end: s + minutes * 60, sport: sport, source: "manual", avgHR: hr > 40 ? hr : nil,
                                         distanceM: km > 0 ? km * 1000 : nil, notes: notes.isEmpty ? nil : notes))
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle())
            .disabled(minutes < 1)
        }
    }
}
