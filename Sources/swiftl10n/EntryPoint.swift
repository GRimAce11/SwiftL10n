import ArgumentParser

@main
struct SwiftL10nCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftl10n",
        abstract: "Detect hardcoded localizable strings in Swift projects and generate a strongly-typed i18n API.",
        version: "0.9.0",
        subcommands: [ScanCommand.self, InitCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}
