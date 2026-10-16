import XCTest
@testable import StowiaCore

private final class Settings: SettingsStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class MigrationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("stowia-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func defaults() -> Settings { Settings() }

    private func oldHistory() throws -> URL {
        let old = root.appendingPathComponent("Sakla")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: old.appendingPathComponent("history.json"))
        try Data("clip".utf8).write(to: old.appendingPathComponent("A.clip"))
        return old
    }

    func testCopiesHistoryAndSettingsOnceAndKeepsTheOriginals() throws {
        let old = try oldHistory(), new = root.appendingPathComponent("Stowia")
        let oldDefaults = defaults(), newDefaults = defaults()
        oldDefaults.set(Data("prefs".utf8), forKey: "preferences")
        oldDefaults.set("{{1, 2}, {3, 4}}", forKey: "NSWindow Frame SaklaMainWindow")
        oldDefaults.set(1200.0, forKey: "NSStatusItem Preferred Position com.hamzabasaran.sakla.menubar")
        oldDefaults.set("unrelated", forKey: "other")

        XCTAssertTrue(SaklaMigration.run(from: old, to: new, oldDefaults: oldDefaults, newDefaults: newDefaults))
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("A.clip")), Data("clip".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("A.clip").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Stowia.migrating").path))
        XCTAssertEqual(newDefaults.values["preferences"] as? Data, Data("prefs".utf8))
        XCTAssertEqual(newDefaults.values["NSWindow Frame StowiaMainWindow"] as? String, "{{1, 2}, {3, 4}}")
        XCTAssertEqual(newDefaults.values["NSStatusItem Preferred Position com.hamzabasaran.stowia.menubar"] as? Double, 1200)
        XCTAssertNil(newDefaults.values["other"])
        XCTAssertEqual(newDefaults.values[SaklaMigration.marker] as? Bool, true)

        try Data("changed".utf8).write(to: old.appendingPathComponent("A.clip"))
        oldDefaults.set(Data("later".utf8), forKey: "preferences")
        SaklaMigration.run(from: old, to: new, oldDefaults: oldDefaults, newDefaults: newDefaults)
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("A.clip")), Data("clip".utf8), "Runs only once")
        XCTAssertEqual(newDefaults.values["preferences"] as? Data, Data("prefs".utf8))
    }

    func testNeverReplacesStowiasOwnHistoryOrSettings() throws {
        let old = try oldHistory(), new = root.appendingPathComponent("Stowia")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("[1]".utf8).write(to: new.appendingPathComponent("history.json"))
        let oldDefaults = defaults(), newDefaults = defaults()
        oldDefaults.set(true, forKey: "paused")
        newDefaults.set(false, forKey: "paused")

        XCTAssertTrue(SaklaMigration.run(from: old, to: new, oldDefaults: oldDefaults, newDefaults: newDefaults))
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("history.json")), Data("[1]".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: new.appendingPathComponent("A.clip").path))
        XCTAssertEqual(newDefaults.values["paused"] as? Bool, false)
    }

    func testFillsAnEmptyFolderAndWorksWithoutAnOldInstallation() throws {
        let old = try oldHistory(), new = root.appendingPathComponent("Stowia")
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        XCTAssertTrue(SaklaMigration.run(from: old, to: new, oldDefaults: nil, newDefaults: defaults()))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("A.clip").path))

        let fresh = root.appendingPathComponent("Fresh"), newDefaults = defaults()
        XCTAssertTrue(SaklaMigration.run(from: root.appendingPathComponent("Missing"), to: fresh, oldDefaults: nil, newDefaults: newDefaults))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertEqual(newDefaults.values[SaklaMigration.marker] as? Bool, true)
    }
}
