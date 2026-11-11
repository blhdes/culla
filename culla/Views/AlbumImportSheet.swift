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
                                    albumCell(album)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.vertical, 8)
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
                    Button {
                        Task { await importSelected() }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text(label)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedAlbumIDs.isEmpty || isImporting)
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
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, accent)
                                .padding(6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: isSelected ? accent.opacity(0.35) : .clear, radius: 12, y: 5)
                    .scaleEffect(isSelected ? 0.96 : 1.0)

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
    }

    // MARK: - Filtering & Sorting

    private var availableAlbums: [PhoneAlbum] {
        let importedIDs = Set(galleries.compactMap(\.albumIdentifier))
        // Smart albums (Screenshots…) can't take new photos, so a gallery
        // built on one would silently stop matching its iPhone album.
        return phoneAlbums.filter { $0.canAddPhotos && !importedIDs.contains($0.collectionIdentifier) }
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

    private func importSelected() async {
        guard !isImporting else { return }
        isImporting = true

        let existingCount = galleries.count
        let albumsToImport = availableAlbums.filter { selectedAlbumIDs.contains($0.id) }
        let albumIDs = albumsToImport.map(\.collectionIdentifier)
        let service = PhotoLibraryService.shared

        // Listing the photos of big albums takes a moment, so do it in the
        // background while the button shows a spinner. Saving the records
        // below stays on the main thread, where the database context lives.
        let identifiersPerAlbum = await Task.detached(priority: .userInitiated) {
            albumIDs.map { service.fetchAssetIdentifiers(from: .distantPast, excluding: [], inAlbum: $0) }
        }.value

        var newGalleryIDs: [UUID] = []

        for (index, (album, identifiers)) in zip(albumsToImport, identifiersPerAlbum).enumerated() {
            let gallery = Gallery(
                name: album.name,
                displayOrder: existingCount + index,
                albumIdentifier: album.collectionIdentifier
            )
            modelContext.insert(gallery)
            newGalleryIDs.append(gallery.id)

            for id in identifiers {
                let sorted = SortedPhoto(assetIdentifier: id, gallery: gallery, isImported: true)
                modelContext.insert(sorted)
            }
        }

        try? modelContext.save()
        onImport?(newGalleryIDs)
        dismiss()
    }
}

// MARK: - Thumbnail View

private struct AlbumThumbnailView: View {
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
