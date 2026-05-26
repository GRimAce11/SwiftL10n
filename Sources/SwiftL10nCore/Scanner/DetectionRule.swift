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

/// A rule that recognises one localizable call site (SwiftUI or UIKit).
///
/// ### Conformance contract
/// - `match(in:)` must be **pure** — no side effects, no mutation.
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

/// Ordered list of rules applied to every function call and property assignment.
///
/// The default engine detects strings from both SwiftUI and UIKit — no configuration needed.
/// Pass a custom `RuleEngine` only if you need to add your own rules.
///
/// ```swift
/// // Add a custom rule on top of everything built-in
/// let engine = RuleEngine(
///     rules: RuleEngine.default.rules + [MySheetTitleRule()],
///     assignmentRules: RuleEngine.default.assignmentRules
/// )
/// let scanner = StringScanner(ruleEngine: engine)
/// ```
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

    /// Detects strings from SwiftUI and UIKit — used automatically by `StringScanner()`.
    public static let `default` = RuleEngine(
        rules: [
            // SwiftUI
            TextViewRule(),
            ButtonRule(),
            LabelViewRule(),
            ToggleRule(),
            NavigationTitleRule(),
            AlertRule(),
            ConfirmationDialogRule(),
            TextFieldRule(),
            AccessibilityLabelRule(),
            SectionRule(),
            PickerRule(),
            MenuRule(),
            DisclosureGroupRule(),
            HelpTextRule(),
            // UIKit function calls
            UIButtonSetTitleRule(),
            UIAlertControllerTitleRule(),
            UIAlertControllerMessageRule(),
            UIAlertActionRule(),
            UIBarButtonItemRule(),
            UITabBarItemRule(),
        ],
        assignmentRules: [
            // UIKit property assignments (label.text = "…", title = "…", etc.)
            UIKitPropertyAssignmentRule(),
        ]
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
