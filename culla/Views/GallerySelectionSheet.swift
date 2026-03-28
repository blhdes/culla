import SwiftUI
import SwiftData

struct GallerySelectionSheet: View {
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @Binding var selectedIDs: Set<UUID>
    let maxSelection: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var newGalleryName = ""
    @State private var showCreateField = false
    @State private var showAlbumImport = false
    @State private var sortOption: GallerySortOption = .custom
    @FocusState private var isFieldFocused: Bool

    private enum GallerySortOption: String, CaseIterable {
        case custom = "Custom"
        case name = "Name"
        case photoCount = "Photo Count"
    }

    var body: some View {
        NavigationStack {
            List {
                if !filteredGalleries.isEmpty {
                    Section {
                        ForEach(sortedGalleries) { gallery in
                            galleryRow(gallery)
                        }
                    } header: {
                        HStack {
                            Text("\(selectedIDs.count) of \(maxSelection) selected")
                            Spacer()
                            Menu {
                                ForEach(GallerySortOption.allCases, id: \.self) { option in
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
                                .font(.caption)
                            }
                        }
                    }
                }

                Section {
                    if showCreateField {
                        HStack {
                            TextField("Gallery name", text: $newGalleryName)
                                .focused($isFieldFocused)
                                .onSubmit { createGallery() }

                            Button("Add") { createGallery() }
                                .disabled(newGalleryName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        Button("Create New Gallery") {
                            showCreateField = true
                            isFieldFocused = true
                        }
                    }

                    Button {
                        showAlbumImport = true
                    } label: {
                        Label("Import from Phone", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search galleries")
            .navigationTitle("Select Galleries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showAlbumImport) {
            AlbumImportSheet()
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func galleryRow(_ gallery: Gallery) -> some View {
        let isSelected = selectedIDs.contains(gallery.id)
        let atLimit = selectedIDs.count >= maxSelection

        Button {
            if isSelected {
                selectedIDs.remove(gallery.id)
            } else {
                selectedIDs.insert(gallery.id)
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(gallery.color)
                    .frame(width: 10, height: 10)

                Text(gallery.name)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(gallery.sortedPhotos.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .primary : .quaternary)
                    .font(.title3)
            }
            .padding(.vertical, 2)
        }
        .disabled(!isSelected && atLimit)
        .opacity(!isSelected && atLimit ? 0.35 : 1.0)
    }

    // MARK: - Filtering

    private var filteredGalleries: [Gallery] {
        if searchText.isEmpty { return Array(galleries) }
        return galleries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var sortedGalleries: [Gallery] {
        switch sortOption {
        case .custom:
            return filteredGalleries
        case .name:
            return filteredGalleries.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .photoCount:
            return filteredGalleries.sorted { $0.sortedPhotos.count > $1.sortedPhotos.count }
        }
    }

    // MARK: - Create

    private func createGallery() {
        let name = newGalleryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let gallery = Gallery(name: name, displayOrder: galleries.count)
        modelContext.insert(gallery)
        try? modelContext.save()

        if selectedIDs.count < maxSelection {
            selectedIDs.insert(gallery.id)
        }

        newGalleryName = ""
        showCreateField = false

        // Create matching iPhone Photos album
        Task {
            let service = PhotoLibraryService.shared
            if let albumID = await service.createAlbum(name: name) {
                await MainActor.run {
                    gallery.albumIdentifier = albumID
                    try? modelContext.save()
                }
            }
        }
    }
}
