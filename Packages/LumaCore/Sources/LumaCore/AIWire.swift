import Foundation

// MARK: - JSON value

/// A JSON document as a Swift value, so content blocks and tool inputs can be carried, inspected and
/// sent back exactly as they arrived, including fields this code does not know about.
public enum JSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public var text: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? e.encode(self), let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    /// A number, also accepting numeric strings ("12.5"), which models occasionally send.
    public var number: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    public var int: Int? { number.map { LNum.int($0.rounded()) } }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements, uniquingKeysWith: { a, _ in a })) }
}

public extension JSONValue {
    /// A number rounded to `places` decimals (keeps tool results compact).
    static func rounded(_ v: Double?, _ places: Int = 1) -> JSONValue {
        guard let v, v.isFinite else { return .null }
        let p = pow(10, Double(places))
        return .number((v * p).rounded() / p)
    }
    static func optional(_ s: String?) -> JSONValue {
        if let s { return .string(s) }
        return .null
    }
    static func whole(_ v: Int?) -> JSONValue {
        if let v { return .number(Double(v)) }
        return .null
    }
    static func flag(_ v: Bool?) -> JSONValue {
        if let v { return .bool(v) }
        return .null
    }
}

// MARK: - Messages

public struct AIMessage: Equatable, Sendable, Codable {
    public var role: String
    public var content: [JSONValue]

    public init(role: String, content: [JSONValue]) { self.role = role; self.content = content }

    public static func user(_ text: String, images: [(base64: String, mediaType: String)] = []) -> AIMessage {
        var blocks: [JSONValue] = images.map { AIBlock.image(base64: $0.base64, mediaType: $0.mediaType) }
        blocks.append(AIBlock.text(text))
        return AIMessage(role: "user", content: blocks)
    }
    public static func assistant(_ text: String) -> AIMessage { AIMessage(role: "assistant", content: [AIBlock.text(text)]) }
}

public enum AIBlock {
    public static func text(_ s: String) -> JSONValue { ["type": "text", "text": .string(s)] }

    public static func image(base64: String, mediaType: String) -> JSONValue {
        ["type": "image", "source": ["type": "base64", "media_type": .string(mediaType), "data": .string(base64)]]
    }

    public static func toolResult(id: String, content: String, isError: Bool = false) -> JSONValue {
        var o: [String: JSONValue] = ["type": "tool_result", "tool_use_id": .string(id), "content": .string(content)]
        if isError { o["is_error"] = true }
        return .object(o)
    }

    public static func type(_ block: JSONValue) -> String? { block["type"]?.string }
}

public struct AITool: Equatable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    public init(name: String, description: String, properties: [String: JSONValue] = [:], required: [String] = []) {
        self.name = name
        self.description = description
        self.inputSchema = ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })]
    }

    /// Ask the API to hold the model to this tool's schema exactly. Off unless a request turns it on.
    public var strict = false

    var json: JSONValue {
        guard strict else { return ["name": .string(name), "description": .string(description), "input_schema": inputSchema] }
        return ["name": .string(name), "description": .string(description), "input_schema": AISchema.closed(inputSchema), "strict": true]
    }
}

/// Tools the API runs itself. Nothing in the app answers them; their results come back in the reply.
public enum AIServerTool {
    public static let webSearchName = "web_search"
    /// Web search, the plain version. No cap on searches is set: the athlete asked for none.
    public static let webSearch: JSONValue = ["type": "web_search_20250305", "name": .string(webSearchName)]
}

/// Schema helpers for tool parameters.
public enum AISchema {
    public static func string(_ description: String, enum values: [String]? = nil) -> JSONValue {
        var o: [String: JSONValue] = ["type": "string", "description": .string(description)]
        if let values { o["enum"] = .array(values.map { .string($0) }) }
        return .object(o)
    }
    public static func number(_ description: String) -> JSONValue { ["type": "number", "description": .string(description)] }
    public static func integer(_ description: String) -> JSONValue { ["type": "integer", "description": .string(description)] }
    public static func boolean(_ description: String) -> JSONValue { ["type": "boolean", "description": .string(description)] }
    public static func array(_ description: String, items: JSONValue) -> JSONValue {
        ["type": "array", "description": .string(description), "items": items]
    }
    public static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map { .string($0) })]
    }

    /// The same schema with every object closed to keys it does not name, which a strict tool needs.
    public static func closed(_ schema: JSONValue) -> JSONValue {
        switch schema {
        case .object(var o):
            for (key, value) in o { o[key] = closed(value) }
            if o["type"]?.string == "object", o["properties"] != nil { o["additionalProperties"] = false }
            return .object(o)
        case .array(let items):
            return .array(items.map(closed))
        default:
            return schema
        }
    }
}

