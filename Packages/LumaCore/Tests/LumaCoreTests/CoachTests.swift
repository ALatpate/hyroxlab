import XCTest
@testable import LumaCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

final class AIWireTests: XCTestCase {
    func testJSONValueRoundTripsAndKeepsUnknownFields() {
        let raw = #"{"type":"thinking","thinking":"abc","signature":"sig==","extra":{"n":1.5,"ok":true,"list":[1,"two",null]}}"#
        let v = JSONValue.parse(raw)!
        XCTAssertEqual(v["signature"]?.string, "sig==")
        XCTAssertEqual(v["extra"]?["n"]?.number, 1.5)
        XCTAssertEqual(v["extra"]?["ok"]?.bool, true)
        XCTAssertEqual(v["extra"]?["list"]?.array?.count, 3)
        XCTAssertEqual(JSONValue.parse(v.text), v)
        // Whole numbers are written without a decimal point.
        XCTAssertEqual(JSONValue.number(42).text, "42")
        XCTAssertEqual(JSONValue.string("12.5").number, 12.5)
    }

    func testRequestBodyShape() {
        let tool = AITool(name: "log_water", description: "d", properties: ["ml": AISchema.number("ml")], required: ["ml"])
        let req = AIRequest(model: "m", system: "sys", messages: [.user("hi", images: [(base64: "QUJD", mediaType: "image/jpeg")])], tools: [tool])
        let b = req.body()
        XCTAssertEqual(b["model"]?.string, "m")
        XCTAssertEqual(b["stream"]?.bool, true)
        XCTAssertNil(b["temperature"])
        XCTAssertNil(b["tool_choice"])
        XCTAssertEqual(b["system"]?.array?.first?["cache_control"]?["type"]?.string, "ephemeral")
        let content = b["messages"]?.array?.first?["content"]?.array
        XCTAssertEqual(content?.first?["type"]?.string, "image")
        XCTAssertEqual(content?.first?["source"]?["media_type"]?.string, "image/jpeg")
        XCTAssertEqual(content?.last?["text"]?.string, "hi")
        XCTAssertEqual(b["tools"]?.array?.first?["input_schema"]?["required"]?.array?.first?.string, "ml")
    }

