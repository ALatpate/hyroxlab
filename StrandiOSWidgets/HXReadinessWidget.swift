import SwiftUI
import WidgetKit

/// HYROX Lab Home Screen widget: readiness ring, verdict and today's session. Small and medium.
struct HXReadinessEntry: TimelineEntry {
    let date: Date
    let state: HXWidgetState?
}

struct HXReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> HXReadinessEntry {
        HXReadinessEntry(date: Date(), state: HXWidgetState(score: 74, advice: "Train as planned", sessionTitle: "Threshold 3 × 8 min",
                                                           sessionPurpose: "Raises the pace you can hold for 8 × 1 km.", sessionDone: false, raceDaysLeft: 42, updated: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (HXReadinessEntry) -> Void) {
        completion(HXReadinessEntry(date: Date(), state: HXWidgetState.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HXReadinessEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [HXReadinessEntry(date: Date(), state: HXWidgetState.load())], policy: .after(next)))
    }
}

struct HXReadinessWidgetView: View {
    let entry: HXReadinessEntry
    @Environment(\.widgetFamily) private var family

    private let volt = Color(red: 0.784, green: 1.0, blue: 0.180)
    private let dim = Color(red: 0.604, green: 0.639, blue: 0.686)

    private func color(_ s: Int) -> Color {
        switch s {
        case ..<40: return Color(red: 0.976, green: 0.447, blue: 0.447)
        case 40..<62: return Color(red: 0.980, green: 0.757, blue: 0.345)
        default: return Color(red: 0.420, green: 0.863, blue: 0.616)
        }
    }

    var body: some View {
        let s = entry.state
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 9)
                Circle().trim(from: 0, to: CGFloat(s?.score ?? 0) / 100)
                    .stroke(color(s?.score ?? 0), style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(s?.score.map { "\($0)" } ?? "—").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("READY").font(.system(size: 8, weight: .semibold, design: .rounded)).tracking(1).foregroundStyle(dim)
                }
            }
            .frame(width: 68, height: 68)
            if family != .systemSmall {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s?.advice ?? "No data yet").font(.system(.subheadline, design: .rounded).weight(.semibold))
                    if let t = s?.sessionTitle {
                        HStack(spacing: 4) {
                            if s?.sessionDone == true { Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(volt) }
                            Text(t).font(.system(.caption, design: .rounded)).foregroundStyle(dim).lineLimit(1)
                        }
                    }
                    if let p = s?.sessionPurpose, !p.isEmpty { Text(p).font(.system(size: 10, design: .rounded)).foregroundStyle(dim).lineLimit(2) }
                    if let d = s?.raceDaysLeft { Text("Race in \(d) days").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(volt) }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color(red: 0.043, green: 0.051, blue: 0.063) }
    }
}

struct HXReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: HXWidgetState.kind, provider: HXReadinessProvider()) { entry in
            HXReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("Luma readiness")
        .description("Today's readiness and session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
