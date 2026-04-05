import SwiftUI
import SwiftData

struct GalleryDetailView: View {
    @Bindable var gallery: Gallery

    @Environment(\.modelContext) private var modelContext
    private let photoService = PhotoLibraryService.shared

    @State private var allIdentifiers: [String] = []
    @State private var hasSynced = false
    @State private var previewIdentifier: String?

    private let columns = PhotoThumbnailView.gridColumns

    var body: some View {
        Group {
            if allIdentifiers.isEmpty && hasSynced {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo",
                    description: Text("Swipe photos into this gallery to see them here.")
                )
            } else if allIdentifiers.isEmpty {
                ProgressView()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(allIdentifiers.count) photos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 1.5) {
                            ForEach(allIdentifiers, id: \.self) { identifier in
                                PhotoThumbnailView(
                                    assetIdentifier: identifier,
                                    photoService: photoService
                                )
                                .onLongPressGesture {
                                    previewIdentifier = identifier
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(gallery.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(
            get: { previewIdentifier.map { PhotoPreviewItem(id: $0) } },
            set: { previewIdentifier = $0?.id }
        )) { item in
            PhotoPreviewOverlay(
                identifier: item.id,
                photoService: photoService,
                onDismiss: { previewIdentifier = nil }
            )
        }
        .task {
            await syncAndLoad()
        }
    }

    // MARK: - Sync

    /// Syncs missing photos from the linked iPhone album into SortedPhoto records,
    /// then builds the full identifier list.
    private func syncAndLoad() async {
        // If gallery is linked to a real album, sync any photos not yet tracked
        if let albumID = gallery.albumIdentifier {
            let albumIdentifiers = photoService.fetchAssetIdentifiers(
                from: .distantPast,
                excluding: [],
                inAlbum: albumID
            )

            let existingIDs = Set(gallery.sortedPhotos.map(\.assetIdentifier))
            var added = false

            for id in albumIdentifiers {
                if !existingIDs.contains(id) {
                    let sorted = SortedPhoto(assetIdentifier: id, gallery: gallery, isImported: true)
                    modelContext.insert(sorted)
                    added = true
                }
            }

            if added {
                try? modelContext.save()
            }
        }

        // Build the display list from SortedPhoto records
        allIdentifiers = gallery.sortedPhotos
            .sorted { $0.sortedAt < $1.sortedAt }
            .map(\.assetIdentifier)

        hasSynced = true
    }
}

// MARK: - Thumbnail View

/// Square thumbnail that clips to 1:1 with correct hit targets.
struct PhotoThumbnailView: View {
    let assetIdentifier: String
    let photoService: PhotoLibraryService
    let targetSize: CGSize

    @State private var loader: PhotoImageLoader

    /// Standard thumbnail size for a 3-column grid.
    static let gridSize: CGSize = {
        let side = (UIScreen.main.bounds.width / 3) * UIScreen.main.scale
        return CGSize(width: side, height: side)
    }()

    /// Standard 3-column grid layout.
    static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 3)

    init(assetIdentifier: String, photoService: PhotoLibraryService, targetSize: CGSize = PhotoThumbnailView.gridSize) {
        self.assetIdentifier = assetIdentifier
        self.photoService = photoService
        self.targetSize = targetSize
        self._loader = State(initialValue: PhotoImageLoader(
            service: photoService,
            assetIdentifier: assetIdentifier,
            targetSize: targetSize
        ))
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if let image = loader.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay { ProgressView() }
                    }
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task { await loader.load() }
    }
}
