import SwiftUI

/// In-sheet guidance banner shown inside GalleriesView during the tour's galleries stop.
struct TourSheetBanner: View {
    let step: TourStep
    let galleriesCount: Int

    @Environment(\.appAccent) private var accent
    @Environment(\.tourAdvance) private var tourAdvance

    private var isDone: Bool { galleriesCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : step.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isDone ? .green : accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDone ? String(localized: "Done!") : step.title)
                    .font(.subheadline.weight(.semibold))
                if !isDone {
                    Text(guidanceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if isDone {
                Button { tourAdvance?() } label: {
                    HStack(spacing: 4) {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            (isDone ? Color.green : accent).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((isDone ? Color.green : accent).opacity(0.18), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: isDone)
    }

    private var guidanceText: String {
        String(localized: "Tap + to create a gallery or import an iPhone album.")
    }
}
