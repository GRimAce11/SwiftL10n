import SwiftSyntax
import SwiftParser
import Foundation

// MARK: - Models

/// A reference to a named asset found in Swift source code.
public struct DetectedAssetReference: Sendable, Hashable {
    /// The literal name passed at the call site, e.g. `"profile_icon"`.
    public let name: String
    /// Whether this is an image or a color asset.
    public let type: AssetType
    /// The call-site form that contained the reference.
    public let context: AssetContext
    /// Where in source the reference appears.
    public let location: SourceLocation

    public init(name: String, type: AssetType, context: AssetContext, location: SourceLocation) {
        self.name = name
        self.type = type
        self.context = context
        self.location = location
    }
}

public enum AssetType: Sendable, Hashable {
    case image
    case color
}

public enum AssetContext: Sendable, Hashable {
    /// SwiftUI `Image("name")` — asset catalog image.
    case swiftUIImage
    /// SwiftUI `Image(decorative: "name")` — asset catalog image, decorative.
    case swiftUIImageDecorative
    /// SwiftUI `Color("name")` — asset catalog color.
    case swiftUIColor
    /// UIKit `UIImage(named: "name")`.
    case uiImageNamed
    /// UIKit `UIColor(named: "name")`.
    case uiColorNamed

    public var displayName: String {
        switch self {
        case .swiftUIImage:           return "Image"
        case .swiftUIImageDecorative: return "Image(decorative:)"
        case .swiftUIColor:           return "Color"
        case .uiImageNamed:           return "UIImage(named:)"
        case .uiColorNamed:           return "UIColor(named:)"
        }
    }
}

// MARK: - AssetScanner

/// Scans Swift source files for named asset references and optionally validates
/// them against a parsed `AssetCatalog`.
///
/// Unlike `StringScanner`, `AssetScanner` does **not** apply `FalsePositiveFilter`
/// — asset names are intentionally identifier-like (`profile_icon`, `PrimaryBlue`)
/// and would be incorrectly rejected.
///
/// ```swift
/// let catalog = try AssetCatalogParser.parseCatalogs(in: projectURL)
/// let scanner = AssetScanner()
/// let result  = try scanner.scan(filePath: "HomeView.swift")
/// let missing = scanner.validate(result, against: catalog)
/// // missing → diagnostics for Image("name") where "name" isn't in the catalog
/// ```
public struct AssetScanner: Sendable {

    public struct ScanResult: Sendable {
        public let references: [DetectedAssetReference]
        public let filePath: String
    }

    public init() {}

    // MARK: - Scan

    /// Scan `source` text. `filePath` is embedded in location metadata only.
    public func scan(source: String, filePath: String) -> ScanResult {
        let tree    = Parser.parse(source: source)
        let visitor = AssetScannerVisitor(filePath: filePath, tree: tree)
        visitor.walk(tree)
        return ScanResult(references: visitor.references, filePath: filePath)
    }

    /// Read `filePath` from disk and scan it.
    public func scan(filePath: String) throws -> ScanResult {
        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        return scan(source: source, filePath: filePath)
    }

    // MARK: - Validation

    /// Compare every reference in `result` against `catalog`.
    /// Returns one `.warning` diagnostic per reference whose name is absent from the catalog.
    ///
    /// This is the key differentiator: SwiftGen and R.swift generate typed accessors
    /// *from* a catalog; SwiftL10n detects calls *to* a catalog and flags missing names.
    public func validate(_ result: ScanResult, against catalog: AssetCatalog) -> [Diagnostic] {
        result.references.compactMap { ref in
            let found: Bool = switch ref.type {
            case .image: catalog.contains(image: ref.name)
            case .color: catalog.contains(color: ref.name)
            }
            guard !found else { return nil }
            let assetKind = ref.type == .image ? "image" : "color"
            return Diagnostic(
                severity: .warning,
                message: "Asset \(assetKind) \"\(ref.name)\" not found in \(catalog.url.lastPathComponent) — this will crash at runtime",
                location: ref.location
            )
        }
    }
}

// MARK: - SyntaxVisitor

final class AssetScannerVisitor: SyntaxVisitor {
    private(set) var references: [DetectedAssetReference] = []

    private let filePath: String
    private let converter: SourceLocationConverter

    init(filePath: String, tree: SourceFileSyntax) {
        self.filePath  = filePath
        self.converter = SourceLocationConverter(fileName: filePath, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = calleeName(node)

        switch callee {
        case "Image":
            // Image("name") — first unlabeled argument → asset
            if let name = stringArg(node, label: nil) {
                append(name: name, type: .image, context: .swiftUIImage, node: node)
            }
            // Image(decorative: "name") → also an asset reference
            if let name = stringArg(node, label: "decorative") {
                append(name: name, type: .image, context: .swiftUIImageDecorative, node: node)
            }

        case "Color":
            // Color("name") — first unlabeled argument → catalog color
            if let name = stringArg(node, label: nil) {
                append(name: name, type: .color, context: .swiftUIColor, node: node)
            }

        case "UIImage":
            // UIImage(named: "name")
            if let name = stringArg(node, label: "named") {
                append(name: name, type: .image, context: .uiImageNamed, node: node)
            }

        case "UIColor":
            // UIColor(named: "name")
            if let name = stringArg(node, label: "named") {
                append(name: name, type: .color, context: .uiColorNamed, node: node)
            }

        default:
            break
        }

        return .visitChildren
    }

    // MARK: - Helpers

    /// Extracts the bare callee name from a function call, handling both
    /// `Image(…)` (DeclReferenceExpr) and `SwiftUI.Image(…)` (MemberAccessExpr).
    private func calleeName(_ node: FunctionCallExprSyntax) -> String? {
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let mem = node.calledExpression.as(MemberAccessExprSyntax.self) {
            return mem.declName.baseName.text
        }
        return nil
    }

    /// Returns the string literal value for the argument with the given label.
    /// Pass `nil` for the first unlabeled argument.
    private func stringArg(_ node: FunctionCallExprSyntax, label: String?) -> String? {
        let arg: LabeledExprSyntax?
        if let label {
            arg = node.arguments.first { $0.label?.text == label }
        } else {
            arg = node.arguments.first { $0.label == nil }
        }
        guard let arg,
              let literal = arg.expression.as(StringLiteralExprSyntax.self),
              // Only plain string literals — no interpolation
              !literal.segments.contains(where: { $0.is(ExpressionSegmentSyntax.self) }),
              let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else { return nil }
        let name = segment.content.text
        return name.isEmpty ? nil : name
    }

    private func append(
        name: String,
        type: AssetType,
        context: AssetContext,
        node: some SyntaxProtocol
    ) {
        let sloc = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        references.append(DetectedAssetReference(
            name: name,
            type: type,
            context: context,
            location: SourceLocation(file: filePath, line: sloc.line, column: sloc.column)
        ))
    }
}
