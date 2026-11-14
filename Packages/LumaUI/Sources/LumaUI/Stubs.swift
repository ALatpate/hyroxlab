import SwiftUI
import LumaCore
import LumaKit

// Temporary placeholders so the package builds while screens land one batch at a time.
// Each entry is deleted when its real screen is added.

struct StubScreen: View {
    let name: String
    var body: some View {
        LumaDetailScreen(title: name) { LumaEmpty(symbol: "hammer", title: name, message: "This screen is being built.") }
    }
}

struct TrainScreen: View {
    var body: some View { StubScreen(name: "TrainScreen") }
}

struct FuelScreen: View {
    var body: some View { StubScreen(name: "FuelScreen") }
}

struct CoachScreen: View {
    var body: some View { StubScreen(name: "CoachScreen") }
}

struct WorkoutScreen: View {
    let id: String
    var body: some View { StubScreen(name: "WorkoutScreen") }
}

struct RaceReadinessScreen: View {
    var body: some View { StubScreen(name: "RaceReadinessScreen") }
}

struct StrengthScreen: View {
    var body: some View { StubScreen(name: "StrengthScreen") }
}

struct HistoryScreen: View {
    var body: some View { StubScreen(name: "HistoryScreen") }
}

struct SessionReportScreen: View {
    let id: UUID
    var body: some View { StubScreen(name: "SessionReportScreen") }
}

struct LiftDetailScreen: View {
    let id: UUID
    var body: some View { StubScreen(name: "LiftDetailScreen") }
}

struct SupplementsScreen: View {
    var body: some View { StubScreen(name: "SupplementsScreen") }
}

struct FuelHistoryScreen: View {
    var body: some View { StubScreen(name: "FuelHistoryScreen") }
}

struct DevicesScreen: View {
    var body: some View { StubScreen(name: "DevicesScreen") }
}

struct SettingsScreen: View {
    var body: some View { StubScreen(name: "SettingsScreen") }
}

struct ProfileScreen: View {
    var body: some View { StubScreen(name: "ProfileScreen") }
}

struct AboutScreen: View {
    var body: some View { StubScreen(name: "AboutScreen") }
}

struct GoSheet: View {
    var body: some View { StubScreen(name: "GoSheet") }
}

struct YouSheet: View {
    var body: some View { StubScreen(name: "YouSheet") }
}

struct CheckInSheet: View {
    let day: String
    var body: some View { StubScreen(name: "CheckInSheet") }
}

struct FuelAddSheet: View {
    let mode: FuelAddMode
    var body: some View { StubScreen(name: "FuelAddSheet") }
}

struct PlanEditSheet: View {
    let session: PlannedSession?
    let day: String
    var body: some View { StubScreen(name: "PlanEditSheet") }
}

struct RoutineSheet: View {
    var body: some View { StubScreen(name: "RoutineSheet") }
}

struct CoachSetupSheet: View {
    var body: some View { StubScreen(name: "CoachSetupSheet") }
}

struct ManualWorkoutSheet: View {
    var body: some View { StubScreen(name: "ManualWorkoutSheet") }
}

struct RunLiveScreen: View {
    let plan: RunPlan
    var body: some View { StubScreen(name: "RunLiveScreen") }
}

struct RaceLiveScreen: View {
    let kind: HXSessionKind
    var body: some View { StubScreen(name: "RaceLiveScreen") }
}

struct LiftLiveScreen: View {
    var body: some View { StubScreen(name: "LiftLiveScreen") }
}

struct OnboardingScreen: View {
    var body: some View { StubScreen(name: "OnboardingScreen") }
}
