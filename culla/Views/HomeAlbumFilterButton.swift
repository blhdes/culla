import SwiftUI

/// The home "filter by album" row. Tapping it opens the album picker; the
/// clear button inside it goes back to all photos.
struct HomeAlbumFilterButton: View {
    let selectedAlbum: PhoneAlbum?
    let onTap: () -> Void
    let onClear: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack {
                if selectedAlbum?.isClutter == true {
                    Image(systemName: "sparkles")
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "rectangle.stack")
                }
                if let selectedAlbum {
                    Text(selectedAlbum.name)
                    Spacer()
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("All Photos")
                    Spacer()
                    Text("Filter by album")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .modifier(GlassOrQuaternaryRounded())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct GlassOrQuaternaryRounded: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 10))
        } else {
            content.background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
