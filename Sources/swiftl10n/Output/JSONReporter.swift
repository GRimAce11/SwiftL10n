import Foundation
import SwiftL10nCore

/// Serializes a `ScanPipeline.PipelineResult` to a stable JSON schema.
///
/// Output is written to stdout so callers can pipe it to `jq`, store it as a
/// CI artefact, or feed it to downstream tooling.
struct JSONReporter: Sendable {

    // MARK: - Schema types

    private struct Output: Encodable {
        let schemaVersion: String
        let swiftl10nVersion: String
        let scanned: Scanned
        let diagnostics: [DiagnosticEntry]
        let namespaces: [NamespaceEntry]

        struct Scanned: Encodable {
            let files: Int
            let strings: Int
            let namespaces: Int
            let warnings: Int
            let errors: Int
            let cacheHits: Int
            let existingLocalized: Int
            let migrationMode: String
            let scanDuration: Double
            let staleEntriesRemoved: Int
            let missingCatalogKeys: Int
            let orphanedCatalogKeys: Int
            let duplicateCatalogGroups: Int
            let accessibilityWarnings: Int

            enum CodingKeys: String, CodingKey {
                case files, strings, namespaces, warnings, errors
                case cacheHits             = "cache_hits"
                case existingLocalized     = "existing_localized"
                case migrationMode         = "migration_mode"
                case scanDuration          = "scan_duration_seconds"
                case staleEntriesRemoved   = "stale_entries_removed"
                case missingCatalogKeys    = "missing_catalog_keys"
                case orphanedCatalogKeys   = "orphaned_catalog_keys"
                case duplicateCatalogGroups = "duplicate_catalog_groups"
                case accessibilityWarnings = "accessibility_warnings"
            }
        }

        struct DiagnosticEntry: Encodable {
            let code: String
            let severity: String
            let message: String
            let file: String?
            let line: Int?
        }

        struct NamespaceEntry: Encodable {
            let name: String
            let sourceFile: String
            let strings: [StringEntry]

            struct StringEntry: Encodable {
                let value: String
                let context: String
                let confidence: Double
                let hasInterpolation: Bool
                let suggestedPropertyName: String
                let file: String
                let line: Int
                let scoreExplanation: ScoreExplanation?

                enum CodingKeys: String, CodingKey {
                    case value, context, confidence, hasInterpolation, file, line, scoreExplanation
                    case suggestedPropertyName = "suggested_property_name"
                }
            }
        }

        // Use snake_case keys in output
        enum CodingKeys: String, CodingKey {
            case schemaVersion    = "schema_version"
            case swiftl10nVersion = "swiftl10n_version"
            case scanned, diagnostics, namespaces
        }
    }

    private struct Output_Scanned: Encodable {}

    // MARK: - Version

    static var version: String { SwiftL10nCoreVersion.current }

    // MARK: - Report

    /// Returns a pretty-printed JSON string for `result`.
    func report(_ result: ScanPipeline.PipelineResult) throws -> String {
        let output = Output(
            schemaVersion: "1",
            swiftl10nVersion: Self.version,
            scanned: .init(
                files:                result.scannedFiles,
                strings:              result.totalStrings,
                namespaces:           result.namespaces.count,
                warnings:             result.warningCount,
                errors:               result.errorCount,
                cacheHits:            result.cacheHits,
                existingLocalized:    result.existingLocalizationCount,
                migrationMode:        result.migrationMode.rawValue,
                scanDuration:         (result.scanDuration * 1000).rounded() / 1000,
                staleEntriesRemoved:  result.staleEntriesRemoved,
                missingCatalogKeys:   result.missingCatalogKeys,
                orphanedCatalogKeys:  result.orphanedCatalogKeys,
                duplicateCatalogGroups: result.duplicateCatalogGroups,
                accessibilityWarnings: result.accessibilityWarnings
            ),
            diagnostics: result.diagnostics
                .filter { $0.severity != .note }
                .map { d in
                    Output.DiagnosticEntry(
                        code: diagnosticCode(for: d),
                        severity: severityName(d.severity),
                        message: d.message,
                        file: d.location?.file,
                        line: d.location?.line
                    )
                },
            namespaces: result.namespaces.map { ns in
                Output.NamespaceEntry(
                    name: ns.name,
                    sourceFile: ns.sourceFile,
                    strings: ns.strings.map { s in
                        Output.NamespaceEntry.StringEntry(
                            value: s.value,
                            context: s.context.displayName,
                            confidence: (s.confidence * 1000).rounded() / 1000,
                            hasInterpolation: s.hasInterpolation,
                            suggestedPropertyName: s.suggestedPropertyName,
                            file: s.location.file,
                            line: s.location.line,
                            scoreExplanation: s.scoreExplanation
                        )
                    }
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(output)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Helpers

    private func diagnosticCode(for diagnostic: Diagnostic) -> String {
        switch diagnostic.severity {
        case .note:       return "SL000"
        case .suggestion: return "SL000"
        case .warning:    return "SL001"
        case .error:      return "SL002"
        }
    }

    private func severityName(_ severity: Diagnostic.Severity) -> String {
        switch severity {
        case .note:       return "note"
        case .suggestion: return "note"
        case .warning:    return "warning"
        case .error:      return "error"
        }
    }
}
