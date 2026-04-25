import Foundation

struct StoredFileOverride: Codable, Equatable {
    var path: String
    var fileExtension: String
    var appName: String
    var bundleID: String
    var appPath: String
    var updatedAt: Date

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var appInfo: AppInfo {
        AppInfo(name: appName, bundleID: bundleID, url: URL(fileURLWithPath: appPath))
    }
}

/// Persists OW-created per-file overrides. Finder stores per-file defaults as
/// xattrs, so there is no system-wide index to query later.
enum FileOverrideStore {

    static var storeURL: URL {
        StorageSupport.appSupportFile("file-overrides.json", envOverride: "OW_OVERRIDE_STORE")
    }

    static func load() -> [StoredFileOverride] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard
            let data = try? Data(contentsOf: storeURL),
            let overrides = try? decoder.decode([StoredFileOverride].self, from: data)
        else {
            return []
        }
        return overrides
    }

    static func save(_ overrides: [StoredFileOverride]) throws {
        try StorageSupport.ensureParentDirectory(for: storeURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(overrides)
        try data.write(to: storeURL, options: .atomic)
    }

    static func record(_ app: AppInfo, forFile url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        let override = StoredFileOverride(
            path: standardizedURL.path,
            fileExtension: LaunchServicesClient.normalizedExtension(standardizedURL.pathExtension),
            appName: app.name,
            bundleID: app.bundleID,
            appPath: app.url.path,
            updatedAt: Date()
        )

        var overrides = load()
        overrides.removeAll { $0.path == override.path }
        overrides.append(override)
        try save(overrides)
    }

    static func remove(forFile url: URL) throws {
        let path = url.standardizedFileURL.path
        var overrides = load()
        let before = overrides.count
        overrides.removeAll { $0.path == path }
        guard overrides.count < before else {
            return
        }
        try save(overrides)
    }

    static func currentOverrides(
        forExtension ext: String,
        excludingBundleID bundleID: String
    ) -> [FileOverride] {
        let normalizedExt = LaunchServicesClient.normalizedExtension(ext)
        let stored = load()
        var keptRecords: [StoredFileOverride] = []
        var matchingOverrides: [FileOverride] = []

        for record in stored {
            let url = record.url
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }

            guard let currentApp = try? ExtendedAttributesClient.getDefaultApp(forFile: url) else {
                continue
            }

            var currentRecord = record
            if currentApp.bundleID.caseInsensitiveCompare(record.bundleID) != ComparisonResult.orderedSame {
                currentRecord = StoredFileOverride(
                    path: url.standardizedFileURL.path,
                    fileExtension: LaunchServicesClient.normalizedExtension(url.pathExtension),
                    appName: currentApp.name,
                    bundleID: currentApp.bundleID,
                    appPath: currentApp.url.path,
                    updatedAt: Date()
                )
            }
            keptRecords.append(currentRecord)

            guard currentRecord.fileExtension == normalizedExt else {
                continue
            }

            guard currentRecord.bundleID.caseInsensitiveCompare(bundleID) != ComparisonResult.orderedSame else {
                continue
            }

            matchingOverrides.append(FileOverride(url: url, app: currentRecord.appInfo))
        }

        if keptRecords != stored {
            try? save(keptRecords)
        }

        return matchingOverrides.sorted {
            $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
        }
    }
}
