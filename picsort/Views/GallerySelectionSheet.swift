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
    @FocusState private var isFieldFocused: Bool

    // Drag-to-select state
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var isDragSelecting = false
    @State private var dragSelectAdding: Bool? = nil
    @State private var lastDraggedID: UUID? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if !filteredGalleries.isEmpty {
                        galleriesSection
                            .padding(.bottom, 20)
                    }
                    actionsSection
                }
                .padding(.vertical)
                .coordinateSpace(.named("galleryList"))
                .simultaneousGesture(dragSelectGesture)
            }
            .scrollDisabled(isDragSelecting)
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

    // MARK: - Sections

    private var galleriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(selectedIDs.count) of \(maxSelection) selected")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(filteredGalleries) { gallery in
                    galleryRow(gallery)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            GeometryReader { geo in
                                Color.clear.onAppear {
                                    cellFrames[gallery.id] = geo.frame(in: .named("galleryList"))
                                }
                            }
                        )

                    if gallery.id != filteredGalleries.last?.id {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            if showCreateField {
                HStack {
                    TextField("Gallery name", text: $newGalleryName)
                        .focused($isFieldFocused)
                        .onSubmit { createGallery() }

                    Button("Add") { createGallery() }
                        .disabled(newGalleryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Button("Create New Gallery") {
                    showCreateField = true
                    isFieldFocused = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)
            }

            Button {
                showAlbumImport = true
            } label: {
                Label("Import from Phone", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Drag-to-Select Gesture

    private var dragSelectGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("galleryList"))
            .onChanged { value in
                if dragSelectAdding == nil {
                    guard let id = galleryID(at: value.startLocation) else { return }
                    isDragSelecting = true
                    dragSelectAdding = !selectedIDs.contains(id)
                    apply(dragSelectAdding!, to: id)
                    lastDraggedID = id
                }
                guard let adding = dragSelectAdding,
                      let id = galleryID(at: value.location),
                      id != lastDraggedID else { return }
                lastDraggedID = id
                apply(adding, to: id)
            }
            .onEnded { _ in
                isDragSelecting = false
                dragSelectAdding = nil
                lastDraggedID = nil
            }
    }

    private func apply(_ adding: Bool, to id: UUID) {
        if adding {
            guard selectedIDs.count < maxSelection else { return }
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    private func galleryID(at point: CGPoint) -> UUID? {
        cellFrames.first { $0.value.contains(point) }?.key
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
                    .fill(Color.pastel(for: gallery.colorIndex))
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
