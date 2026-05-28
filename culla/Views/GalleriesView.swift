import SwiftUI
import SwiftData

struct GalleriesView: View {
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.activeTourStep) private var tourStep
    @Environment(\.tourAdvance) private var tourAdvance
    @Environment(\.dismiss) private var dismiss
    @Query private var allSortedPhotos: [SortedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @State private var viewModel: GalleryViewModel?
    @State private var insightsViewModel = InsightsViewModel()

    /// Only photos the user actually sorted — excludes imports.
    private var sortedPhotos: [SortedPhoto] {
        allSortedPhotos.filter { !$0.isImported }
    }

    @State private var navPath: [Gallery] = []
    @State private var editMode: EditMode = .inactive

    @State private var newGalleryName = ""
    @State private var showCreateAlert = false
    @State private var showAlbumImport = false
    @State private var showInsights = false
    @State private var showPaywall = false
    @State private var galleryToDelete: Gallery?
    @State private var namesBeforeEdit: [UUID: String] = [:]

    var body: some View {
        NavigationStack(path: $navPath) {
        List {
            if let step = tourStep, step == .setupGallery {
                TourSheetBanner(
                    step: step,
                    galleriesCount: galleries.count,
                    activeCount: activeGalleryCount
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
            }

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
                Section {
                    ForEach(galleries) { gallery in
                        NavigationLink(value: gallery) {
                            galleryRow(gallery)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                    galleryToDelete = gallery
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
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
                } header: {
                    Text(selectionStatusText)
                        .font(.system(.footnote, design: .rounded).weight(.medium))
                        .foregroundStyle(activeGalleryCount == 0 ? Color.orange : Color.secondary)
                        .textCase(nil)
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
        .overlay {
            if let gallery = galleryToDelete {
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) {
                                galleryToDelete = nil
                            }
                        }

                    DeleteGalleryMenu(
                        galleryName: gallery.name,
                        onDeleteWithPhotos: {
                            viewModel?.deleteGalleryAndPhotos(gallery)
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { galleryToDelete = nil }
                        },
                        onDeleteKeepPhotos: {
                            viewModel?.deleteGallery(gallery)
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { galleryToDelete = nil }
                        },
                        onUnlink: {
                            viewModel?.unlinkGallery(gallery)
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { galleryToDelete = nil }
                        },
                        onCancel: {
                            withAnimation(.spring(duration: 0.25, bounce: 0.1)) { galleryToDelete = nil }
                        }
                    )
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
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

    // MARK: - Stats Header

    private var statsHeader: some View {
        Button {
            if subscriptions.isPro {
                showInsights = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sortedPhotos.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: sortedPhotos.count)
                    Text("photos sorted")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if insightsViewModel.currentStreak > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: insightsViewModel.currentStreak)
                        Text("\(insightsViewModel.currentStreak)")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassSurface(in: Capsule())
                }

                Image(systemName: subscriptions.isPro ? "chevron.right" : "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
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
        // Active = selected for swiping. The card glows with the gallery's own
        // color when active — Culla's per-gallery identity carrying the
        // "selected" state (vs. a generic accent halo).
        let isActive = sidebarGalleryIDs.contains(gallery.id)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 14) {
            if editMode == .active {
                Circle()
                    .fill(gallery.color)
                    .frame(width: 12, height: 12)
                    .shadow(color: gallery.color.opacity(0.6), radius: 5)
            } else {
                Button { toggleSelection(gallery) } label: {
                    selectionCircle(for: gallery)
                }
                .buttonStyle(.plain)
            }

            // When the row is active, the glass picks up `gallery.color` as
            // tint — some neons are dark enough that .primary text collides.
            // `foregroundOnTintedGlass` flips to white only when needed.
            let labelColor: Color = isActive
                ? gallery.color.foregroundOnTintedGlass(in: colorScheme)
                : .primary

            if editMode == .active {
                TextField("Gallery name", text: $gallery.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor)
                    .onSubmit {
                        try? modelContext.save()
                    }
            } else {
                Text(gallery.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor)
            }

            Spacer()

            Text("\(gallery.sortedPhotos.count)")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(isActive ? labelColor.opacity(0.7) : .secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassSurface(in: shape, tint: isActive ? gallery.color : nil)
        .overlay(
            shape.strokeBorder(
                isActive ? gallery.color.opacity(0.5) : .white.opacity(0.06),
                lineWidth: isActive ? 1.4 : 1
            )
        )
        .shadow(color: isActive ? gallery.color.opacity(0.3) : .clear, radius: 14, y: 6)
        .animation(.snappy(duration: 0.25), value: isActive)
    }
}

private struct DeleteMenuGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content.background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct DeleteGalleryMenu: View {
    let galleryName: String
    let onDeleteWithPhotos: () -> Void
    let onDeleteKeepPhotos: () -> Void
    let onUnlink: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("Delete \"\(galleryName)\"?")
                    .font(.subheadline.weight(.semibold))
                Text("\"Remove from Culla\" just hides it here — your iPhone album stays intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)

            menuButton(title: "Delete Gallery & Photos", color: .red, action: onDeleteWithPhotos)
            menuButton(title: "Delete Gallery, Keep Photos", color: .red, action: onDeleteKeepPhotos)
            menuButton(title: "Remove from Culla", color: .primary, action: onUnlink)
            menuButton(title: "Cancel", color: .primary, action: onCancel)
        }
        .padding(8)
        .modifier(DeleteMenuGlass())
        .shadow(color: .black.opacity(0.15), radius: 24, y: 6)
    }

    @ViewBuilder
    private func menuButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

