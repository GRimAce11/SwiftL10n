import SwiftUI
import SwiftL10nCore

struct ContentView: View {
    @State private var viewModel = ScanViewModel()
    @State private var showGeneratedCode = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SourcePane(viewModel: viewModel, showGeneratedCode: $showGeneratedCode)
                .navigationSplitViewColumnWidth(min: 380, ideal: 460)
        } detail: {
            ResultsPane(viewModel: viewModel)
        }
        .sheet(isPresented: $showGeneratedCode) {
            GeneratedCodeSheet(code: viewModel.generatedCode)
        }
        .task {
            await viewModel.scan()
        }
    }
}

// MARK: - Source pane

private struct SourcePane: View {
    @Bindable var viewModel: ScanViewModel
    @Binding var showGeneratedCode: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TextEditor(text: $viewModel.sourceCode)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .padding(8)
            Divider()
            statusBar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Fixture picker
            Picker("", selection: Binding(
                get: { viewModel.selectedFixture.rawValue },
                set: { idx in
                    if let fixture = DemoFixture(rawValue: idx) {
                        viewModel.selectedFixture = fixture
                        viewModel.sourceCode = fixture.source
                        Task { await viewModel.scan() }
                    }
                }
            )) {
                ForEach(DemoFixture.allCases, id: \.rawValue) { fixture in
                    Text(fixture.label).tag(fixture.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()
            HStack(spacing: 4) {
                Text("Min confidence:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.minConfidence, in: 0...1, step: 0.05)
                    .frame(width: 80)
                Text(String(format: "%.0f%%", viewModel.minConfidence * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            Button {
                Task { await viewModel.scan() }
            } label: {
                Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isScanning)

            Button {
                showGeneratedCode = true
            } label: {
                Label("Generate", systemImage: "curlybraces")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.results.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("\(viewModel.results.count) strings", systemImage: "text.quote")
            if viewModel.interpolatedCount > 0 {
                Label("\(viewModel.interpolatedCount) interpolated", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if viewModel.recognizedCount > 0 {
                Label("\(viewModel.recognizedCount) recognized", systemImage: "checkmark.seal")
                    .foregroundStyle(.teal)
            }
            if viewModel.accessibilityWarningCount > 0 {
                Label("\(viewModel.accessibilityWarningCount) a11y", systemImage: "accessibility")
                    .foregroundStyle(.purple)
            }
            Spacer()
            if viewModel.isScanning {
                ProgressView().scaleEffect(0.6)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Results pane

private struct ResultsPane: View {
    @Bindable var viewModel: ScanViewModel

    var body: some View {
        Group {
            if viewModel.isScanning {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty && viewModel.existingDetections.isEmpty && viewModel.accessibilityDiagnostics.isEmpty && !viewModel.sourceCode.isEmpty {
                ContentUnavailableView(
                    "No localizable strings detected",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try lowering the confidence threshold or paste a SwiftUI view.")
                )
            } else {
                resultsList
            }
        }
        .navigationTitle(navigationTitle)
        .navigationSubtitle(navigationSubtitle)
    }

    private var navigationTitle: String {
        if viewModel.results.isEmpty && viewModel.recognizedCount == 0 && viewModel.accessibilityWarningCount == 0 { return "Results" }
        var parts: [String] = []
        if viewModel.results.count > 0 { parts.append("\(viewModel.results.count) gaps") }
        if viewModel.recognizedCount > 0 { parts.append("\(viewModel.recognizedCount) recognized") }
        if viewModel.accessibilityWarningCount > 0 { parts.append("\(viewModel.accessibilityWarningCount) a11y") }
        return parts.joined(separator: " · ")
    }

    private var navigationSubtitle: String {
        if viewModel.accessibilityWarningCount > 0 { return "\(viewModel.accessibilityWarningCount) accessibility warning(s)" }
        if viewModel.warningCount > 0 { return "\(viewModel.warningCount) warning(s)" }
        if viewModel.recognizedCount > 0 { return "L10n. · i18n. patterns recognized" }
        return ""
    }

    private var resultsList: some View {
        List {
            // Gaps — strings that need localization
            if !viewModel.results.isEmpty {
                Section {
                    ForEach(viewModel.results, id: \.self) { string in
                        StringRowView(string: string)
                    }
                } header: {
                    Label("Needs localization", systemImage: "exclamationmark.bubble")
                        .foregroundStyle(.primary)
                }
            }

            // Recognized — existing localization call sites
            if !viewModel.existingDetections.isEmpty {
                Section {
                    ForEach(viewModel.existingDetections.indices, id: \.self) { idx in
                        RecognizedRowView(detection: viewModel.existingDetections[idx])
                    }
                } header: {
                    Label("Recognized (existing localization)", systemImage: "checkmark.seal")
                        .foregroundStyle(.teal)
                }
            }

            // Accessibility warnings
            if !viewModel.accessibilityDiagnostics.isEmpty {
                Section {
                    ForEach(viewModel.accessibilityDiagnostics.indices, id: \.self) { idx in
                        AccessibilityWarningRowView(diagnostic: viewModel.accessibilityDiagnostics[idx])
                    }
                } header: {
                    Label("Accessibility warnings", systemImage: "accessibility")
                        .foregroundStyle(.purple)
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
    }
}

// MARK: - Recognized row

private struct RecognizedRowView: View {
    let detection: ExistingLocalizationDetector.Detection

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.teal)
                    .frame(width: 4, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(detection.fullExpression)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    KindBadge(kind: detection.kind)
                }
                HStack(spacing: 6) {
                    PatternBadge(pattern: detection.matchedPattern)
                    Spacer()
                    Text("line \(detection.location.line)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct KindBadge: View {
    let kind: ExistingLocalizationDetector.Detection.Kind

    var body: some View {
        Text(kind == .callExpression ? "call" : "property")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.teal)
    }
}

private struct PatternBadge: View {
    let pattern: String

    var body: some View {
        Text("\(pattern).")
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(Color.teal.opacity(0.8))
    }
}

// MARK: - Accessibility warning row

private struct AccessibilityWarningRowView: View {
    let diagnostic: Diagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.purple)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(diagnostic.message)
                    .font(.body)
                    .lineLimit(2)
                if let line = diagnostic.location?.line {
                    Text("line \(line)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Generated code sheet

struct GeneratedCodeSheet: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Generated Swift")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .buttonStyle(.bordered)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding()
            Divider()
            ScrollView {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 500)
    }
}
