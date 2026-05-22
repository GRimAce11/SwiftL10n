import Foundation

/// Converts an `AssetCatalog` into a single `Assets.swift` source file string.
///
/// **Source of truth:** the parsed `AssetCatalog` — not detected source references.
/// Every asset declared in the catalog gets a typed accessor, regardless of whether
/// it is already referenced in source.
///
/// ```swift
/// let catalog = try AssetCatalogParser.parseCatalogs(in: projectURL)
/// let code    = AssetCodeGenerator().generate(catalog: catalog)
/// // write code to Assets.swift
/// ```
///
/// Generated output (default configuration):
/// ```swift
/// public enum Assets {
///     public static func logo() -> Image { Image("logo") }
/// }
/// extension Assets {
///     public enum Icons {
///         public static func profileIcon() -> Image { Image("Icons/profile_icon") }
///     }
/// }
/// ```
public struct AssetCodeGenerator: Sendable {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        /// Root enum name. Default: `Assets`.
        public let rootEnumName: String
        /// Swift access level for generated declarations. Default: `public`.
        public let accessLevel: String
        /// Generate `ImageResource` accessors instead of `Image` for image assets.
        ///
        /// `ImageResource` is available on iOS 16+, macOS 13+, tvOS 16+, watchOS 9+.
        /// Generated accessors are annotated with `@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)`.
        /// Set `true` only when your deployment target supports these OS versions.
        /// Default: `false`.
        public let useImageResource: Bool

