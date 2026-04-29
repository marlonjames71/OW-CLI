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
        let ext = LaunchServicesClient.normalizedExtension(extension_)
        guard !ext.isEmpty else {
            throw ValidationError("Provide a file extension, such as .pdf.")
        }

        guard LaunchServicesClient.uti(forExtension: ext) != nil else {
            throw ValidationError("""
            Cannot list apps for .\(ext) files because macOS has not registered that file type yet.

            OW can still set a default when you provide the app:
              ow set .\(ext) <App Name>
            """)
        }

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
