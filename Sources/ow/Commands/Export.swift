import ArgumentParser
import Foundation

struct Export: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export portable OW settings to an .owconfig file.",
        discussion: """
        Export to the configured export path, or ~/Downloads if none is set:

          ow export

        Export to a directory or exact file path:

          ow export -p ~/Desktop
          ow export -p ~/Desktop/my-settings.owconfig

        Export selected sections:

          ow export --only defaults,groups
          ow export --only d,g
          ow export --exclude rules
          ow export --exclude r

        Sections:

          defaults            alias: d
          groups              alias: g
          rules               alias: r
          config              alias: c
          fileOverrideNotes   alias: fon
        """
    )

    @Option(name: [.short, .long], help: "Directory or exact .owconfig file path.")
    var path: String?

    @Option(name: .long, help: "Comma-separated sections to export.")
    var only: String?

    @Option(name: .long, help: "Comma-separated sections to exclude.")
    var exclude: String?

    func run() throws {
        let sections = try ExportSectionParser.selectedSections(only: only, exclude: exclude)
        guard !sections.isEmpty else {
            throw OWArchiveError.noSectionsSelected
        }

        let config = ConfigStore.load()
        let destination = try exportDestination(config: config)
        let archive = makeArchive(sections: sections, config: config)

        try StorageSupport.ensureParentDirectory(for: destination)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: destination, options: .atomic)

        print("Exported OW config to:")
        print("  \(destination.path)")
        print("")
        print("Sections:")
        print("  defaults: \(countDescription(archive.defaults?.count))")
        print("  groups: \(countDescription(archive.groups.map(groupCount)))")
        print("  rules: \(countDescription(archive.rules?.count))")
        print("  config: \(archive.config == nil ? "not exported" : "yes")")
        print("  file override notes: \(countDescription(archive.fileOverrideNotes?.count))")

        if path == nil, config.exportPath == nil {
            print("")
            print("Set a default export location with:")
            print("  ow config export-path ~/Desktop")
        }
    }

    private func makeArchive(sections: [ExportSection], config: OWConfig) -> OWConfigArchive {
        OWConfigArchive(
            exportedAt: Date(),
            sections: sections,
            defaults: sections.contains(.defaults) ? LaunchServicesClient.customDefaultApps() : nil,
            groups: sections.contains(.groups) ? GroupsStore.load() : nil,
            rules: sections.contains(.rules) ? RulesStore.load() : nil,
            config: sections.contains(.config) ? config : nil,
            fileOverrideNotes: sections.contains(.fileOverrideNotes) ? Self.fileOverrideNotes() : nil
        )
    }

    private func exportDestination(config: OWConfig) throws -> URL {
        let rawPath = path ?? config.exportPath
        let destination: URL

        if let rawPath {
            destination = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
        } else {
            destination = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads", isDirectory: true)
        }

        if destination.pathExtension == "owconfig" {
            return destination
        }

        return availableExportURL(in: destination)
    }

    private func availableExportURL(in directory: URL) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"
        let stamp = dateFormatter.string(from: Date())

        let baseName = "ow_cli-\(stamp)"
        let first = directory.appendingPathComponent("\(baseName).owconfig")
        guard FileManager.default.fileExists(atPath: first.path) else {
            return first
        }

        for index in 2...999 {
            let candidate = directory.appendingPathComponent("\(baseName)-\(index).owconfig")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).owconfig")
    }

    static func fileOverrideNotes() -> [FileOverrideNote] {
        FileOverrideStore.load()
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map {
                FileOverrideNote(
                    path: $0.path,
                    fileExtension: $0.fileExtension,
                    appName: $0.appName,
                    bundleID: $0.bundleID,
                    appPath: $0.appPath
                )
            }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
    }

    private func groupCount(_ groups: GroupsData) -> Int {
        FileTypeGroup.all.count + groups.customGroups.count
    }

    private func countDescription(_ count: Int?) -> String {
        count.map(String.init) ?? "not exported"
    }
}
