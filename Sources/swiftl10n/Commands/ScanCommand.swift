import ArgumentParser
import SwiftL10nCore
import Foundation

struct ScanCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan Swift source files for hardcoded localizable strings."
    )

    // MARK: - Arguments & Flags

    @Argument(help: "Path to a .swift file or directory to scan recursively.")
    var path: String

    @Flag(name: .long, help: "Print every detected string with its location and context.")
    var verbose: Bool = false

    @Flag(name: [.customShort("q"), .long], help: "Suppress informational output; show only errors.")
    var quiet: Bool = false

    @Option(name: .long, help: "Only report strings at or above this confidence threshold (0.0–1.0).")
    var minConfidence: Double = 0.0

    @Option(name: [.customShort("o"), .long], help: "Write the generated Swift Strings enum to this file.")
    var output: String?

    // MARK: - Run

    mutating func run() throws {
        let diagnosticsEngine = DiagnosticsEngine()
        let swiftFiles = try resolveSwiftFiles()

        if swiftFiles.isEmpty {
            printInfo("No Swift files found at \(path).")
            return
        }

        if verbose {
            printInfo("Scanning \(swiftFiles.count) file(s)…")
        }

        // Scan each file.
        let scanner = StringScanner()
        var fileResults: [(filePath: String, strings: [DetectedString])] = []

        for fileURL in swiftFiles {
            do {
                let result = try scanner.scan(filePath: fileURL.path)
                result.diagnostics.forEach { diagnosticsEngine.emit($0) }
                fileResults.append((filePath: fileURL.path, strings: result.detectedStrings))

                if verbose {
                    for s in result.detectedStrings where s.confidence >= minConfidence {
                        let conf = String(format: "%.2f", s.confidence)
                        printInfo("  [\(s.context.displayName)] \"\(s.value)\" conf:\(conf) — \(s.location)")
                    }
                }
            } catch {
                diagnosticsEngine.emit(.error, "Cannot read file: \(error.localizedDescription)", at: nil)
            }
        }

        // Apply confidence filter.
        if minConfidence > 0.0 {
            fileResults = fileResults.map { (path, strings) in
                (path, strings.filter { $0.confidence >= minConfidence })
            }
        }

        // Infer namespaces.
        let namespaces = NamespaceInferrer().infer(from: fileResults)
        let totalStrings = fileResults.lazy.map(\.strings.count).reduce(0, +)

        if !quiet {
            print("Found \(totalStrings) localizable string(s) across \(namespaces.count) namespace(s).")
            for ns in namespaces.sorted(by: { $0.name < $1.name }) {
                print("  \(ns.name): \(ns.strings.count) string(s) (\(ns.sourceFile))")
            }
        }

        // Code generation.
        if let outputPath = output {
            let code = CodeGenerator().generate(namespaces: namespaces)
            let outputURL = URL(fileURLWithPath: outputPath)
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

    private func resolveSwiftFiles() throws -> [URL] {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ValidationError("Path does not exist: \(path)")
        }

        if isDirectory.boolValue {
            return collectSwiftFiles(inDirectory: url)
        }

        guard url.pathExtension == "swift" else {
            throw ValidationError("File must have a .swift extension: \(path)")
        }
        return [url]
    }

    private func collectSwiftFiles(inDirectory directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    // MARK: - Helpers

    private func printInfo(_ message: String) {
        guard !quiet else { return }
        print(message)
    }
}
