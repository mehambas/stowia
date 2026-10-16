import Foundation

/// What the migration needs from UserDefaults, so tests can use a dictionary instead of leaving domains behind.
public protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

/// Stowia was called Sakla before its first release. Its history and settings are copied once and the originals are
/// left where they are, so going back to Sakla loses nothing.
public enum SaklaMigration {
    public static let marker = "migratedFromSakla"
    public static let oldDomain = "com.hamzabasaran.sakla"
    /// Old key → new key. The menu bar position and window frame are stored under names that contained the old one.
    static let keys = [
        "preferences": "preferences",
        "paused": "paused",
        "NSStatusItem Preferred Position com.hamzabasaran.sakla.menubar": "NSStatusItem Preferred Position com.hamzabasaran.stowia.menubar",
        "NSWindow Frame SaklaMainWindow": "NSWindow Frame StowiaMainWindow"
    ]

    /// Copies the history while Stowia has none of its own, and the settings Stowia doesn't have yet. Returns false
    /// when the history could not be copied; the next launch tries again until Stowia has saved a history itself.
    @discardableResult
    public static func run(from oldDirectory: URL, to newDirectory: URL, oldDefaults: SettingsStore?, newDefaults: SettingsStore) -> Bool {
        guard newDefaults.object(forKey: marker) as? Bool != true else { return true }
        let manager = FileManager.default
        if manager.fileExists(atPath: oldDirectory.appendingPathComponent("history.json").path),
           !manager.fileExists(atPath: newDirectory.appendingPathComponent("history.json").path) {
            // Copying under another name first keeps a half-copied folder from passing for a finished one.
            let partial = newDirectory.deletingLastPathComponent().appendingPathComponent(newDirectory.lastPathComponent + ".migrating")
            do {
                try? manager.removeItem(at: partial)
                try manager.copyItem(at: oldDirectory, to: partial)
                if manager.fileExists(atPath: newDirectory.path) {
                    _ = try manager.replaceItemAt(newDirectory, withItemAt: partial)
                } else {
                    try manager.moveItem(at: partial, to: newDirectory)
                }
            } catch {
                try? manager.removeItem(at: partial)
                return false
            }
        }
        if let oldDefaults {
            for (old, new) in keys where newDefaults.object(forKey: new) == nil {
                if let value = oldDefaults.object(forKey: old) { newDefaults.set(value, forKey: new) }
            }
        }
        newDefaults.set(true, forKey: marker)
        return true
    }
}
