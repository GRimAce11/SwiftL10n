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
    public func scan(filePath: String, suppressionIndex: SuppressionIndex = .empty) throws -> ScanResult {
        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        return scan(source: source, filePath: filePath, suppressionIndex: suppressionIndex)
    }

    /// Scan `source` text directly.  `filePath` is embedded in location metadata only.
    ///
    /// `// swiftl10n:ignore` comments in `source` are honoured automatically —
    /// any string literal on the same line as the comment is suppressed.
    public func scan(
        source: String,
        filePath: String,
        suppressionIndex: SuppressionIndex = .empty
    ) -> ScanResult {
        let tree = Parser.parse(source: source)
        let visitor = StringScannerVisitor(
            filePath: filePath,
            tree: tree,
            ruleEngine: ruleEngine,
            filter: filter,
            minimumConfidence: minimumConfidence,
            suppressionIndex: suppressionIndex,
            inlineSuppression: InlineSuppression(source: source)
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
    private let suppressionIndex: SuppressionIndex
    private let inlineSuppression: InlineSuppression
    private let scorer = ConfidenceScorer()
    private let contextExtractor = ContextExtractor()

    init(
        filePath: String,
        tree: SourceFileSyntax,
        ruleEngine: RuleEngine,
        filter: FalsePositiveFilter,
        minimumConfidence: Double,
        suppressionIndex: SuppressionIndex = .empty,
        inlineSuppression: InlineSuppression = .empty
    ) {
        self.filePath          = filePath
        self.converter         = SourceLocationConverter(fileName: filePath, tree: tree)
        self.ruleEngine        = ruleEngine
        self.filter            = filter
        self.minimumConfidence = minimumConfidence
        self.suppressionIndex  = suppressionIndex
        self.inlineSuppression = inlineSuppression
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Visit function calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        for rule in ruleEngine.rules {
            guard let context = rule.match(in: node) else { continue }
            guard let (value, hasInterp, litLoc) = extractString(
                from: node.arguments,
                selector: rule.stringArgumentSelector
            ) else { continue }

            // Suppression: string literal is an argument to an excluded localization function
            if let litLoc, suppressionIndex.isSuppressed(litLoc) {
                emittedDiagnostics.append(Diagnostic(
                    severity: .note,
                    message: "Skipped \"\(truncated(value))\" — argument to excluded localization function",
                    location: makeLocation(for: node)
                ))
                break
            }

            record(rawValue: value, hasInterpolation: hasInterp,
                   context: context, baseConfidence: rule.baseConfidence, node: node)
            // No break — allows e.g. UIAlertController to match both
            // UIAlertControllerTitleRule and UIAlertControllerMessageRule
        }
        return .visitChildren
    }

    // MARK: - Visit property assignments (UIKit)

    /// Handles `receiver.property = "string"` and bare `property = "string"`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count == 3,
              elements[1].is(AssignmentExprSyntax.self),
              let literal = elements[2].as(StringLiteralExprSyntax.self)
        else { return .visitChildren }

        let propName: String?
        if let member = elements[0].as(MemberAccessExprSyntax.self) {
            propName = member.declName.baseName.text
        } else if let decl = elements[0].as(DeclReferenceExprSyntax.self) {
            propName = decl.baseName.text
        } else {
            propName = nil
        }

        guard let name = propName else { return .visitChildren }

        for rule in ruleEngine.assignmentRules {
            guard let context = rule.match(propertyName: name) else { continue }
            let (value, hasInterp) = segments(of: literal)
            let litLoc = makeLocation(for: literal)
            if suppressionIndex.isSuppressed(litLoc) {
                emittedDiagnostics.append(Diagnostic(
                    severity: .note,
                    message: "Skipped \"\(truncated(value))\" — argument to excluded localization function",
                    location: makeLocation(for: node)
                ))
                break
            }
            record(rawValue: value, hasInterpolation: hasInterp,
                   context: context, baseConfidence: rule.baseConfidence, node: node)
            break
        }
        return .visitChildren
    }

    // MARK: - Shared detection pipeline

    private func record(
        rawValue: String,
        hasInterpolation: Bool,
        context: DetectionContext,
        baseConfidence: Double,
        node: some SyntaxProtocol
    ) {
        let location = makeLocation(for: node)

        // Inline suppression: // swiftl10n:ignore on the same line
        if inlineSuppression.isSuppressed(line: location.line) {
            emittedDiagnostics.append(Diagnostic(
                severity: .note,
                message: "Suppressed \"\(truncated(rawValue))\" — swiftl10n:ignore",
                location: location
            ))
            return
        }

        let filterTarget = hasInterpolation ? staticContent(of: rawValue) : rawValue
        if let reason = filter.exclusionReason(for: filterTarget) {
            emittedDiagnostics.append(Diagnostic(
                severity: .note,
                message: "Skipped \"\(truncated(rawValue))\" — \(reason.explanation)",
                location: location
            ))
            return
        }

        let enclosing = contextExtractor.extract(from: node)
        let explanation = scorer.explain(
            value: filterTarget,
            baseConfidence: baseConfidence,
            enclosingContext: enclosing
        )
        guard explanation.final >= minimumConfidence else { return }

        if hasInterpolation {
            emittedDiagnostics.append(Diagnostic(
                severity: .warning,
                message: "Interpolated string in localizable context — no API will be generated: \"\(truncated(rawValue))\"",
                location: location
            ))
        }

        detected.append(DetectedString(
            value: rawValue,
            location: location,
            context: context,
            confidence: explanation.final,
            hasInterpolation: hasInterpolation,
            enclosingContext: enclosing,
            scoreExplanation: explanation
        ))
    }

    // MARK: - String Extraction

    /// Returns `(template, hasInterpolation, literalLocation)` or `nil` if no string literal is present.
    /// `literalLocation` is the source position of the string literal itself (used for suppression checks).
    private func extractString(
        from arguments: LabeledExprListSyntax,
        selector: ArgumentSelector
    ) -> (value: String, hasInterpolation: Bool, literalLocation: SourceLocation?)? {
        guard let arg = arguments.argument(for: selector),
              let literal = arg.expression.as(StringLiteralExprSyntax.self)
        else { return nil }
        let (value, hasInterp) = segments(of: literal)
        return (value, hasInterp, makeLocation(for: literal))
    }

    /// Decodes a `StringLiteralExprSyntax` into a template string, replacing
    /// `\(…)` interpolations with `{…}` markers.
    private func segments(of literal: StringLiteralExprSyntax) -> (value: String, hasInterpolation: Bool) {
        let hasInterp = literal.segments.contains { $0.is(ExpressionSegmentSyntax.self) }
        let value = literal.segments.compactMap { seg -> String? in
            if let str = seg.as(StringSegmentSyntax.self) { return str.content.text }
            if seg.is(ExpressionSegmentSyntax.self) { return "{…}" }
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
        case .emojiOnly:              return "contains only emoji — no translatable text"
        }
    }
}
