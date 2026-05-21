/// A diagnostic message produced during scanning, namespace inference, or code generation.
public struct Diagnostic: Sendable, Hashable, Codable {

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

extension Diagnostic.Severity: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "warning": self = .warning
        case "error":   self = .error
        default:        self = .note
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .note:    try c.encode("note")
        case .warning: try c.encode("warning")
        case .error:   try c.encode("error")
        }
    }
}

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
