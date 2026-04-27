import SwiftUI

/// In-sheet guidance banner shown inside GalleriesView when the tour is active.
struct TourSheetBanner: View {
    let step: TourStep
    let galleriesCount: Int
    let activeCount: Int

    @Environment(\.appAccent) private var accent
    @Environment(\.tourAdvance) private var tourAdvance

    private var isDone: Bool {
        switch step {
        case .setupGallery:    return galleriesCount > 0
        case .activateGallery: return activeCount > 0
        default:               return false
        }
    }

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
        switch step {
        case .setupGallery:
            return "Tap + to create a new gallery, or use the menu to import an existing iPhone album."
        case .activateGallery:
            return "Tap the colored circle next to any gallery to make it active for your swipe session."
        default:
            return ""
        }
    }
}

/// Compact hint shown inside GalleryDetailView when the tour is on the changeColor step.
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
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
