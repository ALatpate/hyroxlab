import XCTest
@testable import LumaCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
}

/// Sums the coach can ask for, the extras a request can carry, and what Glimm reads, says and keeps.
final class SmartTests: XCTestCase {
    private let cal = utc()
    /// A Monday.
    private let today = "2026-11-16"

    // MARK: Sums the coach can ask for

    /// Four weeks ending today: HRV rising a millisecond a night from 50, recovery a point a night from 40.
    private var days: [LDay] {
        LDate.range(ending: today, count: 28, calendar: cal).enumerated().map { i, key in
            LDay(day: key, hrv: 50 + Double(i), recovery: 40 + Double(i))
        }
    }

    /// A session at midday on the day `ago` days before today.
    private func session(_ ago: Int, sport: String, minutes: Double, km: Double? = nil) -> LWorkout {
        let start = LDate.startOfDay(LDate.adding(-ago, to: today, calendar: cal), calendar: cal)!.timeIntervalSince1970 + 12 * 3600
        return LWorkout(start: start, end: start + minutes * 60, sport: sport, durationS: minutes * 60, distanceM: km.map { $0 * 1000 })
    }

    /// A 10 km run every Monday and one strength session on the Wednesday before last.
    private var workouts: [LWorkout] {
        [0, 7, 14, 21].map { session($0, sport: "Running", minutes: 60, km: 10) } + [session(5, sport: "Strength", minutes: 45)]
    }

    private func calc(_ input: JSONValue) -> JSONValue {
        CoachCalc.run(input, days: days, workouts: workouts, today: today, calendar: cal)
    }

    func testASummaryIsWorkedOutOverTheLastFourWeeksByDefault() {
        let out = calc(["operation": "summary", "metric": "hrv"])
        XCTAssertNil(out["error"])
        XCTAssertEqual(out["from"]?.string, LDate.adding(-27, to: today, calendar: cal))
        XCTAssertEqual(out["to"]?.string, today)
        XCTAssertEqual(out["days_in_period"]?.number, 28)
        XCTAssertEqual(out["days_with_a_value"]?.number, 28)
        XCTAssertEqual(out["mean"]?.number, 63.5)
        XCTAssertEqual(out["median"]?.number, 63.5)
        XCTAssertEqual(out["lowest"]?.number, 50)
        XCTAssertEqual(out["highest"]?.number, 77)
        XCTAssertNil(out["caution"])
        XCTAssertNil(out["total"], "a total means nothing for a nightly figure")

        // Sessions are counted from what was recorded; a day with none is a real zero.
        let minutes = calc(["operation": "summary", "metric": "training_minutes"])
        XCTAssertEqual(minutes["total"]?.number, 285)
        XCTAssertEqual(minutes["days_with_a_value"]?.number, 28)
        XCTAssertEqual(calc(["operation": "summary", "metric": "run_km"])["total"]?.number, 40)
        XCTAssertEqual(calc(["operation": "summary", "metric": "sessions"])["total"]?.number, 5)

        // A handful of days is said to be a handful.
        let few = calc(["operation": "summary", "metric": "hrv", "from": .string(LDate.adding(-2, to: today, calendar: cal))])
        XCTAssertEqual(few["days_in_period"]?.number, 3)
        XCTAssertNotNil(few["caution"])
        // A period never runs past today, and never longer than a year.
        let long = calc(["operation": "summary", "metric": "hrv", "from": "2020-01-01", "to": "2030-01-01"])
        XCTAssertEqual(long["to"]?.string, today)
        XCTAssertEqual(long["days_in_period"]?.number, Double(CoachCalc.maxDays))
        XCTAssertEqual(long["days_with_a_value"]?.number, 28)
    }

