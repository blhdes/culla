import SwiftUI
import SwiftData
import Photos

/// Lets the user pick from their iPhone photo albums and import them as app galleries.
/// Albums already imported (matched by albumIdentifier) are hidden.
struct AlbumImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Query private var galleries: [Gallery]

    /// Called after import with the UUIDs of every newly created gallery.
    var onImport: (([UUID]) -> Void)? = nil

    @State private var phoneAlbums: [PhoneAlbum] = []
    @State private var selectedAlbumIDs: Set<String> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var isImporting = false
    /// Live progress from the background importer (nil before it starts).
    @State private var importProgress: AlbumImportProgress?
    /// True once every album is saved: the capsule shows "Done" before closing.
    @State private var importFinished = false
    /// Each album being imported, by its position in the import. These albums
    /// stay listed until the sheet closes, even after their gallery is saved,
    /// so the grid doesn't shift mid-import.
    @State private var importIndexByAlbumID: [String: Int] = [:]
    /// Display order of the first new gallery, which sets each one's color.
    @State private var importStartingOrder = 0
    /// Set when an import stops early: the name of the album that failed
    /// ("" when it isn't known). Shows the error alert.
    @State private var failedAlbumName: String?
    @State private var sortOption: AlbumSortOption = .name

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

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
                        VStack(spacing: 12) {
                            HStack {
                                Button {
                                    if selectedAlbumIDs.count == sortedAlbums.count {
                                        selectedAlbumIDs.removeAll()
                                    } else {
                                        selectedAlbumIDs = Set(sortedAlbums.map(\.id))
                                    }
                                } label: {
                                    Text(selectedAlbumIDs.count == sortedAlbums.count ? "Deselect All" : "Select All")
                                        .font(.system(.footnote, design: .rounded).weight(.medium))
                                        .foregroundStyle(accent)
                                }
                                Text("\(selectedAlbumIDs.count) of \(sortedAlbums.count) selected")
                                    .font(.system(.footnote, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: selectedAlbumIDs.count)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    ForEach(AlbumSortOption.allCases, id: \.self) { option in
                                        Button {
                                            sortOption = option
                                        } label: {
                                            HStack {
                                                Text(option.displayName)
                                                if sortOption == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(sortOption.displayName)
                                        Image(systemName: "chevron.up.chevron.down")
                                    }
                                    .font(.footnote)
                                }
                            }
                            .padding(.horizontal)

                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(sortedAlbums) { album in
                                    AlbumImportCell(
                                        album: album,
                                        isSelected: selectedAlbumIDs.contains(album.id),
                                        importState: importState(for: album)
                                    ) {
                                        toggleSelection(of: album)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 8)
                        // The picks are locked in once the import starts.
                        .allowsHitTesting(!isImporting)
                    }
                    .safeAreaInset(edge: .bottom) {
                        if isImporting, let importProgress {
                            AlbumImportProgressCapsule(
                                progress: importProgress,
                                isFinished: importFinished,
                                currentAlbumIdentifier: currentImportAlbumID,
                                color: galleryColor(forImportIndex: importProgress.albumIndex)
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search albums")
                }
            }
            .navigationTitle("Import Albums")
            .navigationBarTitleDisplayMode(.inline)
            // Closing mid-import would still create the galleries a moment later.
            .interactiveDismissDisabled(isImporting)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let label: LocalizedStringKey = selectedAlbumIDs.isEmpty
                        ? "Import"
                        : "Import (\(selectedAlbumIDs.count))"
                    // The progress capsule at the bottom shows the import,
                    // so the button just stays disabled while it runs.
                    Button(label) {
                        Task { await importSelected() }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedAlbumIDs.isEmpty || isImporting)
                }
            }
            .alert(
                "Import Stopped",
                isPresented: Binding(
                    get: { failedAlbumName != nil },
                    set: { if !$0 { failedAlbumName = nil } }
                )
            ) {
                Button("OK") { dismiss() }
            } message: {
                if let failedAlbumName, !failedAlbumName.isEmpty {
                    Text("“\(failedAlbumName)” couldn’t be saved. The albums before it were imported.")
                } else {
                    Text("Some albums couldn’t be saved. Please try again.")
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

    // MARK: - Selection

    private func toggleSelection(of album: PhoneAlbum) {
        if selectedAlbumIDs.contains(album.id) {
            selectedAlbumIDs.remove(album.id)
        } else {
            selectedAlbumIDs.insert(album.id)
        }
    }

    // MARK: - Import State

    /// Where an album stands in the running import, for its grid cell.
    private func importState(for album: PhoneAlbum) -> AlbumImportCell.ImportState {
        guard isImporting else { return .idle }
        guard let index = importIndexByAlbumID[album.collectionIdentifier] else { return .skipped }
        let finishedCount = importProgress?.albumsFinished ?? 0
        if importFinished || index < finishedCount {
            return .imported(color: galleryColor(forImportIndex: index))
        }
        if index == importProgress?.albumIndex {
            return .importing(
                fraction: importProgress?.albumFraction ?? 0,
                color: galleryColor(forImportIndex: index)
            )
        }
        return .waiting
    }

    /// The album being imported right now, for the capsule's cover.
    private var currentImportAlbumID: String? {
        guard let index = importProgress?.albumIndex else { return nil }
        return importIndexByAlbumID.first { $0.value == index }?.key
    }

    /// The color the gallery for the album at `index` in this import will get.
    private func galleryColor(forImportIndex index: Int) -> Color {
        Color.adaptiveNeon(hex: Gallery.defaultColorHex(forDisplayOrder: importStartingOrder + index))
    }

    // MARK: - Filtering & Sorting

    private var availableAlbums: [PhoneAlbum] {
        let importedIDs = Set(galleries.compactMap(\.albumIdentifier))
        // Smart albums (Screenshots…) can't take new photos, so a gallery
        // built on one would silently stop matching its iPhone album.
        return phoneAlbums.filter {
            $0.canAddPhotos && (!importedIDs.contains($0.collectionIdentifier) || importIndexByAlbumID[$0.collectionIdentifier] != nil)
        }
    }

    private var filteredAlbums: [PhoneAlbum] {
        if searchText.isEmpty { return availableAlbums }
        return availableAlbums.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sortedAlbums: [PhoneAlbum] {
        switch sortOption {
        case .name:
            return filteredAlbums.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .photoCount:
            return filteredAlbums.sorted { $0.photoCount > $1.photoCount }
        case .dateCreated:
            return filteredAlbums.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }
    }

    // MARK: - Import

    /// How long "Done" stays on screen before the sheet closes.
    /// Tuned in the design workshop (`doneHold: 0.8`).
    private static let doneHold: Duration = .seconds(0.8)

    private func importSelected() async {
        guard !isImporting else { return }

        let albumsToImport = availableAlbums.filter { selectedAlbumIDs.contains($0.id) }
        guard let firstAlbum = albumsToImport.first else { return }
        let requests = albumsToImport.map {
            AlbumImportRequest(
                name: $0.name,
                albumIdentifier: $0.collectionIdentifier,
                estimatedPhotoCount: $0.photoCount
            )
        }
        let startingOrder = galleries.count
        let container = modelContext.container
        let report: @MainActor @Sendable (AlbumImportProgress) -> Void = { importProgress = $0 }

        importStartingOrder = startingOrder
        importIndexByAlbumID = Dictionary(
            uniqueKeysWithValues: albumsToImport.enumerated().map { ($1.collectionIdentifier, $0) }
        )
        // Show the capsule right away, before the first report arrives.
        importProgress = AlbumImportProgress(
            albumName: firstAlbum.name,
            albumCount: requests.count,
            photosTotal: requests.reduce(0) { $0 + $1.estimatedPhotoCount }
        )
        withAnimation(.snappy) { isImporting = true }

        let newGalleryIDs: [UUID]
        do {
            // Everything (reading albums, creating and saving records) runs in
            // the background, so the screen keeps moving during big imports.
            newGalleryIDs = try await Task.detached(priority: .userInitiated) {
                let importer = AlbumImporter(modelContainer: container)
                return try await importer.importAlbums(
                    requests,
                    startingDisplayOrder: startingOrder,
                    onProgress: report
                )
            }.value
        } catch let failure as AlbumImportFailure {
            print("culla: Album import stopped at \"\(failure.albumName)\": \(failure.underlying)")
            onImport?(failure.importedGalleryIDs)
            failedAlbumName = failure.albumName
            return
        } catch {
            print("culla: Album import failed: \(error)")
            failedAlbumName = ""
            return
        }

        onImport?(newGalleryIDs)
        importFinished = true
        Haptics.importFinished()

        // Let "Done" register before the sheet slides away.
        do {
            try await Task.sleep(for: Self.doneHold)
        } catch {
            print("culla: The pause before closing Import Albums was cut short: \(error)")
        }
        dismiss()
    }
}
