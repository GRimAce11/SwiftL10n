// MARK: - ScoreExplanation

/// A breakdown of how a string's confidence score was computed.
///
/// Useful for understanding why a particular string was detected at a given
/// confidence level. Shown in `--verbose` output and included in JSON diagnostics.
///
/// Example summary: `"+2% multi-word phrase, +1% title case, -12% very short (2 chars)"`
public struct ScoreExplanation: Sendable, Codable, Equatable, Hashable {

    public struct Factor: Sendable, Codable, Equatable, Hashable {
        public let reason: String
        public let delta: Double
    }

    /// Rule's base confidence before any content adjustments.
    public let base: Double
    /// Each adjustment that was applied, in order.
    public let factors: [Factor]
    /// Final clamped score: `base + Σ(factors)`, clamped to `[0, 1]`.
    public let final: Double

    public var isEmpty: Bool { factors.isEmpty }

    /// Human-readable score breakdown for CLI output.
    public var summary: String {
        guard !factors.isEmpty else { return "" }
        return factors.map { f in
            let sign = f.delta >= 0 ? "+" : ""
            return "\(sign)\(formatted(f.delta)) \(f.reason)"
        }.joined(separator: ", ")
    }

    private func formatted(_ d: Double) -> String {
        String(format: "%.0f%%", d * 100)
    }
}

// MARK: - ConfidenceScorer

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

    /// Fast path — returns just the final score without allocating factor storage.
    public func score(
        value: String,
        baseConfidence: Double,
        enclosingContext: EnclosingContext
    ) -> Double {
        explain(value: value, baseConfidence: baseConfidence, enclosingContext: enclosingContext).final
    }

    /// Returns the final score plus a full breakdown of every applied adjustment.
    public func explain(
        value: String,
        baseConfidence: Double,
        enclosingContext: EnclosingContext
    ) -> ScoreExplanation {
        var acc = Accumulator()

        // ── String content adjustments ─────────────────────────────────────────
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        switch trimmed.count {
        case 0:     acc.add("empty string", -0.30)
        case 1...2: acc.add("very short (\(trimmed.count) chars)", -0.12)
        case 3...4: acc.add("short (\(trimmed.count) chars)", -0.04)
        default:    break
        }

        if trimmed.count > 200      { acc.add("very long (>\(trimmed.count) chars)", -0.25) }
        else if trimmed.count > 100 { acc.add("long (\(trimmed.count) chars)", -0.08) }

        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if words.count >= 2       { acc.add("multi-word phrase", +0.02) }
        if words.count >= 2 && isTitleCase(words) { acc.add("title case", +0.01) }
        if trimmed.first?.isUppercase == true { acc.add("starts uppercase", +0.01) }

        if trimmed.contains(where: \.isNumber) { acc.add("contains digits", -0.03) }

        if trimmed.count > 4,
           trimmed.filter(\.isLetter).allSatisfy(\.isUppercase),
           trimmed.contains(where: \.isLetter) {
            acc.add("all-caps", -0.08)
        }

        let unusualChars: Set<Character> = ["{", "}", "[", "]", "<", ">", "|", "\\", "^", "~", "`", "@", "#", "$", "%", "*", "="]
        if trimmed.contains(where: { unusualChars.contains($0) }) {
            acc.add("unusual characters", -0.05)
        }

        // ── Enclosing context adjustments ──────────────────────────────────────
        if let typeName = enclosingContext.typeName {
            let viewSuffixes = ["View", "Screen", "Page", "Controller", "ViewController"]
            if viewSuffixes.contains(where: { typeName.hasSuffix($0) }) {
                acc.add("inside \(typeName) (View family)", +0.02)
            }
        }
        if enclosingContext.propertyName == "body" { acc.add("inside body property", +0.01) }

        let final = max(0.0, min(1.0, baseConfidence + acc.delta))
        return ScoreExplanation(base: baseConfidence, factors: acc.factors, final: final)
    }

    // MARK: - Helpers

    private func isTitleCase(_ words: [String]) -> Bool {
        words.allSatisfy { word in
            guard let first = word.first else { return true }
            return first.isUppercase || !first.isLetter
        }
    }
}

// MARK: - Internal accumulator

/// Collects deltas and labels while scoring; zero overhead when explanation is unused.
private struct Accumulator {
    var delta = 0.0
    var factors: [ScoreExplanation.Factor] = []

    mutating func add(_ reason: String, _ d: Double) {
        guard d != 0 else { return }
        delta += d
        factors.append(.init(reason: reason, delta: d))
    }
}
