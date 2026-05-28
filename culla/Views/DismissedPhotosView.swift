import SwiftUI
import SwiftData

struct DismissedPhotosView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent

    @State private var viewModel: DismissedPhotosViewModel?
    @State private var deleteMessage: DeleteFeedback?
    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0
    @State private var previewIdentifier: String?
    @Namespace private var heroNamespace

    private let photoService = PhotoLibraryService.shared
    private let columns = PhotoThumbnailView.gridColumns

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.dismissedPhotos.isEmpty {
                    ContentUnavailableView(
                        "No Dismissed Photos",
                        systemImage: "trash.slash",
                        description: Text("Photos you dismiss will appear here for review.")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Photo count + selection controls
                        HStack {
                            Text("\(viewModel.dismissedPhotos.count) photos")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            Spacer()

                            if viewModel.hasSelection {
                                Button("Deselect All") {
                                    viewModel.deselectAll()
                                }
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(accent)
                            } else {
                                Button("Select All") {
                                    viewModel.selectAll()
                                }
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(accent)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        // Grid
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 1.5) {
                                ForEach(viewModel.dismissedPhotos, id: \.assetIdentifier) { photo in
                                    let isSelected = viewModel.selectedIdentifiers.contains(photo.assetIdentifier)

                                    PhotoThumbnailView(
                                        assetIdentifier: photo.assetIdentifier,
                                        photoService: photoService
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                    .overlay {
                                        if isSelected {
                                            Color.accentColor.opacity(0.2)
                                        }
                                    }
                                    .onTapGesture {
                                        viewModel.toggleSelection(photo.assetIdentifier)
                                    }
                                    .onLongPressGesture {
                                        previewIdentifier = photo.assetIdentifier
                                    }
                                    .matchedTransitionSource(id: photo.assetIdentifier, in: heroNamespace)
                                    .id(photo.assetIdentifier)
                                }
                            }
                        }

                        // Bottom action bar
                        actionBar(viewModel: viewModel)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Dismissed Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .deleteFeedback($deleteMessage)
        // Full-size preview
        .fullScreenCover(item: Binding(
            get: { previewIdentifier.map { PhotoPreviewItem(id: $0) } },
            set: { previewIdentifier = $0?.id }
        )) { item in
            PhotoPreviewOverlay(
                identifier: item.id,
                photoService: photoService,
                onDismiss: { previewIdentifier = nil }
            )
            .navigationTransition(.zoom(sourceID: item.id, in: heroNamespace))
        }
        .task {
            if viewModel == nil {
                let vm = DismissedPhotosViewModel(modelContext: modelContext)
                vm.loadDismissedPhotos()
                viewModel = vm
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(viewModel: DismissedPhotosViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if viewModel.hasSelection {
                    recoverButton("Recover (\(viewModel.selectedCount))") {
                        withAnimation { viewModel.recoverSelected() }
                    }
                    deleteButton("Delete (\(viewModel.selectedCount))", disabled: viewModel.isDeleting) {
                        Haptics.deleteConfirm()
                        Task {
                            let count = await viewModel.deleteSelected()
                            showDeleteFeedback(count)
                        }
                    }
                } else {
                    recoverButton("Recover All") {
                        withAnimation { viewModel.recoverAll() }
                    }
                    deleteButton("Delete All", disabled: viewModel.isDeleting) {
                        Haptics.deleteConfirm()
                        Task {
                            let count = await viewModel.deleteAll()
                            showDeleteFeedback(count)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    /// Secondary action — a glass capsule (recover keeps photos, so it reads
    /// as the calm choice next to the bold red delete CTA).
    private func recoverButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .glassSurface(in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func deleteButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        GradientCapsuleButton(title: title, icon: "trash", tint: .red, action: action)
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    private func showDeleteFeedback(_ count: Int) {
        guard count > 0 else { return }
        totalDeletedPhotos += count
        DailyStats.upsert(in: modelContext, deletedDelta: count)
        deleteMessage = DeleteFeedback(sessionCount: count, totalCount: totalDeletedPhotos)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            deleteMessage = nil
        }
    }
}

