import SwiftUI
import LumaCore
import LumaKit
#if canImport(UIKit)
import UIKit
#endif

/// Something the coach did, shown under its reply.
enum CoachCard: Equatable, Codable, Identifiable {
    case chart(metric: String, days: Int)
    case logged(entryIDs: [UUID])
    case planned(sessionIDs: [UUID])
    case note(String)
    case done(String)

    var id: String {
        switch self {
        case .chart(let m, let d): return "chart-\(m)-\(d)"
        case .logged(let ids): return "logged-" + ids.map { $0.uuidString }.joined()
        case .planned(let ids): return "planned-" + ids.map { $0.uuidString }.joined()
        case .note(let s): return "note-\(s)"
        case .done(let s): return "done-\(s)"
        }
    }
}

struct CoachMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    var role: Role
    var text: String
    /// File names of attached photos (kept beside the conversation).
    var photos: [String] = []
    var cards: [CoachCard] = []
    var date = Date()
    var failed = false
}

enum CoachError: LocalizedError {
    case noKey
    case api(status: Int, message: String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add your Anthropic API key to use the coach."
        case .api(let status, let message):
            switch status {
            case 401, 403: return "The API key was rejected. Check it in Coach settings."
            case 429: return "The coach is being rate-limited. Wait a minute and try again."
            case 529, 503: return "The AI service is overloaded right now. Try again shortly."
            default: return message.isEmpty ? "The AI service returned an error (\(status))." : message
            }
        case .message(let m): return m
        }
    }
}

/// Luma's coach: a streaming, tool-using conversation with the athlete's AI provider, plus the
/// one-shot reads that turn photos and text into log entries. All data access goes through the tools
/// in LumaCore; nothing is sent unless the athlete has added a key, and health data only with consent.
@MainActor
public final class CoachEngine: ObservableObject {
    @Published private(set) var messages: [CoachMessage] = []
    @Published private(set) var working = false
    /// What the coach is doing right now ("Reading your sleep"), while a turn runs.
    @Published private(set) var activity: String?
    @Published private(set) var models: [AIModel] = []
    @Published private(set) var notes: [String] = []
    @Published private(set) var brief: String?
    @Published private(set) var briefDay: String?
    @Published private(set) var briefLoading = false

    private unowned let env: LumaEnv
    private var task: Task<Void, Never>?
    private let session: URLSession

    nonisolated static let maxSteps = 12
    nonisolated static let maxPhotos = 8

    init(env: LumaEnv) {
        self.env = env
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
        messages = env.disk.load([CoachMessage].self, "coach-thread.json") ?? []
        notes = env.disk.load([String].self, "coach-notes.json") ?? []
        if let saved = env.disk.load([String].self, "coach-brief.json"), saved.count == 2 { briefDay = saved[0]; brief = saved[1] }
    }

    /// The gallery's stand-in conversation, so the design can be judged without a key or a network.
    func seedDemo() {
        guard env.isDemo, hasKey, messages.isEmpty else { return }
        let today = LumaAnalysis.todayKey()
        briefDay = today
        // Written from the demo's own numbers, so the card never contradicts the screen it sits on.
        let a = env.analysis
        var opening = a.call.title + "."
        if let night = a.lastNight, let r = night.recovery {
            opening = "Recovery is \(Int(r.rounded()))%" + (night.sleepMin.map { " after \(LFormat.hm(minutes: $0)) of sleep." } ?? ".")
        }
        brief = opening + " " + a.call.body + " Eat to your carbohydrate target around training and aim for lights out by 22:30."
        let lunch = env.fuel.last { $0.kind == .meal && $0.source == .photo }
        let coachPlan = env.planned.filter { $0.origin == .coach && $0.day >= today }.prefix(2).map { $0.id }
        messages = [
            CoachMessage(role: .user, text: "What is moving my recovery up or down?"),
            CoachMessage(role: .assistant, text: "Three things stand out in your last 60 days:\n\n- **Alcohol** is the clearest drag: nights after a drink score about 11 points lower, mostly through a higher resting heart rate.\n- **Late sessions** cost you around 25 minutes of sleep; your 06:30 classes do not.\n- **HRV** is trending up, about 4 ms over six weeks, which fits the steadier training load.\n\nHere is the HRV trend against your normal range.",
                         cards: [.chart(metric: LMetric.hrv.rawValue, days: 30)]),
            CoachMessage(role: .user, text: "Log my lunch from the photo and plan the rest of the week around my classes."),
            CoachMessage(role: .assistant, text: "Lunch is logged; you are at 96 g of protein, so a 40 g serving this evening gets you to target.\n\nFor the week I kept your classes as they are and added two sessions that fit around them.",
                         cards: [.logged(entryIDs: lunch.map { [$0.id] } ?? []), .planned(sessionIDs: Array(coachPlan)), .note("Prefers morning sessions on weekdays")]),
        ]
    }

