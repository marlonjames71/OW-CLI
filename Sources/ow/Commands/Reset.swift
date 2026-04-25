import ArgumentParser
import Foundation

struct Reset: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Reset default app associations back to macOS defaults.",
        discussion: """
        Reset a single file type:

          ow reset .pdf

        Remove a per-file override (falls back to the system default):

          ow reset ~/Documents/report.pdf
          ow reset ~/Desktop/*.jpg ~/Desktop/*.jpeg

        Reset every custom file-type association at once:

          ow reset --all
        """
    )

    @Argument(help: "One or more file extensions (.pdf) or file paths. Omit when using --all.")
    var targets: [String] = []

    @Flag(name: .long, help: "Reset every custom file-type association.")
    var all: Bool = false

    @Flag(name: [.short, .long], help: "Skip confirmation prompts.")
    var yes: Bool = false

    func validate() throws {
        if all && !targets.isEmpty {
            throw ValidationError("Cannot combine --all with targets.")
        }
        if !all && targets.isEmpty {
            throw ValidationError("Provide one or more file extensions or paths, or use --all.")
        }
    }

    func run() throws {
        if all {
            try runResetAll()
        } else {
            try runResetTargets()
        }
    }

    private func runResetTargets() throws {
        for target in targets {
            if target.hasPrefix(".") {
                try runResetExtension(target)
            } else {
                try runResetFile(target)
            }
        }
    }

    // MARK: - Variants

    private func runResetExtension(_ target: String) throws {
        let ext = String(target.dropFirst())
        let current = try LaunchServicesClient.getDefaultApp(forExtension: ext)

        if !yes {
            let currentDescription = current.map { "\($0.name)" } ?? "(none)"
            let question = "Reset default for \(target)? Current: \(currentDescription)"
            guard Prompt.confirm(question) else {
                print("Cancelled.")
                return
            }
        }

        try LaunchServicesClient.resetDefaultApp(forExtension: ext)
        print("Reset default for \(target).")
    }

    private func runResetFile(_ target: String) throws {
        let url = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)

        if !yes {
            let question = "Remove per-file override for \(url.lastPathComponent)?"
            guard Prompt.confirm(question) else {
                print("Cancelled.")
                return
            }
        }

        let removed = try ExtendedAttributesClient.removeOverride(forFile: url)
        if removed {
            print("Removed override for \(url.lastPathComponent).")
        } else {
            print("No per-file override was set on \(url.lastPathComponent).")
        }
    }

    private func runResetAll() throws {
        if !yes {
            let phrase = "reset all open with"
            let message = """

              \u{1B}[1mThis will reset every custom file-type association on this machine.\u{1B}[0m
              All extensions will fall back to their macOS defaults.

            """
            guard Prompt.requirePhrase(message, phrase: phrase) else {
                print("Cancelled.")
                return
            }
        }

        try LaunchServicesClient.resetAllDefaults()
        print("All custom file-type associations have been reset.")
    }
}
