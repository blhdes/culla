import SwiftUI
import SwiftData

struct GalleryDetailView: View {
    @Bindable var gallery: Gallery
    var viewModel: GalleryViewModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activeTourStep) private var tourStep
    @Environment(\.tourActivateGallery) private var tourActivateGallery
    @Environment(\.tourSetStep) private var tourSetStep
    private let photoService = PhotoLibraryService.shared

    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"

    @State private var allIdentifiers: [String] = []
    @State private var hasSynced = false
    @State private var showColorPicker = false
    @State private var showDeleteMenu = false
    @State private var tourHintDismissed = false
    @State private var previewIdentifier: String?
    @Namespace private var heroNamespace

    private let columns = PhotoThumbnailView.gridColumns

    var body: some View {
        Group {
            if !hasSynced {
                ProgressView()
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        if sidebarTintMode == "accent" {
                            // Accent sidebar mode switches per-gallery colours
                            // off — there's nothing to customise, so the header
                            // collapses to a plain, non-interactive photo count.
                            HStack(spacing: 10) {
                                photoCountLabel
                                Spacer()
                            }
                        } else {
                            colorPickerSection
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))

                    if tourStep == .changeColor && !showColorPicker && !tourHintDismissed {
                        // Override tourAdvance so the Continue button follows the same
                        // path as picking a color (activate + jump to readyToSwipe).
                        TourColorHint()
                            .environment(\.tourAdvance) { handleTourColorPicked() }
                    }

                    if allIdentifiers.isEmpty {
                        ContentUnavailableView(
                            "No Photos Yet",
                            systemImage: "photo",
                            description: Text("Swipe photos into this gallery to see them here.")
                        )
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 1.5) {
                                ForEach(allIdentifiers, id: \.self) { identifier in
                                    PhotoThumbnailView(
                                        assetIdentifier: identifier,
                                        photoService: photoService
                                    )
                                    .matchedTransitionSource(id: identifier, in: heroNamespace)
                                    .onLongPressGesture {
                                        previewIdentifier = identifier
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(gallery.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                        showDeleteMenu = true
                    }
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .overlay {
            if showDeleteMenu {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                showDeleteMenu = false
                            }
                        }

                    DeleteGalleryMenu(
                        galleryName: gallery.name,
                        onDeleteWithPhotos: {
                            let count = allIdentifiers.count
                            viewModel?.deleteGalleryAndPhotos(gallery)
                            if count > 0 {
                                totalDeletedPhotos += count
                                DailyStats.upsert(in: modelContext, deletedDelta: count)
                            }
                            dismiss()
                        },
                        onDeleteKeepPhotos: {
                            viewModel?.deleteGallery(gallery)
                            dismiss()
                        },
                        onUnlink: {
                            viewModel?.unlinkGallery(gallery)
                            dismiss()
                        },
                        onCancel: {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                showDeleteMenu = false
                            }
                        }
                    )
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .fullScreenCover(item: Binding(
            get: { previewIdentifier.map { PhotoPreviewItem(id: $0) } },
            set: { previewIdentifier = $0?.id }
        )) { item in
            PhotoPreviewOverlay(
                identifier: item.id,
                photoService: photoService,
                onDismiss: { previewIdentifier = nil }
            )
            .navigationTransition(.zoom(sourceID: item.id, in: heroNamespace))
        }
        .task {
            await syncAndLoad()
        }
    }

    // MARK: - Header

    /// Photo count shown in the gallery header. Shared by both sidebar-tint
    /// modes so the label can't drift between them.
    private var photoCountLabel: some View {
        Text("\(allIdentifiers.count) photos")
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    /// "Per gallery" mode header: a tappable row that discloses the neon swatch
    /// grid + custom ColorPicker for this gallery's colour.
    @ViewBuilder
    private var colorPickerSection: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showColorPicker.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(gallery.color)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .shadow(color: gallery.color.opacity(0.5), radius: 5)

                photoCountLabel

                Spacer()

                Image(systemName: showColorPicker ? "chevron.up" : "paintpalette.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showColorPicker {
            VStack(spacing: 12) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 9),
                    spacing: 10
                ) {
                    ForEach(Array(Color.neonHexes.enumerated()), id: \.offset) { _, hex in
                        Button {
                            gallery.colorHex = hex
                            try? modelContext.save()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showColorPicker = false
                            }
                            handleTourColorPicked()
                        } label: {
                            Circle()
                                .fill(Color.adaptiveNeon(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle()
                                        .stroke(.primary, lineWidth: gallery.colorHex == hex ? 2 : 0)
                                        .padding(-3)
                                }
                                .shadow(color: gallery.colorHex == hex ? Color.adaptiveNeon(hex: hex).opacity(0.5) : .clear, radius: 5)
                        }
                    }
                }

                ColorPicker(
                    "Custom color",
                    selection: Binding(
                        get: { gallery.color },
                        set: { newColor in
                            gallery.colorHex = newColor.hexString
                            try? modelContext.save()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showColorPicker = false
                            }
                            handleTourColorPicked()
                        }
                    ),
                    supportsOpacity: false
                )
                .font(.subheadline)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// During the tour, picking a color implies the user is configuring this gallery
    /// for swiping — auto-activate it and skip ahead to the final step instead of
    /// making them tap Continue twice and navigate back manually.
    private func handleTourColorPicked() {
        guard tourStep == .changeColor else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            tourHintDismissed = true
        }
        tourActivateGallery?(gallery)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            tourSetStep?(.readyToSwipe)
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
    @State private var videoDuration: TimeInterval?

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
                    } else if loader.loadAttempted && !loader.isLoading {
                        // Load finished but returned nil — asset deleted or unavailable.
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay { ProgressView() }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let videoDuration {
                    VideoDurationBadge(duration: videoDuration)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task {
                if let info = photoService.assetInfo(for: assetIdentifier), info.isVideo {
                    videoDuration = info.duration
                }
                await loader.load()
            }
    }
}