    func testTrendComparisonRelationAndWeekdays() {
        let trend = calc(["operation": "trend", "metric": "hrv"])
        XCTAssertEqual(trend["change_per_week"]?.number ?? 0, 7, accuracy: 1e-6)
        XCTAssertEqual(trend["clear"]?.bool, true)

        let compare = calc(["operation": "compare", "metric": "hrv", "from": .string(LDate.adding(-6, to: today, calendar: cal)),
                            "from_b": .string(LDate.adding(-27, to: today, calendar: cal)), "to_b": .string(LDate.adding(-21, to: today, calendar: cal))])
        XCTAssertEqual(compare["mean_a"]?.number, 74)
        XCTAssertEqual(compare["mean_b"]?.number, 53)
        XCTAssertEqual(compare["a_minus_b"]?.number, 21)
        XCTAssertEqual(compare["clear"]?.bool, true)

        let relate = calc(["operation": "relate", "metric": "hrv", "other_metric": "recovery"])
        XCTAssertEqual(relate["pairs"]?.number, 28)
        XCTAssertEqual(relate["rank_correlation"]?.number, 1)
        XCTAssertNotNil(relate["note"])
        // A day's lag sets each day against the next, so there is one pair fewer.
        XCTAssertEqual(calc(["operation": "relate", "metric": "hrv", "other_metric": "recovery", "lag_days": 1])["pairs"]?.number, 27)

        let byDay = calc(["operation": "by_weekday", "metric": "sessions"])["by_weekday"]?.array ?? []
        XCTAssertEqual(byDay.map { $0["day"]?.string ?? "" }, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        XCTAssertEqual(byDay.map { $0["days"]?.number ?? 0 }, [4, 4, 4, 4, 4, 4, 4])
        // A run every Monday, one session on one of the four Wednesdays.
        XCTAssertEqual(byDay.map { $0["mean"]?.number ?? -1 }, [1, 0, 0.25, 0, 0, 0, 0])
    }

    func testAQuestionThatCannotBeAnsweredSaysWhy() {
        XCTAssertNotNil(calc(["operation": "guess", "metric": "hrv"])["error"])
        XCTAssertNotNil(calc(["operation": "summary", "metric": "mood"])["error"])
        XCTAssertNotNil(calc(["operation": "summary"])["error"])
        XCTAssertNotNil(calc(["operation": "compare", "metric": "hrv"])["error"])
        XCTAssertNotNil(calc(["operation": "relate", "metric": "hrv"])["error"])
        // A period that starts after today holds no days.
        XCTAssertNotNil(calc(["operation": "summary", "metric": "hrv", "from": .string(LDate.adding(5, to: today, calendar: cal))])["error"])

        let tool = CoachCalc.tool()
        XCTAssertEqual(tool.name, CoachCalc.toolName)
        XCTAssertEqual(tool.inputSchema["required"]?.array?.count, 2)
        XCTAssertTrue(CoachTools.all.contains { $0.name == CoachCalc.toolName })
        XCTAssertTrue(CoachTools.readNames.contains(CoachCalc.toolName))
        XCTAssertEqual(CoachTools.activity(CoachCalc.toolName), "Working out the numbers")
        XCTAssertEqual(CoachTools.activity(AIServerTool.webSearchName), "Searching the web")
    }

    // MARK: What a request can carry

    func testARequestCarriesWebSearchEffortAndAFixedShapeOnlyWhenAsked() {
        let tool = AITool(name: "log_water", description: "d", properties: ["ml": AISchema.number("ml")], required: ["ml"])
        var req = AIRequest(model: "m", system: "sys", messages: [.user("hi")], tools: [tool])
        XCTAssertNil(req.body()["output_config"])
        XCTAssertEqual(req.body()["tools"]?.array?.count, 1)
        XCTAssertFalse(req.hasExtras)

        req.serverTools = [AIServerTool.webSearch]
        req.effort = "low"
        req.format = GlimmDaily.format
        let body = req.body()
        let tools = body["tools"]?.array ?? []
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools.last?["type"]?.string, "web_search_20250305")
        XCTAssertEqual(tools.last?["name"]?.string, "web_search")
        // No cap on searches is sent.
        XCTAssertNil(tools.last?["max_uses"])
        XCTAssertEqual(body["output_config"]?["effort"]?.string, "low")
        XCTAssertEqual(body["output_config"]?["format"]?["type"]?.string, "json_schema")
        XCTAssertTrue(req.hasExtras)

        // The plain form drops what a model might refuse and keeps the rest.
        let plain = req.plain
        XCTAssertNil(plain.body()["output_config"])
        XCTAssertEqual(plain.body()["tools"]?.array?.count, 2)
        XCTAssertFalse(plain.hasExtras)
        XCTAssertEqual(plain.body()["model"]?.string, "m")
    }

    func testAStrictToolClosesEveryObjectInItsSchema() {
        var tool = GuidedReading.tool()
        XCTAssertNil(AIRequest(model: "m", system: "s", messages: [.user("hi")], tools: [tool]).body()["tools"]?.array?.first?["strict"])
        tool.strict = true
        let req = AIRequest(model: "m", system: "s", messages: [.user("hi")], tools: [tool])
        let sent = req.body()["tools"]?.array?.first
        XCTAssertEqual(sent?["strict"]?.bool, true)
        let schema = sent?["input_schema"]
        XCTAssertEqual(schema?["additionalProperties"]?.bool, false)
        let block = schema?["properties"]?["blocks"]?["items"]
        XCTAssertEqual(block?["additionalProperties"]?.bool, false)
        XCTAssertEqual(block?["properties"]?["steps"]?["items"]?["additionalProperties"]?.bool, false)
        // What the schema says is otherwise untouched.
        XCTAssertEqual(schema?["required"]?.array?.count, 3)
        XCTAssertEqual(schema?["properties"]?["sport"]?["enum"]?.array?.count, 4)
        XCTAssertTrue(req.hasExtras)
        XCTAssertNil(req.plain.body()["tools"]?.array?.first?["strict"])
        XCTAssertNil(req.plain.body()["tools"]?.array?.first?["input_schema"]?["additionalProperties"])
    }

