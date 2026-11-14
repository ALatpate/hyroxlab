import SwiftUI
import PhotosUI
import HYROXCore
import WhoopStore

// MARK: - Coach tab

/// NOOP's Coach with HYROX Lab's context underneath it and quick prompts on top.
struct HXCoachView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var store: HXStore

    private let prompts = [
        "Why is my readiness what it is today?",
        "Plan my week around my classes.",
        "Which station is costing me most time?",
        "Am I ready for Open Singles?",
        "What should I eat before tomorrow's session?",
        "Write my weekly review."
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    NavigationLink { HXCoachCaptureView(mode: .meal) } label: { chip("Meal photo", "camera.fill") }
                    NavigationLink { HXCoachCaptureView(mode: .workout) } label: { chip("Class board", "doc.text.viewfinder") }
                    ForEach(prompts, id: \.self) { p in
                        Button { coach.pendingPrompt = p } label: { chip(p, nil) }
                    }
                }
                .padding(.horizontal, HX.screenPad).padding(.vertical, 8)
            }
            .background(HX.ink)
            CoachView()
        }
        .background(HX.ink.ignoresSafeArea())
    }

    private func chip(_ text: String, _ symbol: String?) -> some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.caption) }
            Text(text).font(HX.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(symbol == nil ? HX.text : HX.ink)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(symbol == nil ? HX.surface : HX.volt))
    }
}

// MARK: - Context pack

/// Assembles the HYROX Lab block appended to every coach message: readiness and its drivers, this
/// week's plan and what was done, the last sessions, benchmarks, race readiness and today's fuel.
/// Numbers only come from the store; the model is told to quote them, never to invent any.
enum HXCoachContext {
    @MainActor static func install(store: HXStore) {
        AICoachEngine.extraContextProvider = { [weak store] in
            guard let store else { return "" }
            return await MainActor.run { build(store) }
        }
    }

    @MainActor static func build(_ s: HXStore) -> String {
        var out: [String] = ["HYROX LAB CONTEXT (the athlete trains for HYROX; use these figures verbatim, say when something is missing, never invent a number):"]
        let p = s.profile
        out.append("Goal format: \(p.format.title). 5 km time: \(HXFormat.duration(p.fiveKSeconds)). Gym classes on \(p.classWeekdays.count) days/week. Race: \(p.raceDate.map { "\(p.raceName.isEmpty ? "booked" : p.raceName) on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "none booked").")
        if let r = s.readiness {
            out.append("Readiness today: \(r.score)/100 → \(r.advice.title). Drivers: " + r.drivers.map { "\($0.label) (\(String(format: "%+.0f", $0.points)))" }.joined(separator: "; ") + ".")
        } else { out.append("Readiness today: unavailable (no synced night yet).") }
        let ac = HXTrainingLoad.acuteChronic(dailyLoads: s.dailyLoads.map(\.load))
        if let ratio = ac.ratio { out.append(String(format: "Training load: acute %.0f, chronic %.0f, ratio %.2f.", ac.acute, ac.chronic, ratio)) }
        let cal = Calendar.current
        let week = s.plan.filter { cal.isDate($0.date, equalTo: Date(), toGranularity: .weekOfYear) }
        if !week.isEmpty {
            out.append("This week's plan: " + week.map { "\($0.date.formatted(.dateTime.weekday(.abbreviated))) \($0.title)\($0.completedSessionID != nil ? " ✓" : ($0.skipped ? " (skipped)" : ""))" }.joined(separator: "; ") + ".")
        }
        let recent = s.sessions.filter(\.isComplete).prefix(5)
        if !recent.isEmpty {
            out.append("Recent HYROX Lab sessions:")
            for x in recent {
                var line = "- \(x.startedAt.formatted(date: .abbreviated, time: .omitted)) \(x.kind.title): \(HXFormat.duration(x.totalS ?? 0))"
                let dist = x.runs.compactMap(\.distanceM).reduce(0, +)
                if dist > 0 { line += ", \(HXFormat.km(dist)) km" }
                if x.kind.isHyrox {
                    let rep = RaceAnalytics.report(x, benchmarks: s.benchmarks)
                    line += String(format: "; runs %@, stations %@, roxzone %@", HXFormat.duration(rep.runTotalS), HXFormat.duration(rep.stationTotalS), HXFormat.duration(rep.roxzoneTotalS))
                    if let cv = rep.pacingCV { line += String(format: ", pacing CV %.1f%%", cv * 100) }
                    if let worst = rep.stations.compactMap({ r in r.lostVsBestS.map { (r.station.title, $0) } }).max(by: { $0.1 < $1.1 }), worst.1 > 5 {
                        line += ", most time lost at \(worst.0) (+\(Int(worst.1)) s)"
                    }
                }
                out.append(line)
            }
        }
        let bests = Station.allCases.compactMap { st -> String? in
            s.benchmarks.bestStationS(st, loadKg: st.loadKg(format: p.format, sex: s.sex)).map { "\(st.shortTitle) \(HXFormat.duration($0))" }
        }
        if !bests.isEmpty { out.append("Station bests at \(p.format.title) loads: " + bests.joined(separator: ", ") + ".") }
        if let r1 = s.benchmarks.bestRun1kS { out.append("Best 1 km in a session: \(HXFormat.duration(r1.seconds)).") }
        if !s.runPBs.isEmpty { out.append("Run PBs: " + s.runPBs.map { "\($0.label) \(HXFormat.duration($0.seconds))" }.joined(separator: ", ") + ".") }
        for rr in s.raceReadiness {
            var line = "Race readiness \(rr.format.title): \(rr.verdict.title)"
            if let lo = rr.predictedLowS, let hi = rr.predictedHighS { line += " (predicted \(HXFormat.duration(lo))–\(HXFormat.duration(hi)))" }
            if !rr.gaps.isEmpty { line += "; gaps: " + rr.gaps.joined(separator: "; ") }
            out.append(line + ".")
        }
        let t = s.nutritionTargets()
        let food = s.todayFood()
        out.append(String(format: "Fuel today: targets %.0f kcal, %.0f g protein, %.0f g carbs, %.0f ml water. Logged so far: %.0f kcal, %.0f g protein in %d entries (unlogged is not zero).",
                          t.kcal, t.proteinG, t.carbsG, t.waterMl, food.compactMap(\.kcal).reduce(0, +), food.compactMap(\.proteinG).reduce(0, +), food.count))
        return out.joined(separator: "\n")
    }
}

