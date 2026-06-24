import PackagePlugin
import Foundation

/// Build tool plugin that runs `swiftl10n scan` before Swift compilation,
/// eliminating the two-build gap caused by the runtime `.task {}` approach.
///
/// **SPM package targets (Package.swift):**
/// ```swift
/// .target(name: "MyApp", plugins: [.plugin(name: "SwiftL10nPlugin", package: "SwiftL10n")])
/// ```
///
/// **Xcode project targets (.xcodeproj):**
/// Select your app target → Build Phases → + → Add Build Tool Plug-in →
/// choose SwiftL10nPlugin. Grant permission when prompted.
@main
struct SwiftL10nPlugin: BuildToolPlugin {

    // MARK: - SPM package targets

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let tool    = try context.tool(named: "swiftl10n")
        let workDir = context.pluginWorkDirectoryURL
        let i18nURL   = workDir.appendingPathComponent("i18n.swift")
        let assetsURL = workDir.appendingPathComponent("Assets.swift")
        let sourceDir = sourceTarget.directoryURL.path(percentEncoded: false)

        var args: [CustomStringConvertible] = [
            "scan", sourceDir,
            "--output",        i18nURL.path(percentEncoded: false),
            "--assets-output", assetsURL.path(percentEncoded: false),
        ]
        if let cfg = findConfig(from: sourceDir) { args += ["--config", cfg] }

        let inputs = sourceTarget.sourceFiles(withSuffix: "swift").map(\.url)

        return [.buildCommand(
            displayName: "SwiftL10n: generate i18n.swift + Assets.swift",
            executable:  tool.url,
            arguments:   args,
            inputFiles:  Array(inputs),
            outputFiles: [i18nURL, assetsURL]
        )]
    }

    // MARK: - Config discovery

    private func findConfig(from startPath: String) -> String? {
        let anchors = ["Package.swift", ".git", ".xcworkspace", ".xcodeproj"]
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: startPath, isDirectory: true)
        while true {
            let candidate = dir.appendingPathComponent(".swiftl10n.yml")
            if fm.fileExists(atPath: candidate.path) { return candidate.path }
            for anchor in anchors
            where fm.fileExists(atPath: dir.appendingPathComponent(anchor).path) { return nil }
            let parent = dir.deletingLastPathComponent()
            guard parent.standardized.path != dir.standardized.path else { return nil }
            dir = parent
        }
    }
}

// MARK: - Xcode project targets

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

// Swift treats a bare `XcodeProjectPlugin` in a conformance position as the
// module name, not the protocol. The module-qualified form resolves the ambiguity.
extension SwiftL10nPlugin: XcodeProjectPlugin.XcodeProjectPlugin {

    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool    = try context.tool(named: "swiftl10n")
        let workDir = context.pluginWorkDirectoryURL
        let i18nURL   = workDir.appendingPathComponent("i18n.swift")
        let assetsURL = workDir.appendingPathComponent("Assets.swift")

        let swiftFiles = target.inputFiles.filter {
            $0.type == .source && $0.url.pathExtension == "swift"
        }
        guard !swiftFiles.isEmpty else { return [] }

        let projectDir = context.xcodeProject.directoryURL.path(percentEncoded: false)

        var args: [CustomStringConvertible] = [
            "scan", projectDir,
            "--output",        i18nURL.path(percentEncoded: false),
            "--assets-output", assetsURL.path(percentEncoded: false),
        ]
        if let cfg = findConfig(from: projectDir) { args += ["--config", cfg] }

        return [.buildCommand(
            displayName: "SwiftL10n: generate i18n.swift + Assets.swift",
            executable:  tool.url,
            arguments:   args,
            inputFiles:  swiftFiles.map(\.url),
            outputFiles: [i18nURL, assetsURL]
        )]
    }
}
#endif
