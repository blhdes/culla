import SwiftUI

struct ContentView: View {
    @State private var startDate: Date?
    @State private var selectedAlbum: PhoneAlbum?
    @State private var sortMode: SortMode = .copy
    @State private var focusDuration: TimeInterval?
    @State private var isOnThisDay = false
    @State private var showGalleries = false

    var body: some View {
        NavigationStack {
            if let startDate {
                SwipeView(
                    startDate: startDate,
                    albumIdentifier: selectedAlbum?.collectionIdentifier,
                    sortMode: sortMode,
                    focusDuration: focusDuration,
                    isOnThisDay: isOnThisDay,
                    onSessionEnd: {
                        self.startDate = nil
                        self.focusDuration = nil
                        self.isOnThisDay = false
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            self.startDate = nil
                            self.focusDuration = nil
                            self.isOnThisDay = false
                        } label: {
                            Image(systemName: "calendar")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showGalleries = true
                        } label: {
                            Image(systemName: "rectangle.stack")
                        }
                    }
                }
            } else {
                DatePickerView(
                    selectedDate: $startDate,
                    selectedAlbum: $selectedAlbum,
                    sortMode: $sortMode,
                    focusDuration: $focusDuration,
                    isOnThisDay: $isOnThisDay,
                    showGalleries: $showGalleries
                )
            }
        }
        .sheet(isPresented: $showGalleries) {
            NavigationStack {
                GalleriesView()
            }
        }
    }
}
