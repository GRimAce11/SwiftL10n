import Foundation

/// Detects duplicate localization values in both the string catalog and the detected source strings.
public struct DuplicateLocalizationAnalyzer: Sendable {

    public init() {}

    // MARK: - Catalog analysis

    /// Finds catalog entries that share the same source-language value.
    /// Multiple keys with identical values may indicate consolidation opportunities.
    public func analyzeCatalog(_ catalog: StringCatalog) -> [DuplicateKeyGroup] {
        guard !catalog.entries.isEmpty else { return [] }
        var valueToKeys: [String: [String]] = [:]
        for (key, entry) in catalog.entries {
            let value = entry.sourceValue ?? key
            valueToKeys[value, default: []].append(key)
        }
        return valueToKeys
            .filter { $0.value.count > 1 }
            .map { DuplicateKeyGroup(sharedValue: $0.key, keys: $0.value.sorted()) }
            .sorted { $0.sharedValue < $1.sharedValue }
    }

    // MARK: - Source analysis

    /// Finds string values appearing in 2+ distinct namespaces.
    /// `CommonStringExtractor` handles promotion automatically during code generation, but
    /// this surfaces the duplicates as diagnostics so developers can review them.
    public func analyzeNamespaces(_ namespaces: [Namespace]) -> [DuplicateDetectedGroup] {
        var valueToOccurrences: [String: [(namespace: String, location: SourceLocation)]] = [:]
        for namespace in namespaces {
            for string in namespace.strings where !string.hasInterpolation {
                valueToOccurrences[string.value, default: []].append(
                    (namespace.name, string.location)
                )
            }
        }
        return valueToOccurrences
            .filter { Set($0.value.map(\.namespace)).count > 1 }
            .map { DuplicateDetectedGroup(value: $0.key, occurrences: $0.value) }
            .sorted { $0.value < $1.value }
    }
}

// MARK: - Result types

public struct DuplicateKeyGroup: Sendable {
    /// The shared source-language value.
    public let sharedValue: String
    /// All catalog keys that map to this value (always 2 or more).
    public let keys: [String]
}

public struct DuplicateDetectedGroup: Sendable {
    /// The string value detected in multiple namespaces.
    public let value: String
    /// All occurrences — each is a (namespace name, source location) pair.
    public let occurrences: [(namespace: String, location: SourceLocation)]
}
