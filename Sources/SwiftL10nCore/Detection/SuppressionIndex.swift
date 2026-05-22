/// O(1) lookup table for string literal source locations that should be
/// suppressed during `StringScanner` reporting.
///
/// Built by `ScanPipeline` from `ExistingLocalizationDetector.Result.suppressionLocations`
/// and passed into `StringScanner` for each file scan.
///
/// Suppression is purely a diagnostic gate — it never mutates AST traversal.
public struct SuppressionIndex: Sendable {

    private let locations: Set<SourceLocation>

    public init(locations: Set<SourceLocation> = []) {
        self.locations = locations
    }

    public static let empty = SuppressionIndex()

    /// Returns `true` when the string literal at `location` should be suppressed.
    public func isSuppressed(_ location: SourceLocation) -> Bool {
        locations.contains(location)
    }

    public var isEmpty: Bool { locations.isEmpty }
    public var count: Int    { locations.count }

    /// Merge two indices (used when aggregating per-file results).
    public func merging(_ other: SuppressionIndex) -> SuppressionIndex {
        SuppressionIndex(locations: locations.union(other.locations))
    }
}
