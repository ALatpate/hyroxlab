import SwiftUI
import LumaCore
import LumaKit

// MARK: - What recent runs add up to

/// Read from the recordings of recent runs: heart rate at the easy pace, the fastest efforts inside
/// them, and the critical speed those efforts give.
struct RunDepthState: Equatable {
    var easyPace: EasyPaceRead?
    var efforts: [PersonalBest] = []
    /// Critical speed in metres a second and the reserve above it in metres, from those efforts.
    var speed: Double?
    var reserve: Double?
}

extension LumaEnv {
    /// Critical speed as every screen and the coach are given it: from the fastest efforts inside the
    /// runs of the last sixteen weeks when there are enough of them, otherwise from the personal bests.
    var criticalSpeed: (cs: Double, dPrime: Double, recent: Bool)? {
        if let cs = runDepth.speed { return (cs, runDepth.reserve ?? 0, true) }
        if let cs = analysis.fitness.criticalSpeed { return (cs, analysis.fitness.dPrime ?? 0, false) }
        return nil
    }

    /// Reads the recordings of recent runs again when the list of them has changed. The files are
    /// read a few at a time so the screen stays free.
    func refreshRunDepth() {
        if isDemo {
            if runDepthSignature == nil {
                runDepthSignature = "demo"
                runDepth = RunDepthState.read(LumaDemoDepth.runs(today: today))
            }
            return
        }
        guard storesReady else { return }
        let cutoff = LDate.adding(-7 * CriticalSpeedEfforts.weeks, to: today)
        let runs = Array(workouts.filter { $0.kind == .run && $0.day >= cutoff }.sorted { $0.start > $1.start }.prefix(40))
        let signature = runs.map { $0.id }.joined(separator: ",")
        guard signature != runDepthSignature else { return }
        runDepthSignature = signature
        Task { [weak self] in
            var read: [(day: String, samples: [RunSample])] = []
            for run in runs {
                guard let self else { return }
                if let samples = self.runSamples(for: run.id), samples.count > 30 { read.append((day: run.day, samples: samples)) }
                await Task.yield()
            }
            guard let self, self.runDepthSignature == signature else { return }
            let state = RunDepthState.read(read)
            if state != self.runDepth { self.runDepth = state }
        }
    }
}

extension RunDepthState {
    static func read(_ runs: [(day: String, samples: [RunSample])]) -> RunDepthState {
        var state = RunDepthState()
        state.easyPace = EasyPace.read(runs: runs.sorted { $0.day < $1.day })
        state.efforts = CriticalSpeedEfforts.fastest(in: runs.map { $0.samples })
        if let fit = CriticalSpeedEfforts.fit(state.efforts) {
            state.speed = fit.cs
            state.reserve = fit.dPrime
        }
        return state
    }
}

/// The gallery's runs: eight steady ones whose heart rate eases over the weeks, and one with hard
/// efforts in it, so the cards have something true to their own rules to show.
enum LumaDemoDepth {
    static func runs(today: String) -> [(day: String, samples: [RunSample])] {
        func steady(minutes: Double, pace: Double, hr: Double, wobble: Double) -> [RunSample] {
            stride(from: 0.0, through: minutes * 60, by: 5).map { t in
                RunSample(tS: t, distanceM: t / pace * 1000, hr: hr + wobble * sin(t / 70))
            }
        }
        var out: [(day: String, samples: [RunSample])] = []
        for i in 0..<8 {
            out.append((day: LDate.adding(-(i * 6 + 3), to: today), samples: steady(minutes: 42, pace: 338, hr: 141.5 + Double(i) * 1.3, wobble: 1.5)))
        }
        // A session with a hard 400, a hard 800 and a 5 km at tempo, joined by easy running.
        var hard: [RunSample] = []
        var t = 0.0, d = 0.0
        func add(metres: Double, pace: Double, hr: Double) {
            let end = d + metres
            while d < end {
                t += 5
                d += 5 / pace * 1000
                hard.append(RunSample(tS: t, distanceM: d, hr: hr))
            }
        }
        hard.append(RunSample(tS: 0, distanceM: 0, hr: 120))
        add(metres: 1500, pace: 345, hr: 138)
        add(metres: 400, pace: 222, hr: 172)
        add(metres: 600, pace: 400, hr: 150)
        add(metres: 800, pace: 236, hr: 176)
        add(metres: 800, pace: 400, hr: 152)
        add(metres: 5000, pace: 288, hr: 168)
        out.append((day: LDate.adding(-10, to: today), samples: hard))
        return out
    }
}

