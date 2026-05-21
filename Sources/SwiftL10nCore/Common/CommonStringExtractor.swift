/// Finds string values that appear in two or more namespaces and lifts them
/// into a dedicated `Common` namespace so they are generated once and shared.
///
/// ### Example
/// If `"Save"` appears in both `Settings` and `Profile`:
///
/// ```
/// Before:  Settings { save() }   Profile { save() }
/// After:   Common   { save() }   Settings { … }   Profile { … }
/// ```
///
/// Call `extract(from:)` on the output of `NamespaceInferrer`, then pass the
/// resulting namespaces to `CodeGenerator`.
public struct CommonStringExtractor: Sendable {

    // MARK: - Result

    public struct ExtractionResult: Sendable {
        /// Namespace of strings that appeared in 2+ source files, or `nil` if none were found.
        public let common: Namespace?
        /// Original namespaces with shared strings removed. Namespaces that become
        /// fully empty after extraction are dropped.
        public let namespaces: [Namespace]
        /// Maps each common string value to the namespace names it was found in.
        /// Useful for printing a human-readable origin report.
        public let origins: [String: [String]]
    }

    public init() {}

    // MARK: - Extract

    /// Identifies strings shared across 2+ namespaces, removes them from individual
    /// namespaces, and returns them collected in a single `Common` namespace.
    public func extract(from namespaces: [Namespace]) -> ExtractionResult {

        // 1. Map every non-interpolated string value → which namespace names contain it
        var valueToNamespaces: [String: Set<String>] = [:]
        for ns in namespaces {
            for s in ns.strings where !s.hasInterpolation {
                valueToNamespaces[s.value, default: []].insert(ns.name)
            }
        }

        // 2. Keep only values that appear in 2+ distinct namespaces
        let sharedValues = valueToNamespaces
            .filter { $0.value.count >= 2 }

        let sharedValueSet = Set(sharedValues.keys)

        guard !sharedValueSet.isEmpty else {
            return ExtractionResult(common: nil, namespaces: namespaces, origins: [:])
        }

        // 3. Collect one representative DetectedString per shared value (first occurrence,
        //    sorted by namespace name for deterministic output)
        var seen = Set<String>()
        var commonStrings: [DetectedString] = []

        for ns in namespaces.sorted(by: { $0.name < $1.name }) {
            for s in ns.strings where sharedValueSet.contains(s.value) && !seen.contains(s.value) {
                commonStrings.append(s)
                seen.insert(s.value)
            }
        }

        // 4. Strip shared strings from each individual namespace; drop empty namespaces
        let stripped = namespaces
            .map { ns in
                Namespace(
                    name: ns.name,
                    sourceFile: ns.sourceFile,
                    strings: ns.strings.filter { !sharedValueSet.contains($0.value) }
                )
            }
            .filter { !$0.strings.isEmpty }

        let common = Namespace(
            name: "Common",
            sourceFile: "(shared)",
            strings: commonStrings.sorted { $0.value.lowercased() < $1.value.lowercased() }
        )

        let origins = sharedValues.mapValues { Array($0).sorted() }

        return ExtractionResult(common: common, namespaces: stripped, origins: origins)
    }
}
