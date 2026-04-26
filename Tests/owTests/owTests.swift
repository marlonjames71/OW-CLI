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
        defer { unsetenv("OW_OVERRIDE_STORE") }

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
        defer { unsetenv("OW_OVERRIDE_STORE") }

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

    @Test func loadsAndSavesConfig() throws {
        let configURL = try temporaryConfigStoreURL()
        setenv("OW_CONFIG_STORE", configURL.path, 1)
        defer { unsetenv("OW_CONFIG_STORE") }

        #expect(ConfigStore.load() == OWConfig())

        try ConfigStore.save(OWConfig(quarantine: .clear))
        #expect(ConfigStore.load() == OWConfig(quarantine: .clear))
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
