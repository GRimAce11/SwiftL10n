import Foundation

/// A hardcoded string literal found in SwiftUI source that is a candidate for localization.
public struct DetectedString: Sendable, Hashable, Codable {
    /// The raw string value exactly as it appears in source (no surrounding quotes).
    /// For interpolated strings this is the template with `{…}` markers in place of
    /// interpolation segments, e.g. `"Hello {…}!"`.
    public let value: String

    /// Where in the source file the string literal starts.
    public let location: SourceLocation

    /// The SwiftUI call site that contained this string, used for namespace inference
    /// and for generating meaningful property-name suggestions.
    public let context: DetectionContext

    /// How confident the engine is that this is a genuine UI string requiring localization.
    /// Range: 0.0 (very suspicious) → 1.0 (near-certain).
    /// The code generator skips strings below the configured threshold.
    public let confidence: Double

    /// `true` when the string literal contains at least one string-interpolation segment.
    /// Interpolated strings require manual extraction — no API is generated for them.
    public let hasInterpolation: Bool

    /// The nearest enclosing Swift declarations at the detection site.
    public let enclosingContext: EnclosingContext

    /// Full breakdown of how `confidence` was computed. `nil` when the string was
    /// constructed manually (e.g. in tests) rather than through the scoring pipeline.
    public let scoreExplanation: ScoreExplanation?

    public init(
        value: String,
        location: SourceLocation,
        context: DetectionContext,
        confidence: Double = 1.0,
        hasInterpolation: Bool = false,
        enclosingContext: EnclosingContext = .empty,
        scoreExplanation: ScoreExplanation? = nil
    ) {
        self.value            = value
        self.location         = location
        self.context          = context
        self.confidence       = confidence
        self.hasInterpolation = hasInterpolation
        self.enclosingContext = enclosingContext
        self.scoreExplanation = scoreExplanation
    }
}

// MARK: - Suggestions

extension DetectedString {
    /// Suggested Swift property name for the generated localization API.
    ///
    /// Derived from `value` and `context` using the same logic as `CodeGenerator`.
    /// Example: `"Delete Account"` in a `Button` → `"deleteAccountButtonTitle"`.
    public var suggestedPropertyName: String {
        let words = value
            .components(separatedBy: CharacterSet(charactersIn: " \t\n-_.,;:!?()[]{}\"'→←↑↓•…"))
            .filter { !$0.isEmpty }
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "localizedString" }
        let base = words[0].lowercased() + words.dropFirst().map(\.localizedCapitalized).joined()
        let suffix = context.propertySuffix
        return suffix.isEmpty ? base : base + suffix
    }
}

// MARK: - SourceLocation

/// A 1-based line/column position inside a source file.
public struct SourceLocation: Sendable, Hashable, Codable {
    public let file: String
    /// 1-based line number.
    public let line: Int
    /// 1-based UTF-8 column offset.
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}

extension SourceLocation: CustomStringConvertible {
    public var description: String { "\(file):\(line):\(column)" }
}
