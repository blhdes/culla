import SwiftUI

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
    @State private var showDuplicateSweep = false
    @AppStorage("duplicateTimeWindow") private var duplicateTimeWindowSeconds: Double = 3600

    var body: some View {
        NavigationStack {
            if showDuplicateSweep {
                DuplicateSweepView(timeWindow: TimeInterval(duplicateTimeWindowSeconds), onClose: {
                    showDuplicateSweep = false
                })
            } else if let startDate {
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
                    showDuplicateSweep: $showDuplicateSweep,
                    isReady: $isReady,
                    selectedMode: $selectedCullaMode
                )
            }
        }
        .sheet(isPresented: $showGalleries) {
            NavigationStack {
                GalleriesView(sidebarGalleryIDs: $sidebarGalleryIDs, maxSidebarGalleries: maxSidebarGalleries)
            }
        }
    }
}
