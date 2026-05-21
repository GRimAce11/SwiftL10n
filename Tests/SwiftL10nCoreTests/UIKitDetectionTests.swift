import XCTest
@testable import SwiftL10nCore

final class UIKitDetectionTests: XCTestCase {

    private let scanner = StringScanner(ruleEngine: .full)

    // MARK: - UILabel / UITextView

    func testDetectsLabelTextAssignment() {
        let result = scan(#"label.text = "Welcome Back""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Welcome Back")
        XCTAssertEqual(result[0].context, .uiLabel)
    }

    func testDetectsTextViewTextAssignment() {
        let result = scan(#"textView.text = "Terms and Conditions""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].context, .uiLabel)
    }

    // MARK: - UITextField / UISearchBar

    func testDetectsTextFieldPlaceholderAssignment() {
        let result = scan(#"textField.placeholder = "Email address""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Email address")
        XCTAssertEqual(result[0].context, .uiTextFieldPlaceholder)
    }

    func testDetectsSearchBarPlaceholderAssignment() {
        let result = scan(#"searchBar.placeholder = "Search products""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].context, .uiTextFieldPlaceholder)
    }

    // MARK: - UINavigationItem / UIViewController title

    func testDetectsNavigationItemTitleAssignment() {
        let result = scan(#"navigationItem.title = "Settings""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Settings")
        XCTAssertEqual(result[0].context, .uiNavigationTitle)
    }

    func testDetectsSelfTitleAssignment() {
        let result = scan(#"self.title = "Profile""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].context, .uiNavigationTitle)
    }

    func testDetectsBareTitleAssignment() {
        let result = scan(#"title = "Dashboard""#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].context, .uiNavigationTitle)
    }

    // MARK: - UIButton.setTitle

    func testDetectsButtonSetTitle() {
        let result = scan(#"button.setTitle("Tap Me", for: .normal)"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Tap Me")
        XCTAssertEqual(result[0].context, .uiButtonTitle)
    }

    // MARK: - UIAlertController

    func testDetectsAlertControllerTitle() {
        let result = scan(#"UIAlertController(title: "Delete?", message: "This cannot be undone", preferredStyle: .alert)"#)
        let values = result.map(\.value)
        XCTAssertTrue(values.contains("Delete?"))
        XCTAssertTrue(values.contains("This cannot be undone"))
    }

    func testAlertControllerTitleContext() {
        let result = scan(#"UIAlertController(title: "Delete?", message: "Are you sure?", preferredStyle: .alert)"#)
        let title = result.first(where: { $0.context == .uiAlertTitle })
        let message = result.first(where: { $0.context == .uiAlertMessage })
        XCTAssertNotNil(title)
        XCTAssertNotNil(message)
        XCTAssertEqual(title?.value, "Delete?")
        XCTAssertEqual(message?.value, "Are you sure?")
    }

    func testAlertControllerDetectsBothStrings() {
        let result = scan(#"UIAlertController(title: "Title", message: "Message", preferredStyle: .alert)"#)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - UIAlertAction

    func testDetectsAlertActionTitle() {
        let result = scan(#"UIAlertAction(title: "Delete", style: .destructive)"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Delete")
        XCTAssertEqual(result[0].context, .uiAlertAction)
    }

    // MARK: - UIBarButtonItem

    func testDetectsBarButtonItemTitle() {
        let result = scan(#"UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(doneTapped))"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Done")
        XCTAssertEqual(result[0].context, .uiButtonTitle)
    }

    // MARK: - UITabBarItem

    func testDetectsTabBarItemTitle() {
        let result = scan(#"UITabBarItem(title: "Home", image: UIImage(named: "home"), tag: 0)"#)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "Home")
        XCTAssertEqual(result[0].context, .uiTabBarItem)
    }

    // MARK: - RuleEngine presets

    func testDefaultEngineDoesNotDetectUIKitPatterns() {
        let swiftuiScanner = StringScanner(ruleEngine: .default)
        let result = swiftuiScanner.scan(
            source: #"label.text = "Hello""#,
            filePath: "t.swift"
        )
        XCTAssertEqual(result.detectedStrings.count, 0,
            "Default (SwiftUI-only) engine must not detect UIKit property assignments")
    }

    func testUIKitEngineDoesNotDetectSwiftUIPatterns() {
        let uikitScanner = StringScanner(ruleEngine: .uikit)
        let result = uikitScanner.scan(
            source: #"Text("Hello World")"#,
            filePath: "t.swift"
        )
        XCTAssertEqual(result.detectedStrings.count, 0,
            "UIKit-only engine must not detect SwiftUI Text()")
    }

    func testFullEngineDetectsBothFrameworks() {
        let source = """
        Text("SwiftUI Label")
        label.text = "UIKit Label"
        """
        let result = StringScanner(ruleEngine: .full).scan(source: source, filePath: "t.swift")
        let contexts = Set(result.detectedStrings.map(\.context))
        XCTAssertTrue(contexts.contains(.textView))
        XCTAssertTrue(contexts.contains(.uiLabel))
    }

    // MARK: - Full UIKit view

    func testDetectsStringsInRealisticUIKitViewController() {
        let source = """
        class ProfileViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
                title = "Profile"
                nameLabel.text = "Full Name"
                emailLabel.text = "Email"
                editButton.setTitle("Edit Profile", for: .normal)
                emailField.placeholder = "Enter your email"
            }

            func deleteAccount() {
                let alert = UIAlertController(
                    title: "Delete Account",
                    message: "This action cannot be undone.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            }
        }
        """
        let result = StringScanner(ruleEngine: .full).scan(source: source, filePath: "ProfileViewController.swift")
        let values = result.detectedStrings.map(\.value)

        XCTAssertTrue(values.contains("Profile"))
        XCTAssertTrue(values.contains("Full Name"))
        XCTAssertTrue(values.contains("Edit Profile"))
        XCTAssertTrue(values.contains("Enter your email"))
        XCTAssertTrue(values.contains("Delete Account"))
        XCTAssertTrue(values.contains("This action cannot be undone."))
        XCTAssertTrue(values.contains("Delete"))
        XCTAssertTrue(values.contains("Cancel"))
    }

    // MARK: - Helper

    private func scan(_ source: String) -> [DetectedString] {
        scanner.scan(source: source, filePath: "t.swift").detectedStrings
    }
}
