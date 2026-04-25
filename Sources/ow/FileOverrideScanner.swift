import Foundation

struct FileOverride: Equatable {
    var url: URL
    var app: AppInfo
}

struct FileOverrideScanResult: Equatable {
    var overrides: [FileOverride]
    var stoppedEarly: Bool
}

enum FileOverrideScanner {

    static func findOverrides(
        forExtension ext: String,
        excludingBundleID bundleID: String,
        roots: [URL] = defaultSearchRoots(),
        limit: Int = 12,
        maxScannedFiles: Int = 20_000
    ) -> FileOverrideScanResult {
        let normalizedExt = LaunchServicesClient.normalizedExtension(ext)
        var overrides: [FileOverride] = []
        var scannedFiles = 0
        var stoppedEarly = false

        for root in roots {
            guard overrides.count < limit, scannedFiles < maxScannedFiles else {
                stoppedEarly = true
                break
            }

            scan(
                root: root,
                ext: normalizedExt,
                excludingBundleID: bundleID,
                limit: limit,
                maxScannedFiles: maxScannedFiles,
                scannedFiles: &scannedFiles,
                overrides: &overrides,
                stoppedEarly: &stoppedEarly
            )
        }

        return FileOverrideScanResult(overrides: overrides, stoppedEarly: stoppedEarly)
    }

    static func displayPath(for url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static func defaultSearchRoots() -> [URL] {
        let fileManager = FileManager.default
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true),
        ]

        return candidates.filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private static func scan(
        root: URL,
        ext: String,
        excludingBundleID bundleID: String,
        limit: Int,
        maxScannedFiles: Int,
        scannedFiles: inout Int,
        overrides: inout [FileOverride],
        stoppedEarly: inout Bool
    ) {
        let resourceKeys: Swift.Set<URLResourceKey> = [
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isRegularFileKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants]
        ) else {
            return
        }

        for case let url as URL in enumerator {
            guard overrides.count < limit, scannedFiles < maxScannedFiles else {
                stoppedEarly = true
                return
            }

            guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                continue
            }

            if values.isDirectory == true {
                if values.isHidden == true || values.isPackage == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            scannedFiles += 1
            guard url.pathExtension.caseInsensitiveCompare(ext) == .orderedSame else {
                continue
            }

            guard let app = try? ExtendedAttributesClient.getDefaultApp(forFile: url) else {
                continue
            }

            guard app.bundleID.caseInsensitiveCompare(bundleID) != ComparisonResult.orderedSame else {
                continue
            }

            overrides.append(FileOverride(url: url, app: app))
        }
    }
}
