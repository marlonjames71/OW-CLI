import ArgumentParser
import Foundation

struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the default app for a file type or a specific file.",
        discussion: """
        Pass a file extension to query the system-wide default:

          ow get .pdf

        Pass a file path to check if that file has a per-file override:

          ow get ~/Documents/report.pdf
        """
    )

    @Argument(help: "A file extension (e.g. .pdf) or a file path.")
    var target: String

    func run() throws {
        if target.hasPrefix(".") {
            try getForExtension(String(target.dropFirst()))
        } else {
            try getForFile(expandingPath: target)
        }
    }

    private func getForExtension(_ ext: String) throws {
        guard let app = try LaunchServicesClient.getDefaultApp(forExtension: ext) else {
            print("No default app found for .\(ext) files.")
            return
        }
        print("\(app.name)  (\(app.bundleID))")
    }

    private func getForFile(expandingPath path: String) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        // Check for a per-file override first.
        if let app = try ExtendedAttributesClient.getDefaultApp(forFile: url) {
            print("\(app.name)  (\(app.bundleID))  [file-specific]")
            return
        }

        // Fall back to the extension-level default.
        let ext = url.pathExtension
        guard !ext.isEmpty else {
            print("No file extension and no per-file override found.")
            return
        }
        guard let app = try LaunchServicesClient.getDefaultApp(forExtension: ext) else {
            print("No default app found for .\(ext) files.")
            return
        }
        print("\(app.name)  (\(app.bundleID))")
    }
}
