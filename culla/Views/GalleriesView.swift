import SwiftUI
import SwiftData

struct GalleriesView: View {
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.activeTourStep) private var tourStep
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"
    // Shared with GallerySelectionSheet via the same keys, so the sort choice is
    // consistent across both gallery sheets and survives relaunch.
    @AppStorage("gallerySortField") private var sortFieldRaw = GallerySortField.custom.rawValue
    @AppStorage("gallerySortDescending") private var sortDescending = false
    /// Only photos the user actually sorted — excludes imports. Filtered by the
    /// database itself, so imported albums' photos are never loaded just to be
    /// thrown away on every redraw.
    @Query(filter: #Predicate<SortedPhoto> { !$0.isImported }) private var sortedPhotos: [SortedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]

    /// Bridges the persisted raw string to the typed field the `SortChip` binds.
    private var sortField: Binding<GallerySortField> {
        Binding(
            get: { GallerySortField(rawValue: sortFieldRaw) ?? .custom },
            set: { sortFieldRaw = $0.rawValue }
        )
    }

    /// The galleries in the order the chosen sort dictates. `custom` falls
    /// straight through to the `displayOrder` query, which is what lets the
    /// Edit-mode drag reorder keep working.
    private var sortedGalleries: [Gallery] {
        galleries.sortedBy(field: sortField.wrappedValue, descending: sortDescending)
    }
    @State private var viewModel: GalleryViewModel?
    @State private var insightsViewModel = InsightsViewModel()

    @State private var navPath: [Gallery] = []
    @State private var editMode: EditMode = .inactive

    @State private var newGalleryName = ""
    @State private var showCreateAlert = false
    @State private var showAlbumImport = false
    @State private var showInsights = false
    @State private var showPaywall = false
    /// The gallery whose row is asking "Delete …?". An id, not the model:
    /// the gallery is deleted while its row is still on its way out.
    @State private var deletingID: UUID?
    @State private var namesBeforeEdit: [UUID: String] = [:]

    var body: some View {
        NavigationStack(path: $navPath) {
        List {
            if let step = tourStep, step == .setupGallery {
                TourSheetBanner(
                    step: step,
                    galleriesCount: galleries.count
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            }

            GalleriesStatsHeader(
                sortedCount: sortedPhotos.count,
                currentStreak: insightsViewModel.currentStreak,
                isPro: subscriptions.isPro,
                onTap: {
                    if subscriptions.isPro {
                        showInsights = true
                    } else {
                        showPaywall = true
                    }
                }
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))

            if galleries.isEmpty {
                ContentUnavailableView(
                    "No Galleries",
                    systemImage: "rectangle.stack",
                    description: Text("Galleries you create will appear here.")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(sortedGalleries) { gallery in
                        NavigationLink(value: gallery) {
                            GalleriesRow(
                                gallery: gallery,
                                isActive: sidebarGalleryIDs.contains(gallery.id),
                                color: tint(gallery),
                                isEditing: editMode == .active,
                                onToggleSelection: { toggleSelection(gallery) },
                                onSubmitName: { try? modelContext.save() }
                            )
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        // A plain role, not .destructive: that role slides the
                        // row away before the answer. No full swipe, so a long
                        // swipe can't skip the question.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                deletingID = gallery.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                        // On the row, not the list, so the question opens beside it.
                        .deleteGalleryConfirmation(
                            name: gallery.name,
                            isPresented: isDeleting(gallery),
                            onDeleteWithPhotos: { await viewModel?.deleteGalleryAndPhotos(gallery) },
                            onDeleteKeepPhotos: { viewModel?.deleteGallery(gallery) },
                            onUnlink: { viewModel?.unlinkGallery(gallery) }
                        )
                    }
                    .onMove { source, destination in
                        // Manual reorder only makes sense in the natural order —
                        // a derived sort owns the order otherwise.
                        guard sortField.wrappedValue == .custom else { return }
                        var reordered = galleries
                        reordered.move(fromOffsets: source, toOffset: destination)
                        for (index, gallery) in reordered.enumerated() {
                            gallery.displayOrder = index
                        }
                        try? modelContext.save()
                    }
                } header: {
                    HStack {
                        Text(selectionStatusText)
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .foregroundStyle(activeGalleryCount == 0 ? Color.orange : Color.secondary)
                            .textCase(nil)
                        Spacer()
                        SortChip(field: sortField, descending: $sortDescending)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground).ignoresSafeArea())
        .environment(\.editMode, $editMode)
        .navigationTitle("Galleries")
        .navigationDestination(for: Gallery.self) { gallery in
            GalleryDetailView(gallery: gallery, viewModel: viewModel)
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
        // Full-screen rather than a sheet — Insights reads as a focused
        // destination, with no receded parent card peeking behind it.
        .fullScreenCover(isPresented: $showInsights) {
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
        // Forget deleted galleries (on open, and whenever one is removed) so
        // they stop counting toward the swipe-sidebar limit.
        .onChange(of: galleries.map(\.id), initial: true) {
            $sidebarGalleryIDs.pruneDeletedGalleries(keeping: galleries)
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
        } // NavigationStack
        .environment(\.tourActivateGallery) { gallery in
            if sidebarGalleryIDs.count < maxSidebarGalleries {
                sidebarGalleryIDs.insert(gallery.id)
            }
        }
        .onChange(of: tourStep) { _, newStep in
            switch newStep {
            case .changeColor:
                // Auto-push the first gallery so the user can colour it without reopening
                if let first = galleries.first {
                    navPath = [first]
                }
            case .readyToSwipe:
                // All gallery setup steps done — close the sheet
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    dismiss()
                }
            default:
                break
            }
        }
    }

    // MARK: - Selection

    /// The colour a gallery presents in this sheet. In "accent" sidebar mode
    /// per-gallery colours are switched off — every gallery uses the single
    /// app accent, so selection reads as one cohesive hue.
    private func tint(_ gallery: Gallery) -> Color {
        sidebarTintMode == "accent" ? accent : gallery.color
    }

    /// True only for the swiped row, so only its question is up.
    private func isDeleting(_ gallery: Gallery) -> Binding<Bool> {
        let id = gallery.id
        return Binding(
            get: { deletingID == id },
            set: { if !$0 { deletingID = nil } }
        )
    }

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
            return String(localized: "Tap a circle to activate galleries for swiping")
        }
        if !subscriptions.isPro && active >= maxSidebarGalleries {
            return String(localized: "\(active) active · Upgrade to select more")
        }
        return String(localized: "\(active) of \(galleries.count) active for swiping")
    }
}
