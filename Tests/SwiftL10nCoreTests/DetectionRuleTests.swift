import XCTest
import SwiftSyntax
import SwiftParser
@testable import SwiftL10nCore

final class DetectionRuleTests: XCTestCase {

    // MARK: - TextViewRule

    func testTextViewRuleMatchesText() {
        let node = parseCall(#"Text("Hello")"#)
        XCTAssertNotNil(TextViewRule().match(in: node))
        XCTAssertEqual(TextViewRule().match(in: node), .textView)
    }

    func testTextViewRuleDoesNotMatchTextField() {
        let node = parseCall(#"TextField("placeholder", text: $t)"#)
        XCTAssertNil(TextViewRule().match(in: node))
    }

    func testTextViewRuleBaseConfidence() {
        XCTAssertEqual(TextViewRule().baseConfidence, 0.98)
    }

    // MARK: - ButtonRule

    func testButtonRuleMatchesButton() {
        let node = parseCall(#"Button("Tap") {}"#)
        XCTAssertEqual(ButtonRule().match(in: node), .buttonLabel)
    }

    func testButtonRuleDoesNotMatchText() {
        let node = parseCall(#"Text("Tap")"#)
        XCTAssertNil(ButtonRule().match(in: node))
    }

    // MARK: - LabelViewRule

    func testLabelViewRuleMatchesLabel() {
        let node = parseCall(#"Label("Settings", systemImage: "gear")"#)
        XCTAssertEqual(LabelViewRule().match(in: node), .labelView)
    }

    func testLabelViewRuleDoesNotMatchText() {
        let node = parseCall(#"Text("Settings")"#)
        XCTAssertNil(LabelViewRule().match(in: node))
    }

    // MARK: - NavigationTitleRule

    func testNavigationTitleRuleMatchesNavigationTitle() {
        let node = parseCall(#".navigationTitle("Home")"#)
        XCTAssertEqual(NavigationTitleRule().match(in: node), .navigationTitle)
    }

    func testNavigationTitleRuleMatchesDeprecatedVariant() {
        let node = parseCall(#".navigationBarTitle("Home")"#)
        XCTAssertEqual(NavigationTitleRule().match(in: node), .navigationTitle)
    }

    func testNavigationTitleRuleDoesNotMatchNavigationSubtitle() {
        let node = parseCall(#".navigationSubtitle("Subtitle")"#)
        XCTAssertNil(NavigationTitleRule().match(in: node))
    }

    // MARK: - AlertRule

    func testAlertRuleMatchesAlert() {
        let node = parseCall(#".alert("Warning", isPresented: $x) {}"#)
        XCTAssertEqual(AlertRule().match(in: node), .alert)
    }

    func testAlertRuleDoesNotMatchConfirmationDialog() {
        let node = parseCall(#".confirmationDialog("Choose", isPresented: $x) {}"#)
        XCTAssertNil(AlertRule().match(in: node))
    }

    // MARK: - ConfirmationDialogRule

    func testConfirmationDialogRuleMatchesConfirmationDialog() {
        let node = parseCall(#".confirmationDialog("Choose", isPresented: $x) {}"#)
        XCTAssertEqual(ConfirmationDialogRule().match(in: node), .confirmationDialog)
    }

    // MARK: - TextFieldRule

    func testTextFieldRuleMatchesTextField() {
        let node = parseCall(#"TextField("Search", text: $q)"#)
        XCTAssertEqual(TextFieldRule().match(in: node), .textField)
    }

    func testTextFieldRuleDoesNotMatchText() {
        let node = parseCall(#"Text("Search")"#)
        XCTAssertNil(TextFieldRule().match(in: node))
    }

    // MARK: - AccessibilityLabelRule

    func testAccessibilityLabelRuleMatchesAccessibilityLabel() {
        let node = parseCall(#".accessibilityLabel("Close")"#)
        XCTAssertEqual(AccessibilityLabelRule().match(in: node), .accessibilityLabel)
    }

    func testAccessibilityLabelBaseConfidence() {
        XCTAssertEqual(AccessibilityLabelRule().baseConfidence, 0.90)
    }

    // MARK: - SectionRule

    func testSectionRuleMatchesSection() {
        let node = parseCall(#"Section("Account") {}"#)
        XCTAssertEqual(SectionRule().match(in: node), .section)
    }

    func testSectionRuleDoesNotMatchText() {
        let node = parseCall(#"Text("Account")"#)
        XCTAssertNil(SectionRule().match(in: node))
    }

    func testSectionRuleBaseConfidence() {
        XCTAssertEqual(SectionRule().baseConfidence, 0.90)
    }

    // MARK: - PickerRule

    func testPickerRuleMatchesPicker() {
        let node = parseCall(#"Picker("Sort By", selection: $s) {}"#)
        XCTAssertEqual(PickerRule().match(in: node), .picker)
    }

    func testPickerRuleDoesNotMatchText() {
        let node = parseCall(#"Text("Sort By")"#)
        XCTAssertNil(PickerRule().match(in: node))
    }

    // MARK: - MenuRule

    func testMenuRuleMatchesMenu() {
        let node = parseCall(#"Menu("Options") {}"#)
        XCTAssertEqual(MenuRule().match(in: node), .menu)
    }

    func testMenuRuleDoesNotMatchButton() {
        let node = parseCall(#"Button("Options") {}"#)
        XCTAssertNil(MenuRule().match(in: node))
    }

    // MARK: - DisclosureGroupRule

    func testDisclosureGroupRuleMatchesDisclosureGroup() {
        let node = parseCall(#"DisclosureGroup("Advanced") {}"#)
        XCTAssertEqual(DisclosureGroupRule().match(in: node), .disclosureGroup)
    }

    func testDisclosureGroupRuleDoesNotMatchSection() {
        let node = parseCall(#"Section("Advanced") {}"#)
        XCTAssertNil(DisclosureGroupRule().match(in: node))
    }

    // MARK: - HelpTextRule

    func testHelpTextRuleMatchesHelp() {
        let node = parseCall(#".help("Tap to delete")"#)
        XCTAssertEqual(HelpTextRule().match(in: node), .helpText)
    }

    func testHelpTextRuleDoesNotMatchAccessibilityLabel() {
        let node = parseCall(#".accessibilityLabel("Label")"#)
        XCTAssertNil(HelpTextRule().match(in: node))
    }

    func testHelpTextRuleBaseConfidence() {
        XCTAssertEqual(HelpTextRule().baseConfidence, 0.88)
    }

    // MARK: - ArgumentSelector

    func testFirstUnlabeledSkipsVerbatim() {
        // `Text(verbatim: "foo")` — no unlabeled argument → rule should return no string
        let result = StringScanner().scan(
            source: #"Text(verbatim: "Should be ignored")"#,
            filePath: "t.swift"
        )
        XCTAssertEqual(result.detectedStrings.count, 0)
    }

    // MARK: - RuleEngine default

    func testDefaultEngineContainsAllBuiltInRules() {
        // 14 SwiftUI + 6 UIKit function-call rules
        XCTAssertEqual(RuleEngine.default.rules.count, 20)
        // 1 UIKit property-assignment rule
        XCTAssertEqual(RuleEngine.default.assignmentRules.count, 1)
    }

    func testDefaultEngineRuleNames() {
        let names = Set(RuleEngine.default.rules.map(\.name))
        // SwiftUI — original 9
        XCTAssertTrue(names.contains("TextViewRule"))
        XCTAssertTrue(names.contains("ButtonRule"))
        XCTAssertTrue(names.contains("LabelViewRule"))
        XCTAssertTrue(names.contains("ToggleRule"))
        XCTAssertTrue(names.contains("NavigationTitleRule"))
        XCTAssertTrue(names.contains("AlertRule"))
        XCTAssertTrue(names.contains("ConfirmationDialogRule"))
        XCTAssertTrue(names.contains("TextFieldRule"))
        XCTAssertTrue(names.contains("AccessibilityLabelRule"))
        // SwiftUI — v1.1 additions
        XCTAssertTrue(names.contains("SectionRule"))
        XCTAssertTrue(names.contains("PickerRule"))
        XCTAssertTrue(names.contains("MenuRule"))
        XCTAssertTrue(names.contains("DisclosureGroupRule"))
        XCTAssertTrue(names.contains("HelpTextRule"))
        // UIKit
        XCTAssertTrue(names.contains("UIButtonSetTitleRule"))
        XCTAssertTrue(names.contains("UIAlertControllerTitleRule"))
        XCTAssertTrue(names.contains("UIAlertControllerMessageRule"))
        XCTAssertTrue(names.contains("UIAlertActionRule"))
        XCTAssertTrue(names.contains("UIBarButtonItemRule"))
        XCTAssertTrue(names.contains("UITabBarItemRule"))
    }

    // MARK: - Helpers

    private func parseCall(_ source: String) -> FunctionCallExprSyntax {
        let tree = Parser.parse(source: source)
        let collector = FunctionCallCollector()
        collector.walk(tree)
        return collector.calls.first!
    }
}

private final class FunctionCallCollector: SyntaxVisitor {
    var calls: [FunctionCallExprSyntax] = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        calls.append(node)
        return .visitChildren
    }
}
