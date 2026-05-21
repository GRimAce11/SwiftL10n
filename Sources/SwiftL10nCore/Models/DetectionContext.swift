/// The syntactic SwiftUI call site in which a localizable string was detected.
///
/// Context drives two downstream decisions:
///   1. Whether a string is worth flagging at all (e.g. `systemImage:` args are excluded).
///   2. What suffix to append to the generated property name so it reads naturally
///      (e.g. `deleteAccountButtonTitle` for a Button label).
public enum DetectionContext: Sendable, Hashable {
    /// `Text("…")` view initializer — the most common source of UI strings.
    case textView

    /// First positional argument to `Button("…") { }`.
    case buttonLabel

    /// First positional argument to `Label("…", systemImage:)`.
    case labelView

    /// Argument to `.navigationTitle("…")` or `.navigationBarTitle("…")`.
    case navigationTitle

    /// First argument to `.alert("title", isPresented:) { }`.
    case alert

    /// First argument to `.confirmationDialog("title", isPresented:) { }`.
    case confirmationDialog

    /// First argument to `TextField("placeholder", text:)`.
    case textField

    /// Argument to `.accessibilityLabel("description")`.
    case accessibilityLabel

    /// First argument to `Toggle("label", isOn:)`.
    case toggle

    /// A call site we recognise as UI-facing but haven't given a dedicated case yet.
    /// `callee` is the bare function/method name (e.g. `"sheet"`).
    case unknownUIContext(callee: String)
}

extension DetectionContext {
    /// Short human-readable label used in CLI output and diagnostics.
    public var displayName: String {
        switch self {
        case .textView:                        return "Text"
        case .buttonLabel:                     return "Button"
        case .labelView:                       return "Label"
        case .navigationTitle:                 return "navigationTitle"
        case .alert:                           return "alert"
        case .confirmationDialog:              return "confirmationDialog"
        case .textField:                       return "TextField"
        case .accessibilityLabel:              return "accessibilityLabel"
        case .toggle:                          return "Toggle"
        case .unknownUIContext(let callee):    return callee
        }
    }

    /// Suggested suffix for the generated Swift property name.
    ///
    /// `NamePropertyBuilder` appends this to the title-cased string value so that
    /// `Button("Delete Account")` → `deleteAccountButtonTitle` without manual input.
    public var propertySuffix: String {
        switch self {
        case .textView:                        return ""
        case .buttonLabel:                     return "ButtonTitle"
        case .labelView:                       return "Label"
        case .navigationTitle:                 return "NavigationTitle"
        case .alert:                           return "AlertTitle"
        case .confirmationDialog:              return "DialogTitle"
        case .textField:                       return "Placeholder"
        case .accessibilityLabel:              return "AccessibilityLabel"
        case .toggle:                          return "ToggleLabel"
        case .unknownUIContext:                return ""
        }
    }
}
