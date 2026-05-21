import SwiftSyntax

// MARK: - Text("…")

/// Detects `Text("literal")` — the most common and highest-confidence SwiftUI call.
public struct TextViewRule: DetectionRule {
    public let name = "TextViewRule"
    public let baseConfidence = 0.98
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "Text") else { return nil }
        return .textView
    }
}

// MARK: - Button("…") { }

/// Detects `Button("label") { action() }`.
/// Does NOT fire for the `Button(role:action:label:)` form since its first argument is labeled.
public struct ButtonRule: DetectionRule {
    public let name = "ButtonRule"
    public let baseConfidence = 0.95
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "Button") else { return nil }
        return .buttonLabel
    }
}

// MARK: - Label("…", systemImage:)

/// Detects `Label("title", systemImage: "gear")`.
/// Only the title (first unlabeled argument) is extracted; `systemImage:` is ignored.
public struct LabelViewRule: DetectionRule {
    public let name = "LabelViewRule"
    public let baseConfidence = 0.95
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "Label") else { return nil }
        return .labelView
    }
}

// MARK: - .navigationTitle("…") / .navigationBarTitle("…")

/// Detects `.navigationTitle("…")` and the deprecated `.navigationBarTitle("…")`.
public struct NavigationTitleRule: DetectionRule {
    public let name = "NavigationTitleRule"
    public let baseConfidence = 0.97
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    private static let memberNames: Set<String> = ["navigationTitle", "navigationBarTitle"]

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard let name = memberName(node), Self.memberNames.contains(name) else { return nil }
        return .navigationTitle
    }
}

// MARK: - .alert("…", isPresented:) { }

/// Detects `.alert("title", isPresented: $binding) { }`.
public struct AlertRule: DetectionRule {
    public let name = "AlertRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard memberName(node) == "alert" else { return nil }
        return .alert
    }
}

// MARK: - .confirmationDialog("…", isPresented:) { }

/// Detects `.confirmationDialog("title", isPresented: $binding) { }`.
public struct ConfirmationDialogRule: DetectionRule {
    public let name = "ConfirmationDialogRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard memberName(node) == "confirmationDialog" else { return nil }
        return .confirmationDialog
    }
}

// MARK: - TextField("placeholder", text:)

/// Detects `TextField("placeholder", text: $binding)`.
/// The placeholder is the first unlabeled argument; `text:` is ignored.
public struct TextFieldRule: DetectionRule {
    public let name = "TextFieldRule"
    public let baseConfidence = 0.92
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "TextField") else { return nil }
        return .textField
    }
}

// MARK: - Toggle("…", isOn:)

/// Detects `Toggle("label", isOn: $binding)`.
/// The label is the first unlabeled argument; `isOn:` is ignored.
public struct ToggleRule: DetectionRule {
    public let name = "ToggleRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "Toggle") else { return nil }
        return .toggle
    }
}

// MARK: - .accessibilityLabel("…")

/// Detects `.accessibilityLabel("description")`.
public struct AccessibilityLabelRule: DetectionRule {
    public let name = "AccessibilityLabelRule"
    public let baseConfidence = 0.90
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled

    public init() {}

    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard memberName(node) == "accessibilityLabel" else { return nil }
        return .accessibilityLabel
    }
}

// MARK: - Shared helpers (file-private)

/// `true` when the call is `Identifier(…)` — a direct (non-member) call.
private func isDirect(_ node: FunctionCallExprSyntax, callee: String) -> Bool {
    node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == callee
}

/// Returns the member name for `.foo(…)` calls, or `nil` for non-member calls.
private func memberName(_ node: FunctionCallExprSyntax) -> String? {
    node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
}
