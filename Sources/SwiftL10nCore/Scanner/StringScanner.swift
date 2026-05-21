import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Public API

/// Parses a single Swift source file and extracts hardcoded string literals
/// that appear inside known SwiftUI localizable call sites.
///
/// `StringScanner` is stateless and `Sendable` — create once, call `scan` on
/// as many files as needed, from as many concurrent tasks as needed.
public struct StringScanner: Sendable {
    public let ruleEngine: RuleEngine
    public let filter: FalsePositiveFilter
    /// Results with confidence below this threshold are silently dropped.
    /// Default `0.0` — report everything and let callers decide.
    public let minimumConfidence: Double

    public init(
        ruleEngine: RuleEngine = .default,
        filter: FalsePositiveFilter = FalsePositiveFilter(),
        minimumConfidence: Double = 0.0
    ) {
        self.ruleEngine = ruleEngine
        self.filter = filter
        self.minimumConfidence = minimumConfidence
    }

    /// Read `filePath` from disk and scan it.
    public func scan(filePath: String) throws -> ScanResult {
        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        return scan(source: source, filePath: filePath)
    }

    /// Scan `source` text directly.  `filePath` is embedded in location metadata only.
    public func scan(source: String, filePath: String) -> ScanResult {
        let tree = Parser.parse(source: source)
        let visitor = StringScannerVisitor(
            filePath: filePath,
            tree: tree,
            ruleEngine: ruleEngine,
            filter: filter,
            minimumConfidence: minimumConfidence
        )
        visitor.walk(tree)
        return ScanResult(
            detectedStrings: visitor.detected,
            diagnostics: visitor.emittedDiagnostics
        )
    }
}

// MARK: - ScanResult

public struct ScanResult: Sendable {
    public let detectedStrings: [DetectedString]
    public let diagnostics: [Diagnostic]
}

// MARK: - SyntaxVisitor

/// Internal implementation.  Kept `internal` so `@testable import` reaches it in tests.
final class StringScannerVisitor: SyntaxVisitor {

    private(set) var detected: [DetectedString] = []
    private(set) var emittedDiagnostics: [Diagnostic] = []

    private let filePath: String
    private let converter: SourceLocationConverter
    private let ruleEngine: RuleEngine
    private let filter: FalsePositiveFilter
    private let minimumConfidence: Double
    private let scorer = ConfidenceScorer()
    private let contextExtractor = ContextExtractor()

    init(
        filePath: String,
        tree: SourceFileSyntax,
        ruleEngine: RuleEngine,
        filter: FalsePositiveFilter,
        minimumConfidence: Double
    ) {
        self.filePath = filePath
        self.converter = SourceLocationConverter(fileName: filePath, tree: tree)
        self.ruleEngine = ruleEngine
        self.filter = filter
        self.minimumConfidence = minimumConfidence
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Visit

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        for rule in ruleEngine.rules {
            guard let detectionContext = rule.match(in: node) else { continue }
            process(node, rule: rule, context: detectionContext)
            break   // first-match-wins: a call site belongs to exactly one rule
        }
        return .visitChildren
    }

    // MARK: - Processing Pipeline

    private func process(
        _ node: FunctionCallExprSyntax,
        rule: any DetectionRule,
        context: DetectionContext
    ) {
        // Step 1 — Extract string argument
        guard let (rawValue, hasInterpolation) = extractString(
            from: node.arguments,
            selector: rule.stringArgumentSelector
        ) else { return }

        // Step 2 — False-positive filter (run on static content only)
        let filterTarget = hasInterpolation ? staticContent(of: rawValue) : rawValue
        if let reason = filter.exclusionReason(for: filterTarget) {
            // Emit a note so callers can understand why the string was skipped
            let location = makeLocation(for: node)
            emittedDiagnostics.append(Diagnostic(
                severity: .note,
                message: "Skipped \"\(truncated(rawValue))\" — \(reason.explanation)",
                location: location
            ))
            return
        }

        // Step 3 — Enclosing context
        let enclosing = contextExtractor.extract(from: node)

        // Step 4 — Confidence score
        let confidence = scorer.score(
            value: filterTarget,
            baseConfidence: rule.baseConfidence,
            enclosingContext: enclosing
        )

        guard confidence >= minimumConfidence else { return }

        // Step 5 — Interpolation diagnostic (warn but still record)
        if hasInterpolation {
            emittedDiagnostics.append(Diagnostic(
                severity: .warning,
                message: "Interpolated string in localizable context — no API will be generated: \"\(truncated(rawValue))\"",
                location: makeLocation(for: node)
            ))
        }

        // Step 6 — Record
        detected.append(DetectedString(
            value: rawValue,
            location: makeLocation(for: node),
            context: context,
            confidence: confidence,
            hasInterpolation: hasInterpolation,
            enclosingContext: enclosing
        ))
    }

    // MARK: - String Extraction

    /// Returns `(template, hasInterpolation)` or `nil` if no string literal is present.
    ///
    /// For interpolated strings the template replaces each interpolation segment with `{…}`,
    /// e.g. `"Hello \(name)!"` → `("Hello {…}!", true)`.
    private func extractString(
        from arguments: LabeledExprListSyntax,
        selector: ArgumentSelector
    ) -> (value: String, hasInterpolation: Bool)? {
        guard let arg = arguments.argument(for: selector) else { return nil }
        guard let literal = arg.expression.as(StringLiteralExprSyntax.self) else { return nil }

        let hasInterp = literal.segments.contains { $0.is(ExpressionSegmentSyntax.self) }

        let value = literal.segments.compactMap { segment -> String? in
            if let str = segment.as(StringSegmentSyntax.self) { return str.content.text }
            if segment.is(ExpressionSegmentSyntax.self) { return "{…}" }
            return nil
        }.joined()

        return (value, hasInterp)
    }

    /// Strips `{…}` markers from an interpolated template to produce the static skeleton.
    private func staticContent(of template: String) -> String {
        template.replacingOccurrences(of: "{…}", with: "")
    }

    // MARK: - Utilities

    private func makeLocation(for node: some SyntaxProtocol) -> SourceLocation {
        let sloc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SourceLocation(file: filePath, line: sloc.line, column: sloc.column)
    }

    private func truncated(_ value: String, maxLength: Int = 40) -> String {
        value.count > maxLength ? value.prefix(maxLength) + "…" : value
    }
}

// MARK: - ExclusionReason display

private extension ExclusionReason {
    var explanation: String {
        switch self {
        case .emptyString:            return "empty string"
        case .urlPattern:             return "looks like a URL"
        case .filePathPattern:        return "looks like a file path"
        case .dotSeparatedIdentifier: return "looks like an SF Symbol or dotted key"
        case .analyticsKey:           return "looks like an analytics/reverse-DNS key"
        case .snakeCaseIdentifier:    return "looks like a snake_case identifier"
        case .camelCaseIdentifier:    return "looks like a camelCase identifier"
        case .allCapsConstant:        return "looks like an ALL_CAPS constant"
        }
    }
}
