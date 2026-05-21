/// Realistic SwiftUI source fixtures used across multiple test files.
enum TestFixtures {

    // MARK: - Realistic view

    /// A representative Settings screen — mix of Text, Button, Label, navigationTitle.
    static let settingsView = """
    import SwiftUI

    struct SettingsView: View {
        @State private var notificationsEnabled = true
        @Binding var isPresented: Bool

        var body: some View {
            Form {
                Section("Account") {
                    Label("Profile", systemImage: "person.circle")
                    Label("Security", systemImage: "lock.shield")
                    Button("Delete Account") {
                        deleteAccount()
                    }
                }
                Section("Preferences") {
                    Toggle("Push Notifications", isOn: $notificationsEnabled)
                    Button("Reset Preferences") {
                        resetPreferences()
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Are you sure?", isPresented: $isPresented) {
                Button("Delete", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) { }
            }
        }

        private func deleteAccount() {}
        private func resetPreferences() {}
    }
    """

    // MARK: - False-positive noise

    /// A file that should produce ZERO detections — all strings are non-UI.
    static let falsePositiveNoise = """
    import Foundation

    class AnalyticsManager {
        func track() {
            // These must all be excluded
            let url = URL(string: "https://api.example.com/v2/events")
            let symbol = NSAttributedString(string: "arrow.right.circle.fill")
            let key = UserDefaults.standard.string(forKey: "auth_token")
            let path = "/Users/developer/Desktop/project"
            let homePath = "~/Library/Preferences"
            let analyticsKey = "com.example.app.session_start"
            let reverseDNS  = "org.swift.package"
            let snakeCase   = "profile_picture_url"
            let camelCase   = "viewModelIdentifier"
            let scream      = "SOME_FEATURE_FLAG"
            let sfSymbol    = "person.crop.circle.badge.checkmark"
            let empty       = ""
        }
    }
    """

    // MARK: - Interpolation fixture

    /// A view containing plain strings AND interpolated strings.
    static let interpolationMix = """
    import SwiftUI

    struct WelcomeView: View {
        let name: String
        let count: Int

        var body: some View {
            VStack {
                Text("Welcome Back")
                Text("Hello \\(name)!")
                Text("You have \\(count) messages waiting")
                Button("Continue") {}
                .navigationTitle("Welcome")
            }
        }
    }
    """

    // MARK: - All supported call sites

    /// Exercises every detection rule in one file.
    static let allCallSites = """
    import SwiftUI

    struct AllCallSitesView: View {
        @State var showAlert = false
        @State var showDialog = false
        @State var searchText = ""

        var body: some View {
            VStack {
                Text("Title Text")
                Button("Tap Me") {}
                Label("Settings", systemImage: "gear")
                TextField("Search…", text: $searchText)
                Text("Subtitle")
                    .accessibilityLabel("Subtitle accessible description")
            }
            .navigationTitle("All Calls")
            .alert("Alert Title", isPresented: $showAlert) {
                Button("OK") {}
            }
            .confirmationDialog("Choose an option", isPresented: $showDialog) {
                Button("Option A") {}
            }
        }
    }
    """

    // MARK: - Text(verbatim:) opt-out

    static let verbatimOptOut = """
    import SwiftUI

    struct VerbatimView: View {
        var body: some View {
            VStack {
                Text(verbatim: "raw content that should NOT be localised")
                Text("But this one SHOULD be localised")
            }
        }
    }
    """
}
