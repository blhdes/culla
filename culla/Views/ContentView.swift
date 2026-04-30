import SwiftUI
import PhotosUI

struct ContentView: View {
    @Binding var isReady: Bool
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int

    @State private var startDate: Date?
    @State private var selectedCullaMode: CullaMode = .cullaing
    @State private var selectedAlbum: PhoneAlbum?
    @State private var sortMode: SortMode = .copy
    @State private var focusDuration: TimeInterval?
    @State private var isOnThisDay = false
    @State private var showGalleries = false
    @State private var showDuplicatePicker = false
    @State private var showDuplicateSweep = false
    @State private var duplicateSelectedID: String?
    @AppStorage("duplicateTimeWindow") private var duplicateTimeWindowSeconds: Double = 3600

    var body: some View {
        NavigationStack {
            if let startDate {
                SwipeView(
                    startDate: startDate,
                    albumIdentifier: selectedAlbum?.collectionIdentifier,
                    sortMode: sortMode,
                    focusDuration: focusDuration,
                    isOnThisDay: isOnThisDay,
                    sidebarGalleryIDs: $sidebarGalleryIDs,
                    onBack: {
                        self.startDate = nil
                        self.focusDuration = nil
                        self.isOnThisDay = false
                    },
                    onShowGalleries: {
                        showGalleries = true
                    },
                    onSessionEnd: {
                        self.startDate = nil
                        self.focusDuration = nil
                        self.isOnThisDay = false
                    }
                )
                .navigationBarHidden(true)
            } else {
                DatePickerView(
                    selectedDate: $startDate,
                    selectedAlbum: $selectedAlbum,
                    sortMode: $sortMode,
                    focusDuration: $focusDuration,
                    isOnThisDay: $isOnThisDay,
                    showGalleries: $showGalleries,
                    showDuplicateSweep: $showDuplicatePicker,
                    isReady: $isReady,
                    selectedMode: $selectedCullaMode
                )
            }
        }
        .sheet(isPresented: $showGalleries) {
            GalleriesView(sidebarGalleryIDs: $sidebarGalleryIDs, maxSidebarGalleries: maxSidebarGalleries)
        }
        // Step 1: show the photo picker fullscreen. Only if a photo was selected
        // do we advance to the sweep view — cancelling returns straight to DatePickerView.
        .fullScreenCover(isPresented: $showDuplicatePicker, onDismiss: {
            if duplicateSelectedID != nil {
                showDuplicateSweep = true
            }
        }) {
            DuplicatePickerCover(
                onSelect: { id in duplicateSelectedID = id },
                onDone:   { showDuplicatePicker = false }
            )
        }
        // Step 2: sweep view already has the selected asset ID — no picker inside.
        .fullScreenCover(isPresented: $showDuplicateSweep) {
            if let id = duplicateSelectedID {
                DuplicateSweepView(
                    initialIdentifier: id,
                    timeWindow: TimeInterval(duplicateTimeWindowSeconds),
                    onClose: {
                        showDuplicateSweep = false
                        duplicateSelectedID = nil
                    }
                )
            }
        }
    }
}

// Thin UIViewControllerRepresentable wrapper around PHPickerViewController so it
// can be presented as a fullScreenCover without nesting inside DuplicateSweepView.
private struct DuplicatePickerCover: UIViewControllerRepresentable {
    let onSelect: (String) -> Void
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onDone: onDone) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onSelect: (String) -> Void
        let onDone: () -> Void

        init(onSelect: @escaping (String) -> Void, onDone: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onDone = onDone
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if let result = results.first, let id = result.assetIdentifier {
                onSelect(id)
            }
            onDone()
        }
    }
}
