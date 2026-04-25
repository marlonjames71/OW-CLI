import Foundation

enum StorageSupport {
    static func appSupportFile(_ relativePath: String, envOverride: String? = nil) -> URL {
        if let envOverride, let value = getenv(envOverride) {
            return URL(fileURLWithPath: (String(cString: value) as NSString).expandingTildeInPath)
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ow/\(relativePath)")
    }

    static func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
