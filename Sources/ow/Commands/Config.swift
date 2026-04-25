import ArgumentParser
import Foundation

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View and update OW preferences.",
        discussion: """
        Show current config:

          ow config
          ow config quarantine

        Configure how OW handles quarantined files when setting per-file overrides:

          ow config quarantine warn
          ow config quarantine clear
          ow config quarantine ignore
        """,
        subcommands: [Quarantine.self]
    )

    func run() throws {
        let config = ConfigStore.load()
        print("quarantine: \(config.quarantine.rawValue)  (\(config.quarantine.description))")
    }
}

extension ConfigCommand {
    struct Quarantine: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "View or set how OW handles quarantined files."
        )

        @Argument(help: "Quarantine policy: warn, clear, or ignore. Omit to show the current policy.")
        var policy: QuarantinePolicy?

        func run() throws {
            let config = ConfigStore.load()
            guard let policy else {
                print("quarantine: \(config.quarantine.rawValue)  (\(config.quarantine.description))")
                return
            }

            var updatedConfig = config
            updatedConfig.quarantine = policy
            try ConfigStore.save(updatedConfig)
            print("quarantine: \(policy.rawValue)  (\(policy.description))")
        }
    }
}

extension QuarantinePolicy: ExpressibleByArgument {
    init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
