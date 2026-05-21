import XCTest
@testable import SwiftL10nCore

final class ScannerTests: XCTestCase {

    private let scanner = StringScanner()

    // MARK: - Text

    func testDetectsTextViewString() {
        let source = """
        import SwiftUI
        struct MyView: View {
            var body: some View {
                Text("Hello, World!")
            }
        }
        """
        let result = scanner.scan(source: source, filePath: "MyView.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        let s = result.detectedStrings[0]
        XCTAssertEqual(s.value, "Hello, World!")
        XCTAssertEqual(s.context, .textView)
        XCTAssertGreaterThan(s.confidence, 0.0)
        XCTAssertLessThanOrEqual(s.confidence, 1.0)
    }

    // MARK: - Button

    func testDetectsButtonLabel() {
        let source = #"Button("Delete Account") { viewModel.delete() }"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        let s = result.detectedStrings[0]
        XCTAssertEqual(s.value, "Delete Account")
        XCTAssertEqual(s.context, .buttonLabel)
    }

    // MARK: - Label

    func testDetectsLabelTitle() {
        let source = #"Label("Settings", systemImage: "gear")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].context, .labelView)
        // systemImage arg must NOT be detected
        XCTAssertFalse(result.detectedStrings.map(\.value).contains("gear"))
    }

    // MARK: - Navigation Title

    func testDetectsNavigationTitle() {
        let source = #".navigationTitle("Settings")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].context, .navigationTitle)
    }

    func testDetectsDeprecatedNavigationBarTitle() {
        let source = #".navigationBarTitle("Profile")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].context, .navigationTitle)
    }

    // MARK: - Alert

    func testDetectsAlertTitle() {
        let source = #".alert("Are you sure?", isPresented: $shown) {}"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].value, "Are you sure?")
        XCTAssertEqual(result.detectedStrings[0].context, .alert)
    }

    // MARK: - Confirmation Dialog

    func testDetectsConfirmationDialogTitle() {
        let source = #".confirmationDialog("Choose action", isPresented: $shown) {}"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].value, "Choose action")
        XCTAssertEqual(result.detectedStrings[0].context, .confirmationDialog)
    }

    // MARK: - TextField

    func testDetectsTextFieldPlaceholder() {
        let source = #"TextField("Email address", text: $email)"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].value, "Email address")
        XCTAssertEqual(result.detectedStrings[0].context, .textField)
    }

    // MARK: - Accessibility Label

    func testDetectsAccessibilityLabel() {
        let source = #"Image("logo").accessibilityLabel("App logo")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].value, "App logo")
        XCTAssertEqual(result.detectedStrings[0].context, .accessibilityLabel)
    }

    // MARK: - Text(verbatim:)

    func testIgnoresTextVerbatim() {
        let source = #"Text(verbatim: "raw content that must not be localised")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 0)
    }

    // MARK: - Interpolation

    func testInterpolatedStringIsDetectedWithFlag() {
        let source = #"Text("Hello, \(name)!")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertTrue(result.detectedStrings[0].hasInterpolation)
    }

    func testInterpolatedStringValueHasMarker() {
        let source = #"Text("Hello, \(name)!")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertTrue(result.detectedStrings[0].value.contains("{…}"))
    }

    func testInterpolatedStringEmitsWarningDiagnostic() {
        let source = #"Text("Hello, \(name)!")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        let warnings = result.diagnostics.filter { $0.severity == .warning }
        XCTAssertFalse(warnings.isEmpty)
    }

    // MARK: - Exclusions

    func testIgnoresNonUIStringLiterals() {
        let source = """
        let url = URL(string: "https://example.com")
        let key = UserDefaults.standard.string(forKey: "authToken")
        """
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 0)
    }

    func testIgnoresURLInTextCall() {
        let source = #"Text("https://example.com")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 0)
    }

    func testIgnoresSFSymbolName() {
        let source = #"Label("Profile", systemImage: "person.circle")"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        let values = result.detectedStrings.map(\.value)
        XCTAssertFalse(values.contains("person.circle"))
    }

    func testIgnoresSnakeCaseKey() {
        let source = #"Button("submit_button_title") {}"#
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 0)
    }

    // MARK: - Multiple Strings

    func testDetectsMultipleStringsInFile() {
        let source = """
        VStack {
            Text("Title")
            Text("Subtitle")
            Button("Confirm") {}
        }
        .navigationTitle("My Screen")
        """
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 4)
    }

    // MARK: - Location

    func testSourceLocationIsRecorded() {
        let source = """

        Text("Hello")
        """
        let result = scanner.scan(source: source, filePath: "Foo.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        let loc = result.detectedStrings[0].location
        XCTAssertEqual(loc.file, "Foo.swift")
        XCTAssertEqual(loc.line, 2)
    }

    // MARK: - Enclosing Context

    func testEnclosingContextCapturesTypeName() {
        let source = """
        struct DashboardView: View {
            var body: some View { Text("Welcome") }
        }
        """
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings.count, 1)
        XCTAssertEqual(result.detectedStrings[0].enclosingContext.typeName, "DashboardView")
    }

    func testEnclosingContextCapturesPropertyName() {
        let source = """
        struct MyView: View {
            var body: some View { Text("Title") }
        }
        """
        let result = scanner.scan(source: source, filePath: "Test.swift")
        XCTAssertEqual(result.detectedStrings[0].enclosingContext.propertyName, "body")
    }

    // MARK: - Edge Cases

    func testEmptySourceProducesNoResults() {
        let result = scanner.scan(source: "", filePath: "Empty.swift")
        XCTAssertTrue(result.detectedStrings.isEmpty)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }
}
