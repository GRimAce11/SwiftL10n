import XCTest
import SwiftSyntax
import SwiftParser
@testable import SwiftL10nCore

final class ContextExtractorTests: XCTestCase {

    func testExtractsStructName() {
        let context = extractFirst(from: """
        struct SettingsView: View {
            var body: some View { Text("Hello") }
        }
        """)
        XCTAssertEqual(context?.typeName, "SettingsView")
    }

    func testExtractsClassName() {
        let context = extractFirst(from: """
        class OnboardingController {
            func makeView() -> some View { Text("Welcome") }
        }
        """)
        XCTAssertEqual(context?.typeName, "OnboardingController")
    }

    func testExtractsExtensionName() {
        let context = extractFirst(from: """
        extension ProfileView {
            var header: some View { Text("Profile") }
        }
        """)
        XCTAssertEqual(context?.typeName, "ProfileView")
    }

    func testExtractsPropertyName() {
        let context = extractFirst(from: """
        struct MyView: View {
            var body: some View { Text("Title") }
        }
        """)
        XCTAssertEqual(context?.propertyName, "body")
    }

    func testExtractsFunctionName() {
        let context = extractFirst(from: """
        struct MyView: View {
            func makeButton() -> some View { Button("Delete") {} }
        }
        """)
        XCTAssertEqual(context?.functionName, "makeButton")
    }

    func testNestingFindsNearestType() {
        let context = extractFirst(from: """
        struct Outer {
            struct Inner: View {
                var body: some View { Text("Nested") }
            }
        }
        """)
        // Should find the NEAREST (Inner), not Outer
        XCTAssertEqual(context?.typeName, "Inner")
    }

    func testTopLevelHasNoTypeContext() {
        let context = extractFirst(from: #"let _ = Text("Global")"#)
        XCTAssertNil(context?.typeName)
        XCTAssertNil(context?.functionName)
    }

    // MARK: - Helpers

    private func extractFirst(from source: String) -> EnclosingContext? {
        let result = StringScanner().scan(source: source, filePath: "t.swift")
        return result.detectedStrings.first?.enclosingContext
    }
}
