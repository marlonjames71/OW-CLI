import Foundation

enum StorageSupport {
    static func configFile(_ relativePath: String, envOverride: String? = nil) -> URL {
        if let envOverride, let value = getenv(envOverride) {
            return URL(fileURLWithPath: (String(cString: value) as NSString).expandingTildeInPath)
        }

        return configDirectory.appendingPathComponent(relativePath)
    }

    static func readableConfigFile(_ relativePath: String, envOverride: String? = nil) -> URL {
        if let envOverride, let value = getenv(envOverride) {
            return URL(fileURLWithPath: (String(cString: value) as NSString).expandingTildeInPath)
        }

        let current = configFile(relativePath)
        if FileManager.default.fileExists(atPath: current.path) {
            return current
        }

        let legacy = legacyAppSupportFile(relativePath)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }

        return current
    }

    static func appSupportFile(_ relativePath: String, envOverride: String? = nil) -> URL {
        configFile(relativePath, envOverride: envOverride)
    }

    static func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    static var configDirectory: URL {
        if let value = getenv("OW_CONFIG_DIR") {
            return URL(fileURLWithPath: (String(cString: value) as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ow", isDirectory: true)
    }

    private static func legacyAppSupportFile(_ relativePath: String) -> URL {
        if let value = getenv("OW_LEGACY_CONFIG_DIR") {
            return URL(fileURLWithPath: (String(cString: value) as NSString).expandingTildeInPath)
                .appendingPathComponent(relativePath)
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ow/\(relativePath)")
    }
}
