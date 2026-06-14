import SwiftUI
import SwiftData

struct GallerySelectionSheet: View {
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @Binding var selectedIDs: Set<UUID>
    let maxSelection: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SubscriptionManager.self) private var subscriptions
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"

    @State private var searchText = ""
    @State private var newGalleryName = ""
    @State private var showCreateField = false
    @State private var showAlbumImport = false
    @State private var showPaywall = false
    @State private var sortOption: GallerySortOption = .custom
    @FocusState private var isFieldFocused: Bool

    private enum GallerySortOption: String, CaseIterable {
        case custom = "Custom"
        case name = "Name"
        case photoCount = "Photo Count"

        var displayName: LocalizedStringKey {
            switch self {
            case .custom: "Custom"
            case .name: "Name"
            case .photoCount: "Photo Count"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if galleries.isEmpty {
                    emptyStateView
                } else {
                    galleryList
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
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
            AlbumImportSheet { newIDs in
                for id in newIDs where selectedIDs.count < maxSelection {
                    selectedIDs.insert(id)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(onClose: { showPaywall = false })
        }
    }

    // MARK: - Empty State

    /// Shown when the user has no galleries at all — guides them straight
    /// to create or import instead of leaving the sheet looking broken.
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Galleries Yet", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Galleries are how you organize swiped photos. Create one or import an existing iPhone album.")
        } actions: {
            VStack(spacing: 10) {
                if showCreateField {
                    HStack {
                        TextField("Gallery name", text: $newGalleryName)
                            .focused($isFieldFocused)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { createGallery() }
                        Button("Add") { createGallery() }
                            .buttonStyle(.borderedProminent)
                            .disabled(newGalleryName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, 32)
                } else {
                    Button {
                        showCreateField = true
                        isFieldFocused = true
                    } label: {
                        Label("Create New Gallery", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                }

                Button {
                    showAlbumImport = true
                } label: {
                    Label("Import from Phone", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 32)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Gallery List

    @ViewBuilder
    private var galleryList: some View {
        List {
            if !filteredGalleries.isEmpty {
                Section {
                    ForEach(sortedGalleries) { gallery in
                        galleryRow(gallery)
                    }
                    .onMove { source, destination in
                        guard sortOption == .custom else { return }
                        reorderGalleries(from: source, to: destination)
                    }
                } header: {
                    HStack {
                        Text("\(selectedIDs.count) of \(maxSelection) selected")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy, value: selectedIDs.count)
                        Spacer()
                        Menu {
                            ForEach(GallerySortOption.allCases, id: \.self) { option in
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
                            .font(.system(.caption, design: .rounded))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
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
                    .font(.system(.body, design: .rounded))
                } else {
                    Button("Create New Gallery") {
                        showCreateField = true
                        isFieldFocused = true
                    }
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(accent)
                }

                Button {
                    showAlbumImport = true
                } label: {
                    Label("Import from Phone", systemImage: "square.and.arrow.down")
                        .font(.system(.body, design: .rounded))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search galleries")
    }

    // MARK: - Row

    @ViewBuilder
    private func galleryRow(_ gallery: Gallery) -> some View {
        let isSelected = selectedIDs.contains(gallery.id)
        let atLimit = selectedIDs.count >= maxSelection
        // In "accent" sidebar mode per-gallery colours are off — every row
        // shares the single app accent so selection reads as one cohesive hue.
        let color = sidebarTintMode == "accent" ? accent : gallery.color
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        Button {
            if isSelected {
                selectedIDs.remove(gallery.id)
            } else if !atLimit {
                selectedIDs.insert(gallery.id)
            } else if !subscriptions.isPro {
                showPaywall = true
            }
        } label: {
            // Dark light-mode hues (deep teal/purple) become unreadable when
            // .primary text sits on the tinted glass — flip to white only when
            // luminance is low enough to need it.
            let labelColor: Color = isSelected
                ? color.foregroundOnTintedGlass(in: colorScheme)
                : .primary

            HStack(spacing: 14) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(0.6), radius: 5)

                Text(gallery.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor)

                Spacer()

                Text("\(gallery.sortedPhotos.count)")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? labelColor.opacity(0.7) : .secondary)

                // Multi-select idiom: empty circle ↔ filled check, swapping with
                // a bounce so toggling feels landed. The check picks up the tint
                // colour, but flips to the label color when the tint is dark so
                // it stays visible against the wash.
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected
                            ? (labelColor == .white ? labelColor : color)
                            : Color.secondary.opacity(0.4)
                    )
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isSelected)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .glassSurface(in: shape, tint: isSelected ? color : nil)
            .overlay(
                shape.strokeBorder(
                    isSelected ? color.opacity(0.5) : .white.opacity(0.06),
                    lineWidth: isSelected ? 1.4 : 1
                )
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .disabled(!isSelected && atLimit && subscriptions.isPro)
        .opacity(!isSelected && atLimit ? 0.35 : 1.0)
        .animation(.snappy(duration: 0.22), value: isSelected)
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

    // MARK: - Reorder

    private func reorderGalleries(from source: IndexSet, to destination: Int) {
        var ordered = sortedGalleries
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, gallery) in ordered.enumerated() {
            gallery.displayOrder = index
        }
        try? modelContext.save()
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
