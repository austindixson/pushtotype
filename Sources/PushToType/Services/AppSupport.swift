import Foundation

/// Application Support folder for PushToType, with a one-time copy from NotFluid.
enum AppSupport {
    static let folderName = "PushToType"
    static let legacyFolderName = "NotFluid"
    static let bundleID = "dev.pushtotype.app"
    static let legacyBundleID = "dev.n0tfluid.app"

    static func directory() -> URL {
        migrateFilesIfNeeded()
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    )[0]
    private static let lock = NSLock()
    private static var didMigrate = false

    private static func migrateFilesIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if didMigrate { return }
        didMigrate = true
        let dest = base.appendingPathComponent(folderName, isDirectory: true)
        let legacy = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        let files = FileManager.default
        guard !files.fileExists(atPath: dest.path), files.fileExists(atPath: legacy.path) else { return }
        try? files.copyItem(at: legacy, to: dest)
    }
}

enum SettingsMigration {
    private static let flag = "pushtotype.migratedLegacyDefaults"

    static func copyLegacyDomainIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: flag) { return }
        if defaults.object(forKey: "transcriptionEngine") == nil,
           let legacy = defaults.persistentDomain(forName: AppSupport.legacyBundleID) {
            copyMissing(legacy, into: defaults)
        }
        defaults.set(true, forKey: flag)
    }

    private static func copyMissing(_ legacy: [String: Any], into defaults: UserDefaults) {
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