// MARK: - Photo / text capture

/// Meal photo or class whiteboard → a structured draft from Claude → the athlete reviews and edits →
/// saved to the food log or as a NOOP workout. Nothing leaves the phone until "Analyse" is tapped.
struct HXCoachCaptureView: View {
    enum Mode { case meal, workout }
    let mode: Mode
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var store: HXStore
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var meal: MealDraft?
    @State private var workout: WorkoutDraft?

    struct MealDraft: Codable { var title: String; var kcal: Double?; var protein_g: Double?; var carbs_g: Double?; var fat_g: Double?; var confidence: String?; var notes: String? }
    struct WorkoutDraft: Codable { var title: String; var duration_min: Double?; var exercises: [String]?; var intensity: String?; var notes: String? }

    var body: some View {
        HXScreen(title: mode == .meal ? "Log a meal" : "Log a class", subtitle: mode == .meal ? "Photo or words → macros you can edit" : "Photo of the board → a workout record") {
            if !coach.isConfigured || coach.provider != .anthropic {
                HXCard(tint: HX.warn) { Text("Add your Anthropic key in Coach settings and pick Anthropic as the provider to analyse photos.").font(HX.body).foregroundStyle(HX.text) }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: HX.radius, style: .continuous).fill(HX.surface).frame(height: 200)
                    if let d = imageData, let ui = UIImage(data: d) {
                        Image(uiImage: ui).resizable().scaledToFill().frame(height: 200).clipShape(RoundedRectangle(cornerRadius: HX.radius, style: .continuous))
                    } else {
                        VStack(spacing: 6) { Image(systemName: "camera.fill").font(.title).foregroundStyle(HX.volt); Text("Choose a photo").font(HX.caption).foregroundStyle(HX.textDim) }
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in Task { imageData = try? await item?.loadTransferable(type: Data.self) } }
            TextField(mode == .meal ? "Or describe it: 2 eggs, toast, 300 ml milk" : "Or type it: 5 rounds 10 thrusters 40 kg, 200 m row…", text: $text, axis: .vertical)
                .lineLimit(2...4).padding().background(RoundedRectangle(cornerRadius: 16).fill(HX.surface)).foregroundStyle(HX.text)
            Button { Task { await analyse() } } label: { busy ? AnyView(ProgressView().tint(HX.ink)) : AnyView(Text("Analyse")) }
                .buttonStyle(HXPrimaryButtonStyle()).disabled(busy || (imageData == nil && text.isEmpty))
            if let error { Text(error).font(HX.caption).foregroundStyle(HX.bad) }
            if let m = meal { mealForm(m) }
            if let w = workout { workoutForm(w) }
        }
    }

