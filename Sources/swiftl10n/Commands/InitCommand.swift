import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create a .swiftl10n.yml config file in the current directory."
    )

    @Option(name: .long, help: "Directory to scan for Swift source files.")
    var sources: String = "Sources"

    @Option(name: [.customShort("o"), .long], help: "Output path for the generated i18n.swift file.")
    var output: String = "Sources/Generated/i18n.swift"

    @Option(name: .long, help: "Minimum confidence threshold (0.0–1.0).")
    var minConfidence: Double = 0.85

    @Flag(name: .long, help: "Overwrite an existing .swiftl10n.yml without prompting.")
    var force: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let configURL = cwd.appendingPathComponent(ConfigLoader.fileName)

        if FileManager.default.fileExists(atPath: configURL.path), !force {
            print("\(ConfigLoader.fileName) already exists. Use --force to overwrite.")
            throw ExitCode.failure
        }

        let yaml = """
        # SwiftL10n configuration — https://github.com/GRimAce11/SwiftL10n
        # Run `swiftl10n scan` to detect localizable strings using this config.

        # Directories to scan (relative to this file).
        sources:
          - \(sources)

        # Localization output — generates i18n.swift.
        output:
          path: \(output)
          enum_name: i18n
          table_name: Localizable
          # merge_strategy: overwrite  # overwrite (default) | region (preserve manual code outside markers)

        # Strings below this score are ignored (0.0–1.0).
        minimum_confidence: \(String(format: "%.2f", minConfidence))

        # Paths or patterns to exclude. Examples:
        #   - Sources/Generated
        #   - "**/*.generated.swift"
        exclude: []

        # Cache per-file results to skip unchanged files on subsequent runs.
        incremental: false

        # Asset output — generates Assets.swift from .xcassets catalogs.
        # Set enabled: true to activate.
        assets:
          enabled: false
          path: Sources/Generated/Assets.swift
          enum_name: Assets

        # Incremental adoption — recognise your existing localization system.
        # Uncomment and configure if you use SwiftGen, NSLocalizedString, or a
        # custom enum. Patterns are prefix-and-boundary matched ("L10n." matches
        # "L10n.save" but not "L10nHelper.save").
        # existing_localization:
        #   patterns:
        #     - "L10n."
        #   exclude_arguments_of:
        #     - "NSLocalizedString"

        # Migration mode: audit (default) | incremental | strict
        #   audit:       report all hardcoded strings — zero breaking change
        #   incremental: skip already-localized call sites; report only gaps
        #   strict:      exit non-zero if any hardcoded string is found (CI enforcement)
        # migration:
        #   mode: audit
        """

        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        print("Created \(ConfigLoader.fileName)")
        print("")
        print("Edit the file to customise sources, output path, and exclusions,")
        print("then run:  swiftl10n scan")
    }
}
