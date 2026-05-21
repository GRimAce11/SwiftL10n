import SwiftUI
import SwiftL10nCore

@MainActor
@Observable
final class ScanViewModel {

    var sourceCode: String = defaultSource
    var results: [DetectedString] = []
    var diagnostics: [Diagnostic] = []
    var isScanning = false
    var selectedString: DetectedString?
    var minConfidence: Double = 0.0

    // MARK: - Actions

    func scan() async {
        isScanning = true
        results = []
        diagnostics = []

        let source = sourceCode
        let threshold = minConfidence
        let scanner = StringScanner()

        let result = await Task.detached(priority: .userInitiated) {
            scanner.scan(source: source, filePath: "Demo.swift")
        }.value

        results = result.detectedStrings
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
        diagnostics = result.diagnostics
        isScanning = false
    }

    // MARK: - Derived

    var interpolatedCount: Int { results.filter(\.hasInterpolation).count }
    var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }

    var namespaces: [SwiftL10nCore.Namespace] {
        NamespaceInferrer().infer(from: [("Demo.swift", results)])
    }

    var generatedCode: String {
        CodeGenerator().generate(namespaces: namespaces)
    }

    // MARK: - Fixtures

    static let swiftUISource = """
    import SwiftUI

    struct SettingsView: View {
        @State private var notificationsEnabled = true
        @State private var showDeleteAlert = false
        @State private var email = ""

        var body: some View {
            Form {
                Section("Account") {
                    Label("Profile", systemImage: "person.circle")
                    Label("Security", systemImage: "lock.shield")
                    TextField("Email address", text: $email)
                    Button("Delete Account") { showDeleteAlert = true }
                }
                Section("Preferences") {
                    Toggle("Push Notifications", isOn: $notificationsEnabled)
                    Button("Reset Preferences") {}
                }
            }
            .navigationTitle("Settings")
            .alert("Delete your account?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    struct OnboardingView: View {
        let name: String
        var body: some View {
            VStack(spacing: 24) {
                Text("Welcome to the App")
                Text("Hello \\(name), let's get started.")
                Button("Continue") {}
                Button("Skip for now") {}
            }
            .navigationTitle("Get Started")
        }
    }
    """

    static let uiKitSource = """
    import UIKit

    class ProfileViewController: UIViewController {
        @IBOutlet weak var nameLabel: UILabel!
        @IBOutlet weak var emailField: UITextField!
        @IBOutlet weak var editButton: UIButton!

        override func viewDidLoad() {
            super.viewDidLoad()
            title = "Profile"
            nameLabel.text = "Full Name"
            emailField.placeholder = "Enter your email"
            editButton.setTitle("Edit Profile", for: .normal)
        }

        func confirmDelete() {
            let alert = UIAlertController(
                title: "Delete Account",
                message: "This action cannot be undone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        }
    }

    class HomeViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            navigationItem.title = "Home"
        }
    }
    """

    static let defaultSource = swiftUISource
}
