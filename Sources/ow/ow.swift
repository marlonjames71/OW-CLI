import ArgumentParser

@main
struct OW: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ow",
        abstract: "Manage default apps for file types on macOS.",
        subcommands: [Get.self, Set.self, List.self, Reset.self, RuleCommand.self, ConfigCommand.self]
    )
}
