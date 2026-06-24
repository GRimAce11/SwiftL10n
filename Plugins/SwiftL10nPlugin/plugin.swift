import PackagePlugin
import Foundation

/// Build tool plugin that runs `swiftl10n scan` before Swift compilation,
/// eliminating the two-build gap caused by the runtime `.task {}` approach.
///
/// Supports both SwiftPM package targets and Xcode project targets.
///
/// **SwiftPM (Package.swift):**
/// ```swift
/// .target(
///     name: "MyApp",
///     plugins: [.plugin(name: "SwiftL10nPlugin", package: "SwiftL10n")]
/// )
/// ```
///
/// **Xcode project:**
/// Select your app target → Build Phases → + → Add Build Tool Plug-in →
/// choose SwiftL10nPlugin. Grant permission when prompted.
///
/// **Migration from runtime generation:**
/// 1. Add the plugin to your target (above).
/// 2. Delete `Generated/i18n.swift` and `Generated/Assets.swift` from your source tree.
/// 3. Remove the runtime `.task { SwiftL10n.scan(...) }` call from your app.
/// 4. Build — the plugin generates fresh files into DerivedData before every compile.
@main
struct SwiftL10nPlugin: BuildToolPlugin {

    // MARK: - SPM package targets

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

    // MARK: - Config discovery (shared)

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

// MARK: - Xcode project targets

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

// `XcodeProjectPlugin` names both the module and the protocol inside it, which
// causes Swift to treat bare `XcodeProjectPlugin` as a module reference in a
// conformance position. Use the fully-qualified spelling to resolve the ambiguity.
extension SwiftL10nPlugin: XcodeProjectPlugin.XcodeProjectPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool = try context.tool(named: "swiftl10n")
        let outputDir    = context.pluginWorkDirectory
        let i18nOutput   = outputDir.appending("i18n.swift")
        let assetsOutput = outputDir.appending("Assets.swift")

        // Collect the target's Swift source files as incremental-build inputs.
        let swiftFiles = target.inputFiles.filter {
            $0.type == .source && $0.path.extension == "swift"
        }
        guard !swiftFiles.isEmpty else { return [] }

        // Use the Xcode project's root directory as the scan root — this matches
        // the mental model of running `swiftl10n scan` from the project directory.
        // Add `sources:` in .swiftl10n.yml to restrict the scan to a subdirectory
        // (e.g. `sources: ["MyApp"]` to skip Pods/ or other unrelated targets).
        let projectDir = context.xcodeProject.directory.string

        var args: [CustomStringConvertible] = [
            "scan", projectDir,
            "--output", i18nOutput.string,
            "--assets-output", assetsOutput.string,
        ]

        // Config is checked at the project root level first (same directory as
        // .xcodeproj), then walks upward until another project root is reached.
        if let configPath = findConfig(from: projectDir) {
            args += ["--config", configPath]
        }

        return [
            .buildCommand(
                displayName: "SwiftL10n: generate i18n.swift + Assets.swift",
                executable: tool.path,
                arguments: args,
                inputFiles: swiftFiles.map(\.path),
                outputFiles: [i18nOutput, assetsOutput]
            )
        ]
    }
}
#endif
