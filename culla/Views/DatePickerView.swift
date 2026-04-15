import SwiftUI
import SwiftData
import Photos

enum CullaMode: String, CaseIterable {
    case cullaing
    case thisDay
    case duplicates
}

struct DatePickerView: View {
    @Binding var selectedDate: Date?
    @Binding var selectedAlbum: PhoneAlbum?
    @Binding var sortMode: SortMode
    @Binding var focusDuration: TimeInterval?
    @Binding var isOnThisDay: Bool
    @Binding var showGalleries: Bool
    @Binding var showDuplicateSweep: Bool
    @Binding var isReady: Bool
    @Binding var selectedMode: CullaMode

    @Environment(\.appAccent) private var accent

    @AppStorage("lastSelectedDate") private var pickerDate = Date()
    @AppStorage("lastSelectedAlbumID") private var lastSelectedAlbumID: String = ""
    @AppStorage("showCullaEyes") private var showCullaEyes = false

    private let photoService = PhotoLibraryService.shared
    @State private var earliestDate: Date?
    @State private var latestDate: Date?
    @State private var albums: [PhoneAlbum] = []
    @State private var unsortedCount: Int = 0
    @State private var favoritesCount: Int = 0
    @State private var showAlbumPicker = false
    @State private var showFullCalendar = false
    @State private var showDismissedPhotos = false
    @State private var showSettings = false
    @State private var permissionDenied = false
    @State private var noPhotosAvailable = false

