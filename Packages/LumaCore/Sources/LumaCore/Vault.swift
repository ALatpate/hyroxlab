import Foundation

// MARK: - Where the athlete's own records are kept

/// How a store came off the disk. The difference between the first two and the rest is the reason
/// this type exists: a file that could not be read is not an empty one, and treating it as empty
/// ends with the real file saved over.
public enum VaultRead: String, Equatable, Sendable {
    /// Read and understood.
    case loaded
    /// No file: nothing has been saved under this name yet.
    case missing
    /// A file is there and could not be read. On an iPhone that is a file opened while the phone was
    /// locked. Nothing is saved over it until it has been read.
    case blocked
    /// A file is there, was read, and is not what it should be. It is kept aside, and no backup could
    /// be read in its place.
    case damaged
    /// As `damaged`, with the newest backup that could be read in use in its place.
    case recovered

    /// Whether what is in memory may be written over the file.
    public var maySave: Bool { self != .blocked }
}

/// What the vault knows about one store, for the data check.
public struct VaultNote: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let read: VaultRead?
    public let bytes: Int?
    public let savedAt: Date?
    /// The last thing that went wrong with it, in words; nil when nothing has.
    public let failure: String?

    public init(name: String, read: VaultRead?, bytes: Int?, savedAt: Date?, failure: String?) {
        self.name = name
        self.read = read
        self.bytes = bytes
        self.savedAt = savedAt
        self.failure = failure
    }

    /// The state in a few words, for a list of readings: what happened, and how much is there.
    public var words: String {
        let size: String = bytes.map { LumaVault.sizeText($0) } ?? ""
        var out: String
        switch read {
        case .loaded?: out = size.isEmpty ? "read" : "read, \(size)"
        case .missing?: out = "nothing saved yet"
        case .blocked?: out = "could not be read"
        case .damaged?: out = "could not be understood; kept aside"
        case .recovered?: out = "could not be understood; a copy is in use"
        case nil: out = size.isEmpty ? "not read in this run" : "saved, \(size)"
        }
        if let failure { out += " (\(failure))" }
        return out
    }
}

/// One set of copies of the stores.
public struct VaultBackup: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        /// Every store as it stood at the end of one day.
        case day
        /// Every store as it stood just before a set was gone back to: what undoing that goes back to.
        case beforeRestore
        /// One store as it stood before a save that left under half of it.
        case beforeChange
        /// Every store as it was found the first time copies were kept.
        case asFound
    }

    public var id: String { name }
    /// A day key for a day's set; otherwise the kind and the moment it was kept.
    public let name: String
    public let files: [String]
    public let bytes: Int

    public init(name: String, files: [String], bytes: Int) {
        self.name = name
        self.files = files
        self.bytes = bytes
    }

    public var kind: Kind {
        if name.hasPrefix(LumaVault.beforeRestore) { return .beforeRestore }
        if name.hasPrefix(LumaVault.beforeChange) { return .beforeChange }
        if name.hasPrefix(LumaVault.asFound) { return .asFound }
        return .day
    }

    private var stamp: Substring {
        switch kind {
        case .day: return Substring(name)
        case .beforeRestore: return name.dropFirst(LumaVault.beforeRestore.count)
        case .beforeChange: return name.dropFirst(LumaVault.beforeChange.count)
        case .asFound: return name.dropFirst(LumaVault.asFound.count)
        }
    }

    /// The day the set is of, or was kept on.
    public var keptDay: String { String(stamp.prefix(10)) }

    /// The time of day it was kept, "21:45"; nil for a day's set, which is the end of its day.
    public var keptTime: String? {
        guard kind != .day else { return nil }
        let digits = stamp.dropFirst(11).prefix(4)
        guard digits.count == 4, digits.allSatisfy({ $0.isNumber }) else { return nil }
        return "\(digits.prefix(2)):\(digits.suffix(2))"
    }
}

/// Small JSON files in one directory, one per store, and the copies kept of them.
///
/// Three things it will not do. It does not take a file it could not read for an empty one
/// (`VaultRead.blocked`), and refuses to save a store in that state. It does not delete a file it
/// could not understand: the file is copied to `Damaged` first. And it does not let one bad save be
/// the only copy: under `Backups` there is a set for each of the last `keepDays` days a store was
/// saved, holding every store as it stood at the end of that day, and a save that would leave under
/// half of a file keeps the file as a set of its own.
///
/// A `nil` directory keeps nothing (the gallery and previews).
public final class LumaVault: @unchecked Sendable {
    public static let keepDays = 14
    static let backups = "Backups"
    static let damaged = "Damaged"
    static let beforeRestore = "before-restore-"
    static let beforeChange = "before-change-"
    static let asFound = "as-found-"

