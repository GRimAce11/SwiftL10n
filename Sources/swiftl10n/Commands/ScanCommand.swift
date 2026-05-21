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

    @Option(name: .long, help: "Generate Assets.swift from .xcassets catalogs found in the project root.")
    var assetsOutput: String?

    @Option(name: .long, help: "Output format: console (default) or json.")
    var format: OutputFormat = .console

    @Option(name: .long, help: "Exit non-zero if diagnostics at or above this level are found (errors, warnings, never).")
    var failOn: FailSeverity = .errors

    // MARK: - Run

    mutating func run() throws {
        // ── 1. Load config ────────────────────────────────────────────────────
        let loadedConfig: SwiftL10nConfig?
        let configBaseURL: URL

        if let explicitPath = config {
            let url = URL(fileURLWithPath: explicitPath)
            loadedConfig = try ConfigLoader.load(from: url)
            configBaseURL = url.deletingLastPathComponent()
            if format == .console { printInfo("Using config: \(explicitPath)") }
        } else if let discovered = ConfigLoader.discover() {
            loadedConfig = try ConfigLoader.load(from: discovered)
            configBaseURL = discovered.deletingLastPathComponent()
            if verbose && format == .console { print("Using config: \(discovered.path)") }
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
                source.hasPrefix("/") ? source : configBaseURL.appendingPathComponent(source).path
            }
        } else {
            throw ValidationError(
                "Specify a path to scan, or run 'swiftl10n init' to create \(ConfigLoader.fileName)."
            )
        }

        // ── 3. Resolve output path ────────────────────────────────────────────
        let effectiveOutput: String? = output ?? (loadedConfig != nil ? {
            let p = effectiveConfig.output.path
            return p.hasPrefix("/") ? p : configBaseURL.appendingPathComponent(p).path
        }() : nil)

        // ── 4. Run ScanPipeline ───────────────────────────────────────────────
        let pipeline = ScanPipeline(config: effectiveConfig, baseURL: configBaseURL)
        let result = try pipeline.run(
            sources: sourcePaths,
            minimumConfidence: minConfidence
        )

        // ── 5. Output ─────────────────────────────────────────────────────────
        switch format {
        case .json:
            let json = try JSONReporter().report(result)
            print(json)

        case .console:
            if verbose {
                for ns in result.namespaces {
                    printInfo("── \(ns.sourceFile) (\(ns.strings.count) string(s))")
                    for s in ns.strings {
                        let conf = String(format: "%.2f", s.confidence)
                        printInfo("  [\(s.context.displayName)] \"\(s.value)\" conf:\(conf) — \(s.location)")
                    }
                }
            }

            if !quiet {
                let cacheNote = result.cacheHits > 0 ? " (\(result.cacheHits) cached)" : ""
                print("Found \(result.totalStrings) string(s) across \(result.namespaces.count) namespace(s) in \(result.scannedFiles) file(s)\(cacheNote).")
                for ns in result.namespaces.sorted(by: { $0.name < $1.name }) {
                    print("  \(ns.name): \(ns.strings.count) string(s)")
                }
            }

            // Code generation
            if let outputPath = effectiveOutput {
                let code = CodeGenerator(
                    configuration: .init(
                        rootEnumName: effectiveConfig.output.enumName,
                        tableName: effectiveConfig.output.tableName
                    )
                ).generate(namespaces: result.namespaces)
                let outputURL = URL(fileURLWithPath: outputPath)
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let existed = FileManager.default.fileExists(atPath: outputPath)
                try code.write(to: outputURL, atomically: true, encoding: .utf8)
                if !quiet {
                    print("\(existed ? "Updated" : "Created") \(outputURL.lastPathComponent).")
                }
            }

            // Diagnostics to stderr (skip notes unless verbose)
            let minSeverity: Diagnostic.Severity = verbose ? .note : .warning
            let quietSeverity: Diagnostic.Severity = quiet ? .error : minSeverity
            for d in result.diagnostics where d.severity >= quietSeverity {
                fputs(d.description + "\n", stderr)
            }
        }

        // ── 6. Asset generation ───────────────────────────────────────────────
        let assetsOutputPath: String? = assetsOutput ?? (effectiveConfig.assets.enabled ? {
            let p = effectiveConfig.assets.path
            return p.hasPrefix("/") ? p : configBaseURL.appendingPathComponent(p).path
        }() : nil)

        if let assetsPath = assetsOutputPath {
            let catalog = try AssetCatalogParser.parseCatalogs(in: configBaseURL)
            let generatorConfig = AssetCodeGenerator.Configuration(
                rootEnumName: effectiveConfig.assets.enumName
            )
            let assetsCode = AssetCodeGenerator(configuration: generatorConfig).generate(catalog: catalog)
            let assetsURL  = URL(fileURLWithPath: assetsPath)
            try FileManager.default.createDirectory(
                at: assetsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let existed = FileManager.default.fileExists(atPath: assetsPath)
            try assetsCode.write(to: assetsURL, atomically: true, encoding: .utf8)
            if !quiet {
                print("\(existed ? "Updated" : "Created") \(assetsURL.lastPathComponent) (\(catalog.count) asset(s)).")
            }
        }

        // ── 7. Exit code ──────────────────────────────────────────────────────
        let shouldFail: Bool = switch failOn {
        case .errors:   result.errorCount > 0
        case .warnings: result.warningCount > 0 || result.errorCount > 0
        case .never:    false
        }
        if shouldFail { throw ExitCode.failure }
    }

    // MARK: - Helpers

    private func printInfo(_ message: String) {
        guard !quiet else { return }
        print(message)
    }
}

// MARK: - Argument types

enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case console, json
}

enum FailSeverity: String, ExpressibleByArgument, Sendable {
    case errors, warnings, never
}