    func testStreamAccumulatorRebuildsThinkingTextAndToolCalls() {
        var acc = AIStreamAccumulator()
        var updates: [AIStreamUpdate] = []
        let lines = [
            #"event: message_start"#,
            #"data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","content":[],"usage":{"input_tokens":25,"output_tokens":1}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Check today."}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqQB"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type": "ping"}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Let me "}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"look."}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_01","name":"get_daily_metrics","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"start_date\": \"2026-1"}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"1-01\"}"}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":89}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        for l in lines { updates += acc.consume(line: l) }
        XCTAssertEqual(updates, [.text("Let me "), .text("look."), .toolStarted(name: "get_daily_metrics")])
        XCTAssertEqual(acc.text, "Let me look.")
        XCTAssertEqual(acc.stopReason, "tool_use")
        XCTAssertEqual(acc.inputTokens, 25)
        XCTAssertEqual(acc.outputTokens, 89)
        XCTAssertEqual(acc.toolCalls, [.init(id: "toolu_01", name: "get_daily_metrics", input: ["start_date": "2026-11-01"])])
        // The assistant turn goes back with the thinking block and its signature intact.
        let back = acc.assistantMessage
        XCTAssertEqual(back.content.count, 3)
        XCTAssertEqual(back.content[0]["thinking"]?.string, "Check today.")
        XCTAssertEqual(back.content[0]["signature"]?.string, "EqQB")
        XCTAssertEqual(back.content[2]["input"]?["start_date"]?.string, "2026-11-01")
    }

    func testStreamErrorAndToolWithNoArguments() {
        var acc = AIStreamAccumulator()
        XCTAssertEqual(acc.consume(line: #"data: {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}"#), [.error("Overloaded")])
        XCTAssertEqual(acc.errorMessage, "Overloaded")
        var b = AIStreamAccumulator()
        _ = b.consume(line: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"get_overview","input":{}}}"#)
        _ = b.consume(line: #"data: {"type":"content_block_stop","index":0}"#)
        XCTAssertEqual(b.toolCalls.first?.input, .object([:]))
    }

    func testModelListPrefersNewestSonnet() {
        let resp = JSONValue.parse(#"{"data":[{"id":"claude-opus-5-5","display_name":"Claude Opus 5.5","lifecycle":"active","line":"opus","capabilities":{"image_input":{"supported":true}}},{"id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5","lifecycle":"active","line":"sonnet","capabilities":{"image_input":{"supported":true}}},{"id":"claude-old","display_name":"Old","lifecycle":"deprecated","line":"sonnet"}],"has_more":false}"#)!
        let models = AIModel.list(from: resp)
        XCTAssertEqual(models.map { $0.id }, ["claude-opus-5-5", "claude-sonnet-5-5"])
        XCTAssertEqual(AIModel.preferred(models)?.id, "claude-sonnet-5-5")
    }
}

final class CoachToolTests: XCTestCase {
    private let cal = utc()
    private let now = Date(timeIntervalSince1970: 1_794_657_600 + 3 * 3600)

    private func world(share: Bool = true) -> CoachWorld {
        let demo = LumaDemoSource(dayCount: 120, today: now, calendar: cal)
        let profile = LumaDemoContent.profile()
        let planned = LumaDemoContent.planned(today: demo.today)
        let a = LumaAnalysis.build(days: demo.days, sleeps: demo.sleeps, workouts: demo.workouts, profile: profile, planned: planned,
                                   checkIns: demo.checkIns, today: demo.today, now: now, calendar: cal)
        return CoachWorld(today: demo.today, now: now, profile: profile, days: demo.days, workouts: demo.workouts, analysis: a,
                          planned: planned, routine: LumaDemoContent.routine(), fuel: LumaDemoContent.fuel(today: now, calendar: cal),
                          supplements: LumaDemoContent.supplements(), checkIns: demo.checkIns, lifts: LumaDemoContent.lifts(today: now),
                          sessions: [], benchmarks: Benchmarks(), personalBests: [PersonalBest(distanceM: 5000, seconds: 1480)],
                          notes: ["Left knee gets sore on long descents."], shareHealth: share)
    }

    func testEveryToolHasAUniqueNameAndAnObjectSchema() {
        let names = CoachTools.all.map { $0.name }
        XCTAssertEqual(Set(names).count, names.count)
        for t in CoachTools.all {
            XCTAssertEqual(t.inputSchema["type"]?.string, "object", t.name)
            XCTAssertFalse(t.description.isEmpty)
        }
        XCTAssertTrue(CoachTools.readNames.isSubset(of: Set(names)))
    }

    func testReadToolsReturnData() {
        let w = world()
        for name in CoachTools.readNames.sorted() {
            let out = CoachTools.read(name, input: ["start_date": .string(LDate.adding(-13, to: w.today, calendar: cal))], world: w, calendar: cal)
            XCTAssertNotNil(out, name)
            XCTAssertNil(out?["error"], name)
            XCTAssertGreaterThan(out!.text.count, 20, name)
        }
        let metrics = CoachTools.read("get_daily_metrics", input: ["start_date": .string(LDate.adding(-6, to: w.today, calendar: cal))], world: w, calendar: cal)!
        XCTAssertEqual(metrics["rows"]?.array?.count, 7)
        XCTAssertEqual(metrics["columns"]?.array?.first?.string, "date")
        let overview = CoachTools.read("get_overview", input: .object([:]), world: w, calendar: cal)!
        XCTAssertEqual(overview["date"]?.string, w.today)
        XCTAssertNotNil(overview["recovery"]?["score_pct"]?.number)
        XCTAssertNil(CoachTools.read("log_food", input: .object([:]), world: w, calendar: cal))
    }

    func testReadToolsAreClosedWithoutConsent() {
        let out = CoachTools.read("get_overview", input: .object([:]), world: world(share: false), calendar: cal)
        XCTAssertNotNil(out?["error"])
        XCTAssertTrue(CoachPrompt.system(world: world(share: false), calendar: cal).contains("has not enabled sharing"))
    }

    func testFoodAndSupplementCommands() throws {
        let w = world()
        let input = JSONValue.parse(#"{"title":"Chicken and rice","kind":"meal","time":"13:05","source":"photo","note":"assumed 1 tbsp oil","items":[{"name":"Chicken thigh","quantity":"180 g","kcal":330,"protein_g":42,"carbs_g":0,"fat_g":17},{"name":"Rice","quantity":"220 g","kcal":"290","protein_g":6,"carbs_g":63,"fat_g":1}]}"#)!
        guard case .success(.logFuel(let entries))? = CoachTools.command("log_food", input: input, world: w, calendar: cal) else { return XCTFail("no command") }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kcal, 620)
        XCTAssertEqual(entries[0].proteinG, 48)
        XCTAssertEqual(entries[0].source, .photo)
        XCTAssertEqual(entries[0].day, w.today)
        XCTAssertEqual(cal.component(.hour, from: entries[0].at), 13)

        let supp = JSONValue.parse(#"{"supplements":[{"name":"Vitamin D3","amount":2000,"unit":"IU"},{"name":"Omega-3","amount":2,"unit":"capsule"}]}"#)!
        guard case .success(.logFuel(let s))? = CoachTools.command("log_supplement", input: supp, world: w, calendar: cal) else { return XCTFail("no command") }
        XCTAssertEqual(s.map { $0.supplement?.text }, ["2000 IU", "2 capsules"])
        XCTAssertTrue(s.allSatisfy { $0.kind == .supplement })

        // An empty meal is rejected with a message the model can act on.
        guard case .failure(let e)? = CoachTools.command("log_food", input: ["title": "x", "items": []], world: w, calendar: cal) else { return XCTFail("expected failure") }
        XCTAssertTrue(e.message.contains("item"))
        XCTAssertNil(CoachTools.command("get_overview", input: .object([:]), world: w, calendar: cal))
    }

    func testPlanningCommands() {
        let w = world()
        let tomorrow = LDate.adding(1, to: w.today, calendar: cal)
        let input: JSONValue = ["sessions": [["date": .string(tomorrow), "kind": "tempoRun", "title": "Tempo 3 × 8 min", "duration_min": 50,
                                              "detail": "15 min easy, 3 × 8 min at threshold, 10 min easy", "start_time": "18:30"]]]
        guard case .success(.plan(let sessions, _, _))? = CoachTools.command("plan_sessions", input: input, world: w, calendar: cal) else { return XCTFail("no plan") }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].day, tomorrow)
        XCTAssertEqual(sessions[0].kind, .tempoRun)
        XCTAssertEqual(sessions[0].intensity, .hard)
        XCTAssertEqual(sessions[0].origin, .coach)
        XCTAssertEqual(sessions[0].startMinutes, 18 * 60 + 30)

        let existing = w.planned.first { $0.day >= w.today }!
        let upd: JSONValue = ["id": .string(existing.id.uuidString), "status": "skipped", "duration_min": 30]
        guard case .success(.updateSession(let u))? = CoachTools.command("update_session", input: upd, world: w, calendar: cal) else { return XCTFail("no update") }
        XCTAssertEqual(u.status, .skipped)
        XCTAssertEqual(u.durationMin, 30)
        XCTAssertEqual(u.title, existing.title)
        guard case .failure? = CoachTools.command("remove_session", input: ["id": "not-a-uuid"], world: w, calendar: cal) else { return XCTFail("expected failure") }

        guard case .success(.showChart(let m, let days))? = CoachTools.command("show_chart", input: ["metric": "hrv", "days": 500], world: w, calendar: cal) else { return XCTFail("no chart") }
        XCTAssertEqual(m, .hrv)
        XCTAssertEqual(days, 180)
    }

    func testSystemPromptCarriesAthleteAndMemory() {
        let s = CoachPrompt.system(world: world(), calendar: cal)
        XCTAssertTrue(s.contains("Alex"))
        XCTAssertTrue(s.contains("Left knee"))
        XCTAssertTrue(s.contains("UN1T Hatch Street"))
        XCTAssertTrue(s.contains("recovery "))
        XCTAssertFalse(s.contains("\t"))
    }
}

final class InsightTests: XCTestCase {
    private let cal = utc()
    private let now = Date(timeIntervalSince1970: 1_794_657_600 + 3 * 3600)

    func testEffectsFindAlcoholInTheDemo() {
        let demo = LumaDemoSource(dayCount: 120, today: now, calendar: cal)
        let effects = EffectModel.analyze(days: demo.days, checkIns: demo.checkIns, workouts: demo.workouts, calendar: cal)
        // The demo lowers HRV and raises resting HR after alcohol; the analysis must recover both directions.
        let hrv = effects.first { $0.factorKey == "alcohol" && $0.outcome == .hrv }
        XCTAssertNotNil(hrv)
        XCTAssertLessThan(hrv!.delta, 0)
        XCTAssertEqual(hrv!.helps, false)
        let rhr = effects.first { $0.factorKey == "alcohol" && $0.outcome == .restingHR }
        XCTAssertNotNil(rhr)
        XCTAssertGreaterThan(rhr!.delta, 0)
        XCTAssertTrue(hrv!.sentence.hasPrefix("After alcohol, your hrv"))
    }

    func testTrendFitnessAndInsightFeed() {
        let demo = LumaDemoSource(dayCount: 120, today: now, calendar: cal)
        let a = LumaAnalysis.build(days: demo.days, sleeps: demo.sleeps, workouts: demo.workouts, profile: LumaDemoContent.profile(), planned: [],
                                   checkIns: demo.checkIns, personalBests: [PersonalBest(distanceM: 1000, seconds: 252), PersonalBest(distanceM: 5000, seconds: 1480)],
                                   today: demo.today, now: now, calendar: cal)
        XCTAssertFalse(a.trends.isEmpty)
        XCTAssertNotNil(a.fitness.vo2max)
        XCTAssertTrue((35...70).contains(a.fitness.vo2max!), "vo2max \(a.fitness.vo2max!)")
        XCTAssertNotNil(a.fitness.criticalSpeed)
        XCTAssertEqual(a.fitness.predictions.count, 4)
        XCTAssertFalse(a.insights.isEmpty)
        XCTAssertEqual(a.insights.map { $0.priority }, a.insights.map { $0.priority }.sorted(by: >))
        XCTAssertEqual(Set(a.insights.map { $0.id }).count, a.insights.count)
        // With six days of data the feed says so instead of inventing patterns.
        let few = LumaDemoSource(dayCount: 6, today: now, calendar: cal)
        let b = LumaAnalysis.build(days: few.days, sleeps: few.sleeps, workouts: few.workouts, profile: LProfile(), planned: [], today: few.today, now: now, calendar: cal)
        XCTAssertEqual(b.insights.first?.id, "building")
        XCTAssertTrue(b.effects.isEmpty)
        XCTAssertFalse(b.load.ready)
    }

    func testVO2maxFormulaAndCriticalSpeed() {
        // 10 km in 50 min at 85 % of heart-rate reserve: cost 43.5, VO2max = 3.5 + 40 / 0.85 = 50.6
        let v = FitnessModel.vo2max(distanceM: 10_000, seconds: 3000, avgHR: 50 + 0.85 * 140, restHR: 50, maxHR: 190)!
        XCTAssertEqual(v, 3.5 + 40 / 0.85, accuracy: 0.01)
        XCTAssertNil(FitnessModel.vo2max(distanceM: 10_000, seconds: 3000, avgHR: 100, restHR: 50, maxHR: 190))   // too easy to extrapolate
        // Two points define the line exactly: 1 km in 240 s and 5 km in 1400 s → CS = 4000 / 1160.
        let cs = FitnessModel.criticalSpeed([PersonalBest(distanceM: 1000, seconds: 240), PersonalBest(distanceM: 5000, seconds: 1400)])!
        XCTAssertEqual(cs.cs, 4000.0 / 1160.0, accuracy: 1e-9)
        XCTAssertEqual(cs.dPrime, 1000 - cs.cs * 240, accuracy: 1e-6)
    }
}