    static let marker = "luma-vault.json"

    public let directory: URL?
    /// Reads a file. Replaced in tests to stand in for a phone that is locked.
    public var reader: (URL) throws -> Data = { try Data(contentsOf: $0) }
    /// Whether the phone says its protected files are sealed right now. Set by the app; the vault
    /// itself has no way to ask. Only used to decide how far a "no such file" can be trusted.
    public var sealed: () -> Bool = { false }
    private let now: () -> Date
    private let calendar: Calendar
    private let lock = NSLock()
    private var reads: [String: VaultRead] = [:]
    private var failures: [String: String] = [:]
    private var saved: [String: Date] = [:]
    private var prunedOn: String?
    /// Events not yet written to the vault's own log, because nothing could be written when they happened.
    private var unwritten: [String] = []

    public init(directory: URL?, now: @escaping () -> Date = { Date() }, calendar: Calendar = LDate.calendar) {
        self.directory = directory
        self.now = now
        self.calendar = calendar
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        protect()
    }

    // MARK: Coding

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // A figure that is not a number must not be what stops a whole store from being saved.
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        // Files written by the first build used the default (reference-date) encoding; accept both.
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self), let date = ISO8601DateFormatter().date(from: s) { return date }
            return Date(timeIntervalSinceReferenceDate: try c.decode(Double.self))
        }
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }

    // MARK: Reading

    public func url(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    /// The store, or nil when there is nothing to use: no file yet, a file that could not be read, or
    /// one that could not be understood with no backup to stand in. `state(_:)` says which.
    public func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let url = url(name) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            // "No such file" is only believed when files can be seen at all: with the phone sealed and
            // the vault's own marker out of reach, a store that looks absent may just be out of reach.
            if sealed(), !markerReads() {
                set(name, .blocked, failure: "the phone's files are sealed")
                return nil
            }
            set(name, .missing, failure: nil)
            return nil
        }
        let data: Data
        do {
            data = try reader(url)
        } catch {
            set(name, .blocked, failure: Self.words(error))
            return nil
        }
        if let value = try? Self.decoder().decode(type, from: data) {
            set(name, .loaded, failure: nil)
            return value
        }
        // Not what it should be. The file is kept, and the newest copy that reads is used.
        let first = keepDamaged(data, name: name)
        for backup in backupDays().reversed() {
            guard let copy = directory?.appendingPathComponent(Self.backups).appendingPathComponent(backup).appendingPathComponent(name),
                  let held = try? reader(copy), let value = try? Self.decoder().decode(type, from: held) else { continue }
            set(name, .recovered, failure: "the copy of \(backup) is in use")
            if first { note("\(name) could not be understood; the copy of \(backup) is in use") }
            return value
        }
        set(name, .damaged, failure: "no copy of it could be read; the file is kept in \(Self.damaged)")
        if first { note("\(name) could not be understood and no copy of it could be read") }
        return nil
    }

    public func state(_ name: String) -> VaultRead? {
        lock.lock(); defer { lock.unlock() }
        return reads[name]
    }

    /// The stores that could not be read. While there are any, what is in memory is not the athlete's
    /// records and must not be shown or saved as if it were.
    public var blocked: [String] {
        lock.lock(); defer { lock.unlock() }
        return reads.filter { $0.value == .blocked }.map { $0.key }.sorted()
    }

    public var isReady: Bool { blocked.isEmpty }

    /// Before every store is read again: what could not be read last time says nothing about now.
    /// A store that is not read again is read when it is next asked for.
    public func forgetBlocked() {
        lock.lock()
        for (name, read) in reads where read == .blocked { reads[name] = nil; failures[name] = nil }
        lock.unlock()
    }

    /// The way out when a store cannot be read and the phone is not locked: the file is moved into
    /// `Damaged`, not deleted, and the newest copy of it that reads is put in its place, so the app can
    /// start. Returns the stores moved. The caller reads the stores again afterwards.
    @discardableResult
    public func setAsideBlocked() -> [String] {
        guard let directory else { return [] }
        let fm = FileManager.default
        let aside = directory.appendingPathComponent(Self.damaged)
        try? fm.createDirectory(at: aside, withIntermediateDirectories: true)
        var moved: [String] = []
        for name in blocked {
            let file = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: file.path) {
                let to = aside.appendingPathComponent(Self.stamp(now(), calendar: calendar) + "-unread-" + name)
                do { try fm.moveItem(at: file, to: to) } catch {
                    fail(name, "could not be read, and could not be moved aside: \(Self.words(error))")
                    continue
                }
            }
            for backup in backupDays().reversed() {
                let copy = directory.appendingPathComponent(Self.backups).appendingPathComponent(backup).appendingPathComponent(name)
                guard let held = try? reader(copy) else { continue }
                try? held.write(to: file, options: Self.writing)
                break
            }
            set(name, .damaged, failure: "it was moved to \(Self.damaged) and the last copy that reads is in use")
            moved.append(name)
        }
        if !moved.isEmpty { note("set aside as unreadable: \(moved.joined(separator: ", "))") }
        return moved
    }

    /// Leaves the vault's marker, once its stores have all been read: a file known to exist, so a later
    /// start can tell "sealed" from "nothing saved yet". The marker also carries the vault's log.
    public func markOpened() {
        guard let url = url(Self.marker) else { return }
        if !FileManager.default.fileExists(atPath: url.path) { writeLog([]) }
        flushLog()
    }

    private func markerReads() -> Bool {
        guard let url = url(Self.marker) else { return true }
        return (try? reader(url)) != nil
    }

    public func list(prefix: String) -> [String] {
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) }.sorted()
    }

    // MARK: Writing

    /// Saves a store. False when it was not saved: the store is blocked, or the write failed. Either
    /// way the file on disk is as it was.
    @discardableResult
    public func save<T: Encodable>(_ value: T, _ name: String) -> Bool {
        guard let url = url(name) else { return true }
        if let read = state(name), !read.maySave {
            fail(name, "not saved: the file on disk has not been read yet")
            return false
        }
        let data: Data
        do { data = try Self.encoder().encode(value) } catch {
            fail(name, "could not be written: \(Self.words(error))")
            return false
        }
        // The samples of a run are written once and can be large; they are not copied.
        return store(data, to: url, name: name, copy: !name.hasPrefix("run-"))
    }

    /// Writes bytes that are not a store (a photo). No copy is kept.
    @discardableResult
    public func write(_ data: Data, _ name: String) -> Bool {
        guard let url = url(name) else { return true }
        return store(data, to: url, name: name, copy: false)
    }

    public func remove(_ name: String) {
        guard let url = url(name) else { return }
        try? FileManager.default.removeItem(at: url)
        lock.lock(); reads[name] = nil; saved[name] = nil; failures[name] = nil; lock.unlock()
    }

    private func store(_ data: Data, to url: URL, name: String, copy: Bool) -> Bool {
        let fm = FileManager.default
        let at = now()
        let day = LDate.key(at, calendar: calendar)
        if copy, let directory {
            let root = directory.appendingPathComponent(Self.backups)
            // The first save of a day. Before it changes anything, the set of the last day a store was
            // saved is filled in with every store as it stands now, so that a day's set is everything
            // as it stood at the end of that day and not only what happened to be saved on it.
            if !fm.fileExists(atPath: root.appendingPathComponent(day).path) { closeEarlierDay(before: day, at: at) }
            // A save that would leave under half of what is there keeps what is there, in case the half
            // is all that was read.
            if let size = Self.size(url), size >= 4096, data.count * 2 < size, let old = try? reader(url) {
                keepSet(Self.beforeChange, at: at, files: [(name, old)], limit: 6)
                note("\(name) went from \(Self.sizeText(size)) to \(Self.sizeText(data.count)); what was there is kept")
            }
        }
        do {
            try data.write(to: url, options: Self.writing)
        } catch {
            fail(name, "could not be written: \(Self.words(error))")
            return false
        }
        lock.lock(); saved[name] = at; failures[name] = nil; if reads[name] == nil || reads[name] == .missing { reads[name] = .loaded }; lock.unlock()
        guard copy, let directory else { return true }
        let folder = directory.appendingPathComponent(Self.backups).appendingPathComponent(day)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(name), options: Self.writing)
        prune(today: day)
        return true
    }

    // MARK: Copies

    /// The stores in the directory: every JSON file but the recordings of runs and the vault's own marker.
    private func storeFiles() -> [String] {
        guard let directory else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix("run-") && $0 != Self.marker }.sorted()
    }

    /// The days that have copies, oldest first.
    func backupDays() -> [String] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(Self.backups).path) else { return [] }
        return names.filter { Self.isDay($0) }.sorted()
    }

    /// Fills in the set of the last day before `day` that has one, with each store that set lacks, as
    /// the store stands now: nothing has been saved since that day, so now is how it stood then. With
    /// no set at all yet, what is there is kept once, as it was found.
    private func closeEarlierDay(before day: String, at: Date) {
        guard let directory else { return }
        let fm = FileManager.default
        let root = directory.appendingPathComponent(Self.backups)
        let current = storeFiles()
        guard !current.isEmpty else { return }
        let sets = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
        if let last = sets.filter({ Self.isDay($0) && $0 < day }).max() {
            let folder = root.appendingPathComponent(last)
            for name in current where !fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                guard let held = try? reader(directory.appendingPathComponent(name)) else { continue }
                try? held.write(to: folder.appendingPathComponent(name), options: Self.writing)
            }
        } else if !sets.contains(where: { $0.hasPrefix(Self.asFound) }) {
            var files: [(String, Data)] = []
            for name in current {
                if let held = try? reader(directory.appendingPathComponent(name)) { files.append((name, held)) }
            }
            keepSet(Self.asFound, at: at, files: files, limit: 1)
        }
    }

    /// Keeps files as a set of their own under `Backups`, named by kind and moment, and no more than
    /// `limit` sets of that kind.
    private func keepSet(_ prefix: String, at: Date, files: [(String, Data)], limit: Int) {
        guard let directory, !files.isEmpty else { return }
        let fm = FileManager.default
        let root = directory.appendingPathComponent(Self.backups)
        var name = prefix + Self.stamp(at, calendar: calendar)
        // Two in one second would otherwise share a folder.
        if fm.fileExists(atPath: root.appendingPathComponent(name).path) { name += "-" + String(UUID().uuidString.prefix(6)) }
        let folder = root.appendingPathComponent(name)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (file, data) in files { try? data.write(to: folder.appendingPathComponent(file), options: Self.writing) }
        let kept = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted(by: >)
        for old in kept.dropFirst(limit) where old != name { try? fm.removeItem(at: root.appendingPathComponent(old)) }
    }

    /// The sets that can be gone back to: one per day, newest first, then the others, newest first.
    public func backupList() -> [VaultBackup] {
        guard let directory else { return [] }
        let root = directory.appendingPathComponent(Self.backups)
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        let others = names.filter { $0.hasPrefix(Self.beforeRestore) || $0.hasPrefix(Self.beforeChange) || $0.hasPrefix(Self.asFound) }
            .map { VaultBackup(name: $0, files: [], bytes: 0) }
            .sorted { ($0.keptDay, $0.keptTime ?? "", $0.name) > ($1.keptDay, $1.keptTime ?? "", $1.name) }
            .map { $0.name }
        let wanted = names.filter { Self.isDay($0) }.sorted(by: >) + others
        return wanted.compactMap { folder in
            let files = ((try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)) ?? []).sorted()
            guard !files.isEmpty else { return nil }
            let bytes = files.reduce(0) { $0 + (Self.size(root.appendingPathComponent(folder).appendingPathComponent($1)) ?? 0) }
            return VaultBackup(name: folder, files: files, bytes: bytes)
        }
    }

    /// Puts back every store held in one set. What is there now is kept first, as a set of its own, so
    /// a restore can itself be undone. A store the set does not hold is left as it is. The caller reads
    /// the stores again afterwards.
    @discardableResult
    public func restore(_ backup: String) -> Bool {
        guard let directory else { return false }
        let fm = FileManager.default
        let root = directory.appendingPathComponent(Self.backups)
        let from = root.appendingPathComponent(backup)
        guard let names = try? fm.contentsOfDirectory(atPath: from.path), !names.isEmpty else { return false }
        // Read everything first: nothing is changed unless all of it can be.
        var held: [(String, Data)] = []
        for name in names.sorted() {
            guard let data = try? reader(from.appendingPathComponent(name)) else { return false }
            held.append((name, data))
        }
        var current: [(String, Data)] = []
        for name in storeFiles() {
            if let data = try? reader(directory.appendingPathComponent(name)) { current.append((name, data)) }
        }
        keepSet(Self.beforeRestore, at: now(), files: current, limit: 3)
        var all = true
        for (name, data) in held {
            do {
                try data.write(to: directory.appendingPathComponent(name), options: Self.writing)
                lock.lock(); reads[name] = .loaded; failures[name] = nil; saved[name] = now(); lock.unlock()
            } catch {
                fail(name, "could not be put back: \(Self.words(error))")
                all = false
            }
        }
        note(all ? "went back to the set \(backup)" : "went back to the set \(backup), in part")
        return all
    }

    private func prune(today: String) {
        lock.lock()
        let done = prunedOn == today
        prunedOn = today
        lock.unlock()
        guard !done, let directory else { return }
        let fm = FileManager.default
        let root = directory.appendingPathComponent(Self.backups)
        let oldest = LDate.adding(-(Self.keepDays - 1), to: today, calendar: calendar)
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            let set = VaultBackup(name: name, files: [], bytes: 0)
            // A day's set, and the set kept as found, go once they are older than the days kept.
            let dated = (set.kind == .day && Self.isDay(name)) || set.kind == .asFound
            if dated, set.keptDay < oldest { try? fm.removeItem(at: root.appendingPathComponent(name)) }
        }
    }

    /// Keeps a file that could not be understood, named by when, unless the newest file kept for the
    /// same store already holds the same bytes. True when it was kept now.
    @discardableResult
    private func keepDamaged(_ data: Data, name: String) -> Bool {
        guard let directory else { return false }
        let fm = FileManager.default
        let dir = directory.appendingPathComponent(Self.damaged)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let mine = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix("-" + name) }.sorted()
        if let newest = mine.last, let held = try? reader(dir.appendingPathComponent(newest)), held == data { return false }
        try? data.write(to: dir.appendingPathComponent(Self.stamp(now(), calendar: calendar) + "-" + name), options: Self.writing)
        for old in mine.dropLast(19) { try? fm.removeItem(at: dir.appendingPathComponent(old)) }
        return true
    }

    // MARK: Reporting

    /// Every store the vault has read or saved in this run, by name.
    public func notes() -> [VaultNote] {
        lock.lock()
        let names = Set(reads.keys).union(saved.keys).union(failures.keys)
        let reads = self.reads, saved = self.saved, failures = self.failures
        lock.unlock()
        return names.sorted().map { name in
            VaultNote(name: name, read: reads[name], bytes: url(name).flatMap { Self.size($0) }, savedAt: saved[name], failure: failures[name])
        }
    }

    // MARK: The vault's own log

    private struct Marker: Codable {
        var luma = 1
        var log: [String] = []
    }

    static let logLimit = 60

    /// Records something that happened to the records, with the moment, where it will still be found
    /// after the app has been closed: a start with the files out of reach, a file that could not be
    /// understood, a set gone back to. Written at once when it can be, and with the next that can.
    public func note(_ event: String) {
        guard directory != nil else { return }
        lock.lock()
        unwritten.append(Self.stamp(now(), calendar: calendar) + " " + event)
        if unwritten.count > Self.logLimit { unwritten.removeFirst(unwritten.count - Self.logLimit) }
        lock.unlock()
        flushLog()
    }

    /// What has been recorded, oldest first, including what has not been written yet.
    public func events() -> [String] {
        lock.lock(); let waiting = unwritten; lock.unlock()
        return writtenLog() + waiting
    }

    private func writtenLog() -> [String] {
        guard let url = url(Self.marker), let data = try? reader(url),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else { return [] }
        return marker.log
    }

    private func flushLog() {
        lock.lock(); let waiting = unwritten; lock.unlock()
        guard !waiting.isEmpty, let url = url(Self.marker) else { return }
        // Only a marker that is there and can be read is added to. It is left by `markOpened` alone,
        // so that its being there goes on meaning the stores were once all read; and one that is out
        // of reach cannot be added to without losing what it holds.
        guard FileManager.default.fileExists(atPath: url.path), (try? reader(url)) != nil else { return }
        guard writeLog(Array((writtenLog() + waiting).suffix(Self.logLimit))) else { return }
        lock.lock(); unwritten.removeFirst(min(waiting.count, unwritten.count)); lock.unlock()
    }

    @discardableResult
    private func writeLog(_ log: [String]) -> Bool {
        guard let url = url(Self.marker), let data = try? JSONEncoder().encode(Marker(log: log)) else { return false }
        return (try? data.write(to: url, options: Self.writing)) != nil
    }

    // MARK: Protection

    /// On an iPhone, a file is by default sealed whenever the phone is locked. Luma is started in the
    /// background by the strap while the phone is locked, so its files are kept readable from the
    /// first unlock after a restart instead: still encrypted on disk, and there when the app needs
    /// them. Changing a file's class only succeeds while the phone is unlocked, so this is asked for
    /// again each time the stores are read.
    public func protect() {
        #if os(iOS)
        guard let directory else { return }
        let fm = FileManager.default
        let open: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.setAttributes(open, ofItemAtPath: directory.path)
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in walker { try? fm.setAttributes(open, ofItemAtPath: item.path) }
        #endif
    }

    static var writing: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }

    // MARK: Small things

    private func set(_ name: String, _ read: VaultRead, failure: String?) {
        lock.lock(); reads[name] = read; failures[name] = failure; lock.unlock()
    }

    private func fail(_ name: String, _ words: String) {
        lock.lock(); failures[name] = words; lock.unlock()
    }

    static func size(_ url: URL) -> Int? {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue
    }

    static func isDay(_ name: String) -> Bool {
        let parts = name.split(separator: "-")
        return name.count == 10 && parts.count == 3 && parts.allSatisfy { Int($0) != nil }
    }

    /// "2026-11-19-214503": sorts by time, and is safe in a file name.
    static func stamp(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return LDate.key(date, calendar: calendar) + String(format: "-%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// An error in a few words that say what kind it was and nothing of where: a domain and a code
    /// on an iPhone, the error's type elsewhere.
    static func words(_ error: Error) -> String {
        #if canImport(Darwin)
        let e = error as NSError
        return "\(e.domain) \(e.code)"
        #else
        return String(describing: type(of: error))
        #endif
    }

    /// "860 B", "46 KB", "1.2 MB".
    public static func sizeText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    /// What a store holds, in the words the app uses for it.
    public static func title(for name: String) -> String {
        if name.hasPrefix("session-") { return "A race session" }
        if name.hasPrefix("run-") { return "A run's recording" }
        switch name {
        case "profile.json": return "Your details"
        case "routine.json": return "Your week"
        case "planned.json": return "Planned sessions"
        case "fuel.json": return "Food, water and supplements taken"
        case "supplements.json": return "Supplement plan"
        case "checkins.json": return "Check-ins"
        case "lifts.json": return "Strength sessions"
        case "runpbs.json": return "Run bests"
        case "trials.json": return "Supplement trials"
        case "weights.json": return "Weigh-ins"
        case "sweat-tests.json": return "Sweat tests"
        case "reviews.json": return "Weekly reviews"
        case "extras.json": return "Settings and reminders"
        case "benchmarks.json": return "Race benchmarks"
        case "stretches-dismissed.json": return "Dismissed suggestions"
        case "night-marks.json": return "Notes on nights recorded in part"
        case "coach-thread.json": return "Coach conversation"
        case "coach-notes.json": return "What the coach remembers"
        case "coach-brief.json": return "Today's brief"
        case "doctor.json": return "Luma Doctor's log"
        case "glimm.json": return "Glimm"
        case "breaths.json": return "Breathing sittings"
        case "guided.json": return "Workouts to be led through"
        default: return name
        }
    }
}

// MARK: - Numbers that cannot stop the app

public enum LNum {
    /// A whole number from a figure that may not be one. Swift stops the app on `Int(x)` when `x` is
    /// not a number or is infinite, and a figure can become either from one bad reading or a division
    /// by nothing; a wrong digit on screen is the smaller harm.
    public static func int<T: BinaryFloatingPoint>(_ value: T) -> Int {
        let v = Double(value)
        guard v.isFinite else { return 0 }
        return Int(max(-9.0e15, min(9.0e15, v)))
    }

    /// A figure that is already whole, so that one spelling serves wherever a whole number is wanted.
    public static func int<T: BinaryInteger>(_ value: T) -> Int { Int(clamping: value) }
}
