/// Computes a confidence score for a detected string, blending the rule's base
/// confidence with adjustments derived from the string content and its enclosing context.
///
/// ### Scoring philosophy
/// - **Deterministic**: the same inputs always produce the same score.
/// - **Explainable**: every adjustment is a named factor with a documented rationale.
/// - **Additive**: factors compose by summing deltas, clamped to [0, 1].
/// - **Conservative**: we bias toward keeping borderline strings (lower penalty)
///   rather than aggressively filtering (higher penalty), because false negatives
///   are less harmful than false positives for developer trust.
public struct ConfidenceScorer: Sendable {
    public init() {}

    /// Compute the final confidence for a detected string.
    ///
    /// - Parameters:
    ///   - value: The string template (may contain `{…}` interpolation markers).
    ///   - baseConfidence: The confidence floor set by the firing `DetectionRule`.
    ///   - enclosingContext: Nearest enclosing Swift declarations at the call site.
    public func score(
        value: String,
        baseConfidence: Double,
        enclosingContext: EnclosingContext
    ) -> Double {
        let delta = stringDelta(value) + contextDelta(enclosingContext)
        return max(0.0, min(1.0, baseConfidence + delta))
    }

    // MARK: - String Content Adjustments

    func stringDelta(_ value: String) -> Double {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        var delta = 0.0

        // Very short strings are suspicious (could be a key or symbol name).
        // We still allow them through but with a confidence dip.
        switch trimmed.count {
        case 0:     delta -= 0.30   // empty — should have been filtered, but guard anyway
        case 1...2: delta -= 0.12
        case 3...4: delta -= 0.04
        default:    break
        }

        // Very long strings are rarely UI labels.
        if trimmed.count > 200 { delta -= 0.25 }
        else if trimmed.count > 100 { delta -= 0.08 }

        let words = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Multi-word phrase → clearly human-readable, boost.
        if words.count >= 2 { delta += 0.02 }

        // Title Case (all words start with uppercase) → likely a UI label.
        if words.count >= 2 && isTitleCase(words) { delta += 0.01 }

        // Starts with an uppercase letter → probably a sentence or heading.
        if trimmed.first?.isUppercase == true { delta += 0.01 }

        // Contains digits → reduced likelihood of being a pure UI label.
        if trimmed.contains(where: \.isNumber) { delta -= 0.03 }

        // ALL CAPS but not a short abbreviation (OK, ID, URL) → unusual for UI.
        if trimmed.count > 4,
           trimmed.filter(\.isLetter).allSatisfy(\.isUppercase),
           trimmed.contains(where: \.isLetter) {
            delta -= 0.08
        }

        // Contains uncommon special characters unlikely in natural language.
        let unusualCharsSet: Set<Character> = ["{", "}", "[", "]", "<", ">", "|", "\\", "^", "~", "`", "@", "#", "$", "%", "*", "="]
        if trimmed.contains(where: { unusualCharsSet.contains($0) }) {
            delta -= 0.05
        }

        return delta
    }

    // MARK: - Enclosing Context Adjustments

    func contextDelta(_ context: EnclosingContext) -> Double {
        var delta = 0.0

        // Strings inside View-family types are very likely UI strings.
        if let typeName = context.typeName {
            let viewSuffixes = ["View", "Screen", "Page", "Controller", "ViewController"]
            if viewSuffixes.contains(where: { typeName.hasSuffix($0) }) {
                delta += 0.02
            }
        }

        // Strings inside the `body` computed property are canonical SwiftUI UI strings.
        if context.propertyName == "body" { delta += 0.01 }

        return delta
    }

    // MARK: - Helpers

    private func isTitleCase(_ words: [String]) -> Bool {
        words.allSatisfy { word in
            guard let first = word.first else { return true }
            return first.isUppercase || !first.isLetter
        }
    }
}
