import ArgumentParser
import Darwin
import Foundation

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set the default app for a file type or a specific file.",
        discussion: """
        Set system-wide default for all .pdf files:

          ow set .pdf Skim
          ow set .pdf                    # interactive picker

        For custom extensions macOS does not recognize yet, OW writes only the
        same filename-extension handler Finder writes from the Info pane:

          ow set .owconfig TextEdit

        Set a per-file override for one specific file:

          ow set ~/Documents/report.pdf Preview
          ow set ~/Documents/report.pdf  # interactive picker

        Pipe one or more file paths from another command — each receives
        a per-file override:

          echo ~/Documents/report.pdf | ow set Preview
          find ~/Documents -name "*.pdf" | ow set Skim
          find ~/projects -name Makefile | ow set "Visual Studio Code"
          find ~/Desktop -name "*.txt" | ow set --clear-quarantine TextEdit
        """
    )

    @Flag(name: .long, help: "Remove macOS quarantine from files after setting a per-file override.")
    var clearQuarantine: Bool = false

    @Argument(parsing: .remaining, help: "Target and optional app. See discussion above.")
    var args: [String] = []

    func run() throws {
        let isStdinPiped = isatty(STDIN_FILENO) == 0

        if isStdinPiped {
            let paths = collectPipedPaths()
            if paths.isEmpty {
                try runDirectInput()
            } else {
                try runPipedInput(paths: paths)
            }
        } else {
            try runDirectInput()
        }
    }

    // MARK: - Piped input (one or more file paths on stdin)

    private func collectPipedPaths() -> [String] {
        var paths: [String] = []
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            paths.append((trimmed as NSString).expandingTildeInPath)
        }
        return paths
    }

    private func runPipedInput(paths: [String]) throws {
        guard !paths.isEmpty else {
            throw ValidationError("No paths received on stdin.")
        }

        // Any positional arguments are the app name when piping (or interactive
        // when omitted). Joining lets `ow set Visual Studio Code` work.
        let appArg = joinedAppArgument(args)

        // For the interactive picker, base the candidate list on the first
        // file's extension — that's the most useful default. Users can still
        // pass an explicit app name to bypass this.
        let firstURL = URL(fileURLWithPath: paths[0])
        let firstExt = firstURL.pathExtension

        let resolvedApp = try resolveApp(
            appArg: appArg,
            ext: firstExt,
            displayTarget: paths.count == 1
                ? firstURL.lastPathComponent
                : "\(paths.count) files"
        )

        // Apply per-file override to each path, tracking results.
        var succeeded: [String] = []
        var failed: [(String, Error)] = []
        var quarantined: [URL] = []
        var clearedQuarantine = 0
        let quarantinePolicy = effectiveQuarantinePolicy()

        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                try ExtendedAttributesClient.setDefaultApp(resolvedApp, forFile: url)
                if ExtendedAttributesClient.isQuarantined(url) {
                    if quarantinePolicy == .clear {
                        try ExtendedAttributesClient.clearQuarantine(forFile: url)
                        clearedQuarantine += 1
                    } else if quarantinePolicy == .warn {
                        quarantined.append(url)
                    }
                }
                succeeded.append(url.lastPathComponent)
            } catch {
                failed.append((url.lastPathComponent, error))
            }
        }

        // Summarize.
        if paths.count == 1, let only = succeeded.first {
            print("\(resolvedApp.name) set for \(only).")
        } else {
            print("\(resolvedApp.name) set for \(succeeded.count) of \(paths.count) file(s).")
        }
        if clearedQuarantine > 0 {
            print("Cleared quarantine from \(clearedQuarantine) file\(clearedQuarantine == 1 ? "" : "s")\(quarantineClearReason()).")
        }
        printQuarantineWarning(for: quarantined)

        if !failed.isEmpty {
            print("\nFailed:")
            for (name, error) in failed {
                print("  \(name) — \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
    }

    // MARK: - Direct input (positional args, no pipe)

    private func runDirectInput() throws {
        guard let first = args.first else {
            throw ValidationError("Provide a file extension (e.g. .pdf) or a file path.")
        }
        let target = (first as NSString).expandingTildeInPath
        let appArg = joinedAppArgument(Array(args.dropFirst()))

        let isExtension = target.hasPrefix(".")
        let ext = isExtension
            ? String(target.dropFirst())
            : URL(fileURLWithPath: target).pathExtension

        let displayTarget = isExtension
            ? target
            : URL(fileURLWithPath: target).lastPathComponent

        let resolvedApp = try resolveApp(
            appArg: appArg,
            ext: ext,
            displayTarget: displayTarget
        )

        if isExtension {
            try LaunchServicesClient.setDefaultApp(resolvedApp, forExtension: ext)
            print("\(resolvedApp.name) is now the default for .\(ext) files.")
            printOverrideWarning(forExtension: ext, defaultApp: resolvedApp)
        } else {
            let fileURL = URL(fileURLWithPath: target)
            try ExtendedAttributesClient.setDefaultApp(resolvedApp, forFile: fileURL)
            if ExtendedAttributesClient.isQuarantined(fileURL) {
                let quarantinePolicy = effectiveQuarantinePolicy()
                if quarantinePolicy == .clear {
                    try ExtendedAttributesClient.clearQuarantine(forFile: fileURL)
                    print("\(resolvedApp.name) set for \(fileURL.lastPathComponent). Quarantine cleared\(quarantineClearReason()).")
                    return
                } else if quarantinePolicy == .warn {
                    print("\(resolvedApp.name) set for \(fileURL.lastPathComponent).")
                    printQuarantineWarning(for: [fileURL])
                    return
                }
            }
            print("\(resolvedApp.name) set for \(fileURL.lastPathComponent).")
        }
    }

    // MARK: - App resolution

    /// Resolves the app to use, either from the explicit argument or via the
    /// interactive picker (using `ext` to filter candidates).
    private func resolveApp(
        appArg: String?,
        ext: String,
        displayTarget: String
    ) throws -> AppInfo {
        if let appArg {
            guard let app = AppResolver.resolve(appArg) else {
                throw ValidationError("Could not find app: \(appArg)")
            }
            return app
        }

        guard !ext.isEmpty else {
            throw ValidationError("Cannot determine file type for: \(displayTarget)")
        }

        guard LaunchServicesClient.uti(forExtension: ext) != nil else {
            throw ValidationError("""
            Cannot open the app picker for .\(LaunchServicesClient.normalizedExtension(ext)) files because macOS has not registered that file type yet.

            OW can still set the default when you provide the app:
              ow set .\(LaunchServicesClient.normalizedExtension(ext)) <App Name>
            """)
        }

        let candidates = try LaunchServicesClient.listApps(forExtension: ext)
        guard !candidates.isEmpty else {
            throw ValidationError("No apps found that can open .\(ext) files.")
        }

        guard let selected = InteractiveSelector.select(
            from: candidates.map(\.name),
            prompt: "Select default app for \(displayTarget)"
        ) else {
            // User cancelled — exit cleanly.
            throw ExitCode.success
        }

        guard let match = candidates.first(where: { $0.name == selected }) else {
            throw ExitCode.success
        }
        return match
    }

    private func joinedAppArgument(_ parts: [String]) -> String? {
        let value = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func printOverrideWarning(forExtension ext: String, defaultApp: AppInfo) {
        let indexedOverrides = FileOverrideStore.currentOverrides(
            forExtension: ext,
            excludingBundleID: defaultApp.bundleID
        )
        let scanResult = FileOverrideScanner.findOverrides(
            forExtension: ext,
            excludingBundleID: defaultApp.bundleID
        )
        let overrides = mergedOverrides(indexedOverrides + scanResult.overrides)

        guard !overrides.isEmpty else {
            return
        }

        print("")
        print("These files have per-file overrides and will not use the .\(LaunchServicesClient.normalizedExtension(ext)) default:")
        for override in overrides {
            let path = FileOverrideScanner.displayPath(for: override.url)
            print("  \(path) → \(override.app.name)")
        }

        if scanResult.stoppedEarly {
            print("  ...scan stopped after reaching the result or file limit.")
        }

        print("")
        print("Remove them with:")
        print("  ow reset -y <file paths>")
    }

    private func printQuarantineWarning(for urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        print("")
        print("These files are quarantined by macOS and may be blocked when opened:")
        for url in urls.prefix(12) {
            print("  \(FileOverrideScanner.displayPath(for: url))")
        }

        if urls.count > 12 {
            print("  ...\(urls.count - 12) more")
        }

        print("")
        print("To clear quarantine while setting overrides, re-run with --clear-quarantine:")
        print("  ow set --clear-quarantine <file> <app>")
        print("  find <dir> -name \"*.ext\" | ow set --clear-quarantine <app>")
        print("Or set the default policy:")
        print("  ow config quarantine clear")
    }

    private func effectiveQuarantinePolicy() -> QuarantinePolicy {
        clearQuarantine ? .clear : ConfigStore.load().quarantine
    }

    private func quarantineClearReason() -> String {
        clearQuarantine ? "" : " based on config: quarantine=clear"
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
}
