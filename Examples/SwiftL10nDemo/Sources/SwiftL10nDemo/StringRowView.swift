import SwiftUI
import SwiftL10nCore

struct StringRowView: View {
    let string: DetectedString

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Confidence bar
            VStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(confidenceColor)
                    .frame(width: 4, height: 36)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(string.value)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if string.hasInterpolation {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .help("Contains string interpolation — review before localising")
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", string.confidence * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(confidenceColor)
                }

                HStack(spacing: 6) {
                    ContextBadge(context: string.context)

                    if let typeName = string.enclosingContext.typeName {
                        Text(typeName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("line \(string.location.line)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var confidenceColor: Color {
        switch string.confidence {
        case 0.9...: return .green
        case 0.75...: return .yellow
        default:      return .orange
        }
    }
}

// MARK: - Context badge

private struct ContextBadge: View {
    let context: DetectionContext

    var body: some View {
        Text(context.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch context {
        case .textView:          return .blue
        case .buttonLabel:       return .purple
        case .labelView:         return .indigo
        case .toggle:            return .teal
        case .textField:         return .cyan
        case .navigationTitle:   return .green
        case .alert:             return .red
        case .confirmationDialog: return .orange
        case .accessibilityLabel: return .mint
        case .unknownUIContext:  return .gray
        }
    }
}
