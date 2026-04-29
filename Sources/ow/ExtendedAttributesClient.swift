import AppKit
import CoreFoundation
import Darwin
import Foundation

/// Reads and writes per-file default app associations using the
/// `com.apple.LaunchServices.OpenWith` extended attribute — the same
/// mechanism Finder uses when you change "Open with" for a single file
/// in Get Info without clicking "Change All".
enum ExtendedAttributesClient {

    private static let key = "com.apple.LaunchServices.OpenWith"
    private static let quarantineKey = "com.apple.quarantine"

    // The binary plist stored in the xattr has these three fields.
    private struct Payload: Codable {
        var version: Int
        var path: String
        var bundleidentifier: String
    }

    // MARK: - Public API

    /// Returns the per-file default app for the given file, if one has been set.
    static func getDefaultApp(forFile url: URL) throws -> AppInfo? {
        try validateRegularFile(url)
        let path = url.path
        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { ptr in
            getxattr(path, key, ptr.baseAddress, size, 0, 0)
        }
        guard result >= 0 else { throw OWError.xattrReadError(errno) }

        let payload = try PropertyListDecoder().decode(Payload.self, from: data)
        let appURL = URL(fileURLWithPath: payload.path)
        let name = appURL.deletingPathExtension().lastPathComponent
        return AppInfo(name: name, bundleID: payload.bundleidentifier, url: appURL)
    }

    /// Writes a per-file default app association for the given file.
    static func setDefaultApp(_ app: AppInfo, forFile url: URL) throws {
        try validateRegularFile(url)
        let payload = Payload(
            version: 0,
            path: app.url.path,
            bundleidentifier: app.bundleID
        )

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(payload)

        let result = data.withUnsafeBytes { ptr in
            setxattr(url.path, key, ptr.baseAddress, data.count, 0, 0)
        }
        guard result == 0 else { throw OWError.xattrWriteError(errno) }

        try? FileOverrideStore.record(app, forFile: url)
        notifySystemOfChange()
        refreshFinder(for: url)
    }

    static func isQuarantined(_ url: URL) -> Bool {
        guard (try? isRegularFile(url)) == true else {
            return false
        }
        return getxattr(url.path, quarantineKey, nil, 0, 0, 0) > 0
    }

    static func clearQuarantine(forFile url: URL) throws {
        try validateRegularFile(url)
        let result = removexattr(url.path, quarantineKey, 0)
        if result == 0 {
            refreshFinder(for: url)
            return
        }
        if errno == ENOATTR {
            return
        }
        throw OWError.xattrWriteError(errno)
    }

    /// Removes the per-file default app association, if any.
    /// Returns `true` if an override was removed, `false` if there wasn't one.
    @discardableResult
    static func removeOverride(forFile url: URL) throws -> Bool {
        try validateRegularFile(url)
        let result = removexattr(url.path, key, 0)
        if result == 0 {
            try? FileOverrideStore.remove(forFile: url)
            notifySystemOfChange()
            refreshFinder(for: url)
            return true
        }
        // ENOATTR means there was no override to remove — not an error.
        if errno == ENOATTR {
            try? FileOverrideStore.remove(forFile: url)
            return false
        }
        throw OWError.xattrWriteError(errno)
    }

    private static func validateRegularFile(_ url: URL) throws {
        guard try isRegularFile(url) else {
            throw OWError.notARegularFile(url.path)
        }
    }

    private static func isRegularFile(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        return values.isRegularFile == true
    }

    // MARK: - Cache invalidation

    /// Tells lsd that the Launch Services handler database has changed so
    /// Finder and other clients pick up the new per-file association immediately.
    private static func notifySystemOfChange() {
        guard systemRefreshAllowed else {
            return
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("com.apple.LaunchServices.databaseChanged" as CFString),
            nil, nil, true
        )
    }

    /// Tells Finder to re-read the metadata for this specific file, so the
    /// Get Info panel reflects the new xattr without needing to reopen.
    private static func refreshFinder(for url: URL) {
        guard systemRefreshAllowed else {
            return
        }

        let script = "tell application \"Finder\" to update item POSIX file \"\(url.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static var systemRefreshAllowed: Bool {
        getenv("OW_DISABLE_SYSTEM_REFRESH") == nil
    }
}
