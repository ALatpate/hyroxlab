#if os(iOS)
import Foundation
import MetricKit
import LumaCore

/// What iOS reports about the app stopping: a crash or a long freeze, with where in the app it
/// happened, and each day's count of the ways the app was ended.
///
/// iOS hands both to the app itself, on the phone (MetricKit). Nothing here sends them anywhere:
/// they are kept on the phone so that the data check, and the report the athlete can choose to send
/// from it, can say what happened the last time Luma stopped. Without this, a crash leaves nothing
/// behind to find its cause by.
final class LumaCrashLog: NSObject, MXMetricManagerSubscriber {
    static let shared = LumaCrashLog()

    struct Entry: Codable, Equatable {
        /// When the report's period ended.
        var at: Double
        var build: String
        /// "Crash" or "Freeze".
        var kind: String
        /// What iOS named as the cause.
        var cause: String
        /// Where: the frames of the thread that stopped, as binary and offset. Offsets, with the
        /// symbols of the same build, give the function and line.
        var frames: [String]
    }

    private static let entriesKey = "luma.stops.entries"
    private static let exitsKey = "luma.stops.exits"
    private static let kept = 8
    private let defaults = UserDefaults.standard
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    // MARK: Delivered by iOS

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var all = entries()
        for payload in payloads {
            let at = payload.timeStampEnd.timeIntervalSince1970
            for crash in payload.crashDiagnostics ?? [] {
                all.append(Entry(at: at, build: crash.metaData.applicationBuildVersion, kind: "Crash",
                                 cause: Self.cause(of: crash), frames: Self.frames(crash.callStackTree)))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                all.append(Entry(at: at, build: hang.metaData.applicationBuildVersion, kind: "Freeze",
                                 cause: String(format: "did not respond for %.1f s", seconds), frames: Self.frames(hang.callStackTree)))
            }
        }
        // The same report can be delivered again; one copy of each is enough.
        var seen: [Entry] = []
        for entry in all where !seen.contains(entry) { seen.append(entry) }
        if let data = try? JSONEncoder().encode(Array(seen.suffix(Self.kept))) { defaults.set(data, forKey: Self.entriesKey) }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // One payload covers about a day. The newest that counts any ending is kept.
        for payload in payloads.sorted(by: { $0.timeStampEnd < $1.timeStampEnd }) {
            guard let exits = payload.applicationExitMetrics else { continue }
            let line = Self.endings(exits)
            let day = LDate.key(payload.timeStampEnd)
            defaults.set(["day": day, "line": line], forKey: Self.exitsKey)
        }
    }

    // MARK: For the data check

    func entries() -> [Entry] {
        guard let data = defaults.data(forKey: Self.entriesKey), let all = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return all
    }

    /// Readings only: what iOS reported, as it reported it.
    func facts(stamp: (Double) -> String) -> [LFact] {
        let section = "When Luma stopped"
        var out: [LFact] = []
        let all = entries()
        out.append(LFact(section, "Crashes and freezes iOS has reported", all.isEmpty ? "none" : String(all.count)))
        for (i, entry) in all.suffix(3).reversed().enumerated() {
            let n = i + 1
            out.append(LFact(section, "Report \(n)", "\(entry.kind), build \(entry.build), in the day to \(stamp(entry.at))"))
            out.append(LFact(section, "Report \(n) cause", entry.cause))
            out.append(LFact(section, "Report \(n) where", entry.frames.isEmpty ? "not given" : entry.frames.joined(separator: " < ")))
        }
        if let exits = defaults.dictionary(forKey: Self.exitsKey), let day = exits["day"] as? String, let line = exits["line"] as? String {
            out.append(LFact(section, "How the app was ended, day to \(day)", line))
        } else {
            out.append(LFact(section, "How the app was ended", "no daily count delivered yet"))
        }
        return out
    }

    // MARK: Reading a report

    private static func cause(of crash: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let type = crash.exceptionType?.intValue { parts.append(exceptionName(type)) }
        if let signal = crash.signal?.intValue { parts.append(signalName(signal)) }
        if let code = crash.exceptionCode?.intValue, code != 0 { parts.append("code \(code)") }
        if let reason = crash.terminationReason, !reason.isEmpty { parts.append(String(reason.prefix(160))) }
        if let said = crash.exceptionReason?.composedMessage, !said.isEmpty { parts.append(String(said.prefix(200))) }
        return parts.isEmpty ? "not given" : parts.joined(separator: ", ")
    }

    private static func exceptionName(_ type: Int) -> String {
        switch type {
        case 1: return "EXC_BAD_ACCESS"
        case 2: return "EXC_BAD_INSTRUCTION"
        case 3: return "EXC_ARITHMETIC"
        case 5: return "EXC_SOFTWARE"
        case 6: return "EXC_BREAKPOINT"
        case 10: return "EXC_CRASH"
        case 11: return "EXC_RESOURCE"
        case 12: return "EXC_GUARD"
        default: return "exception \(type)"
        }
    }

    private static func signalName(_ signal: Int) -> String {
        switch signal {
        case 4: return "SIGILL"
        case 5: return "SIGTRAP"
        case 6: return "SIGABRT"
        case 8: return "SIGFPE"
        case 9: return "SIGKILL"
        case 10: return "SIGBUS"
        case 11: return "SIGSEGV"
        default: return "signal \(signal)"
        }
    }

    /// The thread iOS attributes the stop to, as "binary+offset" frames in the order iOS lists them.
    /// Every frame in one of the app's own binaries is kept, with the first few of any others.
    private static func frames(_ tree: MXCallStackTree) -> [String] {
        guard let read = try? JSONSerialization.jsonObject(with: tree.jsonRepresentation()) as? [String: Any] else { return [] }
        // The tree is given bare, or under its own name.
        let root = (read["callStackTree"] as? [String: Any]) ?? read
        guard let stacks = root["callStacks"] as? [[String: Any]] else { return [] }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        guard var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first else { return [] }
        let own = Bundle.main.executableURL?.lastPathComponent ?? ""
        var out: [String] = []
        var others = 0
        for _ in 0..<400 {
            let binary = (frame["binaryName"] as? String) ?? "?"
            let offset = (frame["offsetIntoBinaryTextSegment"] as? NSNumber)?.uint64Value ?? 0
            let mine = !own.isEmpty && binary == own
            if mine || others < 4 {
                out.append("\(binary)+0x\(String(offset, radix: 16))")
                if !mine { others += 1 }
            }
            guard let next = (frame["subFrames"] as? [[String: Any]])?.first else { break }
            frame = next
            if out.count >= 24 { break }
        }
        return out
    }

    private static func endings(_ exits: MXAppExitMetric) -> String {
        let f = exits.foregroundExitData, b = exits.backgroundExitData
        let counts: [(String, Int)] = [
            ("in front: memory limit", f.cumulativeMemoryResourceLimitExitCount),
            ("in front: bad access", f.cumulativeBadAccessExitCount),
            ("in front: abnormal", f.cumulativeAbnormalExitCount),
            ("in front: illegal instruction", f.cumulativeIllegalInstructionExitCount),
            ("in front: watchdog", f.cumulativeAppWatchdogExitCount),
            ("in front: closed normally", f.cumulativeNormalAppExitCount),
            ("behind: memory limit", b.cumulativeMemoryResourceLimitExitCount),
            ("behind: memory pressure", b.cumulativeMemoryPressureExitCount),
            ("behind: processor limit", b.cumulativeCPUResourceLimitExitCount),
            ("behind: bad access", b.cumulativeBadAccessExitCount),
            ("behind: abnormal", b.cumulativeAbnormalExitCount),
            ("behind: illegal instruction", b.cumulativeIllegalInstructionExitCount),
            ("behind: watchdog", b.cumulativeAppWatchdogExitCount),
            ("behind: file held while suspended", b.cumulativeSuspendedWithLockedFileExitCount),
            ("behind: background task ran out of time", b.cumulativeBackgroundTaskAssertionTimeoutExitCount),
            ("behind: closed normally", b.cumulativeNormalAppExitCount),
        ]
        let listed = counts.filter { $0.1 > 0 }.map { "\($0.0) \($0.1)" }
        return listed.isEmpty ? "no ending counted" : listed.joined(separator: "; ")
    }
}
#endif
