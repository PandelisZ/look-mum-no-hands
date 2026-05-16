import LMNHCore
import SwiftUI

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    var timestamp: String
    var status: String
    var tool: String
    var summary: String
}

struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp)
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(entry.status.uppercased())
                .frame(width: 56, alignment: .leading)
                .foregroundStyle(statusColor)
                .fontWeight(.semibold)
            Text(entry.tool)
                .frame(width: 190, alignment: .leading)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.summary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(entry.status == "error" ? .red : .primary)
                .textSelection(.enabled)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(rowBackground)
    }

    private var statusColor: Color {
        switch entry.status {
        case "error":
            .red
        case "ok":
            .green
        default:
            .secondary
        }
    }

    private var rowBackground: some ShapeStyle {
        entry.status == "error"
            ? AnyShapeStyle(Color.red.opacity(0.08))
            : AnyShapeStyle(Color.clear)
    }
}

struct PermissionRow: View {
    let title: String
    let state: PermissionState

    var body: some View {
        HStack {
            Circle()
                .fill(state == .granted ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(state.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state == .granted ? .green : .red)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
                    .font(.caption.monospacedDigit())
            }
            Slider(value: $value, in: range)
        }
    }
}