// MARK: - HRV against its own band

/// The week's HRV against the athlete's own normal band: the reading the day's call goes by.
struct HRVTrendCard: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let t = env.analysis.hrvTrend
        LumaCard(tint: t.place == .below ? Luma.amber.opacity(0.5) : nil) {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("The week against your normal")
                Text(t.headline).font(LumaFont.title(22)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                if let low = t.lowMs, let high = t.highMs, high > low {
                    LumaLineChart(series: [
                        LumaLineChart.Series(id: "night", values: t.days.map { $0.nightMs }, color: Luma.aqua.opacity(0.4), width: 1.4, gaps: true),
                        LumaLineChart.Series(id: "week", values: t.days.map { $0.weekMs }, color: Luma.aqua),
                    ], labels: t.days.map { LumaText.shortDay($0.day) }, band: low...high, bandColor: Luma.aqua, height: 170,
                    format: { String(format: "%.0f ms", $0) })
                    HStack(spacing: 16) {
                        legend(Luma.aqua, "Week's average")
                        legend(Luma.aqua.opacity(0.4), "Each night")
                        legend(Luma.aqua.opacity(0.18), "Your normal")
                    }
                }
                LumaNote(t.detail)
                if let now = t.weekSpread, let usual = t.usualSpread {
                    LumaNote(String(format: "Night-to-night spread this week %.1f%%, against %.1f%% over two months. A jumpy week often comes with a hard block or broken sleep.", now, usual))
                }
                LumaNote("One night's HRV swings too much to act on. The week's average, set against a band built from your own last two months, is what sports-science practice goes by.")
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(LumaFont.body(12)).foregroundStyle(Luma.mist)
        }
    }
}

// MARK: - Running

/// Heart rate at the easy pace and critical speed, under Aerobic fitness.
struct RunDepthCards: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if let easy = env.runDepth.easyPace { EasyPaceCard(read: easy) }
        if let c = env.criticalSpeed { CriticalSpeedCard(speed: c.cs, recent: c.recent, efforts: env.runDepth.efforts) }
    }
}

struct EasyPaceCard: View {
    let read: EasyPaceRead

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel("Heart rate at \(LumaText.pace(read.paceSPerKm)) /km")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(read.points.last.map { String(format: "%.0f", $0.hr) } ?? "–").font(LumaFont.numeral(44)).foregroundStyle(Luma.frost)
                            Text("bpm").font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist)
                        }
                    }
                    Spacer()
                    LumaPill(text: read.direction == .falling ? "Falling" : (read.direction == .rising ? "Rising" : "Steady"),
                             color: read.direction == .falling ? Luma.mint : (read.direction == .rising ? Luma.amber : Luma.mist))
                }
                LumaLineChart(values: read.points.map { $0.hr }, labels: read.points.map { LumaText.shortDay($0.day) }, color: Luma.coral,
                              fill: false, height: 130, format: { String(format: "%.0f", $0) })
                Text(read.headline).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                LumaNote(read.detail)
                LumaNote("Read from steady four-minute stretches at your own easy pace in recorded runs, one point a day. The same pace at a lower heart rate means fitter; of the heart-rate measures used to follow training, this one stands out most clearly from its day-to-day noise.")
            }
        }
    }
}

struct CriticalSpeedCard: View {
    let speed: Double
    /// From the fastest efforts in recent runs; otherwise from the personal bests.
    let recent: Bool
    let efforts: [PersonalBest]