    var hasKey: Bool { !(env.secrets.coachKey() ?? "").isEmpty }

    // MARK: World

    func world() -> CoachWorld {
        CoachWorld(today: env.today, now: Date(), profile: env.profile, days: env.days, workouts: env.workouts, analysis: env.analysis,
                   planned: env.planned, routine: env.routine, fuel: env.fuel, supplements: env.supplements, checkIns: env.checkIns,
                   lifts: env.lifts, sessions: env.sessions, benchmarks: env.benchmarks, personalBests: env.runPBs, notes: notes,
                   shareHealth: env.profile.shareHealthWithCoach)
    }

    // MARK: Conversation

    func newChat() {
        task?.cancel()
        working = false
        activity = nil
        for m in messages { for p in m.photos { env.disk.remove(p) } }
        messages = []
        persist()
    }

    func stop() {
        task?.cancel()
        working = false
        activity = nil
    }

    func forget(_ note: String) {
        notes.removeAll { $0 == note }
        env.disk.save(notes, "coach-notes.json")
    }

    /// Sends a message with optional photos and runs the tool loop until the coach has answered.
    func send(_ text: String, photos: [Data] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working, !(trimmed.isEmpty && photos.isEmpty) else { return }
        let prepared = photos.prefix(CoachEngine.maxPhotos).compactMap { CoachEngine.prepare($0) }
        let names = prepared.map { env.savePhoto($0) }
        let history = apiHistory()
        messages.append(CoachMessage(role: .user, text: trimmed, photos: names))
        messages.append(CoachMessage(role: .assistant, text: ""))
        let replyID = messages[messages.count - 1].id
        working = true
        activity = "Thinking"
        let photoPhrase = prepared.count == 1 ? "is a photo" : "are \(prepared.count) photos"
        let userText = trimmed.isEmpty ? "Here \(photoPhrase). Work out what it shows and act on it." : trimmed
        let images = prepared.map { (base64: $0.base64EncodedString(), mediaType: "image/jpeg") }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.run(history: history + [AIMessage.user(userText, images: images)], replyID: replyID)
            } catch is CancellationError {
                self.update(replyID) { if $0.text.isEmpty { $0.text = "Stopped." } }
            } catch {
                if Task.isCancelled {
                    self.update(replyID) { if $0.text.isEmpty { $0.text = "Stopped." } }
                } else {
                    let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.update(replyID) { $0.failed = true; $0.text = $0.text.isEmpty ? text : $0.text + "\n\n" + text }
                }
            }
            self.working = false
            self.activity = nil
            self.persist()
        }
    }

    /// Earlier turns as plain text. Tool calls and thinking from finished turns are not replayed: the
    /// API only needs them inside the turn that is still running.
    private func apiHistory() -> [AIMessage] {
        var out: [AIMessage] = []
        for m in messages.suffix(24) where !(m.text.isEmpty && m.photos.isEmpty) && !m.failed {
            var text = m.text
            if !m.photos.isEmpty { text += (text.isEmpty ? "" : "\n") + "[\(m.photos.count) photo\(m.photos.count == 1 ? "" : "s") attached earlier]" }
            for card in m.cards {
                if case .logged(let ids) = card { text += "\n[Logged \(ids.count) entr\(ids.count == 1 ? "y" : "ies") to the food log]" }
                if case .planned(let ids) = card { text += "\n[Put \(ids.count) session\(ids.count == 1 ? "" : "s") on the calendar]" }
            }
            if text.isEmpty { continue }
            // The API needs alternating roles starting with the user.
            let role = m.role == .user ? "user" : "assistant"
            if let last = out.last, last.role == role {
                out[out.count - 1].content.append(AIBlock.text(text))
            } else if out.isEmpty && role == "assistant" {
                continue
            } else {
                out.append(AIMessage(role: role, content: [AIBlock.text(text)]))
            }
        }
        if out.last?.role == "user" { out.removeLast() }
        return out
    }

    private func run(history: [AIMessage], replyID: UUID) async throws {
        guard let key = env.secrets.coachKey(), !key.isEmpty else { throw CoachError.noKey }
        let model = try await resolveModel(key: key)
        var convo = history
        for _ in 0..<CoachEngine.maxSteps {
            try Task.checkCancellation()
            let request = AIRequest(model: model, system: CoachPrompt.system(world: world()), messages: convo, tools: CoachTools.all)
            let acc = try await stream(request, key: key) { [weak self] update in
                guard let self else { return }
                switch update {
                case .text(let t):
                    self.activity = nil
                    self.update(replyID) { $0.text += t }
                case .toolStarted(let name):
                    self.activity = CoachTools.activity(name)
                case .error:
                    break
                }
            }
            if let message = acc.errorMessage { throw CoachError.message(message) }
            convo.append(acc.assistantMessage)
            let calls = acc.toolCalls
            if !calls.isEmpty {
                var results: [JSONValue] = []
                for call in calls {
                    activity = CoachTools.activity(call.name)
                    let outcome = apply(call)
                    if let card = outcome.card { update(replyID) { if !$0.cards.contains(card) { $0.cards.append(card) } } }
                    results.append(AIBlock.toolResult(id: call.id, content: outcome.result, isError: outcome.isError))
                }
                convo.append(AIMessage(role: "user", content: results))
                update(replyID) { if !$0.text.isEmpty, !$0.text.hasSuffix("\n\n") { $0.text += "\n\n" } }
                activity = "Thinking"
                continue
            }
            if acc.stopReason == "pause_turn" { continue }
            if acc.stopReason == "max_tokens" { update(replyID) { $0.text += "\n\n(The reply was cut short. Ask me to continue.)" } }
            if acc.stopReason == "refusal", acc.text.isEmpty { update(replyID) { $0.text = "I can't help with that request." } }
            break
        }
        update(replyID) { $0.text = $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func update(_ id: UUID, _ change: (inout CoachMessage) -> Void) {
        guard let i = messages.lastIndex(where: { $0.id == id }) else { return }
        change(&messages[i])
    }

    private func persist() {
        env.disk.save(Array(messages.suffix(80)), "coach-thread.json")
    }

    // MARK: Tools

    private struct Outcome {
        var result: String
        var isError = false
        var card: CoachCard?
    }

    private func apply(_ call: AIStreamAccumulator.ToolCall) -> Outcome {
        let w = world()
        if let read = CoachTools.read(call.name, input: call.input, world: w) {
            return Outcome(result: String(read.text.prefix(60_000)))
        }
        guard let parsed = CoachTools.command(call.name, input: call.input, world: w) else {
            return Outcome(result: "Unknown tool \(call.name).", isError: true)
        }
        switch parsed {
        case .failure(let e):
            return Outcome(result: e.message, isError: true)
        case .success(let command):
            return perform(command)
        }
    }

    private func perform(_ command: CoachCommand) -> Outcome {
        switch command {
        case .logFuel(let entries):
            for e in entries { env.log(e) }
            let day = entries.first?.day ?? env.today
            let t = env.fuelTotals(on: day), target = env.fuelTargets(on: day)
            let summary = String(format: "Logged %d entr%@. Totals for %@: %.0f of %.0f kcal, protein %.0f of %.0f g, carbs %.0f of %.0f g, fat %.0f g, water %.0f of %.0f ml.",
                                 entries.count, entries.count == 1 ? "y" : "ies", day, t.kcal, target.kcal, t.proteinG, target.proteinG, t.carbsG, target.carbsG,
                                 t.fatG, t.waterMl, target.waterMl)
            return Outcome(result: summary, card: .logged(entryIDs: entries.map { $0.id }))
        case .plan(let sessions, let from, let to):
            if let from, let to {
                for p in env.planned where p.origin == .coach && p.status == .planned && p.day >= from && p.day <= to { env.remove(p) }
            }
            for s in sessions { env.upsert(s) }
            let list = sessions.map { "\($0.day) \($0.title) (id \($0.id.uuidString))" }.joined(separator: "; ")
            return Outcome(result: "Planned \(sessions.count) session\(sessions.count == 1 ? "" : "s"): \(list)", card: .planned(sessionIDs: sessions.map { $0.id }))
        case .updateSession(let p):
            env.upsert(p)
            return Outcome(result: "Updated \(p.title) on \(p.day).", card: .planned(sessionIDs: [p.id]))
        case .removeSession(let id):
            guard let p = env.planned.first(where: { $0.id == id }) else { return Outcome(result: "That session no longer exists.", isError: true) }
            env.remove(p)
            return Outcome(result: "Removed \(p.title) on \(p.day).", card: .done("Removed \(p.title) on \(LumaText.shortDay(p.day))"))
        case .setRoutine(let slots):
            env.setRoutine(slots)
            return Outcome(result: "Weekly routine set with \(slots.count) standing session\(slots.count == 1 ? "" : "s").", card: .done("Weekly routine updated"))
        case .checkIn(let c):
            env.save(c)
            return Outcome(result: "Check-in saved for \(c.day).", card: .done("Check-in saved for \(LumaText.shortDay(c.day))"))
        case .remember(let fact):
            if !notes.contains(fact) { notes.append(fact); env.disk.save(notes, "coach-notes.json") }
            return Outcome(result: "Noted.", card: .note(fact))
        case .logWorkout(let workout):
            env.saveWorkout(workout)
            return Outcome(result: "Logged \(workout.sport), \(Int(workout.durationS / 60)) min on \(workout.day).", card: .done("Logged \(workout.sport), \(Int(workout.durationS / 60)) min"))
        case .logStrength(let s):
            env.save(s)
            return Outcome(result: "Logged \(s.title) on \(s.day) with \(s.exercises.count) movements.", card: .done("Logged \(s.title)"))
        case .updateProfile(let p):
            env.profile = p
            return Outcome(result: "Profile updated.", card: .done("Profile updated"))
        case .showChart(let metric, let days):
            return Outcome(result: "The chart of \(metric.title) for the last \(days) days is now shown to the athlete.", card: .chart(metric: metric.rawValue, days: days))
        }
    }

    /// Reverses a logging action from a card.
    func undo(_ card: CoachCard, in messageID: UUID) {
        switch card {
        case .logged(let ids):
            for e in env.fuel where ids.contains(e.id) { env.delete(e) }
        case .planned(let ids):
            for p in env.planned where ids.contains(p.id) { env.remove(p) }
        default:
            return
        }
        update(messageID) { $0.cards.removeAll { $0 == card }; $0.cards.append(.done("Undone")) }
        persist()
    }

    // MARK: Transport

    private func makeRequest(_ body: Data, key: String, url: String = AIRequest.endpoint) -> URLRequest {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(AIRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = body
        return req
    }

    private static func apiError(status: Int, data: Data) -> CoachError {
        let message = (String(data: data, encoding: .utf8).flatMap { JSONValue.parse($0) })?["error"]?["message"]?.string ?? ""
        return .api(status: status, message: message)
    }

    private func stream(_ request: AIRequest, key: String, onUpdate: @escaping (AIStreamUpdate) -> Void) async throws -> AIStreamAccumulator {
        var attempt = 0
        while true {
            attempt += 1
            let (bytes, response) = try await session.bytes(for: makeRequest(request.bodyData(), key: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                var data = Data()
                for try await b in bytes { data.append(b); if data.count > 20_000 { break } }
                if (status == 529 || status == 503 || status == 500) && attempt < 3 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                    continue
                }
                throw CoachEngine.apiError(status: status, data: data)
            }
            var acc = AIStreamAccumulator()
            for try await line in bytes.lines {
                try Task.checkCancellation()
                for u in acc.consume(line: line) { onUpdate(u) }
            }
            return acc
        }
    }

    private func complete(_ request: AIRequest, key: String) async throws -> AIStreamAccumulator {
        var r = request
        r.stream = false
        let (data, response) = try await session.data(for: makeRequest(r.bodyData(), key: key))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CoachEngine.apiError(status: status, data: data) }
        guard let json = String(data: data, encoding: .utf8).flatMap({ JSONValue.parse($0) }) else { throw CoachError.message("The reply could not be read.") }
        return AIStreamAccumulator(response: json)
    }

    // MARK: Models

    /// The model to use: the athlete's choice if it is still offered, otherwise the newest Sonnet-line model.
    private func resolveModel(key: String) async throws -> String {
        if models.isEmpty { try? await loadModels() }
        if let chosen = env.profile.coachModel, models.isEmpty || models.contains(where: { $0.id == chosen }) { return chosen }
        if let preferred = AIModel.preferred(models) { return preferred.id }
        throw CoachError.message("Could not get the list of models for this key. Check the key and your connection.")
    }

    func loadModels() async throws {
        guard let key = env.secrets.coachKey(), !key.isEmpty else { throw CoachError.noKey }
        var req = URLRequest(url: URL(string: AIRequest.modelsEndpoint)!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue(AIRequest.apiVersion, forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CoachEngine.apiError(status: status, data: data) }
        guard let json = String(data: data, encoding: .utf8).flatMap({ JSONValue.parse($0) }) else { return }
        models = AIModel.list(from: json)
    }

    /// Checks a key by listing models with it. Saves it only when the service accepts it.
    func connect(key: String) async throws {
        let old = env.secrets.coachKey()
        env.secrets.setCoachKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try await loadModels()
        } catch {
            env.secrets.setCoachKey(old)
            throw error
        }
        objectWillChange.send()
    }

    func disconnect() {
        env.secrets.setCoachKey(nil)
        models = []
        objectWillChange.send()
    }

    // MARK: One-shot reads

    /// Reads photos and/or a description into a food entry for the athlete to review. Nothing is saved.
    func readFood(text: String, photos: [Data]) async throws -> FuelEntry {
        let acc = try await extract(kind: "photos and descriptions of meals, drinks and nutrition labels", tool: CoachTools.foodTool(name: "submit_food"),
                                    text: text.isEmpty ? "Log what these photos show." : text, photos: photos)
        guard let call = acc.toolCalls.first(where: { $0.name == "submit_food" }) else {
            throw CoachError.message(acc.text.isEmpty ? "Nothing readable was found. Try a clearer photo or describe the meal." : acc.text)
        }
        switch CoachTools.foodEntry(call.input, world: world()) {
        case .success(var entry):
            if !photos.isEmpty && entry.source == .coach { entry.source = .photo }
            if photos.isEmpty { entry.source = .typed }
            return entry
        case .failure(let e):
            throw CoachError.message(e.message)
        }
    }

    /// Reads supplement photos and/or a description into doses for the athlete to review.
    func readSupplements(text: String, photos: [Data]) async throws -> [SupplementDose] {
        let acc = try await extract(kind: "photos and descriptions of supplements, tablets and their labels", tool: CoachTools.supplementTool(name: "submit_supplements"),
                                    text: text.isEmpty ? "Log the supplements these photos show." : text, photos: photos)
        guard let call = acc.toolCalls.first(where: { $0.name == "submit_supplements" }) else {
            throw CoachError.message(acc.text.isEmpty ? "No supplement could be read. Try a photo of the facts panel or type the name and dose." : acc.text)
        }
        switch CoachTools.supplementEntries(call.input, world: world()) {
        case .success(let entries): return entries.compactMap { $0.supplement }
        case .failure(let e): throw CoachError.message(e.message)
        }
    }

    /// Reads photos and/or a note of training sessions into sessions for the athlete to review, each
    /// with the positions (1 is the first) of the photos it was read from. `day` is the day a session
    /// is filed under when nothing in the photo or note says which day it was.
    func readWorkouts(text: String, photos: [Data], day: String) async throws -> [(session: LiftSession, photos: [Int])] {
        let w = world()
        let nothing = "No workout could be read. Try a clearer photo, or type what you did."
        let acc = try await extract(system: CoachPrompt.workoutExtraction(today: w.today, sex: w.profile.sex),
                                    tool: CoachTools.workoutsTool(name: "submit_workouts"),
                                    text: text.isEmpty ? "Log the training sessions these photos show." : text, photos: photos, maxTokens: 8192)
        // An answer cut off at the length limit holds half a session; better none than that.
        if acc.stopReason == "max_tokens" { throw CoachError.message("That was too much to read in one go. Try fewer photos at a time.") }
        guard let call = acc.toolCalls.first(where: { $0.name == "submit_workouts" }) else {
            throw CoachError.message(acc.text.isEmpty ? nothing : acc.text)
        }
        let read = CoachTools.loggedSessions(call.input, day: day, now: Date())
        if read.isEmpty { throw CoachError.message(nothing) }
        return read
    }

    private func extract(kind: String, tool: AITool, text: String, photos: [Data]) async throws -> AIStreamAccumulator {
        try await extract(system: CoachPrompt.extraction(kind: kind), tool: tool, text: text, photos: photos, maxTokens: 4096)
    }

    private func extract(system: String, tool: AITool, text: String, photos: [Data], maxTokens: Int) async throws -> AIStreamAccumulator {
        guard let key = env.secrets.coachKey(), !key.isEmpty else { throw CoachError.noKey }
        let model = try await resolveModel(key: key)
        let images = photos.prefix(CoachEngine.maxPhotos).compactMap { CoachEngine.prepare($0) }.map { (base64: $0.base64EncodedString(), mediaType: "image/jpeg") }
        let request = AIRequest(model: model, system: system, messages: [AIMessage.user(text, images: images)],
                                tools: [tool], maxTokens: maxTokens, stream: false)
        return try await complete(request, key: key)
    }

    /// A short morning read of the day. Written once per day and kept.
    func loadBrief(force: Bool = false) async {
        guard !env.isDemo, env.profile.morningBrief else { return }
        let day = env.today
        guard hasKey, env.profile.shareHealthWithCoach, !briefLoading, env.analysis.lastNight?.day == day else { return }
        if briefDay == day, brief != nil, !force { return }
        briefLoading = true
        defer { briefLoading = false }
        guard let key = env.secrets.coachKey(), let model = try? await resolveModel(key: key) else { return }
        let w = world()
        let ask = """
        Write this morning's brief from the data below. Three or four short sentences, plain text, no greeting, no list: how recovered they are and the main reason, what today's training should look like given the plan and the load, and one concrete thing to do for sleep or fuelling. Use their numbers.

        \(CoachTools.overview(w).text)
        """
        let request = AIRequest(model: model, system: CoachPrompt.system(world: w), messages: [AIMessage.user(ask)], maxTokens: 2048, stream: false)
        guard let acc = try? await complete(request, key: key) else { return }
        let text = acc.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        brief = text
        briefDay = day
        env.disk.save([day, text], "coach-brief.json")
    }

    // MARK: Photos

    /// Downscales to at most 1568 px on the long edge and re-encodes as JPEG, which is what the API
    /// reads best and keeps requests small.
    nonisolated static func prepare(_ data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        let scale = min(1, 1568 / max(1, longest))
        let size = CGSize(width: (image.size.width * image.scale * scale).rounded(), height: (image.size.height * image.scale * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.8)
        #else
        return data
        #endif
    }
}
