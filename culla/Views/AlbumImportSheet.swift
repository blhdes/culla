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
                                Text("\(selectedAlbumIDs.count) selected")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    ForEach(AlbumSortOption.allCases, id: \.self) { option in
                                        Button {
                                            sortOption = option
                                        } label: {
                                            HStack {
                                                Text(option.rawValue)
                                                if sortOption == option {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(sortOption.rawValue)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let label = selectedAlbumIDs.isEmpty
                        ? "Import"
                        : "Import (\(selectedAlbumIDs.count))"
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(album.photoCount) photos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtering & Sorting

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
                let sorted = SortedPhoto(assetIdentifier: id, gallery: gallery, isImported: true)
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
