import SwiftSyntax

// MARK: - ArgumentSelector

/// Describes which argument in a function call contains the localizable string.
public enum ArgumentSelector: Sendable {
    /// The first argument that has **no label** at the call site.
    ///
    /// This correctly skips opt-out initializers like `Text(verbatim:)` and
    /// `Image(named:)` whose first arguments are labeled and therefore excluded.
    case firstUnlabeled

    /// The argument at `index` (0-based), regardless of label.
    case atIndex(Int)

    /// The argument whose label exactly matches `name`.
    case withLabel(String)
}

// MARK: - DetectionRule

/// A rule that recognises one family of SwiftUI localizable call sites.
///
/// Rules are composable and independently testable.  Adding UIKit support in a
/// future phase means creating new rule types — existing rules remain untouched.
///
/// ### Conformance contract
/// - `match(in:)` must be **pure** — no side effects, no mutation.
/// - Rules should be **exclusive**: a call site matches at most one rule.
///   The engine breaks on first match, so rule order matters only for ambiguous
///   cases (which the built-in set avoids by checking exact callee names).
public protocol DetectionRule: Sendable {
    /// Short identifier used in diagnostic messages and debug output.
    var name: String { get }

    /// The engine-level confidence ceiling before string-content adjustments.
    /// Set this to reflect how reliably the call site produces a UI string:
    /// `Text` is nearly always localizable (0.98), while `accessibilityLabel`
    /// has a slightly broader range of non-UI usages (0.90).
    var baseConfidence: Double { get }

    /// Which argument holds the candidate localizable string.
    var stringArgumentSelector: ArgumentSelector { get }

    /// Returns the `DetectionContext` if this rule fires for `node`, or `nil`
    /// if this rule does not match.
    func match(in node: FunctionCallExprSyntax) -> DetectionContext?
}

// MARK: - PropertyAssignmentRule

/// A rule that detects strings assigned to a named property, e.g. `label.text = "…"`.
///
/// The visitor calls `match(propertyName:)` for every assignment expression whose
/// right-hand side is a string literal.  Return a `DetectionContext` to claim the
/// assignment, or `nil` to pass.
public protocol PropertyAssignmentRule: Sendable {
    var name: String { get }
    var baseConfidence: Double { get }
    func match(propertyName: String) -> DetectionContext?
}

// MARK: - RuleEngine

/// An ordered list of rules applied to every function call and property assignment.
///
/// - `rules` — tried against every `FunctionCallExprSyntax`.
/// - `assignmentRules` — tried against every `property = "string"` expression.
///
/// Pass a custom `RuleEngine` to `StringScanner` to override or extend detection.
public struct RuleEngine: Sendable {
    public let rules: [any DetectionRule]
    public let assignmentRules: [any PropertyAssignmentRule]

    public init(
        rules: [any DetectionRule],
        assignmentRules: [any PropertyAssignmentRule] = []
    ) {
        self.rules = rules
        self.assignmentRules = assignmentRules
    }

    /// SwiftUI-only rules — the default when `StringScanner` is created with no arguments.
    public static let `default` = RuleEngine(rules: [
        TextViewRule(),
        ButtonRule(),
        LabelViewRule(),
        ToggleRule(),
        NavigationTitleRule(),
        AlertRule(),
        ConfirmationDialogRule(),
        TextFieldRule(),
        AccessibilityLabelRule(),
    ])

    /// UIKit-only rules (function calls + property assignments).
    /// Use this for a pure UIKit project: `StringScanner(ruleEngine: .uikit)`.
    public static let uikit = RuleEngine(
        rules: [
            UIButtonSetTitleRule(),
            UIAlertControllerTitleRule(),
            UIAlertControllerMessageRule(),
            UIAlertActionRule(),
            UIBarButtonItemRule(),
            UITabBarItemRule(),
        ],
        assignmentRules: [
            UIKitPropertyAssignmentRule(),
        ]
    )

    /// SwiftUI + UIKit rules combined.
    /// Use this for a mixed project: `StringScanner(ruleEngine: .full)`.
    public static let full = RuleEngine(
        rules: RuleEngine.default.rules + RuleEngine.uikit.rules,
        assignmentRules: RuleEngine.uikit.assignmentRules
    )
}

// MARK: - Argument Extraction Helper (shared by the visitor)

extension LabeledExprListSyntax {
    func argument(for selector: ArgumentSelector) -> LabeledExprSyntax? {
        switch selector {
        case .firstUnlabeled:
            return first(where: { $0.label == nil })
        case .atIndex(let i):
            return dropFirst(i).first
        case .withLabel(let name):
            return first(where: { $0.label?.text == name })
        }
    }
}
