import Foundation
import SwiftSyntax
import SwiftParser

/// Scans Swift source for UI elements that may be missing accessibility modifiers.
///
/// v1.0 scope: `Image("name")` calls (non-system-name, non-decorative) that have
/// no `.accessibilityLabel`, `.accessibilityHidden`, `.accessibilityElement`, or
/// `.accessibilityValue` anywhere in the modifier chain above the call site.
public struct AccessibilityAuditor: Sendable {

    public init() {}

    public func audit(source: String, filePath: String) -> [Diagnostic] {
        let tree = Parser.parse(source: source)
        let visitor = AccessibilityVisitor(filePath: filePath, tree: tree)
        visitor.walk(tree)
        return visitor.diagnostics
    }
}

// MARK: - Visitor

private final class AccessibilityVisitor: SyntaxVisitor {

    let filePath: String
    let converter: SourceLocationConverter
    var diagnostics: [Diagnostic] = []

    private static let accessibilityModifiers: Set<String> = [
        "accessibilityLabel",
        "accessibilityHidden",
        "accessibilityElement",
        "accessibilityValue",
        "accessibilityIdentifier",
    ]

    init(filePath: String, tree: SourceFileSyntax) {
        self.filePath  = filePath
        self.converter = SourceLocationConverter(fileName: filePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard isNonDecorativeImageLiteral(node),
              !hasAccessibilityModifier(above: Syntax(node)) else { return }

        let sloc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        diagnostics.append(Diagnostic(
            severity: .warning,
            message: "Image literal without accessibility modifier — "
                   + "add .accessibilityLabel(\"…\") or .accessibilityHidden(true) if decorative",
            location: SourceLocation(file: filePath, line: sloc.line, column: sloc.column)
        ))
    }

    // MARK: - Helpers

    private func isNonDecorativeImageLiteral(_ node: FunctionCallExprSyntax) -> Bool {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "Image",
              let firstArg = node.arguments.first else { return false }

        let label = firstArg.label?.text ?? ""
        guard label != "systemName", label != "decorative" else { return false }

        return firstArg.expression.is(StringLiteralExprSyntax.self)
    }

    private func hasAccessibilityModifier(above start: Syntax) -> Bool {
        var current = start
        while let parent = current.parent {
            if let member = parent.as(MemberAccessExprSyntax.self),
               Self.accessibilityModifiers.contains(member.declName.baseName.text) {
                return true
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent
        }
        return false
    }
}
