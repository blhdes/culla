import SwiftUI

/// The card shown when a focus session's timer runs out.
struct SessionSummaryView: View {
    let durationSeconds: Int
    let reviewedCount: Int
    let sortedCount: Int
    let dismissedCount: Int
    let galleriesCount: Int
    let onKeepGoing: () -> Void
    let onDone: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { }

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.primary)

                Text("Session Complete")
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(spacing: 12) {
                    summaryRow("Time", value: formatDuration(durationSeconds))
                    summaryRow("Reviewed", value: "\(reviewedCount)")
                    summaryRow("Sorted", value: "\(sortedCount)")
                    // Own key: the "Dismissed" toast is singular in some languages, this count is plural.
                    summaryRow(
                        LocalizedStringResource("summary.dismissed", defaultValue: "Dismissed"),
                        value: "\(dismissedCount)"
                    )
                    summaryRow("Galleries", value: "\(galleriesCount)")
                }

                VStack(spacing: 12) {
                    Button("Keep Going", action: onKeepGoing)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .tint(accent)

                    Button("Done", action: onDone)
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 40)
        }
    }

    private func summaryRow(_ label: LocalizedStringResource, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.body)
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        if s == 0 { return "\(m) min" }
        return "\(m)m \(s)s"
    }
}
