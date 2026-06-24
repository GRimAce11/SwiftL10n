import PackagePlugin
import Foundation

/// Build tool plugin that runs `swiftl10n scan` before Swift compilation,
/// eliminating the two-build gap caused by the runtime `.task {}` approach.
///
/// **Usage in Package.swift:**
/// ```swift
/// .target(
///     name: "MyApp",
///     plugins: [.plugin(name: "SwiftL10nPlugin", package: "SwiftL10n")]
/// )
/// ```
///
/// **Migration from runtime generation:**
/// 1. Add the plugin to your target (above).
/// 2. Delete `Generated/i18n.swift` and `Generated/Assets.swift` from your source tree.
/// 3. Remove the runtime `.task { SwiftL10n.scan(...) }` call from your app.
/// 4. Build — the plugin generates fresh files into DerivedData before every compile.
@main
struct SwiftL10nPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let tool = try context.tool(named: "swiftl10n")
        let outputDir = context.pluginWorkDirectory
        let i18nOutput   = outputDir.appending("i18n.swift")
        let assetsOutput = outputDir.appending("Assets.swift")
        let sourceDir    = sourceTarget.directory.string

        var args: [CustomStringConvertible] = [
            "scan", sourceDir,
            "--output", i18nOutput.string,
            "--assets-output", assetsOutput.string,
        ]

        // If a .swiftl10n.yml exists at or above the source dir, pass it explicitly
        // so the plugin is deterministic regardless of the tool's working directory.
        if let configPath = findConfig(from: sourceDir) {
            args += ["--config", configPath]
        }

        // Swift source files are declared as inputs so SPM only re-runs the
        // generator when sources (or config) actually change.
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

    // Mirror ConfigLoader.discover() so config resolution is identical to the CLI.
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
