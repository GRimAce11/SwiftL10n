/// Matches file paths against gitignore-style glob patterns.
///
/// Supported syntax:
/// - `*`    — any sequence of characters except `/`
/// - `**`   — any sequence including `/` (zero or more path components)
/// - `?`    — any single character except `/`
/// - All other characters are matched literally (case-sensitive)
public struct GlobMatcher: Sendable {

    /// Returns `true` if `path` matches `pattern`.
    ///
    /// `path` should be a POSIX file path (forward-slash separated).
    /// `pattern` is gitignore-style: `**/Generated`, `*.generated.swift`,
    /// `Sources/Generated/*.swift`.
    public static func matches(pattern: String, path: String) -> Bool {
        match(pat: pattern[...], str: path[...])
    }

    // MARK: - Recursive matcher

    private static func match(pat: Substring, str: Substring) -> Bool {
        // Both exhausted → success
        if pat.isEmpty { return str.isEmpty }

        // Leading `**/` → match zero or more path components
        if pat.hasPrefix("**/") {
            let tail = pat.dropFirst(3)
            // Try matching tail against str starting at every possible position
            var rest = str
            while true {
                if match(pat: tail, str: rest) { return true }
                // Advance to next path component
                guard let slash = rest.firstIndex(of: "/") else { break }
                rest = rest[rest.index(after: slash)...]
            }
            // Also try with an empty remainder (** matches zero components)
            return match(pat: tail, str: rest)
        }

        // Bare `**` at end → matches everything remaining
        if pat == "**" { return true }

        // `*` — matches any chars except `/`
        if pat.first == "*" {
            let tail = pat.dropFirst()
            // Try consuming 0..n non-slash characters from str
            var rest = str
            while true {
                if match(pat: tail, str: rest) { return true }
                if rest.isEmpty || rest.first == "/" { return false }
                rest = rest.dropFirst()
            }
        }

        // `?` — matches any single character except `/`
        if pat.first == "?" {
            guard !str.isEmpty, str.first != "/" else { return false }
            return match(pat: pat.dropFirst(), str: str.dropFirst())
        }

        // Literal character
        guard !str.isEmpty, pat.first == str.first else { return false }
        return match(pat: pat.dropFirst(), str: str.dropFirst())
    }
}