    @Query(filter: #Predicate<SortedPhoto> { !$0.isImported }) private var sortedPhotos: [SortedPhoto]
    @Query private var dismissedPhotos: [DismissedPhoto]

    var body: some View {
        VStack(spacing: 28) {
            if let earliestDate, let latestDate {
                if showCullaEyes {
                    CullaEyes()
                        .tint(accent)
                        .padding(.top, 8)
                }

                Spacer()

                if selectedMode != .duplicates {
                    VStack(spacing: 12) {
                        DatePicker(
                            "Date",
                            selection: $pickerDate,
                            in: earliestDate...latestDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .onChange(of: pickerDate) {
                            Haptics.dateWheelTick()
                        }
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    showFullCalendar = true
                                }
                        )

                        Button {
                            let today = Date.now
                            pickerDate = min(max(today, earliestDate), latestDate)
                        } label: {
                            Label("Today", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .opacity(Calendar.current.isDateInToday(pickerDate) ? 0 : 1)
                        .allowsHitTesting(!Calendar.current.isDateInToday(pickerDate))
                        .animation(.easeInOut(duration: 0.25), value: Calendar.current.isDateInToday(pickerDate))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Album + sort mode + start button — anchored just above the bottom toolbar
                VStack(spacing: 12) {
                    if selectedMode == .cullaing {
                        albumFilterButton

                        if let album = selectedAlbum, !album.isUnsorted, !album.isFavorites {
                            sortModePicker
                                .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                        }
                    }

                    HStack(spacing: 12) {
                        if selectedMode == .cullaing {
                            timerMenu
                        }

                        Button {
                            startAction()
                        } label: {
                            Text(actionButtonLabel)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .animation(.easeInOut(duration: 0.2), value: selectedMode)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .tint(accent)

            } else if permissionDenied {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Photo access required")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Culla needs access to your photo library to organize your photos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else if noPhotosAvailable {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No photos selected")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("You've given Culla limited access but haven't selected any photos. Open Settings to choose which photos to share.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                Spacer()
            } else {
                Spacer()
                ProgressView("Loading your library...")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PhotoCarouselBackground(albumIdentifier: selectedAlbum?.collectionIdentifier) }
        .animation(.easeInOut(duration: 0.25), value: selectedMode)
        .animation(.easeIn(duration: 0.2), value: earliestDate != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedAlbum?.collectionIdentifier)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGalleries = true
                } label: {
                    Image(systemName: "rectangle.stack")
                }
                .tint(accent)
            }
            ToolbarItem(placement: .bottomBar) {
                Picker("Mode", selection: $selectedMode) {
                    Text("Cullaing").tag(CullaMode.cullaing)
                    Text("This Day").tag(CullaMode.thisDay)
                    Text("Duplicates").tag(CullaMode.duplicates)
                }
                .pickerStyle(.segmented)
            }
            if !dismissedPhotos.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Spacer()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showDismissedPhotos = true
                    } label: {
                        Image(systemName: "trash")
                            .overlay(alignment: .topTrailing) {
                                Text("\(dismissedPhotos.count)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.red, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .tint(accent)
        }
        .sheet(isPresented: $showFullCalendar) {
            calendarSheet
                .tint(accent)
        }
        .sheet(isPresented: $showAlbumPicker) {
            NavigationStack {
                AlbumPickerView(albums: albums, unsortedCount: unsortedCount, favoritesCount: favoritesCount) { album in
                    lastSelectedAlbumID = album.collectionIdentifier
                    selectedAlbum = album
                    if let earliest = photoService.earliestPhotoDate(inAlbum: album.collectionIdentifier),
                       let bound = latestDate, let floor = earliestDate {
                        pickerDate = min(max(earliest, floor), bound)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showAlbumPicker = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showDismissedPhotos) {
            NavigationStack {
                DismissedPhotosView()
            }
        }
        .task {
            let status = await photoService.requestAuthorization()
            guard status == .authorized || status == .limited else {
                permissionDenied = true
                isReady = true
                return
            }

            guard let range = photoService.photoDateRange() else {
                noPhotosAvailable = true
                isReady = true
                return
            }

            earliestDate = range.earliest
            latestDate = range.latest

            albums = photoService.fetchAlbums()
            let excludedIDs = Set(sortedPhotos.map(\.assetIdentifier))
            unsortedCount = photoService.unsortedPhotoCount(excluding: excludedIDs)
            favoritesCount = photoService.favoritesPhotoCount()
            isReady = true
        }
        .onChange(of: selectedAlbum?.collectionIdentifier) { _, newID in
            if newID != lastSelectedAlbumID {
                pickerDate = Date()
                lastSelectedAlbumID = newID ?? ""
            }
        }
    }

    // MARK: - Actions

    private func startAction() {
        Haptics.startCullaing()
        switch selectedMode {
        case .cullaing:
            selectedDate = pickerDate
            lastSelectedAlbumID = selectedAlbum?.collectionIdentifier ?? ""
        case .thisDay:
            isOnThisDay = true
            selectedDate = .now
        case .duplicates:
            showDuplicateSweep = true
        }
    }

    private var actionButtonLabel: String {
        switch selectedMode {
        case .cullaing:
            guard let focusDuration else { return "Start Cullaing" }
            let minutes = Int(focusDuration) / 60
            return "Culla for \(minutes) min"
        case .thisDay:
            return "This Day"
        case .duplicates:
            return "Sweep"
        }
    }

    // MARK: - Focus Timer Menu

    private var timerMenu: some View {
        Menu {
            ForEach([2, 5, 10], id: \.self) { minutes in
                Button {
                    focusDuration = TimeInterval(minutes * 60)
                } label: {
                    HStack {
                        Text("\(minutes) min")
                        if focusDuration == TimeInterval(minutes * 60) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if focusDuration != nil {
                Divider()
                Button("No Timer", role: .destructive) {
                    focusDuration = nil
                }
            }
        } label: {
            Image(systemName: focusDuration != nil ? "timer.circle.fill" : "timer")
                .font(.title2)
                .foregroundStyle(focusDuration != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
    }

    // MARK: - Sort Mode Picker

    private var sortModePicker: some View {
        VStack(spacing: 6) {
            Picker("Sort mode", selection: $sortMode) {
                Text("Keep in album").tag(SortMode.copy)
                Text("Move out").tag(SortMode.move)
            }
            .pickerStyle(.segmented)

            Text(sortMode == .copy
                 ? "Sorted photos stay in the source album too."
                 : "Sorted photos are removed from the source album.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: - Full Calendar Sheet

    private var calendarSheet: some View {
        NavigationStack {
            Group {
                if let earliestDate, let latestDate {
                    CalendarView(
                        selectedDate: $pickerDate,
                        earliest: earliestDate,
                        latest: latestDate,
                        albumIdentifier: selectedAlbum?.collectionIdentifier
                    )
                }
            }
            .navigationTitle("Pick a Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFullCalendar = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Album Filter Button

    private var albumFilterButton: some View {
        Button {
            showAlbumPicker = true
        } label: {
            HStack {
                Image(systemName: "rectangle.stack")
                if let selectedAlbum {
                    Text(selectedAlbum.name)
                    Spacer()
                    Button {
                        self.selectedAlbum = nil
                        self.sortMode = .copy
                        if let latest = latestDate { pickerDate = latest }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("All Photos")
                    Spacer()
                    Text("Filter by album")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

}