        public init(
            rootEnumName: String = "Assets",
            accessLevel: String = "public",
            useImageResource: Bool = false
        ) {
            self.rootEnumName     = rootEnumName
            self.accessLevel      = accessLevel
            self.useImageResource = useImageResource
        }
    }

    // MARK: - Internal model

    private struct AssetEntry {
        let stem: String        // bare name, e.g. "profile_icon"
        let fullName: String    // catalog path, e.g. "Icons/profile_icon"
        let type: AssetType
        var identifier: String  // resolved Swift identifier, e.g. "profileIcon"
    }

    // A node in the namespace tree. Root node has name == "".
    private final class Node {
        let name: String
        var images: [AssetEntry] = []
        var colors: [AssetEntry] = []
        var children: [String: Node] = [:]
        init(_ name: String) { self.name = name }
    }

    // MARK: - State

    private let configuration: Configuration

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Render the full catalog to a single `.swift` source string.
    public func generate(catalog: AssetCatalog) -> String {
        let root = buildTree(catalog: catalog)
        resolveIdentifiers(node: root)

        var lines: [String] = []
        lines += header()
        lines += emitRoot(root)
        for childName in root.children.keys.sorted() {
            lines += emitExtension(root.children[childName]!, parentPath: configuration.rootEnumName)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tree construction

    private func buildTree(catalog: AssetCatalog) -> Node {
        let root = Node("")

        for fullName in catalog.imageNames.sorted() {
            insert(into: root, fullName: fullName, type: .image)
        }
        for fullName in catalog.colorNames.sorted() {
            insert(into: root, fullName: fullName, type: .color)
        }
        return root
    }

    private func insert(into root: Node, fullName: String, type: AssetType) {
        let components = fullName.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else { return }

        var node = root
        for (index, component) in components.enumerated() {
            if index == components.count - 1 {
                let entry = AssetEntry(stem: component, fullName: fullName, type: type, identifier: "")
                if type == .image { node.images.append(entry) } else { node.colors.append(entry) }
            } else {
                if node.children[component] == nil { node.children[component] = Node(component) }
                node = node.children[component]!
            }
        }
    }

    // MARK: - Identifier resolution

    private func resolveIdentifiers(node: Node) {
        var used = Set<String>()
        node.images = node.images.map { e in
            var e = e; e.identifier = uniqueIdentifier(swiftIdentifier(from: e.stem), used: &used); return e
        }
        node.colors = node.colors.map { e in
            var e = e; e.identifier = uniqueIdentifier(swiftIdentifier(from: e.stem), used: &used); return e
        }
        for child in node.children.values { resolveIdentifiers(node: child) }
    }

    private func uniqueIdentifier(_ base: String, used: inout Set<String>) -> String {
        var candidate = base
        var n = 2
        while used.contains(candidate) { candidate = "\(base)_\(n)"; n += 1 }
        used.insert(candidate)
        return candidate
    }

    // MARK: - Emission

    private func header() -> [String] {
        [
            "// Auto-generated by SwiftL10n — do not edit.",
            "// swiftlint:disable all",
            "",
            "import SwiftUI",
            "",
        ]
    }

    private func emitRoot(_ root: Node) -> [String] {
        let a = configuration.accessLevel
        let n = configuration.rootEnumName
        var lines: [String] = ["\(a) enum \(n) {"]

        let bodyLines = emitEntries(root, indent: "    ")
        if bodyLines.isEmpty && root.children.isEmpty {
            lines.append("    // No assets found in catalog.")
        } else {
            if !bodyLines.isEmpty { lines.append(""); lines += bodyLines }
        }

        lines += ["}", ""]
        return lines
    }

    private func emitExtension(_ node: Node, parentPath: String) -> [String] {
        let a   = configuration.accessLevel
        let typeName = swiftTypeName(from: node.name)
        var lines: [String] = ["extension \(parentPath) {", "    \(a) enum \(typeName) {"]

        let bodyLines = emitEntries(node, indent: "        ")
        if !bodyLines.isEmpty { lines.append(""); lines += bodyLines }

        // Nested children — inline as nested enums
        for childName in node.children.keys.sorted() {
            let child = node.children[childName]!
            let childTypeName = swiftTypeName(from: childName)
            lines.append("        \(a) enum \(childTypeName) {")
            let childBody = emitEntries(child, indent: "            ")
            if !childBody.isEmpty { lines.append(""); lines += childBody }
            // Recurse deeper if needed
            for grandchildName in child.children.keys.sorted() {
                lines += emitDeepNested(child.children[grandchildName]!, indent: "            ", access: a)
            }
            lines += ["        }", ""]
        }

        lines += ["    }", "}", ""]
        return lines
    }

    private func emitDeepNested(_ node: Node, indent: String, access: String) -> [String] {
        let typeName = swiftTypeName(from: node.name)
        var lines: [String] = ["\(indent)\(access) enum \(typeName) {"]
        let bodyLines = emitEntries(node, indent: indent + "    ")
        if !bodyLines.isEmpty { lines.append(""); lines += bodyLines }
        for childName in node.children.keys.sorted() {
            lines += emitDeepNested(node.children[childName]!, indent: indent + "    ", access: access)
        }
        lines += ["\(indent)}", ""]
        return lines
    }

    private func emitEntries(_ node: Node, indent: String) -> [String] {
        var lines: [String] = []
        let a = configuration.accessLevel

        if !node.images.isEmpty {
            lines.append("\(indent)// MARK: - Images")
            lines.append("")
            for entry in node.images {
                lines.append("\(indent)/// Asset: \"\(entry.fullName)\"")
                if configuration.useImageResource {
                    lines.append("\(indent)@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)")
                    lines.append("\(indent)\(a) static var \(entry.identifier): ImageResource {")
                    lines.append("\(indent)    ImageResource(name: \"\(escaped(entry.fullName))\", bundle: .main)")
                } else {
                    lines.append("\(indent)\(a) static func \(entry.identifier)() -> Image {")
                    lines.append("\(indent)    Image(\"\(escaped(entry.fullName))\")")
                }
                lines.append("\(indent)}")
                lines.append("")
            }
        }

        if !node.colors.isEmpty {
            lines.append("\(indent)// MARK: - Colors")
            lines.append("")
            for entry in node.colors {
                lines.append("\(indent)/// Asset: \"\(entry.fullName)\"")
                lines.append("\(indent)\(a) static func \(entry.identifier)() -> Color {")
                lines.append("\(indent)    Color(\"\(escaped(entry.fullName))\")")
                lines.append("\(indent)}")
                lines.append("")
            }
        }

        return lines
    }

    // MARK: - Naming helpers

    /// Convert an asset stem to a camelCase Swift function identifier.
    ///
    /// Rules:
    /// - Split on `_`, `-`, `.`, ` `
    /// - First word: lowercase the first character only
    /// - Subsequent words: uppercase first character
    /// - If result starts with a digit: prefix with `_`
    func swiftIdentifier(from stem: String) -> String {
        let separators = CharacterSet(charactersIn: "_- .")
        let words = stem.components(separatedBy: separators).filter { !$0.isEmpty }
        guard !words.isEmpty else { return "_asset" }

        let first = words[0]
        let rest  = words.dropFirst()

        let base = (first.prefix(1).lowercased() + first.dropFirst())
            + rest.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()

        if base.isEmpty { return "_asset" }
        return base.first!.isNumber ? "_\(base)" : base
    }

    /// Convert a namespace folder name to a PascalCase Swift type identifier.
    func swiftTypeName(from name: String) -> String {
        let separators = CharacterSet(charactersIn: "_- .")
        let words = name.components(separatedBy: separators).filter { !$0.isEmpty }
        let result = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return result.isEmpty ? "_Namespace" : result
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
