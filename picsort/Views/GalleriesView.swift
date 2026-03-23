import SwiftUI
import SwiftData

struct GalleriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sortedPhotos: [SortedPhoto]
    @State private var viewModel: GalleryViewModel?
    @State private var insightsViewModel = InsightsViewModel()

    @State private var newGalleryName = ""
    @State private var showCreateAlert = false
    @State private var showAlbumImport = false
    @State private var showInsights = false
    @State private var galleryToDelete: Gallery?

    var body: some View {
        Group {
            if let viewModel {
                List {
                    // Stats header
                    statsHeader

                    if viewModel.galleries.isEmpty {
                        ContentUnavailableView(
                            "No Galleries",
                            systemImage: "rectangle.stack",
                            description: Text("Galleries you create will appear here.")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.galleries) { gallery in
                            NavigationLink(value: gallery) {
                                galleryRow(gallery)
                            }
                        }
                        .onMove { source, destination in
                            viewModel.moveGallery(from: source, to: destination)
                        }
                        .onDelete { offsets in
                            if let index = offsets.first {
                                galleryToDelete = viewModel.galleries[index]
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Galleries")
        .navigationDestination(for: Gallery.self) { gallery in
            GalleryDetailView(gallery: gallery)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if viewModel?.galleries.isEmpty == false {
                    EditButton()
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
        .sheet(isPresented: $showAlbumImport, onDismiss: {
            viewModel?.fetchGalleries()
        }) {
            AlbumImportSheet()
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
        .confirmationDialog(
            "Delete \(galleryToDelete?.name ?? "Gallery")?",
            isPresented: Binding(
                get: { galleryToDelete != nil },
                set: { if !$0 { galleryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let gallery = galleryToDelete {
                Button("Delete Gallery & Photos", role: .destructive) {
                    viewModel?.deleteGalleryAndPhotos(gallery)
                    galleryToDelete = nil
                }
                Button("Delete Gallery, Keep Photos") {
                    viewModel?.deleteGallery(gallery)
                    galleryToDelete = nil
                }
                Button("Remove from picsort") {
                    viewModel?.unlinkGallery(gallery)
                    galleryToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    galleryToDelete = nil
                }
            }
        } message: {
            Text("\"Remove from picsort\" just hides it here — your iPhone album stays intact and you can re-import it anytime.")
        }
        .sheet(isPresented: $showInsights) {
            InsightsView()
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
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        Button {
            showInsights = true
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

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden, edges: .top)
    }

    // MARK: - Row

    @ViewBuilder
    private func galleryRow(_ gallery: Gallery) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.pastel(for: gallery.colorIndex))
                .frame(width: 10, height: 10)

            Text(gallery.name)
                .fontWeight(.medium)

            Spacer()

            Text("\(gallery.sortedPhotos.count)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
