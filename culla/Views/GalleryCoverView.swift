import SwiftUI

/// A small square cover for a gallery: the newest photo in its linked
/// Photos album, or the gallery's own icon while that loads or when the
/// gallery has no album yet.
///
/// Takes plain values instead of the `Gallery` model, so the sidebar can
/// redraw on every drag tick without touching SwiftData.
struct GalleryCoverView: View {
    let albumIdentifier: String?
    let iconName: String
    let tint: Color
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 8

    @State private var thumbnail: UIImage?

    /// The icon tile sits *behind* the photo instead of being swapped for it,
    /// so the row never flashes empty while the photo decodes.
    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: iconName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: albumIdentifier) {
            guard let albumIdentifier else {
                thumbnail = nil
                return
            }
            let pixels = size * 3
            thumbnail = await PhotoLibraryService.shared.fetchAlbumThumbnail(
                albumIdentifier: albumIdentifier,
                targetSize: CGSize(width: pixels, height: pixels)
            )
        }
    }
}
