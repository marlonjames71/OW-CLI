import ArgumentParser

@main
struct OW: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ow",
        abstract: "Manage default apps for file types on macOS.",
        version: OWVersion.current,
        subcommands: [Get.self, Set.self, List.self, Reset.self, RuleCommand.self, GroupCommand.self, ConfigCommand.self, Wow.self]
    )
}
