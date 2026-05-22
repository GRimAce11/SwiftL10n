/// Line-level suppression derived from `// swiftl10n:ignore` comments in source.
///
/// When a line contains `swiftl10n:ignore` anywhere (case-sensitive), any string
/// literal detected on that line is dropped from scan results. A `.note` diagnostic
/// is emitted so developers know the suppression fired.
///
/// ```swift
/// Text("internal-use-only")   // swiftl10n:ignore
/// label.text = "debug_value"  // swiftl10n:ignore — not a UI string
/// ```
///
/// - Note: Only same-line suppression is supported. A `// swiftl10n:ignore` comment
///   on a dedicated line above a call site does **not** suppress the line below.
public struct InlineSuppression: Sendable {

    private let suppressedLines: Set<Int>

    /// Build from raw source text. Runs in O(lines) time.
    /// Cost is zero when the source contains no `swiftl10n:ignore` comments.
    public init(source: String) {
        var lines = Set<Int>()
        for (index, line) in source.components(separatedBy: "\n").enumerated()
        where line.contains("swiftl10n:ignore") {
            lines.insert(index + 1)  // 1-based
        }
        suppressedLines = lines
    }

    public static let empty = InlineSuppression()

    public init() {
        suppressedLines = []
    }

    /// Returns `true` when any string literal detected on `line` should be suppressed.
    public func isSuppressed(line: Int) -> Bool {
        suppressedLines.contains(line)
    }

    public var isEmpty: Bool { suppressedLines.isEmpty }
    public var count: Int    { suppressedLines.count }
}
