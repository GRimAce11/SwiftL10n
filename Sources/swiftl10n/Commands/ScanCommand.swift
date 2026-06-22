import ArgumentParser
import SwiftL10nCore
import Foundation

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan Swift source files for hardcoded localizable strings."
    )

    // MARK: - Arguments & Flags

    @Argument(help: "Path to a .swift file or directory. Overrides 'sources' in .swiftl10n.yml.",
              completion: .file(extensions: ["swift"]))
    var path: String?

    @Option(name: .long, help: "Path to a .swiftl10n.yml config file.",
            completion: .file(extensions: ["yml", "yaml"]))
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

    @Option(name: .long, help: "Migration mode: audit (default), incremental, or strict. Overrides config.")
    var migrationMode: MigrationModeArg?

    @Flag(name: .long, help: "Run the full pipeline but skip writing any files — useful for CI preview.")
    var dryRun: Bool = false

    // MARK: - Run

    mutating func run() async throws {
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

        if loadedConfig != nil {
            try ConfigLoader.validate(effectiveConfig, relativeTo: configBaseURL)
        }
        if let mc = minConfidence, !(0.0...1.0).contains(mc) {
            throw ValidationError("--min-confidence must be between 0.0 and 1.0, got \(mc)")
        }

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
        let result = try await pipeline.run(
            sources: sourcePaths,
            minimumConfidence: minConfidence,
            migrationMode: migrationMode?.coreMode,
            collectAccessorReferences: effectiveOutput != nil
        )

        // ── 5. Output ─────────────────────────────────────────────────────────
        switch format {
        case .json:
            let json = try JSONReporter().report(result)
            print(json)

        case .github:
            // GitHub Actions annotation format
            for d in result.diagnostics where d.severity >= .warning {
                let level = d.severity == .error ? "error" : "warning"
                if let loc = d.location {
                    print("::\(level) file=\(loc.file),line=\(loc.line),col=\(loc.column),title=SwiftL10n::\(d.message)")
                } else {
                    print("::\(level) title=SwiftL10n::\(d.message)")
                }
            }
            if !quiet {
                let modeTag = result.migrationMode != .audit ? " [\(result.migrationMode.rawValue)]" : ""
                print("::notice title=SwiftL10n::Found \(result.totalStrings) hardcoded string(s) across \(result.namespaces.count) namespace(s) in \(result.scannedFiles) file(s)\(modeTag)")
                if result.existingLocalizationCount > 0 {
                    print("::notice title=SwiftL10n::\(result.existingLocalizationCount) existing localization call site(s) recognized")
                }
            }

        case .console:
            if verbose {
                for ns in result.namespaces {
                    printInfo("── \(ns.sourceFile) (\(ns.strings.count) string(s))")
                    for s in ns.strings {
                        let conf = String(format: "%.0f%%", s.confidence * 100)
                        var line = "  [\(s.context.displayName)] \"\(s.value)\"  \(conf) — \(s.location)"
                        if let expl = s.scoreExplanation, !expl.factors.isEmpty {
                            line += "\n    score: \(expl.summary)"
                        }
                        line += "\n    → i18n.<Namespace>.\(s.suggestedPropertyName)()"
                        printInfo(line)
                    }
                }
            }

            if !quiet {
                let cacheNote  = result.cacheHits > 0 ? " (\(result.cacheHits) cached)" : ""
                let modeNote: String = switch result.migrationMode {
                case .audit:       ""
                case .incremental: " [incremental]"
                case .strict:      " [strict]"
                }
                let duration   = String(format: "%.2fs", result.scanDuration)
                print("Found \(result.totalStrings) string(s) across \(result.namespaces.count) namespace(s) in \(result.scannedFiles) file(s)\(cacheNote)\(modeNote) in \(duration).")
                if result.existingLocalizationCount > 0 {
                    print("  \(result.existingLocalizationCount) existing localization call site(s) recognized and skipped.")
                }
                if result.staleEntriesRemoved > 0 {
                    print("  \(result.staleEntriesRemoved) stale cache entry(s) removed.")
                }
                if result.missingCatalogKeys > 0 {
                    print("  \(result.missingCatalogKeys) string(s) absent from .xcstrings catalog.")
                }
                if result.orphanedCatalogKeys > 0 {
                    print("  \(result.orphanedCatalogKeys) orphaned catalog key(s) found.")
                }
                if result.duplicateCatalogGroups > 0 {
                    print("  \(result.duplicateCatalogGroups) duplicate catalog value group(s) found.")
                }
                if result.accessibilityWarnings > 0 {
                    print("  \(result.accessibilityWarnings) Image literal(s) missing accessibility modifier.")
                }
                for ns in result.namespaces.sorted(by: { $0.name < $1.name }) {
                    print("  \(ns.name): \(ns.strings.count) string(s)")
                }
            }

            // Code generation
            if let outputPath = effectiveOutput {
                let outputURL = URL(fileURLWithPath: outputPath)
                let existed = FileManager.default.fileExists(atPath: outputPath)

                // Reference-aware preservation: recover accessors from the existing
                // file that are still referenced in source (their literal may have
                // been migrated away) so regeneration is additive, not lossy.
                var preserved: [PreservedAccessor] = []
                if existed, let existing = try? String(contentsOf: outputURL, encoding: .utf8) {
                    let parsed = GeneratedFileParser.parse(existing, rootEnumName: effectiveConfig.output.enumName)
                    preserved = GeneratedFileParser.preserving(parsed, referencedIn: result.referencedGeneratedAccessors)
                }

                if dryRun {
                    if !quiet {
                        let preservedNote = preserved.isEmpty ? "" : " (preserving \(preserved.count) migrated key(s))"
                        print("[dry-run] Would write \(result.totalStrings) string(s) to \(outputURL.lastPathComponent)\(preservedNote).")
                    }
                } else {
                    let code = CodeGenerator(
                        configuration: .init(
                            rootEnumName: effectiveConfig.output.enumName,
                            tableName: effectiveConfig.output.tableName
                        )
                    ).generate(namespaces: result.namespaces, preserved: preserved)
                    try FileManager.default.createDirectory(
                        at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let contentToWrite: String
                    if effectiveConfig.output.mergeStrategy == .region {
                        if existed, let existing = try? String(contentsOf: outputURL, encoding: .utf8) {
                            contentToWrite = FileRegionMerger.merge(existing: existing, newContent: code)
                                ?? FileRegionMerger.wrap(code)
                        } else {
                            contentToWrite = FileRegionMerger.wrap(code)
                        }
                    } else {
                        contentToWrite = code
                    }
                    try contentToWrite.write(to: outputURL, atomically: true, encoding: .utf8)
                    if !quiet {
                        let strategyNote = effectiveConfig.output.mergeStrategy == .region ? " (region merge)" : ""
                        print("\(existed ? "Updated" : "Created") \(outputURL.lastPathComponent)\(strategyNote).")
                    }
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
            if dryRun {
                if !quiet { print("[dry-run] Would write Assets.swift to \(URL(fileURLWithPath: assetsPath).lastPathComponent).") }
            } else {
                let catalog = try AssetCatalogParser.parseCatalogs(in: configBaseURL)
                let generatorConfig = AssetCodeGenerator.Configuration(
                    rootEnumName: effectiveConfig.assets.enumName,
                    useImageResource: effectiveConfig.assets.useImageResource
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
        }

        // ── 7. Exit code ──────────────────────────────────────────────────────
        let strictFail = result.migrationMode == .strict && result.totalStrings > 0
        let failOnFail: Bool = switch failOn {
        case .errors:   result.errorCount > 0
        case .warnings: result.warningCount > 0 || result.errorCount > 0
        case .never:    false
        }
        if strictFail {
            if !quiet { fputs("error: strict mode — \(result.totalStrings) hardcoded string(s) found\n", stderr) }
            throw ExitCode.failure
        }
        if failOnFail { throw ExitCode.failure }
    }

    // MARK: - Helpers

    private func printInfo(_ message: String) {
        guard !quiet else { return }
        print(message)
    }
}

// MARK: - Argument types

enum OutputFormat: String, ExpressibleByArgument, Sendable {
    case console, json, github
}

enum FailSeverity: String, ExpressibleByArgument, Sendable {
    case errors, warnings, never
}

enum MigrationModeArg: String, ExpressibleByArgument, Sendable {
    case audit, incremental, strict

    var coreMode: SwiftL10nConfig.MigrationConfig.Mode {
        switch self {
        case .audit:       .audit
        case .incremental: .incremental
        case .strict:      .strict
        }
    }
}
