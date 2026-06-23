/// Why a string was excluded from localization candidates.
///
/// Every exclusion reason maps to a deterministic, explainable pattern.
/// There are NO heuristic guesses here — if a reason fires, the string is
/// definitively not a human-readable UI label.
public enum ExclusionReason: Sendable, Equatable {
    /// `""` or whitespace-only content.
    case emptyString

    /// Starts with `http://`, `https://`, `ftp://`, or `www.`
    case urlPattern

    /// Starts with `/` or `~/` — an absolute or home-relative file path.
    case filePathPattern

    /// All-lowercase words joined by dots with no spaces, e.g. `arrow.right.circle`.
    /// Matches both SF Symbol names and dot-separated localization/API keys.
    case dotSeparatedIdentifier

    /// Starts with a known reverse-DNS prefix (`com.`, `org.`, `net.`, `io.`, etc.).
    case analyticsKey

    /// Contains an underscore between two word characters and has no spaces,
    /// e.g. `user_name`, `api_key`, `AUTH_TOKEN`.
    case snakeCaseIdentifier

    /// No spaces, starts with a lowercase letter, contains at least one uppercase letter,
    /// and is not a known product name (iPhone, iPad, …).
    case camelCaseIdentifier

    /// All-uppercase letters, contains at least one underscore, no spaces, 3+ characters.
    /// e.g. `SOME_CONSTANT`, `DEBUG_LEVEL`.
    case allCapsConstant

    /// Contains only emoji characters (and optional whitespace).
    /// Strings that mix emoji with text are kept; pure-emoji strings have no translatable content.
    case emojiOnly
}

// MARK: -

/// Applies fast pattern-matching filters to eliminate strings that are definitively
/// not human-readable UI labels.
///
/// ### Design principle
/// The filter is **conservative** — it only excludes patterns where there is zero
/// plausible legitimate UI usage.  Borderline cases (short strings, numeric content)
/// are left to the `ConfidenceScorer` to penalise rather than hard-exclude.
/// This ensures false negatives (missing a real string) are preferred over false
/// positives (flagging a non-UI string), protecting developer trust.
public struct FalsePositiveFilter: Sendable {
    public init() {}

    /// Returns an `ExclusionReason` if `value` should be discarded, or `nil` to keep it.
    public func exclusionReason(for value: String) -> ExclusionReason? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // 1. Empty / whitespace-only
        guard !trimmed.isEmpty else { return .emptyString }

        // 2a. Emoji-only strings — no translatable text content
        if isEmojiOnly(trimmed) { return .emojiOnly }

        // 2. URL-like
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("ftp://") || lower.hasPrefix("ftps://")
            || lower.hasPrefix("www.") {
            return .urlPattern
        }

        // 3. Absolute or home-relative file paths
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            return .filePathPattern
        }

        // --- All remaining patterns require the string to have NO spaces ---
        guard !trimmed.contains(" ") else { return nil }

        // 4. Reverse-DNS / analytics keys — checked BEFORE generic dot-separated so that
        //    com.example.app returns .analyticsKey rather than .dotSeparatedIdentifier.
        if isReverseDNS(lower) { return .analyticsKey }

        // 5. Dot-separated identifiers (SF Symbols, localization keys, API namespaces)
        if isDotSeparatedIdentifier(trimmed) { return .dotSeparatedIdentifier }

        // 6. SCREAMING_SNAKE checked BEFORE generic snake_case so ALL_CAPS_CONSTANT
        //    returns .allCapsConstant rather than .snakeCaseIdentifier.
        if isScreamingCase(trimmed) { return .allCapsConstant }
        if isSnakeCase(trimmed) { return .snakeCaseIdentifier }

        // 7. camelCase identifiers (no spaces, starts lowercase, has an uppercase letter)
        if isCamelCase(trimmed) { return .camelCaseIdentifier }

        return nil
    }

    // MARK: - Pattern Predicates

    /// `arrow.right`, `person.crop.circle.fill`, `common.button.ok`
    private func isDotSeparatedIdentifier(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count >= 2 else { return false }
        // Every part must be non-empty and contain only lowercase letters and digits.
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter && $0.isLowercase || $0.isNumber }
        }
    }

    /// `com.example.app`, `org.project`, `io.github.thing`
    private func isReverseDNS(_ lower: String) -> Bool {
        let prefixes = ["com.", "org.", "net.", "io.", "co.", "app.", "dev."]
        return prefixes.contains { lower.hasPrefix($0) }
    }

    /// `user_name`, `api_key`, `profile_image_url`
    private func isSnakeCase(_ value: String) -> Bool {
        guard value.contains("_") else { return false }
        // There must be a letter immediately before AND after at least one underscore.
        let chars = Array(value)
        for i in 1..<chars.count - 1 where chars[i] == "_" {
            if chars[i - 1].isLetter && chars[i + 1].isLetter { return true }
        }
        return false
    }

    /// `SOME_CONSTANT`, `DEBUG_MODE` (3+ chars, all-uppercase, contains underscore)
    private func isScreamingCase(_ value: String) -> Bool {
        guard value.count >= 3, value.contains("_") else { return false }
        return value.filter(\.isLetter).allSatisfy(\.isUppercase)
    }

    /// `viewModel`, `userDefaultsKey`, `backgroundColor`
    private func isCamelCase(_ value: String) -> Bool {
        guard let first = value.first, first.isLowercase else { return false }
        guard value.contains(where: \.isUppercase) else { return false }
        // Allow product names that start with lowercase but ARE user-visible.
        return !knownLowercaseProductNames.contains(value)
    }

    /// Lowercase-starting Apple product and technology names that may appear in UI copy.
    private let knownLowercaseProductNames: Set<String> = [
        "iPhone", "iPad", "iPod", "iCloud", "iMessage", "iTunes", "iPhoto",
        "macOS", "iOS", "watchOS", "tvOS", "visionOS",
        "eBook", "eSIM",
    ]

    /// Returns `true` when every non-whitespace scalar in `value` is an emoji.
    /// A string like "Hello 👋" returns `false`; "👋🎉" returns `true`.
    private func isEmojiOnly(_ value: String) -> Bool {
        let nonWhitespace = value.unicodeScalars.filter { $0.value != 0x20 && !$0.properties.isWhitespace }
        guard !nonWhitespace.isEmpty else { return false }
        return nonWhitespace.allSatisfy { isEmojiScalar($0) }
    }

    private func isEmojiScalar(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isEmojiPresentation { return true }
        // Emoji with value > 0xFF covers multi-byte emoji that have the isEmoji flag
        // but aren't rendered as emoji by default (e.g. digit keycaps need variation selector).
        if scalar.properties.isEmoji && scalar.value > 0xFF { return true }
        let v = scalar.value
        // Combining characters that appear only inside emoji sequences:
        return v == 0xFE0F   // variation selector-16 (emoji presentation)
            || v == 0x200D   // zero-width joiner
            || v == 0x20E3   // combining enclosing keycap
            || v == 0x1F3FB || v == 0x1F3FC || v == 0x1F3FD || v == 0x1F3FE || v == 0x1F3FF // skin tones
    }
}
