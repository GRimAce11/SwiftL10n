import SwiftSyntax

/// Walks UP the syntax tree from a detected call site to find the nearest enclosing
/// Swift declarations, building an `EnclosingContext`.
///
/// Walking up rather than tracking state during the downward traversal means the
/// extractor is stateless and can be called per-detection without coordination.
/// The cost is O(depth) per detection, which is negligible for typical source files.
struct ContextExtractor {
    func extract(from node: some SyntaxProtocol) -> EnclosingContext {
        var typeName: String?
        var propertyName: String?
        var functionName: String?

        var cursor: Syntax? = Syntax(node).parent

        while let current = cursor {
            // Type declaration (stop at nearest one)
            if typeName == nil {
                if let d = current.as(StructDeclSyntax.self) {
                    typeName = d.name.text
                } else if let d = current.as(ClassDeclSyntax.self) {
                    typeName = d.name.text
                } else if let d = current.as(EnumDeclSyntax.self) {
                    typeName = d.name.text
                } else if let d = current.as(ExtensionDeclSyntax.self) {
                    typeName = d.extendedType.trimmedDescription
                }
            }

            // Variable binding — catches computed properties (`body`, `headerView`, …)
            if propertyName == nil, let d = current.as(VariableDeclSyntax.self) {
                propertyName = d.bindings.first
                    .flatMap { $0.pattern.as(IdentifierPatternSyntax.self) }
                    .map(\.identifier.text)
            }

            // Free function declaration
            if functionName == nil, let d = current.as(FunctionDeclSyntax.self) {
                functionName = d.name.text
            }

            cursor = current.parent
        }

        return EnclosingContext(
            typeName: typeName,
            propertyName: propertyName,
            functionName: functionName
        )
    }
}
