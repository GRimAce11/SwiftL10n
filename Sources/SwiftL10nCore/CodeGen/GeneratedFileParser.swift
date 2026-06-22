import SwiftSyntax
import SwiftParser
import Foundation

/// A single accessor recovered from a previously-generated `i18n.swift`.
///
/// Holds exactly the data `CodeGenerator` needs to re-emit the accessor
/// byte-for-byte: the namespace it lives in, its bare function name, and the
/// source-escaped `localized:` value and `comment:` text exactly as they
/// appeared between the quotes in the existing file. No unescaping or context
/// reconstruction is performed, so a parse → emit round-trip is lossless.
public struct PreservedAccessor: Sendable, Hashable {
    /// The enclosing namespace enum name, e.g. `"AdLibrary"`.
    public let namespace: String
    /// Bare Swift identifier (backticks stripped), e.g. `"title"` or `"continue"`.
    public let funcName: String
    /// The `localized:` value exactly as escaped in source (`\"`, `\\` still present).
    public let escapedValue: String
    /// The `comment:` text exactly as escaped in source.
    public let escapedComment: String

    public init(namespace: String, funcName: String, escapedValue: String, escapedComment: String) {
        self.namespace      = namespace
        self.funcName       = funcName
        self.escapedValue   = escapedValue
        self.escapedComment = escapedComment
    }

    /// Dot-path key used to match against references detected in source,
    /// e.g. `"AdLibrary.title"`. Matches `ExistingLocalizationDetector`'s
    /// `fullExpression` with the root enum prefix stripped.
    public var referenceKey: String { "\(namespace).\(funcName)" }
}

/// Parses an existing generated `i18n.swift` back into structured accessors.
///
/// This is the i18n analogue of `AssetCatalogParser`: it treats the
/// previously-generated file as a source of truth so regeneration can be
/// **additive** instead of lossy. Once a call site is migrated to an accessor
/// (`Text(i18n.AdLibrary.title())`), the original `"…"` literal is gone from
/// source — a pure rescan would drop the `AdLibrary` group and break the build.
/// Recovering the prior accessors lets the generator preserve symbols that are
/// still referenced.
public enum GeneratedFileParser {

    /// Parse `source` and return every accessor declared under `rootEnumName`.
    ///
    /// When the source contains `FileRegionMerger` ownership markers (i.e. it was
    /// written with `merge_strategy: region`), only the generated region between
    /// the markers is parsed — manual extensions outside the markers are ignored,
    /// so they are never duplicated into the regenerated block.
    public static func parse(_ source: String, rootEnumName: String) -> [PreservedAccessor] {
        let content = generatedRegion(of: source) ?? source
        let tree    = Parser.parse(source: content)
        let visitor = GeneratedFileVisitor(rootEnumName: rootEnumName)
        visitor.walk(tree)
        return visitor.accessors
    }

    /// Keep only accessors whose `referenceKey` still appears in source.
    ///
    /// This is the reference-aware pruning step: an accessor that is no longer
    /// referenced anywhere (and no longer backed by a detectable literal) is
    /// genuinely dead and is dropped; everything still referenced is preserved.
    public static func preserving(
        _ accessors: [PreservedAccessor],
        referencedIn referenced: Set<String>
    ) -> [PreservedAccessor] {
        accessors.filter { referenced.contains($0.referenceKey) }
    }

    // MARK: - Region extraction

    private static func generatedRegion(of source: String) -> String? {
        let lines = source.components(separatedBy: "\n")
        guard
            let begin = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == FileRegionMerger.beginMarker }),
            let end   = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == FileRegionMerger.endMarker }),
            begin < end
        else { return nil }
        return lines[(begin + 1)..<end].joined(separator: "\n")
    }
}

// MARK: - Visitor

private final class GeneratedFileVisitor: SyntaxVisitor {
    let rootEnumName: String
    private(set) var accessors: [PreservedAccessor] = []

    init(rootEnumName: String) {
        self.rootEnumName = rootEnumName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Generated accessors are parameterless and return `String`.
        guard node.signature.parameterClause.parameters.isEmpty,
              let returnType = node.signature.returnClause?.type.as(IdentifierTypeSyntax.self),
              returnType.name.text == "String"
        else { return .visitChildren }

        // Namespace = nearest enclosing enum; must sit inside `extension <rootEnumName>`.
        guard let enumDecl = ancestor(EnumDeclSyntax.self, from: Syntax(node)),
              let ext      = ancestor(ExtensionDeclSyntax.self, from: Syntax(enumDecl)),
              ext.extendedType.trimmedDescription == rootEnumName
        else { return .visitChildren }

        // Body is a single `String(localized:…, comment:…)` call.
        guard let body   = node.body,
              let item   = body.statements.first?.item,
              let call   = item.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "String",
              let value  = argLiteral(call, label: "localized")
        else { return .visitChildren }

        let comment  = argLiteral(call, label: "comment") ?? ""
        let funcName = stripBackticks(node.name.text)

        accessors.append(PreservedAccessor(
            namespace:      enumDecl.name.text,
            funcName:       funcName,
            escapedValue:   value,
            escapedComment: comment
        ))
        return .visitChildren
    }

    // MARK: - Helpers

    private func ancestor<T: SyntaxProtocol>(_ type: T.Type, from node: Syntax) -> T? {
        var cursor = node.parent
        while let current = cursor {
            if let match = current.as(T.self) { return match }
            cursor = current.parent
        }
        return nil
    }

    /// Returns the source-escaped content of the labeled string-literal argument,
    /// i.e. the verbatim text between the quotes (escapes left intact).
    private func argLiteral(_ call: FunctionCallExprSyntax, label: String) -> String? {
        for arg in call.arguments where arg.label?.text == label {
            if let literal = arg.expression.as(StringLiteralExprSyntax.self) {
                return rawContent(of: literal)
            }
        }
        return nil
    }

    private func rawContent(of literal: StringLiteralExprSyntax) -> String {
        literal.segments
            .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }
            .joined()
    }

    private func stripBackticks(_ name: String) -> String {
        guard name.count >= 2, name.hasPrefix("`"), name.hasSuffix("`") else { return name }
        return String(name.dropFirst().dropLast())
    }
}
