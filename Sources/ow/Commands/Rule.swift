import ArgumentParser
import Foundation

struct RuleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rule",
        abstract: "Manage rules for automatic per-file app associations.",
        discussion: """
        Add a rule so every Makefile opens in VS Code:

          ow rule add Makefile "Visual Studio Code"
          ow rule add Makefile           # interactive picker

        Glob patterns work too:

          ow rule add "*.env" "Visual Studio Code"

        Apply all rules to a directory tree:

          ow rule apply ~/projects
          ow rule apply                  # current directory
          ow rule apply ~/projects --dry-run

        List and remove rules:

          ow rule list
          ow rule remove Makefile
        """,
        subcommands: [Add.self, List.self, Remove.self, Apply.self]
    )
}

// MARK: - Add

extension RuleCommand {
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add a rule for a filename or glob pattern."
        )

        @Argument(help: "Filename or glob pattern (e.g. Makefile, *.env, Dockerfile).")
        var pattern: String

        @Argument(help: "App name or bundle ID. Omit to use the interactive picker.")
        var app: String?

        func run() throws {
            let resolvedApp = try resolveApp()
            let rule = Rule(
                pattern: pattern,
                appName: resolvedApp.name,
                bundleID: resolvedApp.bundleID,
                appPath: resolvedApp.url.path
            )
            try RulesStore.add(rule)
            print("Rule saved: \(pattern) → \(resolvedApp.name)")
        }

        private func resolveApp() throws -> AppInfo {
            if let app {
                guard let resolved = AppResolver.resolve(app) else {
                    throw ValidationError("Could not find app: \(app)")
                }
                return resolved
            }

            // Build a candidate list from the pattern's extension.
            // Extensionless patterns (Makefile, Dockerfile) fall back to
            // plain-text handlers, which surfaces all the usual code editors.
            let candidates = candidateApps()
            guard !candidates.isEmpty else {
                throw ValidationError("No apps found for pattern: \(pattern)")
            }

            guard let selected = InteractiveSelector.select(
                from: candidates.map(\.name),
                prompt: "Select app for \(pattern)"
            ) else {
                throw ExitCode.success
            }

            guard let match = candidates.first(where: { $0.name == selected }) else {
                throw ExitCode.success
            }
            return match
        }

        /// Returns apps relevant to the pattern, filtering by extension when
        /// possible and falling back to plain-text handlers otherwise.
        private func candidateApps() -> [AppInfo] {
            // Strip a leading glob star to extract the extension.
            // "*.env" → ".env" → "env"  |  "Makefile" → ""
            let stripped = pattern.hasPrefix("*") ? String(pattern.dropFirst()) : pattern
            let ext = URL(fileURLWithPath: stripped).pathExtension

            if !ext.isEmpty,
               let apps = try? LaunchServicesClient.listApps(forExtension: ext),
               !apps.isEmpty {
                return apps
            }

            // No meaningful extension — show plain-text handlers (editors, IDEs).
            return (try? LaunchServicesClient.listApps(forExtension: "txt")) ?? []
        }
    }
}

// MARK: - List

extension RuleCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all saved rules."
        )

        func run() throws {
            let rules = RulesStore.load()
            guard !rules.isEmpty else {
                print("No rules yet. Use 'ow rule add' to create one.")
                return
            }

            let width = rules.map(\.pattern.count).max() ?? 0
            print("")
            for rule in rules {
                let pad = String(repeating: " ", count: width - rule.pattern.count)
                print("  \(rule.pattern)\(pad)  →  \(rule.appName)")
            }
            print("")
        }
    }
}

// MARK: - Remove

extension RuleCommand {
    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove a rule by its pattern."
        )

        @Argument(help: "The pattern to remove (e.g. Makefile, *.env).")
        var pattern: String

        func run() throws {
            let removed = try RulesStore.remove(pattern: pattern)
            if removed {
                print("Removed rule for \(pattern).")
            } else {
                print("No rule found for \(pattern).")
            }
        }
    }
}

// MARK: - Apply

extension RuleCommand {
    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stamp per-file overrides on every file that matches a rule.",
            discussion: """
            Walks a directory recursively and applies saved rules to matching files.
            The first matching rule wins if a file matches more than one.

              ow rule apply ~/projects
              ow rule apply              # current directory
              ow rule apply ~/projects --dry-run
            """
        )

        @Argument(help: "Directory to scan. Defaults to the current directory.")
        var directory: String?

        @Flag(name: .long, help: "Preview changes without writing anything.")
        var dryRun: Bool = false

        func run() throws {
            let rules = RulesStore.load()
            guard !rules.isEmpty else {
                print("No rules yet. Use 'ow rule add' to create one.")
                return
            }

            let dirPath = directory.map { ($0 as NSString).expandingTildeInPath }
                ?? FileManager.default.currentDirectoryPath
            let dirURL = URL(fileURLWithPath: dirPath)

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("Not a directory: \(dirPath)")
            }

            // Walk the tree, skipping package descendants (e.g. inside .app bundles)
            // but including hidden files so dotfiles like .zshrc are covered.
            guard let enumerator = FileManager.default.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                throw ValidationError("Could not enumerate directory: \(dirPath)")
            }

            // Match files against rules (first match wins).
            var matches: [(rule: Rule, url: URL)] = []

            for case let fileURL as URL in enumerator {
                // Skip hidden directories (e.g. .git) but allow hidden files.
                if let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]),
                   vals.isDirectory == true,
                   vals.isHidden == true {
                    enumerator.skipDescendants()
                    continue
                }

                let filename = fileURL.lastPathComponent
                for rule in rules where rule.matches(filename: filename) {
                    matches.append((rule: rule, url: fileURL))
                    break
                }
            }

            guard !matches.isEmpty else {
                print("No files matched any rules in \(dirPath).")
                return
            }

            if dryRun {
                print("")
                print("  \u{1B}[2m(dry run — no changes will be made)\u{1B}[0m")
                print("")
                for (rule, url) in matches {
                    let rel = url.path.hasPrefix(dirPath)
                        ? String(url.path.dropFirst(dirPath.count + 1))
                        : url.path
                    print("  \(rel)  →  \(rule.appName)")
                }
                print("")
                print("  \(matches.count) file\(matches.count == 1 ? "" : "s") would be updated.")
                print("")
                return
            }

            // Apply and collect results.
            var succeeded = 0
            var failed: [(URL, Error)] = []

            for (rule, url) in matches {
                do {
                    try ExtendedAttributesClient.setDefaultApp(rule.appInfo, forFile: url)
                    succeeded += 1
                } catch {
                    failed.append((url, error))
                }
            }

            // Summary grouped by rule.
            var countByPattern: [String: Int] = [:]
            for (rule, _) in matches { countByPattern[rule.pattern, default: 0] += 1 }

            print("")
            for rule in rules where countByPattern[rule.pattern] != nil {
                let n = countByPattern[rule.pattern]!
                print("  \(rule.pattern)  (\(n) file\(n == 1 ? "" : "s"))  →  \(rule.appName)")
            }
            print("")

            if failed.isEmpty {
                print("  Stamped \(succeeded) file\(succeeded == 1 ? "" : "s").")
            } else {
                print("  Stamped \(succeeded) file\(succeeded == 1 ? "" : "s"), \(failed.count) failed:")
                for (url, error) in failed {
                    print("  ✗ \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            print("")
        }
    }
}
