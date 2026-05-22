/// Handles additive, marker-based merging of generated Swift files.
///
/// When `merge_strategy: region` is configured, SwiftL10n only replaces the
/// content between its ownership markers on each regeneration. Everything
/// outside the markers — manual extensions, documentation, custom helpers —
/// is preserved exactly as the developer left it.
///
/// File layout:
/// ```swift
/// // Manual code above — never touched by SwiftL10n
///
/// // MARK: - SwiftL10n Generated BEGIN
/// public enum i18n { ... }
/// // MARK: - SwiftL10n Generated END
///
/// // Manual extensions below — never touched by SwiftL10n
/// extension i18n.Common { ... }
/// ```
public enum FileRegionMerger {

    // Markers are anchored to avoid partial-line false matches.
    static let beginMarker = "// MARK: - SwiftL10n Generated BEGIN"
    static let endMarker   = "// MARK: - SwiftL10n Generated END"

    /// Replace the generated region in `existing` with `newContent`.
    ///
    /// - Returns: The merged string when both markers are found and in order,
    ///   or `nil` when no markers exist (first-run case — caller should `wrap` instead).
    public static func merge(existing: String, newContent: String) -> String? {
        let lines = existing.components(separatedBy: "\n")

        guard let beginIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == beginMarker }),
              let endIdx   = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker }),
              beginIdx < endIdx
        else { return nil }

        // Keep everything up to and including the BEGIN marker,
        // inject new content, then keep END marker and everything after.
        var result: [String] = []
        result.append(contentsOf: lines[...beginIdx])
        result.append(newContent)
        result.append(contentsOf: lines[endIdx...])
        return result.joined(separator: "\n")
    }

    /// Wrap `content` in the ownership markers for first-write or overwrite cases.
    public static func wrap(_ content: String) -> String {
        "\(beginMarker)\n\(content)\n\(endMarker)\n"
    }
}
