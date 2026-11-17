import SwiftUI
import LumaCore
import LumaKit

// MARK: - Weekly review

/// On Today from Sunday on, until the week has been written up: the way to the review.
struct ReviewPrompt: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        if let week = env.reviewDue, !env.days.isEmpty {
            Button { router.push(.reviews, from: "reviews") } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Luma.aqua)
                        .frame(width: 44, height: 44).background(Circle().fill(Luma.aqua.opacity(0.13)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your week is ready to review").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        Text(WeekDigest.title(week)).font(LumaFont.body(13)).foregroundStyle(Luma.mist)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Luma.smoke)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LumaPanel(tint: Luma.aqua.opacity(0.4), radius: 22))
            }
            .buttonStyle(.plain)
            .lumaZoomSource("reviews")
        }
    }
}

/// Every review that has been written, newest first, and the week that is due.
struct ReviewsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        LumaDetailScreen(title: "Weekly review", tone: .hrv) {
            if let week = env.reviewDue { ReviewDueCard(week: week) }
            if env.reviews.isEmpty && env.reviewDue == nil {
                LumaCard {
                    LumaEmpty(symbol: "calendar", title: "No review yet", message: "From Sunday evening the week can be written up: what went well, what slipped, and three things for the week ahead.")
                }
            }
            ForEach(env.reviews.sorted { $0.weekStart > $1.weekStart }) { review in ReviewCard(review: review) }
            if !env.reviews.isEmpty {
                LumaNote("Reviews are kept on this iPhone. Each was written by the coach from Luma's figures for that week, which are shown with it.")
            }
        }
    }
}

/// The week that is due: its figures, which are Luma's own, and the way to have it written up.
private struct ReviewDueCard: View {
    let week: String
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let figures = env.reviewFigures(week)
        LumaCard(tint: Luma.aqua.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("Week of \(WeekDigest.title(week))")
                FigureGrid(figures: figures)
                if env.reviewWriting {
                    ReadingRows(caption: "Writing up your week", rows: 3)
                } else if env.canWriteReview {
                    Button {
                        Task { await env.writeReview(for: week) }
                    } label: {
                        Label("Write up this week", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LumaPrimaryButtonStyle(color: Luma.aqua))
                    LumaNote("The coach gets the week's figures and nothing else, and writes from those alone.")
                } else if !env.coach.hasKey {
                    LumaNote("These are the week's figures. Connect the coach to have the week written up in words.")
                    Button("Connect the coach") { router.sheet = .coachSetup }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                } else {
                    LumaNote("These are the week's figures. The write-up is made from your health data, so it needs “Share health data with the coach” switched on in Settings.")
                }
                if let error = env.reviewError {
                    Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct FigureGrid: View {
    let figures: [ReviewFigure]

    var body: some View {
        if figures.isEmpty {
            LumaNote("No figures for this week yet.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(figures) { f in
                    HStack(alignment: .firstTextBaseline) {
                        Text(f.label).font(LumaFont.body(13.5, .medium)).foregroundStyle(Luma.mist)
                        Spacer()
                        Text(f.value).font(LumaFont.body(14.5, .semibold)).foregroundStyle(Luma.frost).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}

struct ReviewCard: View {
    let review: WeeklyReview

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    LumaLabel("Week of \(WeekDigest.title(review.weekStart))")
                    Text(review.headline).font(LumaFont.heading(19)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                }
                FigureGrid(figures: review.figures)
                block("Went well", review.wentWell, "checkmark.circle.fill", Luma.mint)
                block("Watch", review.watch, "eye.fill", Luma.amber)
                block("Next week", review.next, "arrow.right.circle.fill", Luma.aqua)
            }
        }
    }

    @ViewBuilder
    private func block(_ title: String, _ lines: [String], _ symbol: String, _ color: Color) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(LumaFont.heading(14)).foregroundStyle(color)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                        Text(line).font(LumaFont.body(14.5)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
