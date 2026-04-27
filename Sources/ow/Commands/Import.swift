import ArgumentParser
import Foundation

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import portable OW settings from an .owconfig file.",
        discussion: """
        Import an OW config archive:

          ow import ~/Downloads/ow_cli-20260426.owconfig

        Preview without applying changes:

          ow import ~/Downloads/ow_cli-20260426.owconfig --dry-run

        Import applies defaults, groups, rules, and config when those sections
        are present. File override notes are reported but not applied because
        per-file overrides are machine-specific.
        """
    )

    @Argument(help: "Path to an .owconfig file.")
    var path: String

    @Flag(name: .long, help: "Preview import changes without applying them.")
    var dryRun: Bool = false

    func run() throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(OWConfigArchive.self, from: data)

        guard archive.formatVersion == 1 else {
            throw OWArchiveError.unsupportedFormatVersion(archive.formatVersion)
        }

        let result = try apply(archive)
        printSummary(result, source: url)
    }

    private func apply(_ archive: OWConfigArchive) throws -> ImportResult {
        var result = ImportResult()

        if let defaults = archive.defaults {
            result.hasDefaults = true
            result.defaultCount = defaults.count
            for defaultApp in defaults {
                guard let app = defaultApp.appInfo else {
                    result.unresolvedDefaults.append(defaultApp)
                    continue
                }
                if !dryRun {
                    try LaunchServicesClient.setDefaultApp(app, forExtension: defaultApp.fileExtension)
                }
                result.appliedDefaults += 1
            }
        }

        if let groups = archive.groups {
            result.groupCount = FileTypeGroup.all.count + groups.customGroups.count
            if !dryRun {
                try GroupsStore.save(groups)
            }
        }

        if let rules = archive.rules {
            result.ruleCount = rules.count
            if !dryRun {
                try RulesStore.save(rules)
            }
        }

        if let config = archive.config {
            result.hasConfig = true
            if !dryRun {
                try ConfigStore.save(config)
            }
        }

        result.fileOverrideNotes = archive.fileOverrideNotes ?? []
        return result
    }

    private func printSummary(_ result: ImportResult, source: URL) {
        let action = dryRun ? "Dry run for" : "Imported"
        print("\(action) OW config from \(source.lastPathComponent)")
        print("")
        print(dryRun ? "Would apply:" : "Applied:")
        print("  defaults: \(result.hasDefaults ? "\(result.appliedDefaults) of \(result.defaultCount)" : "not present")")
        print("  groups: \(result.groupCount.map(String.init) ?? "not present")")
        print("  rules: \(result.ruleCount.map(String.init) ?? "not present")")
        print("  config: \(result.hasConfig ? "yes" : "not present")")

        if !result.unresolvedDefaults.isEmpty {
            print("")
            print("Not applied:")
            for defaultApp in result.unresolvedDefaults {
                print("  .\(defaultApp.fileExtension) -> \(defaultApp.appName) (\(defaultApp.bundleID))")
            }
        }

        if !result.fileOverrideNotes.isEmpty {
            print("")
            print("Per-file overrides are machine-specific and were not applied:")
            for note in result.fileOverrideNotes.prefix(20) {
                print("  \(note.path) -> \(note.appName)")
            }
            if result.fileOverrideNotes.count > 20 {
                print("  ...\(result.fileOverrideNotes.count - 20) more")
            }
        }
    }
}

private struct ImportResult {
    var hasDefaults = false
    var defaultCount = 0
    var appliedDefaults = 0
    var groupCount: Int?
    var ruleCount: Int?
    var hasConfig = false
    var unresolvedDefaults: [DefaultAppAssociation] = []
    var fileOverrideNotes: [FileOverrideNote] = []
}
