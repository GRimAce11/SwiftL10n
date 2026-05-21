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
            Text("Swift Source")
                .font(.headline)
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
            } else if viewModel.results.isEmpty && !viewModel.sourceCode.isEmpty {
                ContentUnavailableView(
                    "No localizable strings detected",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try lowering the confidence threshold or paste a SwiftUI view.")
                )
            } else {
                resultsList
            }
        }
        .navigationTitle(viewModel.results.isEmpty ? "Results" : "\(viewModel.results.count) detected")
        .navigationSubtitle(viewModel.warningCount > 0 ? "\(viewModel.warningCount) warning(s)" : "")
    }

    private var resultsList: some View {
        List(viewModel.results, id: \.self, selection: $viewModel.selectedString) { string in
            StringRowView(string: string)
                .tag(string)
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
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
