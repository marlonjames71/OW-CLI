import AppKit
import CoreServices
import Foundation

/// Resolves an app name (e.g. "Skim") or bundle ID (e.g. "net.sourceforge.skim-app.skim")
/// to a fully-populated AppInfo.
enum AppResolver {

    /// Accepts either a bundle ID or a plain app name.
    static func resolve(_ nameOrBundleID: String) -> AppInfo? {
        // Heuristic: bundle IDs contain dots and no path separators.
        let looksLikeBundleID = nameOrBundleID.contains(".")
            && !nameOrBundleID.contains("/")
            && !nameOrBundleID.hasSuffix(".app")

        if looksLikeBundleID, let info = resolve(bundleID: nameOrBundleID) {
            return info
        }

        return resolveByName(nameOrBundleID)
    }

    /// Looks up an app by its bundle identifier using Launch Services.
    static func resolve(bundleID: String) -> AppInfo? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return appInfo(bundleID: bundleID, url: url)
        }

        guard
            let cfArray = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil),
            let urls = cfArray.takeRetainedValue() as? [URL],
            let url = urls.first
        else {
            return resolveBundleIDByScanningApplications(bundleID)
        }

        return appInfo(bundleID: bundleID, url: url)
    }

    /// Searches common app directories for an app by its display name.
    private static func resolveByName(_ name: String) -> AppInfo? {
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let searchDirs = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]

        for dir in searchDirs {
            let appURL = URL(fileURLWithPath: dir).appendingPathComponent(appName)
            guard
                FileManager.default.fileExists(atPath: appURL.path),
                let bundle = Bundle(url: appURL),
                let bundleID = bundle.bundleIdentifier
            else { continue }

            return appInfo(bundleID: bundleID, url: appURL)
        }

        return nil
    }

    private static func resolveBundleIDByScanningApplications(_ bundleID: String) -> AppInfo? {
        for appURL in applicationBundleURLs() {
            guard
                let bundle = Bundle(url: appURL),
                bundle.bundleIdentifier?.caseInsensitiveCompare(bundleID) == .orderedSame
            else {
                continue
            }
            return appInfo(bundleID: bundle.bundleIdentifier ?? bundleID, url: appURL)
        }
        return nil
    }

    private static func applicationBundleURLs() -> [URL] {
        let searchDirs = [
            "/Applications",
            "\(NSHomeDirectory())/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        var urls: [URL] = []

        for dir in searchDirs {
            let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                urls.append(url)
                enumerator.skipDescendants()
            }
        }

        return urls
    }

    private static func appInfo(bundleID: String, url: URL) -> AppInfo {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let name = displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
        return AppInfo(name: name, bundleID: bundleID, url: url)
    }
}
