import Darwin
import Foundation
import Testing
@testable import ow

@Suite(.serialized)
struct LaunchServicesClientTests {

    @Test func normalizesFileExtensions() {
        #expect(LaunchServicesClient.normalizedExtension(" .PDF ") == "pdf")
        #expect(LaunchServicesClient.normalizedExtension("md") == "md")
        #expect(LaunchServicesClient.normalizedExtension("..TXT") == "txt")
    }

    @Test func resolvesCommonExtensionsToCanonicalUTIs() {
        #expect(LaunchServicesClient.uti(forExtension: ".pdf") == "com.adobe.pdf")
        #expect(LaunchServicesClient.uti(forExtension: "txt") == "public.plain-text")
        #expect(LaunchServicesClient.uti(forExtension: "md") == "public.markdown")
    }

    @Test func rejectsSyntheticDynamicUTIsForUnknownExtensions() {
        #expect(LaunchServicesClient.uti(forExtension: "") == nil)
        #expect(LaunchServicesClient.uti(forExtension: ".owunregisteredtest") == nil)
    }

    @Test func resetExtensionRemovesUTIAndFilenameExtensionHandlers() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentType": "public.plain-text",
                "LSHandlerRoleAll": "com.example.editor",
            ],
            [
                "LSHandlerContentTag": "txt",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.example.editor",
            ],
            [
                "LSHandlerURLScheme": "example",
                "LSHandlerRoleAll": "com.example.editor",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        try LaunchServicesClient.resetDefaultApp(forExtension: ".txt")

        let handlers = try loadHandlers(from: url)
        #expect(handlers.count == 1)
        #expect(handlers.first?["LSHandlerURLScheme"] as? String == "example")
    }

    @Test func launchServicesWritesCreateBackupBeforeReplacingDatabase() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentTag": "txt",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.example.old",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        let app = AppInfo(
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )
        try LaunchServicesClient.setDefaultApp(app, forExtension: ".txt")

        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".ow-backup-") }

        #expect(backupURLs.count == 1)
        let backupHandlers = try loadHandlers(from: backupURLs[0])
        #expect(backupHandlers.first?["LSHandlerRoleAll"] as? String == "com.example.old")

        let updatedHandlers = try loadHandlers(from: url)
        #expect(updatedHandlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "txt"
                && handler["LSHandlerRoleAll"] as? String == "com.apple.TextEdit"
        })
        #expect(updatedHandlers.contains { handler in
            handler["LSHandlerContentType"] as? String == "public.plain-text"
                && handler["LSHandlerRoleAll"] as? String == "com.apple.TextEdit"
        })
    }

    @Test func launchServicesWriteRefusesCorruptExistingDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-corrupt-ls-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        try Data("not a plist".utf8).write(to: url)

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        let app = AppInfo(
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )

        do {
            try LaunchServicesClient.setDefaultApp(app, forExtension: ".txt")
            Issue.record("Expected corrupt Launch Services database to be rejected.")
        } catch let error as OWError {
            #expect(error.localizedDescription.contains("Launch Services database is invalid"))
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents == "not a plist")
    }

    @Test func launchServicesWriteUsesFilenameExtensionOnlyForUnknownExtensions() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentTag": "txt",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.example.old",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        let app = AppInfo(
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )

        try LaunchServicesClient.setDefaultApp(app, forExtension: ".owunregisteredtest")

        let handlers = try loadHandlers(from: url)
        #expect(handlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "txt"
                && handler["LSHandlerRoleAll"] as? String == "com.example.old"
        })
        #expect(handlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "owunregisteredtest"
                && handler["LSHandlerContentTagClass"] as? String == "public.filename-extension"
                && handler["LSHandlerRoleAll"] as? String == "com.apple.TextEdit"
        })
        #expect(!handlers.contains { handler in
            (handler["LSHandlerContentType"] as? String)?.hasPrefix("dyn.") == true
        })
    }

    @Test func resetUnknownExtensionRemovesFilenameExtensionHandler() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentTag": "owunregisteredtest",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.apple.TextEdit",
            ],
            [
                "LSHandlerContentTag": "txt",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.example.old",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        try LaunchServicesClient.resetDefaultApp(forExtension: ".owunregisteredtest")

        let handlers = try loadHandlers(from: url)
        #expect(!handlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "owunregisteredtest"
        })
        #expect(handlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "txt"
        })
    }

    @Test func readsUnknownExtensionDefaultFromFilenameExtensionHandler() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentTag": "owunregisteredtest",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.apple.TextEdit",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        let app = try #require(try LaunchServicesClient.getDefaultApp(forExtension: ".owunregisteredtest"))
        #expect(app.bundleID == "com.apple.TextEdit")
    }

    @Test func exportsUnknownExtensionDefaultsFromFilenameExtensionHandlers() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentTag": "owunregisteredtest",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.apple.TextEdit",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        let defaults = LaunchServicesClient.customDefaultApps()
        let association = try #require(defaults.first { $0.fileExtension == "owunregisteredtest" })
        #expect(association.bundleID == "com.apple.TextEdit")
    }

    @Test func mixedKnownAndUnknownGroupExtensionsUseSafeHandlers() throws {
        let plistURL = try temporaryLaunchServicesPlist([])
        let groupsURL = try temporaryGroupsStoreURL()
        setenv("OW_LAUNCHSERVICES_PLIST", plistURL.path, 1)
        setenv("OW_GROUPS_STORE", groupsURL.path, 1)
        defer {
            unsetenv("OW_LAUNCHSERVICES_PLIST")
            unsetenv("OW_GROUPS_STORE")
        }

        let group = try GroupsStore.createGroup(named: "stuff", extensions: [".txt", ".flux", ".md"])
        let app = AppInfo(
            name: "CotEditor",
            bundleID: "com.coteditor.CotEditor",
            url: URL(fileURLWithPath: "/Applications/CotEditor.app")
        )

        for ext in group.extensions {
            try LaunchServicesClient.setDefaultApp(app, forExtension: ext)
        }

        let handlers = try loadHandlers(from: plistURL)
        #expect(handlers.contains { handler in
            handler["LSHandlerContentType"] as? String == "public.plain-text"
                && handler["LSHandlerRoleAll"] as? String == app.bundleID
        })
        #expect(handlers.contains { handler in
            handler["LSHandlerContentType"] as? String == "public.markdown"
                && handler["LSHandlerRoleAll"] as? String == app.bundleID
        })
        #expect(handlers.contains { handler in
            handler["LSHandlerContentTag"] as? String == "flux"
                && handler["LSHandlerContentTagClass"] as? String == "public.filename-extension"
                && handler["LSHandlerRoleAll"] as? String == app.bundleID
        })
        #expect(!handlers.contains { handler in
            (handler["LSHandlerContentType"] as? String)?.hasPrefix("dyn.") == true
        })
    }

    @Test func resetAllPreservesURLSchemeHandlers() throws {
        let url = try temporaryLaunchServicesPlist([
            [
                "LSHandlerContentType": "public.markdown",
                "LSHandlerRoleAll": "com.example.editor",
            ],
            [
                "LSHandlerContentTag": "theme",
                "LSHandlerContentTagClass": "public.filename-extension",
                "LSHandlerRoleAll": "com.example.editor",
            ],
            [
                "LSHandlerURLScheme": "ow-test",
                "LSHandlerRoleAll": "com.example.editor",
            ],
        ])

        setenv("OW_LAUNCHSERVICES_PLIST", url.path, 1)
        defer { unsetenv("OW_LAUNCHSERVICES_PLIST") }

        try LaunchServicesClient.resetAllDefaults()

        let handlers = try loadHandlers(from: url)
        #expect(handlers.count == 1)
        #expect(handlers.first?["LSHandlerURLScheme"] as? String == "ow-test")
    }

    @Test func findsPerFileOverridesForExtension() throws {
        let storeURL = try temporaryOverrideStoreURL()
        setenv("OW_OVERRIDE_STORE", storeURL.path, 1)
        setenv("OW_DISABLE_SYSTEM_REFRESH", "1", 1)
        defer {
            unsetenv("OW_OVERRIDE_STORE")
            unsetenv("OW_DISABLE_SYSTEM_REFRESH")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-override-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let jpg = directory.appendingPathComponent("sample.jpg")
        let jpeg = directory.appendingPathComponent("sample.jpeg")
        let txt = directory.appendingPathComponent("sample.txt")
        FileManager.default.createFile(atPath: jpg.path, contents: Data())
        FileManager.default.createFile(atPath: jpeg.path, contents: Data())
        FileManager.default.createFile(atPath: txt.path, contents: Data())

        let preview = AppInfo(
            name: "Preview",
            bundleID: "com.apple.Preview",
            url: URL(fileURLWithPath: "/System/Applications/Preview.app")
        )
        let photomator = AppInfo(
            name: "Photomator",
            bundleID: "com.pixelmatorteam.pixelmator.touch.x.photo",
            url: URL(fileURLWithPath: "/Applications/Photomator.app")
        )

        try ExtendedAttributesClient.setDefaultApp(photomator, forFile: jpg)
        try ExtendedAttributesClient.setDefaultApp(preview, forFile: jpeg)
        try ExtendedAttributesClient.setDefaultApp(photomator, forFile: txt)

        let result = FileOverrideScanner.findOverrides(
            forExtension: "jpg",
            excludingBundleID: preview.bundleID,
            roots: [directory]
        )

        #expect(result.overrides.map { $0.url.standardizedFileURL } == [jpg.standardizedFileURL])
        #expect(result.overrides.map(\.app) == [photomator])
        #expect(result.stoppedEarly == false)
    }

    @Test func recordsAndRemovesPerFileOverrides() throws {
        let storeURL = try temporaryOverrideStoreURL()
        setenv("OW_OVERRIDE_STORE", storeURL.path, 1)
        setenv("OW_DISABLE_SYSTEM_REFRESH", "1", 1)
        defer {
            unsetenv("OW_OVERRIDE_STORE")
            unsetenv("OW_DISABLE_SYSTEM_REFRESH")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-override-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let jpg = directory.appendingPathComponent("sample.jpg")
        let jpeg = directory.appendingPathComponent("sample.jpeg")
        FileManager.default.createFile(atPath: jpg.path, contents: Data())
        FileManager.default.createFile(atPath: jpeg.path, contents: Data())

        let preview = AppInfo(
            name: "Preview",
            bundleID: "com.apple.Preview",
            url: URL(fileURLWithPath: "/System/Applications/Preview.app")
        )
        let photomator = AppInfo(
            name: "Photomator",
            bundleID: "com.pixelmatorteam.pixelmator.touch.x.photo",
            url: URL(fileURLWithPath: "/Applications/Photomator.app")
        )

        try ExtendedAttributesClient.setDefaultApp(photomator, forFile: jpg)
        try ExtendedAttributesClient.setDefaultApp(preview, forFile: jpeg)

        let overrides = FileOverrideStore.currentOverrides(
            forExtension: "jpg",
            excludingBundleID: preview.bundleID
        )

        #expect(overrides.map { $0.url.standardizedFileURL } == [jpg.standardizedFileURL])
        #expect(overrides.map(\.app) == [photomator])

        try ExtendedAttributesClient.removeOverride(forFile: jpg)

        let afterRemoval = FileOverrideStore.currentOverrides(
            forExtension: "jpg",
            excludingBundleID: preview.bundleID
        )
        #expect(afterRemoval.isEmpty)
    }

    @Test func perFileOverrideRejectsDirectories() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-directory-xattr-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let app = AppInfo(
            name: "TextEdit",
            bundleID: "com.apple.TextEdit",
            url: URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        )

        do {
            try ExtendedAttributesClient.setDefaultApp(app, forFile: directory)
            Issue.record("Expected directory target to be rejected.")
        } catch let error as OWError {
            #expect(error.localizedDescription.contains("Expected a file path"))
        }
    }

    @Test func loadsAndSavesConfig() throws {
        let configURL = try temporaryConfigStoreURL()
        setenv("OW_CONFIG_STORE", configURL.path, 1)
        defer { unsetenv("OW_CONFIG_STORE") }

        #expect(ConfigStore.load() == OWConfig())

        try ConfigStore.save(OWConfig(quarantine: .clear, exportPath: "/tmp/ow-export"))
        #expect(ConfigStore.load() == OWConfig(quarantine: .clear, exportPath: "/tmp/ow-export"))
    }

    @Test func readsLegacyConfigWhenCurrentConfigDoesNotExist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-config-migration-tests-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = directory
            .appendingPathComponent("legacy/config.json")
        let currentURL = directory
            .appendingPathComponent(".config/ow/config.json")
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let legacyConfig = OWConfig(quarantine: .ignore, exportPath: "/tmp/legacy")
        let data = try JSONEncoder().encode(legacyConfig)
        try data.write(to: legacyURL)

        setenv("OW_CONFIG_DIR", directory.appendingPathComponent(".config/ow").path, 1)
        setenv("OW_LEGACY_CONFIG_DIR", directory.appendingPathComponent("legacy").path, 1)
        unsetenv("OW_CONFIG_STORE")
        defer {
            unsetenv("OW_CONFIG_DIR")
            unsetenv("OW_LEGACY_CONFIG_DIR")
        }

        #expect(ConfigStore.load() == legacyConfig)

        try ConfigStore.save(OWConfig(quarantine: .clear, exportPath: "/tmp/current"))
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
        #expect(ConfigStore.load() == OWConfig(quarantine: .clear, exportPath: "/tmp/current"))
    }

    @Test func resolvesBuiltInFileTypeGroupsAndAliases() throws {
        let images = try #require(FileTypeGroup.named("images"))
        #expect(images.extensions.contains("jpg"))
        #expect(images.extensions.contains("png"))
        #expect(images.extensions.contains("heic"))

        #expect(FileTypeGroup.named("image") == images)
        #expect(FileTypeGroup.named("pictures") == images)
        #expect(FileTypeGroup.named("missing") == nil)
    }

    @Test func createsAndUpdatesCustomFileTypeGroups() throws {
        let storeURL = try temporaryGroupsStoreURL()
        setenv("OW_GROUPS_STORE", storeURL.path, 1)
        defer { unsetenv("OW_GROUPS_STORE") }

        let empty = try GroupsStore.createGroup(named: "design", extensions: [])
        #expect(empty.name == "design")
        #expect(empty.extensions.isEmpty)
        #expect(empty.source == .custom)

        let appended = try GroupsStore.append([".psd", "fig", ".sketch", "psd"], toGroupNamed: "design")
        #expect(appended.extensions == ["psd", "fig", "sketch"])

        let removed = try GroupsStore.remove([".fig"], fromGroupNamed: "design")
        #expect(removed.extensions == ["psd", "sketch"])
    }

    @Test func customizesBuiltInFileTypeGroupsWithAppendAndRemoveLayers() throws {
        let storeURL = try temporaryGroupsStoreURL()
        setenv("OW_GROUPS_STORE", storeURL.path, 1)
        defer { unsetenv("OW_GROUPS_STORE") }

        let removed = try GroupsStore.remove([".png", ".raw"], fromGroupNamed: "images")
        #expect(!removed.extensions.contains("png"))
        #expect(!removed.extensions.contains("raw"))
        #expect(removed.extensions.contains("jpg"))

        let appended = try GroupsStore.append([".psd", ".png"], toGroupNamed: "images")
        #expect(appended.extensions.contains("psd"))
        #expect(appended.extensions.contains("png"))
        #expect(!appended.extensions.contains("raw"))

        let customization = try #require(GroupsStore.customization(forBuiltInGroup: "images"))
        #expect(customization.appended == ["psd"])
        #expect(customization.removed == ["raw"])
    }

    @Test func listsBuiltInAndCustomFileTypeGroups() throws {
        let storeURL = try temporaryGroupsStoreURL()
        setenv("OW_GROUPS_STORE", storeURL.path, 1)
        defer { unsetenv("OW_GROUPS_STORE") }

        _ = try GroupsStore.createGroup(named: "design", extensions: [".psd"])
        _ = try GroupsStore.remove([".raw"], fromGroupNamed: "images")

        let groups = GroupsStore.allGroups()
        let images = try #require(groups.first { $0.name == "images" })
        let design = try #require(groups.first { $0.name == "design" })

        #expect(images.source == .builtIn)
        #expect(!images.extensions.contains("raw"))
        #expect(design.source == .custom)
        #expect(design.extensions == ["psd"])
    }

    @Test func parsesExportSectionNamesAndAliases() throws {
        let sections = try ExportSectionParser.selectedSections(only: "d,g,fon", exclude: nil)
        #expect(sections == [.defaults, .groups, .fileOverrideNotes])

        let withoutRules = try ExportSectionParser.selectedSections(only: nil, exclude: "r")
        #expect(!withoutRules.contains(.rules))
        #expect(withoutRules.contains(.defaults))
        #expect(withoutRules.contains(.fileOverrideNotes))
    }

    @Test func encodesAndDecodesOWConfigArchive() throws {
        let archive = OWConfigArchive(
            exportedAt: Date(timeIntervalSince1970: 1_775_000_000),
            sections: [.config, .fileOverrideNotes],
            defaults: nil,
            groups: nil,
            rules: nil,
            config: OWConfig(quarantine: .warn, exportPath: "/tmp/exports"),
            fileOverrideNotes: [
                FileOverrideNote(
                    path: "/Users/example/Desktop/test.txt",
                    fileExtension: "txt",
                    appName: "TextEdit",
                    bundleID: "com.apple.TextEdit",
                    appPath: "/System/Applications/TextEdit.app"
                ),
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OWConfigArchive.self, from: data)
        #expect(decoded == archive)
    }

    @Test func exportFileOverrideNotesSkipStalePaths() throws {
        let storeURL = try temporaryOverrideStoreURL()
        setenv("OW_OVERRIDE_STORE", storeURL.path, 1)
        defer { unsetenv("OW_OVERRIDE_STORE") }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-export-notes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent("existing.txt")
        let missing = directory.appendingPathComponent("missing.txt")
        FileManager.default.createFile(atPath: existing.path, contents: Data())

        try FileOverrideStore.save([
            StoredFileOverride(
                path: existing.path,
                fileExtension: "txt",
                appName: "TextEdit",
                bundleID: "com.apple.TextEdit",
                appPath: "/System/Applications/TextEdit.app",
                updatedAt: Date()
            ),
            StoredFileOverride(
                path: missing.path,
                fileExtension: "txt",
                appName: "TextEdit",
                bundleID: "com.apple.TextEdit",
                appPath: "/System/Applications/TextEdit.app",
                updatedAt: Date()
            ),
        ])

        let notes = Export.fileOverrideNotes()
        #expect(notes.map(\.path) == [existing.path])
    }

    private func temporaryLaunchServicesPlist(_ handlers: [[String: Any]]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("com.apple.launchservices.secure.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["LSHandlers": handlers],
            format: .binary,
            options: 0
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    private func loadHandlers(from url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        let root = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        return try #require(root["LSHandlers"] as? [[String: Any]])
    }

    private func temporaryOverrideStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-override-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("file-overrides.json")
    }

    private func temporaryConfigStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-config-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config.json")
    }

    private func temporaryGroupsStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ow-groups-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("groups.json")
    }
}
