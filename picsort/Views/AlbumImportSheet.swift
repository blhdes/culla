import SwiftUI
import SwiftData
import Photos

/// Lets the user pick from their iPhone photo albums and import them as app galleries.
/// Albums already imported (matched by albumIdentifier) are hidden.
struct AlbumImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var galleries: [Gallery]

    @State private var phoneAlbums: [PhoneAlbum] = []
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true

    // Drag-to-select state
    @State private var cellFrames: [String: CGRect] = [:]
    @State private var isDragSelecting = false
    @State private var dragSelectAdding: Bool? = nil
    @State private var lastDraggedAlbumID: String? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading albums…")
                } else if availableAlbums.isEmpty {
                    ContentUnavailableView(
                        "No Albums to Import",
                        systemImage: "photo.on.rectangle",
                        description: Text("All phone albums have already been imported.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredAlbums) { album in
                                albumCell(album)
                            }
                        }
                        .padding()
                        .coordinateSpace(.named("albumGrid"))
                        .simultaneousGesture(dragSelectGesture)
                    }
                    .scrollDisabled(isDragSelecting)
                    .searchable(text: $searchText, prompt: "Search albums")
                }
            }
            .navigationTitle("Import Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let label = selectedAlbumIDs.isEmpty ? "Import" : "Import (\(selectedAlbumIDs.count))"
                    Button(label) { importSelected() }
                        .fontWeight(.semibold)
                        .disabled(selectedAlbumIDs.isEmpty)
                }
            }
            .task {
                let service = PhotoLibraryService.shared
                let status = await service.requestAuthorization()
                guard status == .authorized || status == .limited else {
                    isLoading = false
                    return
                }
                phoneAlbums = service.fetchAlbums()
                isLoading = false
            }
        }
    }

    // MARK: - Drag-to-Select Gesture

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("albumGrid"))
            .onChanged { value in
                if dragSelectAdding == nil {
                    guard let id = albumID(at: value.startLocation) else { return }
                    isDragSelecting = true
                    dragSelectAdding = !selectedAlbumIDs.contains(id)
                    apply(dragSelectAdding!, to: id)
                    lastDraggedAlbumID = id
                }
                guard let adding = dragSelectAdding,
                      let id = albumID(at: value.location),
                      id != lastDraggedAlbumID else { return }
                lastDraggedAlbumID = id
                apply(adding, to: id)
            }
            .onEnded { _ in
                isDragSelecting = false
                dragSelectAdding = nil
                lastDraggedAlbumID = nil
            }
    }

    private func apply(_ adding: Bool, to id: String) {
        if adding { selectedAlbumIDs.insert(id) } else { selectedAlbumIDs.remove(id) }
    }

    private func albumID(at point: CGPoint) -> String? {
        cellFrames.first { $0.value.contains(point) }?.key
    }

    // MARK: - Grid Cell

    @ViewBuilder
    private func albumCell(_ album: PhoneAlbum) -> some View {
        let isSelected = selectedAlbumIDs.contains(album.id)

        Button {
            if isSelected {
                selectedAlbumIDs.remove(album.id)
            } else {
                selectedAlbumIDs.insert(album.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AlbumThumbnailView(albumIdentifier: album.collectionIdentifier)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }

                Text(album.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(album.photoCount) photos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    cellFrames[album.id] = geo.frame(in: .named("albumGrid"))
                }
            }
        )
    }

    // MARK: - Filtering

    private var availableAlbums: [PhoneAlbum] {
        let importedIDs = Set(galleries.compactMap(\.albumIdentifier))
        return phoneAlbums.filter { !importedIDs.contains($0.collectionIdentifier) }
    }

    private var filteredAlbums: [PhoneAlbum] {
        if searchText.isEmpty { return availableAlbums }
        return availableAlbums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Import

    private func importSelected() {
        let existingCount = galleries.count
        let albumsToImport = availableAlbums.filter { selectedAlbumIDs.contains($0.id) }
        let service = PhotoLibraryService.shared

        for (index, album) in albumsToImport.enumerated() {
            let gallery = Gallery(
                name: album.name,
                displayOrder: existingCount + index,
                albumIdentifier: album.collectionIdentifier
            )
            modelContext.insert(gallery)

            let identifiers = service.fetchAssetIdentifiers(
                from: .distantPast,
                excluding: [],
                inAlbum: album.collectionIdentifier
            )
            for id in identifiers {
                let sorted = SortedPhoto(assetIdentifier: id, gallery: gallery)
                modelContext.insert(sorted)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Thumbnail View

private struct AlbumThumbnailView: View {
    let albumIdentifier: String
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                            .font(.title2)
                    }
            }
        }
        .task {
            thumbnail = await PhotoLibraryService.shared.fetchAlbumThumbnail(
                albumIdentifier: albumIdentifier,
                targetSize: CGSize(width: 200, height: 200)
            )
        }
    }
}
