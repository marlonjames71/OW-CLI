import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all apps that can open a file type.",
        discussion: """
        ow list .pdf
        """
    )

    @Argument(help: "A file extension (e.g. .pdf).")
    var extension_: String

    func run() throws {
        let ext = extension_.hasPrefix(".") ? String(extension_.dropFirst()) : extension_
        let apps = try LaunchServicesClient.listApps(forExtension: ext)

        guard !apps.isEmpty else {
            print("No apps found for .\(ext) files.")
            return
        }

        let defaultApp = try? LaunchServicesClient.getDefaultApp(forExtension: ext)

        for app in apps {
            let isDefault = app.bundleID == defaultApp?.bundleID
            let marker = isDefault ? "> " : "  "
            let name = isDefault ? "\u{1B}[1m\(app.name)\u{1B}[0m" : app.name
            print("\(marker)\(name)  (\(app.bundleID))")
        }
    }
}
