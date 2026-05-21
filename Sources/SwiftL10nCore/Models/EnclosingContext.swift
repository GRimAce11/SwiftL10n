/// The nearest enclosing Swift declarations around a detected string.
///
/// Populated by `ContextExtractor` and used in two ways:
///   1. **Confidence scoring** — a string inside a type named `SettingsView` is very
///      likely a UI string, which nudges the score upward.
///   2. **Namespace inference improvement** — future phases can override the file-based
///      namespace with the enclosing type name when they differ (e.g. embedded preview helpers).
public struct EnclosingContext: Sendable, Hashable, Codable {
    /// Name of the nearest enclosing `struct`, `class`, `enum`, or `extension`.
    public let typeName: String?

    /// Name of the nearest enclosing stored or computed property binding
    /// (e.g. `body`, `headerView`).
    public let propertyName: String?

    /// Name of the nearest enclosing `func` declaration.
    public let functionName: String?

    public init(
        typeName: String? = nil,
        propertyName: String? = nil,
        functionName: String? = nil
    ) {
        self.typeName = typeName
        self.propertyName = propertyName
        self.functionName = functionName
    }

    public static let empty = EnclosingContext()

    public var isEmpty: Bool {
        typeName == nil && propertyName == nil && functionName == nil
    }
}
