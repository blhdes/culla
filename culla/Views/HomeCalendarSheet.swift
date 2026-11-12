import SwiftUI

/// The full calendar, opened by tapping the home date wheel. Its toolbar also
/// opens the photo grid, where picking a photo starts the session at that photo.
struct HomeCalendarSheet: View {
    @Binding var selectedDate: Date
    let earliest: Date?
    let latest: Date?
    let albumIdentifier: String?
    /// Called with the exact date of the photo picked in the grid.
    let onPhotoPicked: (Date) -> Void
    let onDone: () -> Void

    @State private var showPhotoGrid = false

    var body: some View {
        NavigationStack {
            Group {
                if let earliest, let latest {
                    CalendarView(
                        selectedDate: $selectedDate,
                        earliest: earliest,
                        latest: latest,
                        albumIdentifier: albumIdentifier
                    )
                }
            }
            .navigationTitle("Pick a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPhotoGrid = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showPhotoGrid) {
                if let earliest, let latest {
                    PhotoGridPickerView(
                        albumIdentifier: albumIdentifier,
                        earliest: earliest,
                        latest: latest,
                        selectedDate: $selectedDate,
                        onPick: onPhotoPicked
                    )
                }
            }
        }
    }
}