    func testASearchTheAPIRanIsKeptWholeAndNotAnsweredByTheApp() {
        var acc = AIStreamAccumulator()
        var updates: [AIStreamUpdate] = []
        let lines = [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":30}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"HYROX Dublin 2026 date\"}"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","url":"https://example.org/a","title":"Page A","encrypted_content":"abc"},{"type":"web_search_result","url":"https://example.org/b","title":"Page B","encrypted_content":"def"},{"type":"web_search_result","url":"https://example.org/a","title":"Page A again","encrypted_content":"ghi"}]}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"It is in November."}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://example.org/a","title":"Page A","encrypted_index":"xyz","cited_text":"November"}}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"pause_turn"},"usage":{"output_tokens":40}}"#,
        ]
        for l in lines { updates += acc.consume(line: l) }
        XCTAssertEqual(updates, [.toolStarted(name: "web_search"), .text("It is in November.")])
        // The search is the API's own: the app has nothing to answer.
        XCTAssertTrue(acc.toolCalls.isEmpty)
        XCTAssertEqual(acc.searches, 1)
        XCTAssertEqual(acc.sources.map { $0.url }, ["https://example.org/a", "https://example.org/b"])
        XCTAssertEqual(acc.sources.map { $0.title }, ["Page A", "Page B"])
        XCTAssertTrue(acc.isPaused)
        // Every block goes back as it came, so the turn can be carried on.
        let back = acc.assistantMessage
        XCTAssertEqual(back.content.count, 3)
        XCTAssertEqual(back.content[0]["input"]?["query"]?.string, "HYROX Dublin 2026 date")
        XCTAssertEqual(back.content[1]["content"]?.array?.first?["encrypted_content"]?.string, "abc")
        XCTAssertEqual(back.content[2]["citations"]?.array?.first?["encrypted_index"]?.string, "xyz")
        XCTAssertEqual(back.content[2]["text"]?.string, "It is in November.")

        var plain = AIStreamAccumulator()
        _ = plain.consume(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#)
        XCTAssertFalse(plain.isPaused)
        XCTAssertEqual(plain.searches, 0)
        XCTAssertTrue(plain.sources.isEmpty)
    }

    // MARK: Glimm: small jobs

    func testGlimmOffersOnlyTheSmallJobsTheAppAllows() {
        XCTAssertEqual(GlimmAction.from(["kind": "log_water", "ml": 250]), .logWater(250))
        XCTAssertNil(GlimmAction.from(["kind": "log_water", "ml": 5000]))
        XCTAssertNil(GlimmAction.from(["kind": "log_water"]))
        XCTAssertEqual(GlimmAction.from(["kind": "open", "place": "breathing"]), .open(.breathing))
        XCTAssertNil(GlimmAction.from(["kind": "open", "place": "bank"]))
        XCTAssertNil(GlimmAction.from(["kind": "buy"]))
        XCTAssertNil(GlimmAction.from("log_water"))
        XCTAssertNil(GlimmAction.from(nil))
        XCTAssertEqual(GlimmAction.logWater(250).label, "Log 250 ml of water")
        XCTAssertEqual(GlimmAction.open(.breathing).label, "Open: Breathing")

        // A reply can carry one; a job it does not have is left out, and the words still stand.
        let offer = GlimmChat.parse(#"{"text":"Shall I log that?","mood":"steady","action":{"kind":"log_water","ml":300}}"#, fallback: .steady)
        XCTAssertEqual(offer?.action, .logWater(300))
        let odd = GlimmChat.parse(#"{"text":"Hm.","mood":"steady","action":{"kind":"transfer","ml":300}}"#, fallback: .steady)
        XCTAssertEqual(odd, GlimmReply(text: "Hm.", mood: .steady))
        XCTAssertTrue(GlimmChat.system.contains("log_water"))
    }

    // MARK: Glimm: the day's lines

    func testTheDaysLinesAreCheckedBeforeTheyAreUsed() {
        let raw = #"""
        ```json
        {"morning":{"text":"Morning. Legs feel like a tempo day.","mood":"focused"},
         "after_training":{"text":"That is the work done.","mood":"proud"},
         "evening":{"text":"Wind down, then bed.","mood":"sleepy"},
         "widget":"Tempo day",
         "noticed":["Trains hardest on Tuesdays.","  ","Prefers the morning for runs.","A third thing."]}
        ```
        """#
        let parsed = GlimmDaily.parse(raw, day: today)!
        XCTAssertEqual(parsed.lines.day, today)
        XCTAssertEqual(parsed.lines.morning, GlimmSaying(text: "Morning. Legs feel like a tempo day.", mood: .focused))
        XCTAssertEqual(parsed.lines.afterTraining.mood, .proud)
        XCTAssertEqual(parsed.lines.evening.mood, .sleepy)
        XCTAssertEqual(parsed.lines.widget, "Tempo day")
        // At most two new notes a day, and an empty one is not a note.
        XCTAssertEqual(parsed.noticed, ["Trains hardest on Tuesdays.", "Prefers the morning for runs."])

        // The line for the point of the day.
        XCTAssertEqual(parsed.lines.line(hour: 9, trainedToday: false), parsed.lines.morning)
        XCTAssertEqual(parsed.lines.line(hour: 14, trainedToday: true), parsed.lines.afterTraining)
        XCTAssertEqual(parsed.lines.line(hour: 19, trainedToday: true), parsed.lines.evening)

        // A mood it does not have falls back; a blank widget line is none; too long is cut.
        let loose = GlimmDaily.parse(#"{"morning":{"text":"Hello.","mood":"furious"},"after_training":{"text":"Done."},"evening":{"text":"\#(String(repeating: "long words ", count: 40))","mood":"sleepy"},"widget":"  "}"#, day: today)!
        XCTAssertEqual(loose.lines.morning.mood, .steady)
        XCTAssertEqual(loose.lines.afterTraining.mood, .steady)
        XCTAssertNil(loose.lines.widget)
        XCTAssertLessThanOrEqual(loose.lines.evening.text.count, GlimmDaily.lineLimit)
        XCTAssertTrue(loose.noticed.isEmpty)

        // A line missing, or no JSON at all: nothing is used, and the fixed lines stay.
        XCTAssertNil(GlimmDaily.parse(#"{"morning":{"text":"Hello.","mood":"steady"},"evening":{"text":"Bye.","mood":"steady"}}"#, day: today))
        XCTAssertNil(GlimmDaily.parse("I could not do that.", day: today))
    }

    func testTheDailyRequestSaysWhatItMaySayAndWhetherToLearn() {
        let request = GlimmDaily.request(day: today, clock: "Monday morning", name: "Alex", facts: ["Recovery this morning is 72%."],
                                         notebook: ["Trains hardest on Tuesdays."], wearing: "coral zip hoodie", learns: false)
        let json = JSONValue.parse(request)
        XCTAssertEqual(json?["date"]?.string, today)
        XCTAssertEqual(json?["first_name"]?.string, "Alex")
        XCTAssertEqual(json?["learning"]?.string, "off")
        XCTAssertEqual(json?["facts"]?.array?.count, 1)
        XCTAssertEqual(json?["notebook"]?.array?.first?.string, "Trains hardest on Tuesdays.")
        let nameless = JSONValue.parse(GlimmDaily.request(day: today, clock: "Monday morning", name: "  ", facts: [], notebook: [], wearing: "", learns: true))
        XCTAssertNil(nameless?["first_name"])
        XCTAssertEqual(nameless?["learning"]?.string, "on")

        // The shape the answer is held to names every line.
        XCTAssertEqual(GlimmDaily.format["type"]?.string, "json_schema")
        XCTAssertEqual(GlimmDaily.format["schema"]?["required"]?.array?.count, 5)
        XCTAssertEqual(GlimmDaily.format["schema"]?["additionalProperties"]?.bool, false)
        // Its manners are in the instructions, not left to chance.
        XCTAssertTrue(GlimmDaily.system.contains("no guilt"))
        XCTAssertTrue(GlimmDaily.system.contains("Never a diagnosis"))
    }

    // MARK: Glimm: the notebook

    func testGlimmKeepsItsOwnNotesOnlyWhileLearningIsOn() throws {
        let t = Date(timeIntervalSince1970: 1_795_000_000)
        var state = GlimmState()
        XCTAssertTrue(state.learns)
        XCTAssertTrue(state.remember("Likes the Thursday class", source: "told", now: t))
        XCTAssertTrue(state.notice("Trains hardest on Tuesdays.", now: t))
        // The same note twice is one note.
        XCTAssertFalse(state.notice("trains hardest on tuesdays.", now: t))
        XCTAssertEqual(state.notebook.map { $0.text }, ["Trains hardest on Tuesdays."])
        XCTAssertEqual(state.notebook.first?.source, GlimmState.noticed)

        // Switched off, nothing is added.
        state.learns = false
        XCTAssertFalse(state.notice("Sleeps longer at weekends.", now: t))
        XCTAssertEqual(state.notebook.count, 1)
        state.learns = true

        // Its own notes are capped; the oldest of them give way, never what it was told.
        for i in 0..<40 { state.notice("Note \(i)", now: t.addingTimeInterval(Double(i))) }
        XCTAssertEqual(state.notebook.count, GlimmState.noticedLimit)
        XCTAssertEqual(state.notebook.last?.text, "Note 39")
        XCTAssertEqual(state.notebook.first?.text, "Note 10")
        XCTAssertTrue(state.memories.contains { $0.text == "Likes the Thursday class" })

        // It survives being saved, with the day's lines and the switch.
        state.lines = GlimmDayLines(day: today, morning: GlimmSaying(text: "Morning.", mood: .steady), afterTraining: GlimmSaying(text: "Done.", mood: .proud),
                                    evening: GlimmSaying(text: "Night.", mood: .sleepy), widget: "Hello")
        state.linesAsked = today
        state.learns = false
        let back = try JSONDecoder().decode(GlimmState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back, state)
        // A file from before any of this reads as learning on and no lines yet.
        let old = try JSONDecoder().decode(GlimmState.self, from: Data("{}".utf8))
        XCTAssertTrue(old.learns)
        XCTAssertNil(old.lines)
        XCTAssertNil(old.linesAsked)

        // The notebook can be emptied without touching what it was told.
        state.clearNotebook()
        XCTAssertTrue(state.notebook.isEmpty)
        XCTAssertEqual(state.memories.map { $0.text }, ["Likes the Thursday class"])
    }

    func testWhatGlimmSharesNamesWhereEachThingCameFrom() {
        let t = Date(timeIntervalSince1970: 1_795_000_000)
        var state = GlimmState()
        state.remember("Racing in Dublin in spring", source: "told", now: t)
        state.notice("Trains hardest on Tuesdays.", now: t)
        let look = BuddyLook(mood: .drained, title: "Drained", line: "Recovery 24%. Take it easy.", energy: 0.24)
        let brief = (0..<20).map { "Day fact \($0)." }
        let facts = GlimmChat.facts(name: "Alex", look: look, shareHealth: true, outfit: .signature, why: .setting(.relax), into: "Butter",
                                    memories: state.memories, clock: "Monday morning", taste: GlimmTaste(), brief: brief)
        XCTAssertLessThanOrEqual(facts.count, GlimmChat.factLimit)
        XCTAssertTrue(facts.contains("Day fact 0."))
        // The day's facts never crowd out what it remembers.
        XCTAssertTrue(facts.contains("The user asked Glimm to remember: Racing in Dublin in spring"))
        XCTAssertTrue(facts.contains("Glimm has worked out over time: Trains hardest on Tuesdays."))
    }

    func testTheDaysBriefStaysOnThePhoneWithoutLeave() {
        let now = Date(timeIntervalSince1970: 1_794_657_600 + 3 * 3600)
        let demo = LumaDemoSource(dayCount: 120, today: now, calendar: cal)
        let profile = LumaDemoContent.profile()
        let planned = LumaDemoContent.planned(today: demo.today)
        let a = LumaAnalysis.build(days: demo.days, sleeps: demo.sleeps, workouts: demo.workouts, profile: profile, planned: planned,
                                   checkIns: demo.checkIns, today: demo.today, now: now, calendar: cal)
        XCTAssertTrue(GlimmBrief.facts(analysis: a, planned: planned, workouts: demo.workouts, today: demo.today, shareHealth: false, calendar: cal).isEmpty)
        let shared = GlimmBrief.facts(analysis: a, planned: planned, workouts: demo.workouts, today: demo.today, shareHealth: true, calendar: cal)
        XCTAssertFalse(shared.isEmpty)
        XCTAssertLessThanOrEqual(shared.count, GlimmBrief.limit)
        XCTAssertTrue(shared.contains { $0.hasPrefix("Sessions so far this week:") }, "\(shared)")
        XCTAssertTrue(shared.allSatisfy { $0.count < GlimmChat.factLength }, "nothing is cut short")
    }
}