    private func mealForm(_ m: MealDraft) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                HXOverline("Draft — edit before saving")
                field("Title", Binding(get: { meal?.title ?? "" }, set: { meal?.title = $0 }))
                HStack {
                    numField("kcal", Binding(get: { meal?.kcal }, set: { meal?.kcal = $0 }))
                    numField("protein g", Binding(get: { meal?.protein_g }, set: { meal?.protein_g = $0 }))
                }
                HStack {
                    numField("carbs g", Binding(get: { meal?.carbs_g }, set: { meal?.carbs_g = $0 }))
                    numField("fat g", Binding(get: { meal?.fat_g }, set: { meal?.fat_g = $0 }))
                }
                if let n = m.notes { Text(n).font(HX.caption).foregroundStyle(HX.textDim) }
                Text("A photo cannot see oil, sugar or portion weight; these are estimates until you correct them.").font(HX.caption).foregroundStyle(HX.textDim)
                Button("Save to food log") {
                    store.food.append(HXFoodEntry(at: Date(), title: m.title, kcal: meal?.kcal, proteinG: meal?.protein_g, carbsG: meal?.carbs_g, fatG: meal?.fat_g, provenance: .reviewed, note: m.notes))
                    dismiss()
                }.buttonStyle(HXGhostButtonStyle())
            }
        }
    }

    private func workoutForm(_ w: WorkoutDraft) -> some View {
        HXCard {
            VStack(alignment: .leading, spacing: 10) {
                HXOverline("Draft — confirm you actually did this")
                field("Title", Binding(get: { workout?.title ?? "" }, set: { workout?.title = $0 }))
                numField("duration min", Binding(get: { workout?.duration_min }, set: { workout?.duration_min = $0 }))
                if let ex = w.exercises, !ex.isEmpty { Text(ex.joined(separator: " · ")).font(HX.caption).foregroundStyle(HX.textDim) }
                Button("Save as today's class") {
                    let mins = workout?.duration_min ?? 50
                    let end = Date(), start = end.addingTimeInterval(-mins * 60)
                    let row = WorkoutRow(startTs: Int(start.timeIntervalSince1970), endTs: Int(end.timeIntervalSince1970), sport: "HIIT", source: "manual",
                                         durationS: mins * 60, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil, zonesJSON: nil,
                                         notes: "\(workout?.title ?? "Class") — \((w.exercises ?? []).joined(separator: ", "))", steps: nil)
                    Task { await repo.saveManualWorkout(row) }
                    if let p = store.plan.first(where: { Calendar.current.isDateInToday($0.date) && $0.type == .gymClass }),
                       let i = store.plan.firstIndex(where: { $0.id == p.id }) { store.plan[i].completedSessionID = UUID() }
                    dismiss()
                }.buttonStyle(HXGhostButtonStyle())
            }
        }
    }

    private func field(_ label: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) { HXOverline(label); TextField(label, text: b).foregroundStyle(HX.text) }
    }
    private func numField(_ label: String, _ b: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HXOverline(label)
            TextField(label, value: b, format: .number).keyboardType(.decimalPad).foregroundStyle(HX.text)
        }
    }

    // MARK: Request

    private func analyse() async {
        busy = true; error = nil; defer { busy = false }
        guard let key = AIKeyStore.read(), coach.provider == .anthropic else { error = "Anthropic key not configured."; return }
        let schema = mode == .meal
            ? #"{"title": string, "kcal": number|null, "protein_g": number|null, "carbs_g": number|null, "fat_g": number|null, "confidence": "low"|"medium"|"high", "notes": string}"#
            : #"{"title": string, "duration_min": number|null, "exercises": [string], "intensity": "easy"|"moderate"|"hard"|null, "notes": string}"#
        let instruction = (mode == .meal
            ? "Estimate this meal's nutrition. Give null for anything you cannot see; do not invent portion sizes. "
            : "Transcribe this gym class whiteboard into a workout. Do not assume the athlete did every line; list exercises as written. ")
            + "Reply with ONLY a JSON object matching: \(schema)"
        var content: [[String: Any]] = []
        if let d = imageData, let ui = UIImage(data: d), let jpeg = ui.resized(maxSide: 1280).jpegData(compressionQuality: 0.7) {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": instruction + (text.isEmpty ? "" : "\nAthlete's note: \(text)")])
        let body: [String: Any] = ["model": coach.model, "max_tokens": 600, "messages": [["role": "user", "content": content]]]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                error = "Request failed (\((resp as? HTTPURLResponse)?.statusCode ?? 0))."; return
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blocks = json["content"] as? [[String: Any]],
                  let textOut = blocks.compactMap({ $0["text"] as? String }).first,
                  let start = textOut.firstIndex(of: "{"), let end = textOut.lastIndex(of: "}") else { error = "No JSON in the reply."; return }
            let jsonData = Data(textOut[start...end].utf8)
            if mode == .meal { meal = try JSONDecoder().decode(MealDraft.self, from: jsonData) }
            else { workout = try JSONDecoder().decode(WorkoutDraft.self, from: jsonData) }
        } catch { self.error = error.localizedDescription }
    }
}

private extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
