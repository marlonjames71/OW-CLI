import ArgumentParser
import Foundation

struct GroupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "group",
        abstract: "Manage groups of related file types.",
        discussion: """
        List available groups:

          ow group list
          ow group show

        Create and manage custom groups:

          ow group create design
          ow group design append .psd .fig .sketch
          ow group delete design

        Show or change a group:

          ow group images show
          ow group images set Preview
          ow group images append .psd .ai
          ow group images remove .raw
        """
    )

    @Argument(parsing: .remaining, help: "A group action. Run 'ow help group' for examples.")
    var args: [String] = []

    func run() throws {
        guard let first = args.first else {
            printUsage()
            throw ExitCode.failure
        }

        switch first {
        case "list":
            try requireCount(1)
            listGroups()
        case "show":
            try requireCount(1)
            showAllGroups()
        case "create":
            try createGroup(Array(args.dropFirst()))
        case "delete":
            try deleteGroup(Array(args.dropFirst()))
        default:
            try runGroupAction(groupName: first, args: Array(args.dropFirst()))
        }
    }

    /// Dynamic group names make the nicer noun-first shape possible:
    ///
    ///     ow group images append .psd
    ///
    /// ArgumentParser cannot model `images` as a static subcommand because
    /// built-ins can be aliased and users can create their own groups. This
    /// dispatcher treats the first token as the group name and the second token
    /// as the action.
    private func runGroupAction(groupName: String, args: [String]) throws {
        guard let action = args.first else {
            try showGroup(groupName)
            return
        }

        switch action {
        case "show":
            try requireCount(args.count, expected: 1)
            try showGroup(groupName)
        case "set":
            try setGroup(groupName, appParts: Array(args.dropFirst()))
        case "append":
            try appendToGroup(groupName, extensions: Array(args.dropFirst()))
        case "remove":
            try removeFromGroup(groupName, extensions: Array(args.dropFirst()))
        default:
            throw ValidationError("Unknown group action '\(action)'. Use show, set, append, or remove.")
        }
    }

    private func listGroups() {
        let groups = GroupsStore.allGroups()
        let width = groups.map(\.name.count).max() ?? 0

        for group in groups {
            let pad = String(repeating: " ", count: width - group.name.count)
            let source = group.source == .custom ? "  [custom]" : ""
            print("  \(group.name)\(pad)  \(group.description)\(source)")
        }
    }

    private func showAllGroups() {
        let groups = GroupsStore.allGroups()

        for (index, group) in groups.enumerated() {
            if index > 0 {
                print("")
            }
            printGroupDetails(group)
        }
    }

    private func createGroup(_ args: [String]) throws {
        guard let name = args.first else {
            throw ValidationError("Provide a group name.")
        }

        let group = try GroupsStore.createGroup(
            named: name,
            extensions: Array(args.dropFirst())
        )

        if group.extensions.isEmpty {
            print("Created empty group '\(group.name)'.")
            print("Add file types with:")
            print("  ow group \(group.name) append .ext")
        } else {
            print("Created group '\(group.name)' with \(group.extensions.count) file type(s).")
            print(wrappedExtensions(group.extensions))
        }
    }

    private func deleteGroup(_ args: [String]) throws {
        guard args.count == 1, let name = args.first else {
            throw ValidationError("Provide one custom group name to delete.")
        }

        try GroupsStore.deleteGroup(named: name)
        print("Deleted group '\(FileTypeGroup.normalizedGroupName(name))'.")
    }

    private func showGroup(_ groupName: String) throws {
        let group = try resolvedGroup(named: groupName)
        printGroupDetails(group)
    }

    private func printGroupDetails(_ group: ResolvedFileTypeGroup) {
        let source = group.source == .custom ? "custom" : "built-in"
        print("\(group.name) (\(source)):")

        if group.extensions.isEmpty {
            print("  No file types yet.")
        } else {
            print(wrappedExtensions(group.extensions))
        }

        if group.source == .builtIn,
           let customization = GroupsStore.customization(forBuiltInGroup: group.name) {
            let appended = normalizedDisplayExtensions(customization.appended)
            let removed = normalizedDisplayExtensions(customization.removed)

            if !appended.isEmpty {
                print("  appended: \(appended)")
            }
            if !removed.isEmpty {
                print("  removed: \(removed)")
            }
        }
    }

    private func setGroup(_ groupName: String, appParts: [String]) throws {
        let group = try resolvedGroup(named: groupName)
        let appName = joinedAppArgument(appParts)
        guard let appName else {
            throw ValidationError("Provide an app name or bundle ID.")
        }
        guard let app = AppResolver.resolve(appName) else {
            throw ValidationError("Could not find app: \(appName)")
        }
        guard !group.extensions.isEmpty else {
            throw ValidationError("Group '\(group.name)' has no file types yet.")
        }

        var succeeded: [String] = []
        var failed: [(String, Error)] = []

        for ext in group.extensions {
            do {
                try LaunchServicesClient.setDefaultApp(app, forExtension: ext)
                succeeded.append(ext)
            } catch {
                failed.append((ext, error))
            }
        }

        print("\(app.name) is now the default for \(succeeded.count) of \(group.extensions.count) \(group.name) file type(s).")
        if !succeeded.isEmpty {
            print("Updated:")
            print(wrappedExtensions(succeeded))
        }

        printIndexedOverrideWarning(for: group, defaultApp: app)

        if !failed.isEmpty {
            print("")
            print("Failed:")
            for (ext, error) in failed {
                print("  .\(ext) — \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }

    private func appendToGroup(_ groupName: String, extensions: [String]) throws {
        guard !extensions.isEmpty else {
            throw ValidationError("Provide one or more file extensions to append.")
        }

        let group = try GroupsStore.append(extensions, toGroupNamed: groupName)
        print("Updated group '\(group.name)'.")
        print(wrappedExtensions(group.extensions))
    }

    private func removeFromGroup(_ groupName: String, extensions: [String]) throws {
        guard !extensions.isEmpty else {
            throw ValidationError("Provide one or more file extensions to remove.")
        }

        let group = try GroupsStore.remove(extensions, fromGroupNamed: groupName)
        print("Updated group '\(group.name)'.")
        if group.extensions.isEmpty {
            print("  No file types yet.")
        } else {
            print(wrappedExtensions(group.extensions))
        }
    }

    private func requireCount(_ expected: Int) throws {
        try requireCount(args.count, expected: expected)
    }

    private func requireCount(_ actual: Int, expected: Int) throws {
        guard actual == expected else {
            throw ValidationError("Unexpected extra arguments.")
        }
    }

    private func printUsage() {
        print("""
        Usage:
          ow group list
          ow group show
          ow group create <name> [extensions...]
          ow group delete <name>
          ow group <name> show
          ow group <name> set <app>
          ow group <name> append <extensions...>
          ow group <name> remove <extensions...>
        """)
    }
}

private func resolvedGroup(named name: String) throws -> ResolvedFileTypeGroup {
    guard let group = GroupsStore.group(named: name) else {
        let groups = GroupsStore.allGroups().map(\.name).joined(separator: ", ")
        throw ValidationError("Unknown group '\(name)'. Available groups: \(groups)")
    }
    return group
}

private func joinedAppArgument(_ parts: [String]) -> String? {
    let value = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func normalizedDisplayExtensions(_ extensions: [String]) -> String {
    extensions
        .map(LaunchServicesClient.normalizedExtension)
        .filter { !$0.isEmpty }
        .map { ".\($0)" }
        .joined(separator: " ")
}

private func wrappedExtensions(_ extensions: [String], indent: String = "  ", width: Int = 76) -> String {
    var lines: [String] = []
    var current = indent

    for ext in extensions.map({ ".\($0)" }) {
        let separator = current == indent ? "" : " "
        if current.count + separator.count + ext.count > width {
            lines.append(current)
            current = indent + ext
        } else {
            current += separator + ext
        }
    }

    if current != indent {
        lines.append(current)
    }
    return lines.joined(separator: "\n")
}

private func printIndexedOverrideWarning(for group: ResolvedFileTypeGroup, defaultApp: AppInfo) {
    let overrides = group.extensions.flatMap { ext in
        FileOverrideStore.currentOverrides(
            forExtension: ext,
            excludingBundleID: defaultApp.bundleID
        )
    }
    let merged = mergedOverrides(overrides)

    guard !merged.isEmpty else {
        return
    }

    print("")
    print("These indexed per-file overrides will not use the \(group.name) group default:")
    for override in merged.prefix(12) {
        let path = FileOverrideScanner.displayPath(for: override.url)
        print("  \(path) → \(override.app.name)")
    }

    if merged.count > 12 {
        print("  ...\(merged.count - 12) more")
    }

    print("")
    print("Remove them with:")
    print("  ow reset -y <file paths>")
}

private func mergedOverrides(_ overrides: [FileOverride]) -> [FileOverride] {
    var seen: Swift.Set<String> = []
    var merged: [FileOverride] = []

    for override in overrides.sorted(by: {
        $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending
    }) {
        let path = override.url.standardizedFileURL.path
        guard !seen.contains(path) else {
            continue
        }
        seen.insert(path)
        merged.append(override)
    }

    return merged
}