public struct AIRequest: Sendable {
    public static let apiVersion = "2026-10-21"
    public static let endpoint = "https://api.anthropic.com/v1/messages"
    public static let modelsEndpoint = "https://api.anthropic.com/v1/models?limit=100"

    public var model: String
    public var system: String
    public var messages: [AIMessage]
    public var tools: [AITool]
    public var maxTokens: Int
    public var stream: Bool
    /// Tools the API runs itself, as their raw entries (`AIServerTool`).
    public var serverTools: [JSONValue] = []
    /// How much work the model puts in: "low", "medium" or "high". Nil leaves the model's own default.
    public var effort: String?
    /// A shape the answer must have (`type: json_schema`). Nil for free text.
    public var format: JSONValue?

    public init(model: String, system: String, messages: [AIMessage], tools: [AITool] = [], maxTokens: Int = 8192, stream: Bool = true) {
        self.model = model; self.system = system; self.messages = messages; self.tools = tools
        self.maxTokens = maxTokens; self.stream = stream
    }

    /// The same request without the extras a model or an older API version might refuse: no effort,
    /// no fixed shape, no strict tools. Sent once when the first form is turned down, so a refused
    /// extra cannot cost the athlete the answer.
    public var plain: AIRequest {
        var r = self
        r.effort = nil
        r.format = nil
        r.tools = tools.map { var t = $0; t.strict = false; return t }
        return r
    }

    public var hasExtras: Bool { effort != nil || format != nil || tools.contains { $0.strict } }

    /// The request body. The system prompt and tool list are marked cacheable: they repeat unchanged
    /// on every step of a tool loop. No sampling parameters are sent (the current API rejects them),
    /// and tool choice is left to the model, which newer models require.
    public func body() -> JSONValue {
        var o: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "system": [["type": "text", "text": .string(system), "cache_control": ["type": "ephemeral"]]],
            "messages": .array(messages.map { ["role": .string($0.role), "content": .array($0.content)] }),
        ]
        if stream { o["stream"] = true }
        let toolList = tools.map { $0.json } + serverTools
        if !toolList.isEmpty { o["tools"] = .array(toolList) }
        var config: [String: JSONValue] = [:]
        if let effort { config["effort"] = .string(effort) }
        if let format { config["format"] = format }
        if !config.isEmpty { o["output_config"] = .object(config) }
        return .object(o)
    }

    public func bodyData() -> Data { Data(body().text.utf8) }
}

// MARK: - Streaming

public enum AIStreamUpdate: Equatable, Sendable {
    /// More visible answer text.
    case text(String)
    /// The model has started calling a tool.
    case toolStarted(name: String)
    case error(String)
}

/// Rebuilds the assistant's content blocks from server-sent events. Every block is kept as raw JSON
/// (text, tool calls, and thinking blocks with their signatures), so the assistant turn can be sent
/// back unmodified when a tool loop continues, as the API requires.
public struct AIStreamAccumulator: Sendable {
    public private(set) var blocks: [JSONValue] = []
    public private(set) var stopReason: String?
    public private(set) var inputTokens = 0
    public private(set) var outputTokens = 0
    public private(set) var errorMessage: String?
    private var partialJSON: [Int: String] = [:]

    public init() {}

