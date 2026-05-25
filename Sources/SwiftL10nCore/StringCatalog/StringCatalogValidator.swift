import Foundation

/// Cross-references detected source strings against a parsed `.xcstrings` catalog.
///
/// Two directions:
/// - **Missing**: string value detected in source has no matching key in the catalog.
///   These need to be extracted (Xcode does this automatically during Build, but only
///   for `String(localized:)` calls — not for the raw hardcoded literals SwiftL10n detects).
/// - **Orphaned**: catalog key has no matching detected source string value.
///   Potential dead translations from renamed or deleted strings.
public struct StringCatalogValidator: Sendable {

    public init() {}

    public func validate(
        namespaces: [Namespace],
        against catalog: StringCatalog
    ) -> StringCatalogValidationResult {
        guard !catalog.keys.isEmpty else {
            return StringCatalogValidationResult(missingFromCatalog: [], orphanedInCatalog: [])
        }

        // Build: value → [(namespace, location)]
        var sourceValues: [String: [(namespace: String, location: SourceLocation)]] = [:]
        for namespace in namespaces {
            for string in namespace.strings where !string.hasInterpolation {
                sourceValues[string.value, default: []].append(
                    (namespace.name, string.location)
                )
            }
        }

        // Missing: detected in source, absent from catalog
        let missing: [StringCatalogValidationResult.MissingEntry] = sourceValues
            .filter { !catalog.contains(key: $0.key) }
            .map { value, occurrences in
                StringCatalogValidationResult.MissingEntry(
                    value: value,
                    locations: occurrences.map(\.location),
                    namespaceNames: occurrences.map(\.namespace)
                )
            }
            .sorted { $0.value < $1.value }

        // Orphaned: in catalog, no matching source value
        let sourceValueSet = Set(sourceValues.keys)
        let orphaned = catalog.keys.filter { !sourceValueSet.contains($0) }.sorted()

        return StringCatalogValidationResult(
            missingFromCatalog: missing,
            orphanedInCatalog: orphaned
        )
    }
}

// MARK: - Result

public struct StringCatalogValidationResult: Sendable {
    /// Strings detected in source whose value is absent as a catalog key.
    public let missingFromCatalog: [MissingEntry]
    /// Catalog keys that don't match any detected source string value.
    public let orphanedInCatalog: [String]

    public var missingCount: Int { missingFromCatalog.count }
    public var orphanedCount: Int { orphanedInCatalog.count }

    public struct MissingEntry: Sendable {
        public let value: String
        public let locations: [SourceLocation]
        public let namespaceNames: [String]
    }
}
