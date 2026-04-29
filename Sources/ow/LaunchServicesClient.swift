import CoreServices
import Foundation
import UniformTypeIdentifiers

/// Wraps the macOS Launch Services APIs for reading and writing
/// system-wide default app associations.
enum LaunchServicesClient {

    // MARK: - UTI resolution

    static func normalizedExtension(_ ext: String) -> String {
        ext.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespacesAndNewlines))
            .lowercased()
    }

    static func uti(forExtension ext: String) -> String? {
        let normalizedExt = normalizedExtension(ext)
        guard !normalizedExt.isEmpty else {
            return nil
        }

        if let knownUTI = knownUTIsByExtension[normalizedExt] {
            return knownUTI
        }

        guard let type = UTType(filenameExtension: normalizedExt) else {
            return nil
        }

        // macOS can synthesize dynamic `dyn.*` identifiers for extensions that
        // no installed app has declared as a real type. Do not expose those as
        // writable content types; callers can still use a raw filename-
        // extension handler, matching Finder's Info pane behavior.
        guard !type.identifier.hasPrefix("dyn.") else {
            return nil
        }

        return type.identifier
    }

    private static let knownUTIsByExtension: [String: String] = [
        "css": "public.css",
        "gif": "com.compuserve.gif",
        "heic": "public.heic",
        "htm": "public.html",
        "html": "public.html",
        "jpeg": "public.jpeg",
        "jpg": "public.jpeg",
        "js": "com.netscape.javascript-source",
        "json": "public.json",
        "md": "public.markdown",
        "mov": "com.apple.quicktime-movie",
        "mp3": "public.mp3",
        "mp4": "public.mpeg-4",
        "pdf": "com.adobe.pdf",
        "png": "public.png",
        "py": "public.python-script",
        "rtf": "public.rtf",
        "sh": "public.shell-script",
        "swift": "public.swift-source",
        "text": "public.plain-text",
        "toml": "public.toml",
        "txt": "public.plain-text",
        "wav": "com.microsoft.waveform-audio",
        "xml": "public.xml",
        "yaml": "public.yaml",
        "yml": "public.yaml",
        "zip": "public.zip-archive",
    ]

    // MARK: - Public API

    /// Returns the current default app for the given file extension.
    static func getDefaultApp(forExtension ext: String) throws -> AppInfo? {
        let normalizedExt = normalizedExtension(ext)
        guard !normalizedExt.isEmpty else {
            throw OWError.unknownExtension(normalizedExt)
        }
        let uti = uti(forExtension: normalizedExt)

        if let uti {
            if let app = defaultAppFromTemporaryFile(forExtension: normalizedExt) {
                return app
            }

            if let bundleID = LSCopyDefaultRoleHandlerForContentType(
                uti as CFString, .all
            )?.takeRetainedValue() as String? {
                return AppResolver.resolve(bundleID: bundleID)
            }
        }

        if let bundleID = databaseDefaultBundleID(ext: normalizedExt, uti: uti) {
            return AppResolver.resolve(bundleID: bundleID)
        }
        return nil
    }

    /// Sets the system-wide default app for the given file extension.
    ///
    /// Writes Finder-shaped Launch Services plist entries directly. This avoids
    /// the asynchronous macOS confirmation alert triggered by the public setter
    /// and covers both UTI-based and filename-extension handlers.
    static func setDefaultApp(_ app: AppInfo, forExtension ext: String) throws {
        let normalizedExt = normalizedExtension(ext)
        guard !normalizedExt.isEmpty else {
            throw OWError.unknownExtension(normalizedExt)
        }
        let uti = uti(forExtension: normalizedExt)

        try writeToDatabase(bundleID: app.bundleID, uti: uti, ext: normalizedExt)
        refreshLaunchServices()

        guard waitForDefault(bundleID: app.bundleID, ext: normalizedExt, uti: uti) else {
            throw OWError.defaultChangeNotApplied(
                ext: normalizedExt,
                expected: app.bundleID,
                actual: currentDefaultBundleID(ext: normalizedExt, uti: uti)
            )
        }
    }

    /// Removes the custom default handler for the given file extension,
    /// restoring whatever macOS would choose by default.
    static func resetDefaultApp(forExtension ext: String) throws {
        let normalizedExt = normalizedExtension(ext)
        guard !normalizedExt.isEmpty else {
            throw OWError.unknownExtension(normalizedExt)
        }
        let uti = uti(forExtension: normalizedExt)

        try removeHandlers(matching: { handler in
            (uti != nil && handlerContentType(handler) == uti)
                || handlerFilenameExtension(handler) == normalizedExt
        })
        refreshLaunchServices()
    }

    /// Removes every custom content-type or filename-extension handler from
    /// the Launch Services database, effectively restoring macOS defaults for
    /// file types. URL scheme handlers (`LSHandlerURLScheme`) are preserved.
    static func resetAllDefaults() throws {
        try removeHandlers(matching: { handler in
            handler["LSHandlerContentType"] != nil
                || handler["LSHandlerContentTagClass"] as? String == "public.filename-extension"
        })
        refreshLaunchServices()
    }

    /// Returns all apps registered to open the given file extension,
    /// sorted alphabetically by display name.
    static func listApps(forExtension ext: String) throws -> [AppInfo] {
        let normalizedExt = normalizedExtension(ext)
        guard let uti = uti(forExtension: normalizedExt) else {
            throw OWError.unknownExtension(normalizedExt)
        }

        guard let bundleIDs = LSCopyAllRoleHandlersForContentType(
            uti as CFString, .all
        )?.takeRetainedValue() as? [String] else {
            return scanApplications(forExtension: normalizedExt, uti: uti)
        }

        let apps = bundleIDs
            .compactMap { AppResolver.resolve(bundleID: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return apps.isEmpty ? scanApplications(forExtension: normalizedExt, uti: uti) : apps
    }

    static func customDefaultApps() -> [DefaultAppAssociation] {
        let handlers = loadDatabase()["LSHandlers"] as? [[String: Any]] ?? []
        var defaultsByExtension: [String: DefaultAppAssociation] = [:]

        for handler in handlers {
            guard
                let ext = handlerFilenameExtension(handler),
                let bundleID = roleBundleID(from: handler),
                let app = AppResolver.resolve(bundleID: bundleID)
            else {
                continue
            }

            defaultsByExtension[ext] = DefaultAppAssociation(
                fileExtension: ext,
                appName: app.name,
                bundleID: app.bundleID,
                appPath: app.url.path
            )
        }

        return defaultsByExtension.values.sorted {
            $0.fileExtension.localizedCaseInsensitiveCompare($1.fileExtension) == .orderedAscending
        }
    }

    // MARK: - Direct database write

    private static var databaseURL: URL {
        if let override = getenv("OW_LAUNCHSERVICES_PLIST") {
            return URL(fileURLWithPath: (String(cString: override) as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
    }

    private static func loadDatabase() -> [String: Any] {
        if let data = try? Data(contentsOf: databaseURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return plist
        }
        return [:]
    }

    private static func loadDatabaseForMutation() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: databaseURL)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw OWError.launchServicesDatabaseInvalid(databaseURL.path)
        }
        return plist
    }

    private static func saveDatabase(_ root: [String: Any]) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        let backupURL = try backupDatabaseIfPresent()
        let tempURL = directory.appendingPathComponent(".\(databaseURL.lastPathComponent).ow-write-\(UUID().uuidString)")

        do {
            try data.write(to: tempURL, options: .atomic)
            try validateLaunchServicesPlist(at: tempURL)
            try replaceDatabase(with: tempURL)
            try validateLaunchServicesPlist(at: databaseURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            if let backupURL {
                do {
                    try restoreDatabase(from: backupURL)
                } catch let restoreError {
                    throw OWError.launchServicesRestoreFailed(
                        writeError: error.localizedDescription,
                        restoreError: restoreError.localizedDescription
                    )
                }
            }
            throw error
        }
    }

    /// Mirrors Finder's Launch Services plist entries. Known file types get
    /// both a content-type handler and a filename-extension handler. Unknown
    /// extensions get only the filename-extension handler; Finder does not
    /// write `dyn.*` content-type handlers for these, and neither should OW.
    private static func writeToDatabase(bundleID: String, uti: String?, ext: String) throws {
        var root = try loadDatabaseForMutation()
        var handlers = root["LSHandlers"] as? [[String: Any]] ?? []
        handlers.removeAll { handler in
            (uti != nil && handlerContentType(handler) == uti)
                || handlerFilenameExtension(handler) == ext
        }

        if let uti {
            handlers.append(contentTypeHandler(bundleID: bundleID, uti: uti))
        }
        handlers.append(filenameExtensionHandler(bundleID: bundleID, ext: ext))
        root["LSHandlers"] = handlers

        try saveDatabase(root)
    }

    private static func contentTypeHandler(bundleID: String, uti: String) -> [String: Any] {
        var handler: [String: Any] = [
            "LSHandlerContentType": uti,
            "LSHandlerModificationDate": Date().timeIntervalSinceReferenceDate,
        ]
        addRoleHandlers(to: &handler, bundleID: bundleID)
        return handler
    }

    private static func filenameExtensionHandler(bundleID: String, ext: String) -> [String: Any] {
        var handler: [String: Any] = [
            "LSHandlerContentTag": ext,
            "LSHandlerContentTagClass": "public.filename-extension",
            "LSHandlerModificationDate": Date().timeIntervalSinceReferenceDate,
        ]
        addRoleHandlers(to: &handler, bundleID: bundleID)
        return handler
    }

    private static func addRoleHandlers(to handler: inout [String: Any], bundleID: String) {
        var preferredVersions: [String: String] = [:]
        for roleKey in roleHandlerKeys {
            handler[roleKey] = bundleID
            preferredVersions[roleKey] = "-"
        }
        handler["LSHandlerPreferredVersions"] = preferredVersions
    }

    private static let roleHandlerKeys = [
        "LSHandlerRoleAll",
        "LSHandlerRoleViewer",
        "LSHandlerRoleEditor",
        "LSHandlerRoleShell",
    ]

    private static func handlerContentType(_ handler: [String: Any]) -> String? {
        handler["LSHandlerContentType"] as? String
    }

    private static func handlerFilenameExtension(_ handler: [String: Any]) -> String? {
        guard handler["LSHandlerContentTagClass"] as? String == "public.filename-extension" else {
            return nil
        }
        return (handler["LSHandlerContentTag"] as? String)?.lowercased()
    }

    private static func databaseDefaultBundleID(ext: String, uti: String?) -> String? {
        let handlers = loadDatabase()["LSHandlers"] as? [[String: Any]] ?? []
        if let uti, let handler = handlers.last(where: { handlerContentType($0) == uti }) {
            return roleBundleID(from: handler)
        }
        if let handler = handlers.last(where: { handlerFilenameExtension($0) == ext }) {
            return roleBundleID(from: handler)
        }
        return nil
    }

    private static func roleBundleID(from handler: [String: Any]) -> String? {
        for roleKey in roleHandlerKeys {
            if let bundleID = handler[roleKey] as? String {
                return bundleID
            }
        }
        return nil
    }

    // MARK: - Bundle scanning fallback

    private static func scanApplications(forExtension ext: String, uti: String) -> [AppInfo] {
        var appsByBundleID: [String: AppInfo] = [:]
        for appURL in applicationBundleURLs() {
            guard
                let bundle = Bundle(url: appURL),
                let bundleID = bundle.bundleIdentifier,
                appBundleCanOpen(bundle, ext: ext, uti: uti)
            else {
                continue
            }
            appsByBundleID[bundleID] = AppInfo(
                name: appDisplayName(bundle: bundle, url: appURL),
                bundleID: bundleID,
                url: appURL
            )
        }

        return appsByBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    private static func appBundleCanOpen(_ bundle: Bundle, ext: String, uti: String) -> Bool {
        guard let documentTypes = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] else {
            return false
        }

        for documentType in documentTypes {
            if let extensions = documentType["CFBundleTypeExtensions"] as? [String],
               extensions.contains(where: { $0 == "*" || $0.lowercased() == ext }) {
                return true
            }

            if let contentTypes = documentType["LSItemContentTypes"] as? [String],
               contentTypes.contains(where: { contentTypeMatches(claimed: $0, actual: uti) }) {
                return true
            }
        }

        return false
    }

    private static func contentTypeMatches(claimed: String, actual: String) -> Bool {
        guard claimed != "public.data", claimed != "public.item" else {
            return false
        }
        if claimed == actual {
            return true
        }
        guard let claimedType = UTType(claimed), let actualType = UTType(actual) else {
            return false
        }
        return actualType.conforms(to: claimedType)
    }

    private static func appDisplayName(bundle: Bundle, url: URL) -> String {
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent
    }

    // MARK: - Verification

    private static func currentDefaultBundleID(ext: String, uti: String?) -> String? {
        if getenv("OW_LAUNCHSERVICES_PLIST") != nil {
            return databaseDefaultBundleID(ext: ext, uti: uti)
        }

        if let uti {
            if let bundleID = defaultAppFromTemporaryFile(forExtension: ext)?.bundleID {
                return bundleID
            }

            if let bundleID = LSCopyDefaultRoleHandlerForContentType(
                uti as CFString, .all
            )?.takeRetainedValue() as String? {
                return bundleID
            }

            if let bundleID = LSCopyDefaultRoleHandlerForContentType(
                uti as CFString, .viewer
            )?.takeRetainedValue() as String? {
                return bundleID
            }

            if let bundleID = LSCopyDefaultRoleHandlerForContentType(
                uti as CFString, .editor
            )?.takeRetainedValue() as String? {
                return bundleID
            }
        }

        if let bundleID = databaseDefaultBundleID(ext: ext, uti: uti) {
            return bundleID
        }

        return nil
    }

    private static func waitForDefault(bundleID: String, ext: String, uti: String?) -> Bool {
        for _ in 0..<30 {
            if currentDefaultBundleID(ext: ext, uti: uti)?.caseInsensitiveCompare(bundleID) == .orderedSame {
                return true
            }
            usleep(200_000)
        }
        return false
    }

    private static func defaultAppFromTemporaryFile(forExtension ext: String) -> AppInfo? {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-launchservices-probe-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        FileManager.default.createFile(atPath: tempURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var unmanagedError: Unmanaged<CFError>?
        guard
            let unmanagedURL = LSCopyDefaultApplicationURLForURL(tempURL as CFURL, .all, &unmanagedError),
            let appURL = unmanagedURL.takeRetainedValue() as URL?,
            let bundle = Bundle(url: appURL),
            let bundleID = bundle.bundleIdentifier
        else {
            unmanagedError?.release()
            return nil
        }

        let name = appURL.deletingPathExtension().lastPathComponent
        return AppInfo(name: name, bundleID: bundleID, url: appURL)
    }

    /// Removes handler entries from the Launch Services plist that match
    /// the given predicate.
    private static func removeHandlers(matching predicate: ([String: Any]) -> Bool) throws {
        var root = try loadDatabaseForMutation()
        guard var handlers = root["LSHandlers"] as? [[String: Any]] else {
            return
        }

        handlers.removeAll(where: predicate)
        root["LSHandlers"] = handlers

        try saveDatabase(root)
    }

    private static func backupDatabaseIfPresent() throws -> URL? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        try validateLaunchServicesPlist(at: databaseURL)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("\(databaseURL.lastPathComponent).ow-backup-\(stamp)-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: databaseURL, to: backupURL)
        try validateLaunchServicesPlist(at: backupURL)
        return backupURL
    }

    private static func replaceDatabase(with tempURL: URL) throws {
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            _ = try FileManager.default.replaceItemAt(databaseURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: databaseURL)
        }
    }

    private static func restoreDatabase(from backupURL: URL) throws {
        try validateLaunchServicesPlist(at: backupURL)
        let restoreURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent(".\(databaseURL.lastPathComponent).ow-restore-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: backupURL, to: restoreURL)
        do {
            try replaceDatabase(with: restoreURL)
            try validateLaunchServicesPlist(at: databaseURL)
        } catch {
            try? FileManager.default.removeItem(at: restoreURL)
            throw error
        }
    }

    private static func validateLaunchServicesPlist(at url: URL) throws {
        _ = try Data(contentsOf: url)
        guard try isValidPlistWithPlutil(url) else {
            throw OWError.launchServicesDatabaseInvalid(url.path)
        }
        let data = try Data(contentsOf: url)
        guard (try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) != nil else {
            throw OWError.launchServicesDatabaseInvalid(url.path)
        }
    }

    private static func isValidPlistWithPlutil(_ url: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-lint", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Cache invalidation

    private static func refreshLaunchServices() {
        guard getenv("OW_LAUNCHSERVICES_PLIST") == nil,
              getenv("OW_DISABLE_SYSTEM_REFRESH") == nil else {
            return
        }

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDistributedCenter(),
            CFNotificationName("com.apple.LaunchServices.databaseChanged" as CFString),
            nil, nil, true
        )

        restartUserAgent(named: "cfprefsd")
        restartUserAgent(named: "lsd")
    }

    private static func restartUserAgent(named name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
