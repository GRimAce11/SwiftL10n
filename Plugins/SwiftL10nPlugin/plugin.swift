import PackagePlugin
import Foundation

@main
struct SwiftL10nPlugin: BuildToolPlugin {

    // MARK: - SPM package targets

    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let tool    = try context.tool(named: "swiftl10n")
        let workDir = context.pluginWorkDirectoryURL
        let i18nURL   = workDir.appendingPathComponent("i18n.swift")
        let assetsURL = workDir.appendingPathComponent("Assets.swift")
        // directoryURL is not yet available in this SDK; directory.string still works.
        let sourceDir = sourceTarget.directory.string

        var args: [String] = [
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
// The XcodeProjectPlugin *module* exports XcodePluginContext and XcodeTarget but
// does NOT contain the XcodeProjectPlugin *protocol* — that lives in PackagePlugin.
extension SwiftL10nPlugin: PackagePlugin.XcodeProjectPlugin {

    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let tool    = try context.tool(named: "swiftl10n")
        let workDir = context.pluginWorkDirectoryURL
        let i18nURL   = workDir.appendingPathComponent("i18n.swift")
        let assetsURL = workDir.appendingPathComponent("Assets.swift")

        let swiftFiles = target.inputFiles.filter {
            $0.type == .source && $0.url.pathExtension == "swift"
        }
        guard !swiftFiles.isEmpty else { return [] }

        let projectDir = context.xcodeProject.directory.string

        var args: [String] = [
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
