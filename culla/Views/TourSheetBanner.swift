import SwiftUI

/// In-sheet guidance banner shown inside GalleriesView during the setupGallery step.
struct TourSheetBanner: View {
    let step: TourStep
    let galleriesCount: Int
    let activeCount: Int

    @Environment(\.appAccent) private var accent
    @Environment(\.tourAdvance) private var tourAdvance

    private var isDone: Bool { galleriesCount > 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : step.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isDone ? .green : accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDone ? "Done!" : step.title)
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
        "Tap + to create a new gallery, or use the menu to import an existing iPhone album."
    }
}

/// Compact hint shown inside GalleryDetailView when the tour is on the changeColor step.
/// Renders as a full-width flat strip so its leading edge aligns with the photo grid below
/// and its arrow lines up with the color circle in the header above.
struct TourColorHint: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.tourAdvance) private var tourAdvance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text("Tap the color circle above to give this gallery a neon color (optional).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            HStack {
                Spacer()
                Button { tourAdvance?() } label: {
                    HStack(spacing: 4) {
                        Text("Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accent, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(accent.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.18))
                .frame(height: 1)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
    }
}
