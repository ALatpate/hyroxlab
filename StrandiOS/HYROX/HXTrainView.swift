import SwiftUI
import HYROXCore
import WhoopStore

/// What's my plan and what have I done?
struct HXTrainView: View {
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var repo: Repository
    @State private var noopWorkouts: [WorkoutRow] = []
    @State private var showProfile = false

    private var cal: Calendar { Calendar.current }

    var body: some View {
        HXScreen(title: "Train", subtitle: blockLine) {
            weekStrip
            if let race = store.profile.raceDate {
                let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: race)).day ?? 0
                HXCard(tint: HX.volt) {
                    HStack {
                        HXStat(label: store.profile.raceName.isEmpty ? "Race" : store.profile.raceName, value: "\(max(0, days))", unit: "days", size: 36)
                        Spacer()
                        Text(race.formatted(date: .abbreviated, time: .omitted)).font(HX.caption).foregroundStyle(HX.textDim)
                    }
                }
            }
            HXOverline("This week")
            ForEach(thisWeek) { p in planRow(p) }
            HXOverline("Next week")
            ForEach(nextWeek) { p in planRow(p) }
            HStack {
                Button("Regenerate plan") { store.regeneratePlan() }.font(HX.caption).foregroundStyle(HX.volt)
                Spacer()
                Button("Profile & goals") { showProfile = true }.font(HX.caption).foregroundStyle(HX.volt)
            }
            HXOverline("History")
            if store.sessions.isEmpty && noopWorkouts.isEmpty {
                HXCard { Text("No sessions yet. Start one from Go.").font(HX.body).foregroundStyle(HX.textDim) }
            }
            ForEach(store.sessions.filter(\.isComplete).prefix(20)) { s in
                NavigationLink { HXSessionDetailView(session: s) } label: { sessionRow(s) }.buttonStyle(.plain)
            }
            HStack(spacing: HX.gap) {
                NavigationLink { WorkoutsView() } label: { linkTile("All workouts", "figure.run", "NOOP record incl. Apple Health") }.buttonStyle(.plain)
                NavigationLink { LiftLogView() } label: { linkTile("Lift Log", "dumbbell.fill", "Sets, reps, 1RM") }.buttonStyle(.plain)
            }
        }
        .navigationBarHidden(true)
        .task { noopWorkouts = await repo.workoutRows(days: 30) }
        .sheet(isPresented: $showProfile) { HXOnboardingView().environmentObject(store) }
    }

    private var blockLine: String {
        guard let race = store.profile.raceDate else { return "Maintaining — add a race date for a build" }
        let w = cal.dateComponents([.weekOfYear], from: Date(), to: race).weekOfYear ?? 0
        return "\(PlanGenerator.block(weeksToRace: w).rawValue.capitalized) block · \(w) weeks out"
    }

    private var thisWeek: [PlannedSession] { store.plan.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) } }
    private var nextWeek: [PlannedSession] {
        let next = cal.date(byAdding: .weekOfYear, value: 1, to: Date())!
        return store.plan.filter { cal.isDate($0.date, equalTo: next, toGranularity: .weekOfYear) }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(thisWeek) { p in
                VStack(spacing: 4) {
                    Text(p.date.formatted(.dateTime.weekday(.narrow))).font(HX.caption).foregroundStyle(HX.textDim)
                    Circle().fill(p.completedSessionID != nil ? HX.good : color(p.type).opacity(cal.isDateInToday(p.date) ? 1 : 0.5)).frame(width: 10, height: 10)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(cal.isDateInToday(p.date) ? HX.raised : .clear))
            }
        }
    }

    private func planRow(_ p: PlannedSession) -> some View {
        HXCard(padding: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(p.date.formatted(.dateTime.weekday(.abbreviated))).font(HX.caption).foregroundStyle(HX.textDim)
                    Text(p.date.formatted(.dateTime.day())).font(HX.numeral(20, weight: .bold)).foregroundStyle(HX.text)
                }
                .frame(width: 40)
                RoundedRectangle(cornerRadius: 2).fill(color(p.type)).frame(width: 3, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title).font(HX.body.weight(.semibold)).foregroundStyle(p.skipped ? HX.textDim : HX.text).strikethrough(p.skipped)
                    if !p.purpose.isEmpty { Text(p.purpose).font(HX.caption).foregroundStyle(HX.textDim).lineLimit(2) }
                }
                Spacer()
                if p.completedSessionID != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(HX.good) }
                else if p.date < cal.startOfDay(for: Date()), p.type != .rest { Image(systemName: "minus.circle").foregroundStyle(HX.textDim) }
            }
        }
        .contextMenu {
            Button(p.skipped ? "Unskip" : "Skip") { if let i = store.plan.firstIndex(where: { $0.id == p.id }) { store.plan[i].skipped.toggle() } }
            Button("Mark done") { if let i = store.plan.firstIndex(where: { $0.id == p.id }) { store.plan[i].completedSessionID = UUID() } }
        }
    }

    private func sessionRow(_ s: HXSession) -> some View {
        HXCard(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: s.kind.isRun ? "figure.run" : "flag.checkered").foregroundStyle(s.kind.isRun ? HX.run : HX.volt).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.kind.title).font(HX.body.weight(.semibold)).foregroundStyle(HX.text)
                    Text(s.startedAt.formatted(date: .abbreviated, time: .shortened)).font(HX.caption).foregroundStyle(HX.textDim)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(HXFormat.duration(s.totalS ?? 0)).font(HX.body.monospacedDigit()).foregroundStyle(HX.text)
                    let dist = s.runs.compactMap(\.distanceM).reduce(0, +)
                    if dist > 0 { Text("\(HXFormat.km(dist)) km").font(HX.caption).foregroundStyle(HX.textDim) }
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(HX.textDim)
            }
        }
    }

    private func linkTile(_ title: String, _ symbol: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(HX.textDim)
            Text(title).font(HX.headline).foregroundStyle(HX.text)
            Text(sub).font(HX.caption).foregroundStyle(HX.textDim)
        }
        .padding(HX.pad).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HX.radius, style: .continuous).fill(HX.surface))
    }

    private func color(_ t: PlannedSessionType) -> Color {
        switch t {
        case .gymClass: return HX.station
        case .easyRun, .longRun: return HX.run
        case .thresholdRun, .intervalRun, .compromisedRun: return HX.run
        case .fullSimulation, .halfSimulation, .stationPractice: return HX.volt
        case .rest: return HX.textDim
        }
    }
}
