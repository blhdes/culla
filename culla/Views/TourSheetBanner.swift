import SwiftUI

/// In-sheet guidance banner shown inside GalleriesView and GalleryDetailView
/// when the tour is active on a step that requires action there.
struct TourSheetBanner: View {
    let step: TourStep
    let galleriesCount: Int
    let activeCount: Int

    @Environment(\.appAccent) private var accent

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
                Text(isDone ? "Close this sheet to continue the tour." : guidanceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            Text("Tap the color circle above to pick a neon color. Close to skip this step.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
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
