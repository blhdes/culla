import Photos
import SwiftUI

struct PhotoGridPickerView: View {
    let albumIdentifier: String?
    let earliest: Date
    let latest: Date
    @Binding var selectedDate: Date
    /// Called after a photo is picked. The parent uses this to dismiss the
    /// calendar sheet underneath, so the wheel jumps straight to the new date.
    let onPick: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @State private var items: [GridPhoto] = []
    @State private var isLoading = true

    private let columns = Array(repeating: SwiftUI.GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pick a Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .tint(accent)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await load() }
        } else if items.isEmpty {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text("Nothing in this album for this date range.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(items) { item in
                            GridThumbnailCell(assetID: item.id)
                                .id(item.id)
                                .onTapGesture { pick(item) }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onAppear { scrollToSelected(in: proxy) }
            }
        }
    }

    private func pick(_ item: GridPhoto) {
        Haptics.dateWheelTick()
        selectedDate = item.creationDate
        onPick()
        dismiss()
    }

    private func load() async {
        let albumID = albumIdentifier
        let e = earliest
        let l = latest
        let service = PhotoLibraryService.shared

        let loaded = await Task.detached(priority: .userInitiated) {
            service.gridAssets(from: e, to: l, inAlbum: albumID)
                .map { GridPhoto(id: $0.id, creationDate: $0.creationDate) }
        }.value

        items = loaded.reversed()
        isLoading = false
    }

    private func scrollToSelected(in proxy: ScrollViewProxy) {
        // Items are oldest-first; find the last photo at or before selectedDate
        // so we land on the closest match from below.
        let target = items.last(where: { $0.creationDate <= selectedDate }) ?? items.first
        guard let target else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(target.id, anchor: .top)
        }
    }
}

private struct GridPhoto: Identifiable, Equatable {
    let id: String
    let creationDate: Date
}

private struct GridThumbnailCell: View {
    let assetID: String
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: assetID) {
                image = await PhotoLibraryService.shared.loadThumbnail(for: assetID)
            }
    }
}
