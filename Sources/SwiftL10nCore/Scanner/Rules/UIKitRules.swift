import SwiftSyntax

// MARK: - button.setTitle("…", for: .normal)

/// Detects `button.setTitle("label", for: .normal)`.
public struct UIButtonSetTitleRule: DetectionRule {
    public let name = "UIButtonSetTitleRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.firstUnlabeled
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard memberName(node) == "setTitle" else { return nil }
        return .uiButtonTitle
    }
}

// MARK: - UIAlertController(title: "…", message: "…", preferredStyle:)

/// Detects the `title:` argument of `UIAlertController(title: "…", …)`.
public struct UIAlertControllerTitleRule: DetectionRule {
    public let name = "UIAlertControllerTitleRule"
    public let baseConfidence = 0.96
    public let stringArgumentSelector = ArgumentSelector.withLabel("title")
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "UIAlertController") else { return nil }
        return .uiAlertTitle
    }
}

/// Detects the `message:` argument of `UIAlertController(…, message: "…", …)`.
public struct UIAlertControllerMessageRule: DetectionRule {
    public let name = "UIAlertControllerMessageRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.withLabel("message")
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "UIAlertController") else { return nil }
        return .uiAlertMessage
    }
}

// MARK: - UIAlertAction(title: "…", style:)

/// Detects `UIAlertAction(title: "…", style: …)`.
public struct UIAlertActionRule: DetectionRule {
    public let name = "UIAlertActionRule"
    public let baseConfidence = 0.95
    public let stringArgumentSelector = ArgumentSelector.withLabel("title")
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "UIAlertAction") else { return nil }
        return .uiAlertAction
    }
}

// MARK: - UIBarButtonItem(title: "…", style:, target:, action:)

/// Detects `UIBarButtonItem(title: "…", style: …, target: …, action: …)`.
public struct UIBarButtonItemRule: DetectionRule {
    public let name = "UIBarButtonItemRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.withLabel("title")
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "UIBarButtonItem") else { return nil }
        return .uiButtonTitle
    }
}

// MARK: - UITabBarItem(title: "…", image:, tag:)

/// Detects `UITabBarItem(title: "…", image: …, tag: …)`.
public struct UITabBarItemRule: DetectionRule {
    public let name = "UITabBarItemRule"
    public let baseConfidence = 0.93
    public let stringArgumentSelector = ArgumentSelector.withLabel("title")
    public init() {}
    public func match(in node: FunctionCallExprSyntax) -> DetectionContext? {
        guard isDirect(node, callee: "UITabBarItem") else { return nil }
        return .uiTabBarItem
    }
}

// MARK: - Property assignments

/// Detects common UIKit property assignments whose right-hand side is a string literal.
///
/// | Property | Typical source | Context |
/// |---|---|---|
/// | `text` | `UILabel`, `UITextView`, `UITextField` | `.uiLabel` |
/// | `placeholder` | `UITextField`, `UISearchBar` | `.uiTextFieldPlaceholder` |
/// | `title` | `navigationItem.title`, `self.title`, `tabBarItem.title` | `.uiNavigationTitle` |
/// | `prompt` | `navigationItem.prompt` | `.uiNavigationTitle` |
/// | `backButtonTitle` | `navigationItem.backButtonTitle` | `.uiNavigationTitle` |
public struct UIKitPropertyAssignmentRule: PropertyAssignmentRule {
    public let name = "UIKitPropertyAssignmentRule"
    public let baseConfidence = 0.88

    public init() {}

    private let mapping: [String: DetectionContext] = [
        "text":             .uiLabel,
        "placeholder":      .uiTextFieldPlaceholder,
        "title":            .uiNavigationTitle,
        "prompt":           .uiNavigationTitle,
        "backButtonTitle":  .uiNavigationTitle,
    ]

    public func match(propertyName: String) -> DetectionContext? {
        mapping[propertyName]
    }
}
