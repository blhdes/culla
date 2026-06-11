import SwiftUI

/// Small "0:42"-style label overlaid on video thumbnails.
struct VideoDurationBadge: View {
    let duration: TimeInterval

    var body: some View {
        Text(Self.format(duration))
            .font(.caption2.monospacedDigit())
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(4)
    }

    /// Formats seconds as "0:42", "12:05", or "1:02:33".
    static func format(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
