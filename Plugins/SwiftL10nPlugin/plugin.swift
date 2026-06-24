import PackagePlugin
import Foundation

/// Build tool plugin that runs `swiftl10n scan` before Swift compilation,
/// eliminating the two-build gap caused by the runtime `.task {}` approach.
///
/// **For SPM package targets (Package.swift):**
/// ```swift
/// .target(
///     name: "MyApp",
///     plugins: [.plugin(name: "SwiftL10nPlugin", package: "SwiftL10n")]
/// )
/// ```
///
/// **For Xcode project targets (.xcodeproj):**
/// Use a Run Script Build Phase instead — `XcodeProjectPlugin` is not
/// reliably available across Xcode versions. Add a phase that runs:
///
///   $BUILD_DIR/../../SourcePackages/artifacts/swiftl10n/swiftl10n/bin/swiftl10n \
///     scan "$SRCROOT" \
///     --output "$DERIVED_FILE_DIR/i18n.swift" \
///     --assets-output "$DERIVED_FILE_DIR/Assets.swift"
///
/// See the README → "Xcode project (.xcodeproj) — Run Script setup" for
/// the complete copy-paste script.
@main
struct SwiftL10nPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let tool = try context.tool(named: "swiftl10n")
        let outputDir    = context.pluginWorkDirectory
        let i18nOutput   = outputDir.appending("i18n.swift")
        let assetsOutput = outputDir.appending("Assets.swift")
        let sourceDir    = sourceTarget.directory.string

        var args: [CustomStringConvertible] = [
            "scan", sourceDir,
            "--output", i18nOutput.string,
            "--assets-output", assetsOutput.string,
        ]

        if let configPath = findConfig(from: sourceDir) {
            args += ["--config", configPath]
        }

        let swiftInputs = sourceTarget.sourceFiles(withSuffix: "swift").map(\.path)

        return [
            .buildCommand(
                displayName: "SwiftL10n: generate i18n.swift + Assets.swift",
                executable: tool.path,
                arguments: args,
                inputFiles: Array(swiftInputs),
                outputFiles: [i18nOutput, assetsOutput]
            )
        ]
    }

    // Mirrors ConfigLoader.discover() so resolution is identical to the CLI.
    private func findConfig(from startPath: String) -> String? {
        let anchors = ["Package.swift", ".git", ".xcworkspace", ".xcodeproj"]
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: startPath, isDirectory: true)

        while true {
            let candidate = dir.appendingPathComponent(".swiftl10n.yml")
            if fm.fileExists(atPath: candidate.path) { return candidate.path }

            for anchor in anchors
            where fm.fileExists(atPath: dir.appendingPathComponent(anchor).path) {
                return nil
            }

            let parent = dir.deletingLastPathComponent()
            guard parent.standardized.path != dir.standardized.path else { return nil }
            dir = parent
        }
    }
}
