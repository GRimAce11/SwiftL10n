import ArgumentParser
import SwiftL10nCore
import Foundation

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan Swift source files for hardcoded localizable strings."
    )

    // MARK: - Arguments & Flags

    @Argument(help: "Path to a .swift file or directory. Overrides 'sources' in .swiftl10n.yml.")
    var path: String?

    @Option(name: .long, help: "Path to a .swiftl10n.yml config file.")
    var config: String?

    @Flag(name: .long, help: "Print every detected string with its location and context.")
    var verbose: Bool = false

    @Flag(name: [.customShort("q"), .long], help: "Suppress informational output; show only errors.")
    var quiet: Bool = false

    @Option(name: .long, help: "Minimum confidence threshold (0.0–1.0). Overrides config.")
    var minConfidence: Double?

    @Option(name: [.customShort("o"), .long], help: "Output path for the generated i18n.swift. Overrides config.")
    var output: String?

    // MARK: - Run

    mutating func run() throws {
        // ── 1. Load config ────────────────────────────────────────────────────
        let loadedConfig: SwiftL10nConfig?
        let configBaseURL: URL

        if let explicitPath = config {
            let url = URL(fileURLWithPath: explicitPath)
            loadedConfig = try ConfigLoader.load(from: url)
            configBaseURL = url.deletingLastPathComponent()
            printInfo("Using config: \(explicitPath)")
        } else if let discovered = ConfigLoader.discover() {
            loadedConfig = try ConfigLoader.load(from: discovered)
            configBaseURL = discovered.deletingLastPathComponent()
            if verbose { print("Using config: \(discovered.path)") }
        } else {
            loadedConfig = nil
            configBaseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

        let effectiveConfig = loadedConfig ?? .default

        // ── 2. Resolve sources ────────────────────────────────────────────────
        let sourcePaths: [String]
        if let p = path {
            sourcePaths = [p]
        } else if loadedConfig != nil {
            sourcePaths = effectiveConfig.sources.map { source in
                // Resolve relative paths against the config file directory
                if source.hasPrefix("/") { return source }
                return configBaseURL.appendingPathComponent(source).path
            }
        } else {
            throw ValidationError(
                "Specify a path to scan, or run 'swiftl10n init' to create \(ConfigLoader.fileName)."
            )
        }

        // ── 3. Apply CLI overrides ────────────────────────────────────────────
        let effectiveMinConfidence = minConfidence ?? effectiveConfig.minimumConfidence
        let effectiveOutput: String? = output ?? (loadedConfig != nil ? {
            let p = effectiveConfig.output.path
            if p.hasPrefix("/") { return p }
            return configBaseURL.appendingPathComponent(p).path
        }() : nil)

        let excludePatterns = effectiveConfig.exclude

        // ── 4. Collect Swift files ────────────────────────────────────────────
        let diagnosticsEngine = DiagnosticsEngine()
        var allSwiftFiles: [URL] = []

        for sourcePath in sourcePaths {
            let files = try resolveSwiftFiles(path: sourcePath, excludePatterns: excludePatterns)
            allSwiftFiles.append(contentsOf: files)
        }

        if allSwiftFiles.isEmpty {
            printInfo("No Swift files found.")
            return
        }

        if verbose {
            printInfo("Scanning \(allSwiftFiles.count) file(s)…")
        }

        // ── 5. Scan ───────────────────────────────────────────────────────────
        let scanner = StringScanner()
        var fileResults: [(filePath: String, strings: [DetectedString])] = []

        for fileURL in allSwiftFiles {
            do {
                let result = try scanner.scan(filePath: fileURL.path)
                result.diagnostics.forEach { diagnosticsEngine.emit($0) }
                let filtered = result.detectedStrings.filter { $0.confidence >= effectiveMinConfidence }
                fileResults.append((filePath: fileURL.path, strings: filtered))

                if verbose {
                    for s in filtered {
                        let conf = String(format: "%.2f", s.confidence)
                        printInfo("  [\(s.context.displayName)] \"\(s.value)\" conf:\(conf) — \(s.location)")
                    }
                }
            } catch {
                diagnosticsEngine.emit(.error, "Cannot read file: \(error.localizedDescription)", at: nil)
            }
        }

        // ── 6. Summary ────────────────────────────────────────────────────────
        let namespaces = NamespaceInferrer().infer(from: fileResults)
        let totalStrings = fileResults.lazy.map(\.strings.count).reduce(0, +)

        if !quiet {
            print("Found \(totalStrings) localizable string(s) across \(namespaces.count) namespace(s).")
            for ns in namespaces.sorted(by: { $0.name < $1.name }) {
                print("  \(ns.name): \(ns.strings.count) string(s) (\(ns.sourceFile))")
            }
        }

        // ── 7. Code generation ────────────────────────────────────────────────
        if let outputPath = effectiveOutput {
            let code = CodeGenerator().generate(namespaces: namespaces)
            let outputURL = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try code.write(to: outputURL, atomically: true, encoding: .utf8)
            if !quiet {
                print("Generated \(outputURL.lastPathComponent).")
            }
        }

        diagnosticsEngine.printAll(minimumSeverity: quiet ? .error : .warning)

        if diagnosticsEngine.hasErrors {
            throw ExitCode.failure
        }
    }

    // MARK: - File Collection

    private func resolveSwiftFiles(path: String, excludePatterns: [String]) throws -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(path)")
        }

        if isDirectory.boolValue {
            return collectSwiftFiles(inDirectory: url, excludePatterns: excludePatterns)
        }

        guard url.pathExtension == "swift" else {
            throw ValidationError("File must have a .swift extension: \(path)")
        }
        return isExcluded(url, patterns: excludePatterns) ? [] : [url]
    }

    private func collectSwiftFiles(inDirectory directory: URL, excludePatterns: [String]) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if !isExcluded(url, patterns: excludePatterns) {
                results.append(url)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Phase-1 exclusion: prefix/suffix matching. Full glob support arrives in v0.5.1.
    private func isExcluded(_ url: URL, patterns: [String]) -> Bool {
        guard !patterns.isEmpty else { return false }
        let absolutePath = url.path
        for pattern in patterns {
            if pattern.hasPrefix("**/") {
                // Any-depth suffix: **/Generated, **/*.generated.swift
                let tail = String(pattern.dropFirst(3))
                if absolutePath.contains("/\(tail)") || absolutePath.hasSuffix("/\(tail)") {
                    return true
                }
            } else if pattern.hasPrefix("*.") {
                // Extension wildcard: *.generated.swift
                if absolutePath.hasSuffix(String(pattern.dropFirst(1))) {
                    return true
                }
            } else {
                // Directory prefix or exact path segment
                if absolutePath.contains("/\(pattern)/") || absolutePath.hasSuffix("/\(pattern)") {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Helpers

    private func printInfo(_ message: String) {
        guard !quiet else { return }
        print(message)
    }
}