    private func pace(_ share: Double) -> String { LumaText.pace(CriticalSpeedEfforts.pace(cs: speed, share: share)) }

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("Critical speed")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(pace(1)).font(LumaFont.numeral(44)).foregroundStyle(Luma.frost)
                    Text("/km").font(LumaFont.body(12, .semibold)).foregroundStyle(Luma.mist)
                }
                LumaNote("About the fastest pace you can hold without fading, for half an hour or so. An estimate, good to within several seconds a kilometre.")
                LumaDivider()
                row("95% of it", pace(0.95), "Hard and steady")
                row("85% of it", pace(0.85), "What recreational marathon runners hold for the distance, on average")
                row("75% of it", pace(0.75), "Easy running")
                LumaNote(source)
            }
        }
    }

    private var source: String {
        guard recent else { return "Worked out from your personal bests. Once recorded runs hold hard efforts of different lengths, it is worked out from the fastest of them in the last sixteen weeks." }
        let used = efforts.filter { e in CriticalSpeedEfforts.preferred.contains { abs($0 - e.distanceM) < 1 } }
        let chosen: [PersonalBest] = used.count == CriticalSpeedEfforts.preferred.count ? used : efforts
        let list: String = chosen.map { effort in effort.label + " in " + LumaText.duration(effort.seconds) }.joined(separator: ", ")
        return "Worked out from the fastest efforts inside your runs of the last sixteen weeks: \(list)."
    }

    private func row(_ title: String, _ value: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                Text(note).font(LumaFont.body(12)).foregroundStyle(Luma.smoke).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(value) /km").font(LumaFont.numeral(20, .semibold)).foregroundStyle(Luma.frost)
        }
    }
}

// MARK: - A simulation in depth

/// Under a race report: the shares of the session beside published ones, and how heart rate for the
/// same speed moved from the early runs to the late ones.
struct SessionDepthCards: View {
    let session: HXSession

    var body: some View {
        if let shares = TimeSharesModel.read(session) { TimeSharesCard(shares: shares) }
        if let read = Durability.read(session) { DurabilityCard(read: read) }
    }
}

struct TimeSharesCard: View {
    let shares: TimeShares

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                LumaLabel("Your split beside the reference")
                row("Running", shares.run, shares.referenceRun, Luma.sky)
                row("Stations", shares.stations, shares.referenceStations, Luma.volt)
                row("Roxzone", shares.roxzone, shares.referenceRoxzone, Luma.amber)
                Text(shares.line).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost).fixedSize(horizontal: false, vertical: true)
                LumaNote(TimeShares.referenceNote + " The stations share is what is left after running and the Roxzone.")
            }
        }
    }

    private func row(_ title: String, _ mine: Double, _ reference: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(LumaFont.body(14.5, .medium)).foregroundStyle(Luma.frost)
                Spacer()
                Text("\(LNum.int((mine * 100).rounded()))%").font(LumaFont.numeral(20, .semibold)).foregroundStyle(Luma.frost)
                Text("reference \(LNum.int((reference * 100).rounded()))%").font(LumaFont.body(12)).foregroundStyle(Luma.smoke)
            }
            LumaBar(value: mine, total: 0.7, color: color, height: 8)
            LumaBar(value: reference, total: 0.7, color: Luma.smoke, height: 4)
        }
    }
}

struct DurabilityCard: View {
    let read: DurabilityRead

    private var tint: Color { read.band == .low ? Luma.mint : (read.band == .moderate ? Luma.amber : Luma.coral) }

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        LumaLabel("Heart rate for the same speed, late against early")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", read.ratio)).font(LumaFont.numeral(44)).foregroundStyle(Luma.frost)
                            Text("×").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.mist)
                        }
                    }
                    Spacer()
                    LumaPill(text: read.band == .low ? "Held" : (read.band == .moderate ? "Some drift" : "Drifted"), color: tint)
                }
                LumaBarChart(bars: read.perRun.enumerated().map { i, v in
                    LumaBarChart.Bar(id: i, value: max(0, (v - 0.9) * 100), color: v > Durability.onsetLine ? tint : Luma.sky, label: "\(i + 1)")
                }, height: 110, showAxis: false, format: { String(format: "%.2f×", $0 / 100 + 0.9) })
                Text(read.headline).font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                LumaNote(read.detail)
                LumaNote("Each bar is a run: the heart rate it cost for its speed, against the early runs. Under 1.10 is low drift, 1.20 and over is high. From wrist heart rate, which can read low in hard work, so take it as a guide.")
            }
        }
    }
}

// MARK: - A route as a file

extension LumaEnv {
    /// A run's route as a GPX file other apps open, or nil when there is no route to write.
    func gpxFile(for workout: LWorkout, route: [LCoord]) -> URL? {
        let points = GPX.points(route: route, samples: runSamples(for: workout.id) ?? [], durationS: workout.durationS)
        guard let text = GPX.document(name: workout.sport, startedAt: Date(timeIntervalSince1970: workout.start), points: points) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(GPX.fileName(name: workout.sport, day: workout.day))
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }
}
