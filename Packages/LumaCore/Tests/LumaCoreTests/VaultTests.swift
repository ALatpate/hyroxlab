import XCTest
@testable import LumaCore

/// The vault holds what the athlete typed in. These are the ways it must not lose it.
final class VaultTests: XCTestCase {
    private var dir: URL!
    private var clock = Date(timeIntervalSince1970: 1_795_000_000)   // a fixed afternoon

    private struct Entry: Codable, Equatable { var title: String; var kcal: Double }
    private struct Locked: Error {}

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("luma-vault-\(UUID().uuidString)", isDirectory: true)
        clock = Date(timeIntervalSince1970: 1_795_000_000)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func vault() -> LumaVault { LumaVault(directory: dir, now: { [unowned self] in self.clock }) }
    private func log(_ n: Int) -> [Entry] { (0..<n).map { Entry(title: "Meal number \($0) with a long enough name", kcal: Double(400 + $0)) } }
    private func raw(_ name: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent(name)) }
    private func day() -> String { LDate.key(clock) }

    func testNothingSavedYetIsNotAFault() {
        let v = vault()
        XCTAssertNil(v.load([Entry].self, "fuel.json"))
        XCTAssertEqual(v.state("fuel.json"), .missing)
        XCTAssertTrue(v.isReady)
        XCTAssertTrue(v.save(log(3), "fuel.json"))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(3))
    }

    /// The fault that lost a day of records: the app was started while the phone was locked, could
    /// not read its files, took them for empty, and saved the little it then had over them.
    func testAFileThatCannotBeReadIsNotEmptyAndIsNeverSavedOver() {
        XCTAssertTrue(vault().save(log(40), "fuel.json"))
        let before = raw("fuel.json")

        let v = vault()
        v.reader = { _ in throw Locked() }
        XCTAssertNil(v.load([Entry].self, "fuel.json"))
        XCTAssertEqual(v.state("fuel.json"), .blocked)
        XCTAssertEqual(v.blocked, ["fuel.json"])
        XCTAssertFalse(v.isReady)
        // The app carries on with nothing in memory and logs a glass of water.
        XCTAssertFalse(v.save([Entry(title: "Water", kcal: 0)], "fuel.json"), "a store that was not read is not saved")
        XCTAssertEqual(raw("fuel.json"), before, "and the file is as it was")
        XCTAssertNotNil(v.notes().first { $0.name == "fuel.json" }?.failure)

        // The phone is unlocked: the same vault reads the file, and saving is allowed again.
        v.reader = { try Data(contentsOf: $0) }
        XCTAssertEqual(v.load([Entry].self, "fuel.json"), log(40))
        XCTAssertTrue(v.isReady)
        XCTAssertTrue(v.save(log(41), "fuel.json"))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(41))
    }

    /// Should a sealed phone ever report a file as absent rather than unreadable, absent is not believed.
    func testNoSuchFileIsNotBelievedWhileThePhoneIsSealed() {
        let first = vault()
        XCTAssertTrue(first.save(log(4), "fuel.json"))
        first.markOpened()

        let v = vault()
        v.sealed = { true }
        v.reader = { _ in throw Locked() }
        XCTAssertNil(v.load([Entry].self, "trials.json"))
        XCTAssertEqual(v.state("trials.json"), .blocked, "never saved, but that cannot be known yet")
        XCTAssertFalse(v.save(log(1), "trials.json"))
        // Sealed, but this app's files can be read (the usual case once they have their class): believed.
        v.reader = { try Data(contentsOf: $0) }
        XCTAssertNil(v.load([Entry].self, "trials.json"))
        XCTAssertEqual(v.state("trials.json"), .missing)
        XCTAssertTrue(v.save(log(1), "trials.json"))
    }

    /// A store that is asked for now and then (a run's recording) and could not be read once must not
    /// leave the vault unready for good: reading everything again starts from what can be read now.
    func testWhatCouldNotBeReadOnceDoesNotCountAgainstTheNextReading() {
        XCTAssertTrue(vault().save(log(3), "run-1.json"))
        XCTAssertTrue(vault().save(log(3), "fuel.json"))
        let v = vault()
        v.reader = { _ in throw Locked() }
        _ = v.load([Entry].self, "run-1.json")
        _ = v.load([Entry].self, "fuel.json")
        XCTAssertEqual(v.blocked, ["fuel.json", "run-1.json"])
        v.reader = { try Data(contentsOf: $0) }
        v.forgetBlocked()
        XCTAssertEqual(v.load([Entry].self, "fuel.json"), log(3))
        XCTAssertTrue(v.isReady, "the run was not read again, and is not held against the vault")
        XCTAssertEqual(v.load([Entry].self, "run-1.json"), log(3))
    }

    /// The way out when a file cannot be read and the phone is not locked: it is moved aside, never
    /// deleted, and the last copy that reads takes its place.
    func testAStoreThatWillNotReadCanBeSetAsideForItsLastCopy() throws {
        XCTAssertTrue(vault().save(log(6), "fuel.json"))
        XCTAssertTrue(vault().save(log(2), "weights.json"))
        clock += 86_400
        // Today the file itself will not read; yesterday's copy of it will.
        let bad = dir.appendingPathComponent("fuel.json").path
        let v = vault()
        v.reader = { url in
            if url.path == bad { throw Locked() }
            return try Data(contentsOf: url)
        }
        XCTAssertNil(v.load([Entry].self, "fuel.json"))
        XCTAssertEqual(v.load([Entry].self, "weights.json"), log(2))
        XCTAssertFalse(v.isReady)
        let before = raw("fuel.json")

        XCTAssertEqual(v.setAsideBlocked(), ["fuel.json"])
        let aside = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Damaged").path)
        XCTAssertEqual(aside.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("Damaged").appendingPathComponent(aside[0])), before, "moved, not deleted")
        XCTAssertTrue(v.isReady)
        v.reader = { try Data(contentsOf: $0) }
        XCTAssertEqual(v.load([Entry].self, "fuel.json"), log(6), "yesterday's copy is in its place")
        XCTAssertTrue(v.save(log(7), "fuel.json"))
    }

    func testStoresAreNamedInPlainWords() {
        XCTAssertEqual(LumaVault.title(for: "fuel.json"), "Food, water and supplements taken")
        XCTAssertEqual(LumaVault.title(for: "session-0F1E.json"), "A race session")
        XCTAssertEqual(LumaVault.title(for: "something-else.json"), "something-else.json")
    }

    func testAFileThatCannotBeUnderstoodIsKeptAndTheLastCopyUsed() throws {
        XCTAssertTrue(vault().save(log(5), "lifts.json"))
        clock += 86_400
        let garbage = Data("{ this is not what was saved".utf8)
        try garbage.write(to: dir.appendingPathComponent("lifts.json"))

        let v = vault()
        XCTAssertEqual(v.load([Entry].self, "lifts.json"), log(5), "yesterday's copy stands in")
        XCTAssertEqual(v.state("lifts.json"), .recovered)
        let kept = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Damaged").path)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("Damaged").appendingPathComponent(kept[0])), garbage)
        // Reading it again does not pile up copies of the same bytes.
        _ = vault().load([Entry].self, "lifts.json")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Damaged").path).count, 1)
        // With no copy to stand in, there is nothing to use, and the bad file is still kept.
        try garbage.write(to: dir.appendingPathComponent("weights.json"))
        XCTAssertNil(v.load([Entry].self, "weights.json"))
        XCTAssertEqual(v.state("weights.json"), .damaged)
    }

    private func copy(_ set: String, _ name: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent("Backups").appendingPathComponent(set).appendingPathComponent(name))
    }

    private func entries(_ data: Data?) -> [Entry]? {
        data.flatMap { try? LumaVault.decoder().decode([Entry].self, from: $0) }
    }

    func testEveryDayKeepsItsOwnCopyForTwoWeeks() {
        let v = vault()
        for i in 0..<20 {
            XCTAssertTrue(v.save(log(i + 1), "fuel.json"))
            clock += 86_400
        }
        let days = v.backupList().filter { $0.kind == .day }.map { $0.name }
        XCTAssertEqual(days.count, LumaVault.keepDays)
        XCTAssertEqual(days.first, LDate.adding(-1, to: day()), "newest first: the last day a save was made")
        // Each day's copy is that day's last save.
        XCTAssertEqual(entries(copy(days[2], "fuel.json"))?.count, 20 - 2)
    }

    /// A day's set is everything as it stood at the end of that day, not only what was saved on it:
    /// going back to a day would otherwise put some records back and leave the rest as they are now.
    func testADaysSetHoldsEveryStoreAsItStoodThen() {
        let v = vault()
        XCTAssertTrue(v.save(log(3), "fuel.json"))
        XCTAssertTrue(v.save(log(2), "weights.json"))
        clock += 86_400
        let second = day()
        XCTAssertTrue(v.save(log(4), "fuel.json"))          // the only save of the second day
        clock += 86_400
        XCTAssertTrue(v.save(log(5), "weights.json"))       // the first save of the third
        XCTAssertTrue(v.save(log(1), "trials.json"))        // a store that did not exist before today

        XCTAssertEqual(entries(copy(second, "fuel.json")), log(4))
        XCTAssertEqual(entries(copy(second, "weights.json")), log(2), "not saved that day: as it stood at the end of it")
        XCTAssertNil(copy(second, "trials.json"), "there was no such store that day")
        // A second vault on the same day (the app closed and opened) does not fill a set in twice.
        XCTAssertTrue(vault().save(log(6), "weights.json"))
        XCTAssertEqual(entries(copy(second, "weights.json")), log(2))
        XCTAssertNil(copy(second, "trials.json"))

        XCTAssertTrue(v.restore(second))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(4))
        XCTAssertEqual(vault().load([Entry].self, "weights.json"), log(2))
        XCTAssertEqual(vault().load([Entry].self, "trials.json"), log(1), "a store the set does not hold is left as it is")
    }

    /// The first time copies are kept (the first build with a vault), what is there is kept as found.
    func testWhatIsThereBeforeTheFirstCopyIsKeptAsFound() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try LumaVault.encoder().encode(log(9)).write(to: dir.appendingPathComponent("fuel.json"))
        try LumaVault.encoder().encode(log(2)).write(to: dir.appendingPathComponent("lifts.json"))
        let v = vault()
        XCTAssertEqual(v.load([Entry].self, "fuel.json"), log(9))
        XCTAssertTrue(v.save(log(10), "fuel.json"))
        XCTAssertTrue(v.save(log(3), "lifts.json"))
        let found = v.backupList().filter { $0.kind == .asFound }
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.files, ["fuel.json", "lifts.json"])
        XCTAssertEqual(found.first?.keptDay, day())
        XCTAssertEqual(entries(copy(found[0].name, "fuel.json")), log(9))
        XCTAssertEqual(entries(copy(found[0].name, "lifts.json")), log(2))
    }

    func testASaveThatWouldLeaveUnderHalfKeepsWhatWasThere() {
        let v = vault()
        XCTAssertTrue(v.save(log(200), "fuel.json"))
        let full = raw("fuel.json")
        XCTAssertTrue(v.save(log(2), "fuel.json"))
        let kept = v.backupList().filter { $0.kind == .beforeChange }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.files, ["fuel.json"])
        XCTAssertEqual(copy(kept[0].name, "fuel.json"), full)
        // An ordinary save that grows the file keeps nothing extra.
        XCTAssertTrue(v.save(log(3), "fuel.json"))
        XCTAssertEqual(v.backupList().filter { $0.kind == .beforeChange }.count, 1)
        // It can be gone back to like any other set, and it is in the vault's log.
        XCTAssertTrue(v.restore(kept[0].name))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(200))
        XCTAssertTrue(v.events().contains { $0.contains("fuel.json went from") })
    }

    func testADayCanBeGoneBackToAndTheRestoreUndone() {
        let v = vault()
        XCTAssertTrue(v.save(log(30), "fuel.json"))
        XCTAssertTrue(v.save(Entry(title: "Aniket", kcal: 0), "profile.json"))
        let good = day()
        clock += 86_400
        XCTAssertTrue(v.save(log(1), "fuel.json"))
        XCTAssertTrue(v.save(Entry(title: "", kcal: 0), "profile.json"))

        XCTAssertTrue(v.restore(good))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(30))
        XCTAssertEqual(vault().load(Entry.self, "profile.json"), Entry(title: "Aniket", kcal: 0))
        // What was there before the restore is its own set, and can be put back.
        let undo = v.backupList().first { $0.kind == .beforeRestore }
        XCTAssertEqual(undo?.files, ["fuel.json", "profile.json"])
        XCTAssertEqual(undo?.keptDay, day())
        XCTAssertNotNil(undo?.keptTime)
        XCTAssertTrue(v.restore(undo?.name ?? ""))
        XCTAssertEqual(vault().load([Entry].self, "fuel.json"), log(1))
        XCTAssertFalse(v.restore("2001-01-01"), "a day with no copies changes nothing")
    }

    /// What happens to the records is written where it is still found after the app is closed, and
    /// what could not be written when it happened is written with the next that can.
    func testTheVaultKeepsALogOfWhatHappenedToTheRecords() {
        let first = vault()
        XCTAssertTrue(first.save(log(2), "fuel.json"))
        first.note("started with 3 records out of reach")
        XCTAssertEqual(first.events().count, 1, "held until there is a marker to write it in")
        first.markOpened()
        first.note("records read")
        let read = vault().events()
        XCTAssertEqual(read.count, 2)
        XCTAssertTrue(read[0].hasSuffix("started with 3 records out of reach"))
        XCTAssertTrue(read[1].hasPrefix(day()))
        // The marker is not one of the athlete's records.
        XCTAssertTrue(first.restore(day()))
        XCTAssertEqual(first.backupList().first { $0.kind == .beforeRestore }?.files, ["fuel.json"])
    }

    func testAStoresStateInAFewWords() {
        XCTAssertEqual(VaultNote(name: "fuel.json", read: .loaded, bytes: 47_000, savedAt: nil, failure: nil).words, "read, 46 KB")
        XCTAssertEqual(VaultNote(name: "fuel.json", read: .missing, bytes: nil, savedAt: nil, failure: nil).words, "nothing saved yet")
        XCTAssertEqual(VaultNote(name: "fuel.json", read: .blocked, bytes: 900, savedAt: nil, failure: "NSCocoaErrorDomain 257").words,
                       "could not be read (NSCocoaErrorDomain 257)")
        XCTAssertEqual(LumaVault.sizeText(860), "860 B")
        XCTAssertEqual(LumaVault.sizeText(1_300_000), "1.2 MB")
    }

    func testAFigureThatIsNotANumberDoesNotStopTheStoreBeingSaved() {
        let v = vault()
        let odd = [Entry(title: "a", kcal: .nan), Entry(title: "b", kcal: .infinity), Entry(title: "c", kcal: 12)]
        XCTAssertTrue(v.save(odd, "fuel.json"))
        let back = vault().load([Entry].self, "fuel.json")
        XCTAssertEqual(back?.count, 3)
        XCTAssertTrue(back?[0].kcal.isNaN ?? false)
        XCTAssertEqual(back?[1].kcal, .infinity)
        XCTAssertEqual(back?[2].kcal, 12)
    }

    func testWholeNumbersFromFiguresThatAreNotNumbers() {
        XCTAssertEqual(LNum.int(12.7), 12)
        XCTAssertEqual(LNum.int(-3.2), -3)
        XCTAssertEqual(LNum.int(Double.nan), 0)
        XCTAssertEqual(LNum.int(Double.infinity), 0)
        XCTAssertEqual(LNum.int(1e300), 9_000_000_000_000_000)
        XCTAssertEqual(LNum.int(Float(4.9)), 4)
    }

    func testNothingIsKeptWithoutADirectory() {
        let v = LumaVault(directory: nil)
        XCTAssertTrue(v.save(log(2), "fuel.json"))
        XCTAssertNil(v.load([Entry].self, "fuel.json"))
        XCTAssertTrue(v.isReady)
        XCTAssertTrue(v.backupList().isEmpty)
    }
}
