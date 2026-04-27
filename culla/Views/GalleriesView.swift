import SwiftUI
import SwiftData

struct GalleriesView: View {
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Environment(SubscriptionManager.self) private var subscriptions
    @Query private var allSortedPhotos: [SortedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @State private var viewModel: GalleryViewModel?
    @State private var insightsViewModel = InsightsViewModel()

    /// Only photos the user actually sorted — excludes imports.
    private var sortedPhotos: [SortedPhoto] {
        allSortedPhotos.filter { !$0.isImported }
    }

    @State private var editMode: EditMode = .inactive

    @State private var newGalleryName = ""
    @State private var showCreateAlert = false
    @State private var showAlbumImport = false
    @State private var showInsights = false
    @State private var showPaywall = false
    @State private var galleryToDelete: Gallery?
    @State private var namesBeforeEdit: [UUID: String] = [:]

    var body: some View {
        List {
            // Stats header
            statsHeader

            if galleries.isEmpty {
                ContentUnavailableView(
                    "No Galleries",
                    systemImage: "rectangle.stack",
                    description: Text("Galleries you create will appear here.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Text(selectionStatusText)
                    .font(.caption)
                    .foregroundStyle(activeGalleryCount == 0 ? .orange : .secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(galleries) { gallery in
                    NavigationLink(value: gallery) {
                        galleryRow(gallery)
                    }
                }
                .onMove { source, destination in
                    var reordered = galleries
                    reordered.move(fromOffsets: source, toOffset: destination)
                    for (index, gallery) in reordered.enumerated() {
                        gallery.displayOrder = index
                    }
                    try? modelContext.save()
                }
                .onDelete { offsets in
                    if let index = offsets.first {
                        galleryToDelete = galleries[index]
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Galleries")
        .navigationDestination(for: Gallery.self) { gallery in
            GalleryDetailView(gallery: gallery)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !galleries.isEmpty {
                    Button(editMode == .active ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCreateAlert = true
                    } label: {
                        Label("Create New", systemImage: "plus")
                    }

                    Button {
                        showAlbumImport = true
                    } label: {
                        Label("Import from Phone", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAlbumImport) {
            AlbumImportSheet { newIDs in
                for id in newIDs where sidebarGalleryIDs.count < maxSidebarGalleries {
                    sidebarGalleryIDs.insert(id)
                }
            }
            .tint(accent)
        }
        .alert("New Gallery", isPresented: $showCreateAlert) {
            TextField("Name", text: $newGalleryName)
            Button("Create") {
                let name = newGalleryName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    viewModel?.createGallery(name: name)
                }
                newGalleryName = ""
            }
            Button("Cancel", role: .cancel) {
                newGalleryName = ""
            }
        }
        .overlay {
            if let gallery = galleryToDelete {
                DeleteGalleryDialog(
                    gallery: gallery,
                    onDeleteAndPhotos: {
                        viewModel?.deleteGalleryAndPhotos(gallery)
                        galleryToDelete = nil
                    },
                    onDeleteKeepPhotos: {
                        viewModel?.deleteGallery(gallery)
                        galleryToDelete = nil
                    },
                    onUnlink: {
                        viewModel?.unlinkGallery(gallery)
                        galleryToDelete = nil
                    },
                    onCancel: { galleryToDelete = nil }
                )
            }
        }
        .sheet(isPresented: $showInsights) {
            InsightsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(onClose: { showPaywall = false })
        }
        .task {
            if viewModel == nil {
                viewModel = GalleryViewModel(modelContext: modelContext)
            }
            insightsViewModel.calculateStreaks(from: sortedPhotos.map(\.sortedAt))
        }
        .onChange(of: sortedPhotos.count) {
            insightsViewModel.calculateStreaks(from: sortedPhotos.map(\.sortedAt))
        }
        .onChange(of: editMode) { _, newMode in
            if newMode == .active {
                namesBeforeEdit = Dictionary(uniqueKeysWithValues: galleries.map { ($0.id, $0.name) })
            } else if newMode == .inactive {
                try? modelContext.save()
                for gallery in galleries {
                    if let oldName = namesBeforeEdit[gallery.id],
                       gallery.name != oldName,
                       let albumID = gallery.albumIdentifier {
                        Task { await PhotoLibraryService.shared.renameAlbum(identifier: albumID, to: gallery.name) }
                    }
                }
                namesBeforeEdit = [:]
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        Button {
            if subscriptions.isPro {
                showInsights = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sortedPhotos.count)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("photos sorted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if insightsViewModel.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(insightsViewModel.currentStreak)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }

                Image(systemName: subscriptions.isPro ? "chevron.right" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden, edges: .top)
    }

    // MARK: - Selection

    private func toggleSelection(_ gallery: Gallery) {
        if sidebarGalleryIDs.contains(gallery.id) {
            sidebarGalleryIDs.remove(gallery.id)
        } else if sidebarGalleryIDs.count >= maxSidebarGalleries {
            if !subscriptions.isPro { showPaywall = true }
        } else {
            sidebarGalleryIDs.insert(gallery.id)
        }
    }

    private var activeGalleryCount: Int {
        sidebarGalleryIDs.filter { id in galleries.contains { $0.id == id } }.count
    }

    private var selectionStatusText: String {
        let active = activeGalleryCount
        if active == 0 {
            return "Tap a circle to activate galleries for swiping"
        }
        if !subscriptions.isPro && active >= maxSidebarGalleries {
            return "\(active) active · Upgrade to select more"
        }
        return "\(active) of \(galleries.count) active for swiping"
    }

    @ViewBuilder
    private func selectionCircle(for gallery: Gallery) -> some View {
        let isSelected = sidebarGalleryIDs.contains(gallery.id)
        ZStack {
            Circle()
                .fill(isSelected ? gallery.color : Color.clear)
                .overlay(
                    Circle().strokeBorder(gallery.color.opacity(isSelected ? 0 : 0.45), lineWidth: 1.5)
                )
                .frame(width: 24, height: 24)
                .shadow(color: isSelected ? gallery.color.opacity(0.45) : .clear, radius: 5)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }

    // MARK: - Row

    @ViewBuilder
    private func galleryRow(_ gallery: Gallery) -> some View {
        @Bindable var gallery = gallery
        HStack(spacing: 12) {
            if editMode == .active {
                Circle()
                    .fill(gallery.color)
                    .frame(width: 10, height: 10)
            } else {
                Button { toggleSelection(gallery) } label: {
                    selectionCircle(for: gallery)
                }
                .buttonStyle(.plain)
            }

            if editMode == .active {
                TextField("Gallery name", text: $gallery.name)
                    .fontWeight(.medium)
                    .onSubmit {
                        try? modelContext.save()
                    }
            } else {
                Text(gallery.name)
                    .fontWeight(.medium)
            }

            Spacer()

            Text("\(gallery.sortedPhotos.count)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Delete Gallery Dialog

private struct DeleteGalleryDialog: View {
    let gallery: Gallery
    let onDeleteAndPhotos: () -> Void
    let onDeleteKeepPhotos: () -> Void
    let onUnlink: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("Delete \"\(gallery.name)\"?")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("\"Remove from Culla\" just hides it here — your iPhone album stays intact and you can re-import it anytime.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                Button(role: .destructive, action: onDeleteAndPhotos) {
                    Text("Delete Gallery & Photos")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .foregroundStyle(.red)

                Divider()

                Button(action: onDeleteKeepPhotos) {
                    Text("Delete Gallery, Keep Photos")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }

                Divider()

                Button(action: onUnlink) {
                    Text("Remove from Culla")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }

                Divider()

                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 40)
        }
    }
}
