import ArgumentParser

@main
struct SwiftL10nCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftl10n",
        abstract: "Detect hardcoded localizable strings in SwiftUI projects and generate a strongly-typed i18n API.",
        version: "0.1.0",
        subcommands: [ScanCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}
