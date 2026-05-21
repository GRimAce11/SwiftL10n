import Foundation

/// Central collector for all diagnostics produced during a SwiftL10n run.
///
/// A single engine is created per CLI invocation and passed (or returned) through
/// every pipeline stage so that all warnings and errors surface in one place.
///
/// Thread-safe via `NSLock` — safe to use from concurrent file scans in future phases.
public final class DiagnosticsEngine: @unchecked Sendable {

    private var _diagnostics: [Diagnostic] = []
    private let lock = NSLock()

    public init() {}

    // MARK: - Emitting

    public func emit(_ diagnostic: Diagnostic) {
        lock.withLock { _diagnostics.append(diagnostic) }
    }

    public func emit(
        _ severity: Diagnostic.Severity,
        _ message: String,
        at location: SourceLocation? = nil
    ) {
        emit(Diagnostic(severity: severity, message: message, location: location))
    }

    // MARK: - Reading

    /// All collected diagnostics in emission order.
    public var diagnostics: [Diagnostic] {
        lock.withLock { _diagnostics }
    }

    public var hasErrors: Bool {
        lock.withLock { _diagnostics.contains { $0.severity == .error } }
    }

    public var warningCount: Int {
        lock.withLock { _diagnostics.filter { $0.severity == .warning }.count }
    }

    public var errorCount: Int {
        lock.withLock { _diagnostics.filter { $0.severity == .error }.count }
    }

    // MARK: - Output

    /// Write all diagnostics at or above `minimumSeverity` to `stderr` in Xcode format.
    public func printAll(minimumSeverity: Diagnostic.Severity = .note) {
        let snapshot = lock.withLock { _diagnostics }
        for d in snapshot where d.severity >= minimumSeverity {
            fputs(d.description + "\n", stderr)
        }
    }
}
