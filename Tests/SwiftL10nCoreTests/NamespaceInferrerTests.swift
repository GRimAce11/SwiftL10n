import XCTest
@testable import SwiftL10nCore

final class NamespaceInferrerTests: XCTestCase {

    private let inferrer = NamespaceInferrer()

    // MARK: - Name Derivation

    func testStripsViewSuffix() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/SettingsView.swift"), "Settings")
    }

    func testStripsScreenSuffix() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/HomeScreen.swift"), "Home")
    }

    func testStripsPageSuffix() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/ProfilePage.swift"), "Profile")
    }

    func testStripsViewControllerSuffix() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/LoginViewController.swift"), "Login")
    }

    func testStripsControllerSuffix() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/AuthController.swift"), "Auth")
    }

    func testViewControllerTakesPriorityOverController() {
        // "ViewController" should be stripped as a unit, not "Controller" leaving "View" behind.
        XCTAssertEqual(inferrer.namespaceName(for: "/App/RootViewController.swift"), "Root")
    }

    func testPreservesPlainFileName() {
        XCTAssertEqual(inferrer.namespaceName(for: "/App/Utilities.swift"), "Utilities")
    }

    func testDoesNotStripSuffixIfItIsTheWholeName() {
        // A file literally named "View.swift" should not become an empty string.
        XCTAssertEqual(inferrer.namespaceName(for: "/App/View.swift"), "View")
    }

    // MARK: - Namespace Building

    func testGroupsDetectedStringsUnderNamespace() {
        let strings = [
            DetectedString(
                value: "Title",
                location: SourceLocation(file: "/App/SettingsView.swift", line: 10, column: 9),
                context: .textView
            )
        ]
        let results = [("/App/SettingsView.swift", strings)]
        let namespaces = inferrer.infer(from: results)

        XCTAssertEqual(namespaces.count, 1)
        XCTAssertEqual(namespaces[0].name, "Settings")
        XCTAssertEqual(namespaces[0].strings.count, 1)
        XCTAssertEqual(namespaces[0].sourceFile, "/App/SettingsView.swift")
    }

    func testSkipsFilesWithNoDetectedStrings() {
        let results: [(filePath: String, strings: [DetectedString])] = [
            ("/App/EmptyView.swift", [])
        ]
        XCTAssertTrue(inferrer.infer(from: results).isEmpty)
    }

    func testHandlesMultipleFiles() {
        let makeString: (String, String, DetectionContext) -> DetectedString = { value, file, ctx in
            DetectedString(value: value, location: SourceLocation(file: file, line: 1, column: 1), context: ctx)
        }
        let results = [
            ("/App/SettingsView.swift", [makeString("Title", "/App/SettingsView.swift", .textView)]),
            ("/App/ProfileView.swift",  [makeString("Name", "/App/ProfileView.swift",   .textView)]),
        ]
        let namespaces = inferrer.infer(from: results).sorted { $0.name < $1.name }
        XCTAssertEqual(namespaces.map(\.name), ["Profile", "Settings"])
    }
}
