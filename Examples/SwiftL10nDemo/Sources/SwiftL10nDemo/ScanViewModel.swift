import SwiftUI
import SwiftL10nCore

@MainActor
@Observable
final class ScanViewModel {

    var sourceCode: String = DemoFixture.swiftUI.source
    var selectedFixture: DemoFixture = .swiftUI
    var results: [DetectedString] = []
    var existingDetections: [ExistingLocalizationDetector.Detection] = []
    var diagnostics: [Diagnostic] = []
    var isScanning = false
    var selectedString: DetectedString?
    var minConfidence: Double = 0.0

    // MARK: - Actions

    func scan() async {
        isScanning = true
        results = []
        existingDetections = []
        diagnostics = []

        let source = sourceCode
        let threshold = minConfidence
        let fixture = selectedFixture
        let scanner = StringScanner()
        let detector = ExistingLocalizationDetector(
            config: .init(patterns: fixture == .partial ? ["L10n.", "i18n."] : [])
        )

        let (scanResult, detectorResult) = await Task.detached(priority: .userInitiated) {
            let sr = scanner.scan(source: source, filePath: "Demo.swift")
            let dr = detector.detect(source: source, filePath: "Demo.swift")
            return (sr, dr)
        }.value

        results = scanResult.detectedStrings
            .filter { $0.confidence >= threshold }
            .sorted { $0.confidence > $1.confidence }
        existingDetections = detectorResult.detections
        diagnostics = scanResult.diagnostics
        isScanning = false
    }

    // MARK: - Derived

    var interpolatedCount: Int { results.filter(\.hasInterpolation).count }
    var warningCount: Int { diagnostics.filter { $0.severity == .warning }.count }
    var recognizedCount: Int { existingDetections.count }

    var namespaces: [SwiftL10nCore.Namespace] {
        NamespaceInferrer().infer(from: [("Demo.swift", results)])
    }

    var generatedCode: String {
        CodeGenerator().generate(namespaces: namespaces)
    }
}

// MARK: - Demo fixture

enum DemoFixture: Int, CaseIterable {
    case swiftUI = 0
    case uiKit   = 1
    case partial = 2

    var label: String {
        switch self {
        case .swiftUI: "SwiftUI"
        case .uiKit:   "UIKit"
        case .partial: "Partial"
        }
    }

    var source: String {
        switch self {
        case .swiftUI: Self.swiftUISource
        case .uiKit:   Self.uiKitSource
        case .partial: Self.partialSource
        }
    }

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

    /// A partially-localized file: some strings already use SwiftGen (L10n.),
    /// others are still hardcoded. Demonstrates ExistingLocalizationDetector —
    /// recognized sites appear in a separate "Recognized" section; hardcoded
    /// strings are the remaining gaps needing localization.
    static let partialSource = """
    import SwiftUI

    // Partially migrated to SwiftGen (L10n.).
    // Recognized call sites are shown in the "Recognized" panel.
    // Hardcoded strings below are the remaining gaps.

    struct ProfileView: View {
        @State private var name = ""

        var body: some View {
            Form {
                Section(L10n.Profile.sectionTitle) {
                    TextField("Full name", text: $name)
                    Text(L10n.Profile.emailLabel)
                    Button("Edit Photo") {}
                }
                Section("Preferences") {
                    Toggle("Dark Mode", isOn: .constant(true))
                    Button("Reset all settings") {}
                }
            }
            .navigationTitle(L10n.Profile.navTitle)
            .alert("Delete your profile?", isPresented: .constant(false)) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button("Delete permanently", role: .destructive) {}
            }
        }
    }

    struct NotificationsView: View {
        var body: some View {
            List {
                Toggle(L10n.Notifications.pushToggle, isOn: .constant(true))
                Toggle("Email alerts", isOn: .constant(false))
                Toggle("Badge count", isOn: .constant(true))
            }
            .navigationTitle(L10n.Notifications.navTitle)
        }
    }
    """
}
