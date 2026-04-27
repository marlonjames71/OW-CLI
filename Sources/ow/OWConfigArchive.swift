import Foundation

struct OWConfigArchive: Codable, Equatable {
    var formatVersion: Int = 1
    var exportedAt: Date
    var sections: [ExportSection]
    var defaults: [DefaultAppAssociation]?
    var groups: GroupsData?
    var rules: [Rule]?
    var config: OWConfig?
    var fileOverrideNotes: [FileOverrideNote]?
}

struct DefaultAppAssociation: Codable, Equatable {
    var fileExtension: String
    var appName: String
    var bundleID: String
    var appPath: String?

    var appInfo: AppInfo? {
        if let app = AppResolver.resolve(bundleID: bundleID) {
            return app
        }
        if let app = AppResolver.resolve(appName) {
            return app
        }
        guard let appPath else {
            return nil
        }

        let url = URL(fileURLWithPath: appPath)
        guard
            FileManager.default.fileExists(atPath: url.path),
            let bundle = Bundle(url: url),
            let bundleID = bundle.bundleIdentifier
        else {
            return nil
        }

        return AppInfo(name: appName, bundleID: bundleID, url: url)
    }
}

struct FileOverrideNote: Codable, Equatable {
    var path: String
    var fileExtension: String
    var appName: String
    var bundleID: String
    var appPath: String?
}

enum ExportSection: String, Codable, CaseIterable, Equatable {
    case defaults
    case groups
    case rules
    case config
    case fileOverrideNotes

    static let defaultSections: [ExportSection] = allCases

    init?(token: String) {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "d", "defaults":
            self = .defaults
        case "g", "groups":
            self = .groups
        case "r", "rules":
            self = .rules
        case "c", "config":
            self = .config
        case "fon", "fileoverridenotes", "file-override-notes", "file_override_notes":
            self = .fileOverrideNotes
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .defaults:
            return "defaults"
        case .groups:
            return "groups"
        case .rules:
            return "rules"
        case .config:
            return "config"
        case .fileOverrideNotes:
            return "file override notes"
        }
    }
}

enum ExportSectionParser {
    static func selectedSections(only: String?, exclude: String?) throws -> [ExportSection] {
        var sections = try only.map(parseList) ?? ExportSection.defaultSections
        let excluded = try exclude.map(parseList) ?? []
        sections.removeAll { excluded.contains($0) }
        return sections
    }

    private static func parseList(_ value: String) throws -> [ExportSection] {
        var sections: [ExportSection] = []
        for rawToken in value.split(separator: ",") {
            let token = String(rawToken)
            guard let section = ExportSection(token: token) else {
                let valid = "defaults, groups, rules, config, fileOverrideNotes, or aliases d, g, r, c, fon"
                throw OWArchiveError.invalidSection(token, valid: valid)
            }
            if !sections.contains(section) {
                sections.append(section)
            }
        }
        return sections
    }
}

enum OWArchiveError: Error, LocalizedError {
    case invalidSection(String, valid: String)
    case noSectionsSelected
    case unsupportedFormatVersion(Int)
    case cannotResolveApp(DefaultAppAssociation)

    var errorDescription: String? {
        switch self {
        case .invalidSection(let section, let valid):
            return "Unknown export section '\(section)'. Use \(valid)."
        case .noSectionsSelected:
            return "No export sections selected."
        case .unsupportedFormatVersion(let version):
            return "Unsupported .owconfig format version: \(version)"
        case .cannotResolveApp(let defaultApp):
            return "Could not find app for .\(defaultApp.fileExtension): \(defaultApp.appName) (\(defaultApp.bundleID))"
        }
    }
}
