import SwiftSyntax
import SwiftParser
import Foundation

/// Detects existing localization call sites and string literals that should be
/// suppressed during string scanning.
///
/// Runs as a **pre-pass** in the pipeline before `StringScanner`, producing:
/// - A list of `Detection` records for reporting (how many already-localized sites exist).
/// - A `Set<SourceLocation>` of string literal positions to suppress in `StringScanner`.
///
/// Detection is purely structural — no type resolution, no semantic guessing.
public struct ExistingLocalizationDetector: Sendable {

    // MARK: - Config

    public struct Config: Sendable, Codable, Equatable {
        /// Dot-prefixed namespace roots recognized as existing localization.
        /// Trailing dot is optional: `"L10n."` and `"L10n"` are treated identically.
        public let patterns: [String]
        /// Function names whose string literal arguments are added to the suppression index.
        public let excludeArgumentsOf: [String]

        public init(patterns: [String] = [], excludeArgumentsOf: [String] = []) {
            self.patterns = patterns
            self.excludeArgumentsOf = excludeArgumentsOf
        }

        public static let empty = Config()

        var isEmpty: Bool { patterns.isEmpty && excludeArgumentsOf.isEmpty }

        /// Patterns with optional trailing dot stripped for boundary-safe prefix matching.
        var normalizedPatterns: [String] {
            patterns.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        }

        enum CodingKeys: String, CodingKey {
            case patterns
            case excludeArgumentsOf = "exclude_arguments_of"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            patterns           = try c.decodeIfPresent([String].self, forKey: .patterns)           ?? []
            excludeArgumentsOf = try c.decodeIfPresent([String].self, forKey: .excludeArgumentsOf) ?? []
        }
    }

    // MARK: - Detection

    /// A single existing-localization call site found in source.
    public struct Detection: Sendable, Codable, Equatable {
        public let location: SourceLocation
        /// The root pattern that matched, e.g. `"L10n"` or `"i18n"`.
        public let matchedPattern: String
        /// The full reconstructed expression path, e.g. `"i18n.Settings.title"`.
        public let fullExpression: String
        public let kind: Kind

        public enum Kind: String, Sendable, Codable, Equatable {
            case callExpression  // i18n.Settings.title()
            case memberAccess    // L10n.save
        }

        public init(
            location: SourceLocation,
            matchedPattern: String,
            fullExpression: String,
            kind: Kind
        ) {
            self.location       = location
            self.matchedPattern = matchedPattern
            self.fullExpression = fullExpression
            self.kind           = kind
        }
    }

    // MARK: - Result

    public struct Result: Sendable {
        /// Existing localization call sites found in the source file.
        public let detections: [Detection]
        /// Source locations of string literals inside excluded functions
        /// (e.g., the `"Save"` inside `NSLocalizedString("Save", comment: "")`).
        /// These positions are fed into `SuppressionIndex`.
        public let suppressionLocations: Set<SourceLocation>

        public static let empty = Result(detections: [], suppressionLocations: [])
    }

    // MARK: - API

    public let config: Config

    public init(config: Config) {
        self.config = config
    }

    /// Scan `source` text and return existing localization detections.
    ///
    /// Returns `Result.empty` immediately when `config.isEmpty` so that the
    /// pre-pass is zero-cost when no patterns are configured.
    public func detect(source: String, filePath: String) -> Result {
        guard !config.isEmpty else { return .empty }
        let tree = Parser.parse(source: source)
        let visitor = ExistingLocalizationVisitor(config: config, filePath: filePath, tree: tree)
        visitor.walk(tree)
        return Result(
            detections: visitor.detections,
            suppressionLocations: visitor.suppressedStringLocations
        )
    }
}

// MARK: - Visitor

private final class ExistingLocalizationVisitor: SyntaxVisitor {
    let config: ExistingLocalizationDetector.Config
    let filePath: String
    let converter: SourceLocationConverter

    private(set) var detections: [ExistingLocalizationDetector.Detection] = []
    private(set) var suppressedStringLocations: Set<SourceLocation> = []

    init(config: ExistingLocalizationDetector.Config, filePath: String, tree: SourceFileSyntax) {
        self.config    = config
        self.filePath  = filePath
        self.converter = SourceLocationConverter(fileName: filePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Call expressions: i18n.Settings.title()

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let path = Self.dotPath(of: ExprSyntax(node.calledExpression))

        // Detect existing localization patterns: i18n.Settings.title()
        if let matched = matchedPattern(for: path) {
            detections.append(.init(
                location:       makeLocation(for: node),
                matchedPattern: matched,
                fullExpression: path,
                kind:           .callExpression
            ))
        }

        // Record excluded function string arguments for the suppression index.
        // e.g. NSLocalizedString("Save", comment: "") → record position of "Save"
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
           config.excludeArgumentsOf.contains(callee.baseName.text) {
            for arg in node.arguments {
                if let literal = arg.expression.as(StringLiteralExprSyntax.self) {
                    suppressedStringLocations.insert(makeLocation(for: literal))
                }
            }
        }

        return .visitChildren
    }

    // MARK: - Property-style access: L10n.save (no call parens)

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let parentKind = node.parent?.kind
        // Skip if this is the callee of a function call (handled above)
        // or an intermediate node in a longer member-access chain
        guard parentKind != .functionCallExpr,
              parentKind != .memberAccessExpr
        else { return .visitChildren }

        let path = Self.dotPath(of: ExprSyntax(node))
        if let matched = matchedPattern(for: path) {
            detections.append(.init(
                location:       makeLocation(for: node),
                matchedPattern: matched,
                fullExpression: path,
                kind:           .memberAccess
            ))
        }
        return .visitChildren
    }

    // MARK: - Dot-path reconstruction

    /// Reconstruct a dot-separated expression path from a nested `MemberAccessExprSyntax` tree.
    ///
    /// `i18n.Settings.title` (as a `MemberAccessExprSyntax`) → `"i18n.Settings.title"`
    static func dotPath(of expr: ExprSyntax) -> String {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base {
            let basePath = dotPath(of: base)
            let name     = member.declName.baseName.text
            return basePath.isEmpty ? name : "\(basePath).\(name)"
        }
        return ""
    }

    // MARK: - Pattern matching

    private func matchedPattern(for path: String) -> String? {
        // Boundary-safe: "L10n" matches "L10n.save" but not "L10nHelper.save"
        config.normalizedPatterns.first { p in
            path == p || path.hasPrefix("\(p).")
        }
    }

    // MARK: - Location

    private func makeLocation(for node: some SyntaxProtocol) -> SourceLocation {
        let sloc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourceLocation(file: filePath, line: sloc.line, column: sloc.column)
    }
}
