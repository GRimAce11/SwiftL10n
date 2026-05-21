/// A diagnostic message produced during scanning, namespace inference, or code generation.
public struct Diagnostic: Sendable, Hashable {

    // MARK: - Severity

    public enum Severity: Sendable, Hashable, Comparable {
        case note
        case warning
        case error
    }

    // MARK: - Properties

    public let severity: Severity
    public let message: String
    /// `nil` for diagnostics not tied to a specific source position (e.g. I/O errors).
    public let location: SourceLocation?

    public init(severity: Severity, message: String, location: SourceLocation? = nil) {
        self.severity = severity
        self.message = message
        self.location = location
    }
}

// MARK: - Formatting

extension Diagnostic: CustomStringConvertible {
    /// Xcode-compatible format: `<file>:<line>:<col>: <severity>: <message>`
    public var description: String {
        let tag: String = switch severity {
        case .note:    "note"
        case .warning: "warning"
        case .error:   "error"
        }
        guard let location else { return "\(tag): \(message)" }
        return "\(location): \(tag): \(message)"
    }
}
