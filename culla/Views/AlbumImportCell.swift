import SwiftUI

/// One album in the Import Albums grid: cover, name and photo count.
/// While an import runs, it also shows where that album is in the queue.
struct AlbumImportCell: View {
    /// Where this album stands in a running import.
    enum ImportState: Equatable {
        /// No import running.
        case idle
        /// Not picked for this import.
        case skipped
        /// Picked, waiting for its turn.
        case waiting
        /// Being imported. `color` is the color its new gallery will get.
        case importing(fraction: Double, color: Color)
        /// Saved as a gallery.
        case imported(color: Color)
    }

    let album: PhoneAlbum
    let isSelected: Bool
    var importState: ImportState = .idle
    let onToggle: () -> Void

    @Environment(\.appAccent) private var accent

    /// How much albums outside the current step fade while importing.
    /// Tuned in the design workshop (variant B, `gridDimming: 0.35`).
    private static let dimming = 0.35

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        AlbumThumbnailView(albumIdentifier: album.collectionIdentifier)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? accent : Color.white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        badge
                    }
                    .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: 12, y: 5)
                    .scaleEffect(isSelected ? 0.96 : 1.0)
                    .opacity(tileOpacity)
                    .saturation(tileSaturation)

                Text(album.name)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(album.photoCount) photos")
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.22), value: isSelected)
        .animation(.snappy, value: importState)
    }

    // MARK: - Badge

    @ViewBuilder
    private var badge: some View {
        switch importState {
        case .importing(let fraction, let color):
            AlbumProgressBadge(fraction: fraction, color: color)
                .padding(6)
                .transition(.scale.combined(with: .opacity))
        case .imported(let color):
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, color)
                .padding(6)
                .transition(.scale.combined(with: .opacity))
        case .idle, .waiting, .skipped:
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, accent)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Fading

    private var tileOpacity: Double {
        switch importState {
        case .skipped: 1 - Self.dimming
        case .waiting: 1 - Self.dimming * 0.6
        default: 1
        }
    }

    private var tileSaturation: Double {
        switch importState {
        case .skipped, .waiting: 1 - Self.dimming
        default: 1
        }
    }
}

// MARK: - Progress Badge

/// A small ring in the corner of the album being imported, filling as
/// its photos are added. Same size and place as the selection checkmark.
private struct AlbumProgressBadge: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.45))
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 3)
                .padding(2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

// MARK: - Thumbnail View

/// An album's cover photo, loaded from the photo library.
struct AlbumThumbnailView: View {
    let albumIdentifier: String
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGray5)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
                    .font(.title2)
            }
        }
        .task {
            thumbnail = await PhotoLibraryService.shared.fetchAlbumThumbnail(
                albumIdentifier: albumIdentifier,
                targetSize: CGSize(width: 300, height: 300)
            )
        }
    }
}