    /// Feed one SSE line. Only `data:` lines matter: each carries its own `type`.
    public mutating func consume(line: String) -> [AIStreamUpdate] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let event = JSONValue.parse(payload), let type = event["type"]?.string else { return [] }
        return consume(event: event, type: type)
    }

    public mutating func consume(event: JSONValue, type: String) -> [AIStreamUpdate] {
        switch type {
        case "message_start":
            if let u = event["message"]?["usage"] { inputTokens = u["input_tokens"]?.int ?? inputTokens }
        case "content_block_start":
            guard let index = event["index"]?.int, let block = event["content_block"] else { return [] }
            while blocks.count <= index { blocks.append(.null) }
            blocks[index] = block
            let kind = block["type"]?.string
            if kind == "tool_use" || kind == "server_tool_use", let name = block["name"]?.string { return [.toolStarted(name: name)] }
        case "content_block_delta":
            guard let index = event["index"]?.int, index < blocks.count, let delta = event["delta"],
                  var o = blocks[index].object else { return [] }
            switch delta["type"]?.string {
            case "text_delta":
                let t = delta["text"]?.string ?? ""
                o["text"] = .string((o["text"]?.string ?? "") + t)
                blocks[index] = .object(o)
                return t.isEmpty ? [] : [.text(t)]
            case "input_json_delta":
                partialJSON[index, default: ""] += delta["partial_json"]?.string ?? ""
            case "thinking_delta":
                o["thinking"] = .string((o["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? ""))
                blocks[index] = .object(o)
            case "signature_delta":
                o["signature"] = .string((o["signature"]?.string ?? "") + (delta["signature"]?.string ?? ""))
                blocks[index] = .object(o)
            case "citations_delta":
                if let citation = delta["citation"] {
                    o["citations"] = .array((o["citations"]?.array ?? []) + [citation])
                    blocks[index] = .object(o)
                }
            default:
                break
            }
        case "content_block_stop":
            guard let index = event["index"]?.int, index < blocks.count, var o = blocks[index].object else { return [] }
            if o["type"]?.string == "tool_use" || o["type"]?.string == "server_tool_use" {
                let raw = partialJSON[index] ?? ""
                o["input"] = raw.isEmpty ? (o["input"] ?? .object([:])) : (JSONValue.parse(raw) ?? .object([:]))
                blocks[index] = .object(o)
            }
        case "message_delta":
            if let r = event["delta"]?["stop_reason"]?.string { stopReason = r }
            if let u = event["usage"] { outputTokens = u["output_tokens"]?.int ?? outputTokens }
        case "error":
            let message = event["error"]?["message"]?.string ?? "The service reported an error."
            errorMessage = message
            return [.error(message)]
        default:
            break   // ping, message_stop and event types added later
        }
        return []
    }

    /// Builds the accumulator from a complete (non-streamed) response.
    public init(response: JSONValue) {
        blocks = response["content"]?.array ?? []
        stopReason = response["stop_reason"]?.string
        inputTokens = response["usage"]?["input_tokens"]?.int ?? 0
        outputTokens = response["usage"]?["output_tokens"]?.int ?? 0
        if response["type"]?.string == "error" { errorMessage = response["error"]?["message"]?.string }
    }

    public var text: String {
        blocks.compactMap { $0["type"]?.string == "text" ? $0["text"]?.string : nil }.joined()
    }

    public struct ToolCall: Equatable, Sendable {
        public let id: String
        public let name: String
        public let input: JSONValue
    }

    public var toolCalls: [ToolCall] {
        blocks.compactMap { b in
            guard b["type"]?.string == "tool_use", let id = b["id"]?.string, let name = b["name"]?.string else { return nil }
            return ToolCall(id: id, name: name, input: b["input"] ?? .object([:]))
        }
    }

    /// The turn was paused by the API part-way through its own tools. It is carried on by sending the
    /// conversation back with this turn added, and nothing after it.
    public var isPaused: Bool { stopReason == "pause_turn" }

    /// Web searches the API ran in this turn.
    public var searches: Int {
        blocks.filter { $0["type"]?.string == "server_tool_use" && $0["name"]?.string == AIServerTool.webSearchName }.count
    }

    /// Pages a search in this turn brought back, as title and address, without repeats.
    public var sources: [(title: String, url: String)] {
        var seen = Set<String>(), out: [(String, String)] = []
        for block in blocks where block["type"]?.string == "web_search_tool_result" {
            for item in block["content"]?.array ?? [] {
                guard let url = item["url"]?.string, seen.insert(url).inserted else { continue }
                out.append((item["title"]?.string ?? url, url))
            }
        }
        return out.map { (title: $0.0, url: $0.1) }
    }

    /// The assistant turn to send back while a tool loop continues: every block, unmodified.
    public var assistantMessage: AIMessage { AIMessage(role: "assistant", content: blocks.filter { $0 != .null }) }
}

// MARK: - Models

public struct AIModel: Equatable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    /// Model line as reported by the API ("sonnet", "opus", "haiku", …).
    public let line: String?
    public let images: Bool

    public init(id: String, name: String, line: String?, images: Bool) { self.id = id; self.name = name; self.line = line; self.images = images }

    /// Parses the Models API list response, keeping models that are still active.
    public static func list(from response: JSONValue) -> [AIModel] {
        (response["data"]?.array ?? []).compactMap { m in
            guard let id = m["id"]?.string else { return nil }
            if let life = m["lifecycle"]?.string, life != "active" { return nil }
            return AIModel(id: id, name: m["display_name"]?.string ?? id, line: m["line"]?.string,
                           images: m["capabilities"]?["image_input"]?["supported"]?.bool ?? true)
        }
    }

    /// The default for coaching: the newest Sonnet-line model (the list is newest first), which
    /// balances quality, speed and cost; otherwise the newest model that reads images.
    public static func preferred(_ models: [AIModel]) -> AIModel? {
        models.first { $0.line == "sonnet" && $0.images } ?? models.first { $0.images } ?? models.first
    }
}
