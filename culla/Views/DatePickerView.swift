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

    @State private var showPaywall = false

    @AppStorage("lastSelectedDate") private var pickerDate = Date()
    @AppStorage("lastSelectedAlbumID") private var lastSelectedAlbumID: String = ""
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("includeVideos") private var includeVideos = true
    @AppStorage(OnboardingKey.walkthroughComplete) private var hasCompletedWalkthrough = false

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
    /// The running calendar warm-up, so a newer one can replace it.
    @State private var warmUpTask: Task<Void, Never>?

    /// True while a sheet covers the home screen. The moving background then
    /// stops drawing frames nobody can see, which saves battery. (The photo
    /// grid opens from inside the calendar sheet, so the calendar covers it.)
    private var isCoveredBySheet: Bool {
        showSettings || showFullCalendar || showAlbumPicker
            || showDismissedPhotos || showPaywall || showGalleries
    }
    @State private var permissionDenied = false
    @State private var noPhotosAvailable = false
    @State private var limitedBannerDismissed = false
    /// Exact date of the photo last tapped in the photo grid. Lets a session start at
    /// that very photo instead of at the beginning of its day.
    @State private var pickedPhotoDate: Date?

    private var pickerIsToday: Bool {
        guard let earliest = earliestDate, let latest = latestDate else { return true }
        let target = min(max(Date.now, earliest), latest)
        return Calendar.current.isDate(pickerDate, inSameDayAs: target)
    }

    @Query(filter: #Predicate<SortedPhoto> { !$0.isImported }) private var sortedPhotos: [SortedPhoto]
    @Query private var dismissedPhotos: [DismissedPhoto]

    var body: some View {
        VStack(spacing: 28) {
            if let earliestDate, let latestDate {
                // MARK: - CULLA EYES HIDDEN — restore in vNext
                // if showCullaEyes {
                //     CullaEyes()
                //         .tint(accent)
                //         .padding(.top, 8)
                // }

                Spacer()

                ZStack {
                    VStack(spacing: 12) {
                        DatePicker(
                            "Date",
                            selection: $pickerDate,
                            in: earliestDate...latestDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .tint(accent)
                        .onChange(of: pickerDate) { Haptics.dateWheelTick() }
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    showFullCalendar = true
                                }
                        )
                        .tourTarget(.datePicker)

                        Button {
                            let today = Date.now
                            pickerDate = min(max(today, earliestDate), latestDate)
                        } label: {
                            Label("Today", systemImage: "play.fill")
                                .font(.subheadline)
                        }
                        .opacity(pickerIsToday ? 0 : 1)
                        .allowsHitTesting(!pickerIsToday)
                        .animation(.easeInOut(duration: 0.25), value: pickerIsToday)
                    }
                    .opacity(selectedMode == .cullaing ? 1 : 0)
                    .allowsHitTesting(selectedMode == .cullaing)

                    thisDayHeader
                        .opacity(selectedMode == .thisDay ? 1 : 0)
                        .allowsHitTesting(false)

                    HomeDuplicateEntryButton(
                        onStart: { startAction() },
                        onLocked: { showPaywall = true }
                    )
                    .opacity(selectedMode == .duplicates ? 1 : 0)
                    .allowsHitTesting(selectedMode == .duplicates)
                }
                .animation(.easeInOut(duration: 0.25), value: selectedMode)

                Spacer()

                // Album + sort mode + start button — anchored just above the bottom toolbar
                VStack(spacing: 12) {
                    if selectedMode == .cullaing {
                        HomeAlbumFilterButton(
                            selectedAlbum: selectedAlbum,
                            onTap: { showAlbumPicker = true },
                            onClear: {
                                selectedAlbum = nil
                                sortMode = .copy
                                if let latest = self.latestDate { pickerDate = latest }
                            }
                        )
                    }

                    if selectedMode == .thisDay {
                        Text("Photos already sorted into galleries also appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }

                    if selectedMode == .cullaing && selectedAlbum.map({ !$0.isUnsorted && !$0.isFavorites }) == true {
                        sortModePicker
                            .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                    }

                    if selectedMode != .duplicates {
                        HomeActionButtons(
                            selectedMode: selectedMode,
                            focusDuration: $focusDuration,
                            onStart: { startAction() }
                        )
                    }
                }
                .tint(accent)

            } else if permissionDenied {
                Spacer()
                HomePhotoAccessMessage(
                    title: "Photo access required",
                    message: "Culla needs access to your photo library to organize your photos."
                )
                Spacer()
            } else if noPhotosAvailable {
                Spacer()
                HomePhotoAccessMessage(
                    title: "No photos selected",
                    message: "You've given Culla limited access but haven't selected any photos. Open Settings to choose which photos to share."
                )
                Spacer()
            } else {
                Spacer()
                ProgressView("Loading your library...")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PhotoCarouselBackground(
                albumIdentifier: selectedAlbum?.collectionIdentifier,
                isPaused: isCoveredBySheet,
                isSharpened: selectedMode == .duplicates
            )
        }
        .animation(.easeInOut(duration: 0.25), value: selectedMode)
        .animation(.easeIn(duration: 0.2), value: earliestDate != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedAlbum?.collectionIdentifier)
        .safeAreaInset(edge: .top) {
            if photoService.authorizationStatus == .limited && !limitedBannerDismissed {
                HomeLimitedAccessBanner(
                    onSelectionChanged: { await loadLibrary() },
                    onDismiss: { limitedBannerDismissed = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: limitedBannerDismissed)
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
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(accent)
                        Text("Galleries")
                            .foregroundStyle(.primary)
                    }
                }
                .tourTarget(.galleriesButton)
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
            HomeCalendarSheet(
                selectedDate: $pickerDate,
                earliest: earliestDate,
                latest: latestDate,
                albumIdentifier: selectedAlbum?.collectionIdentifier,
                onPhotoPicked: { photoDate in
                    pickedPhotoDate = photoDate
                    showFullCalendar = false
                },
                onDone: { showFullCalendar = false }
            )
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
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(onClose: { showPaywall = false })
        }
        .task {
            let status = await photoService.requestAuthorization()
            guard status == .authorized || status == .limited else {
                permissionDenied = true
                isReady = true
                return
            }
            await loadLibrary()
        }
        .onAppear {
            ReviewManager.shared.checkAndRequestReview(sortedCount: sortedPhotos.count)
        }
        .onChange(of: selectedAlbum?.collectionIdentifier) { _, newID in
            if newID != lastSelectedAlbumID {
                pickerDate = newID == nil ? (latestDate ?? Date()) : Date()
                lastSelectedAlbumID = newID ?? ""
            }
        }
        .onChange(of: includeVideos) {
            Task { await loadLibrary() }
        }
        .onChange(of: hasCompletedWalkthrough) { _, done in
            if done { scheduleCalendarWarmUp() }
        }
    }

    // MARK: - Actions

    private func startAction() {
        Haptics.startCullaing()
        switch selectedMode {
        case .cullaing:
            selectedDate = sessionStartDate
            lastSelectedAlbumID = selectedAlbum?.collectionIdentifier ?? ""
        case .thisDay:
            isOnThisDay = true
            selectedDate = pickerDate
        case .duplicates:
            showDuplicateSweep = true
        }
    }

    /// Where a Cullaing session begins. A photo picked in the grid starts at that exact
    /// photo; every other choice (wheel, calendar, Today, defaults) starts at midnight of
    /// that day, so the whole day is included rather than only photos after a clock time.
    private var sessionStartDate: Date {
        // `pickerDate` is persisted, so allow sub-second drift when comparing.
        if let pickedPhotoDate, abs(pickerDate.timeIntervalSince(pickedPhotoDate)) < 1 {
            return pickedPhotoDate
        }
        return Calendar.current.startOfDay(for: pickerDate)
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

    // MARK: - This Day Header

    /// This Day always looks at today's date in past years, so it shows that
    /// date where Cullaing shows the wheel.
    private var thisDayHeader: some View {
        VStack(spacing: 8) {
            Text(Date.now, format: .dateTime.day().month(.wide))
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Photos from this day in past years")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }

    // MARK: - Library Loading

    /// Fetches date range, albums, and counts. Resets empty/error states
    /// so the view reflects the current authorized photo set.
    /// The home screen shows as soon as the date range is known. Albums and
    /// counts only feed the album picker, so they load afterwards.
    @MainActor
    private func loadLibrary() async {
        let service = photoService
        // PhotoKit can be slow the first time it is asked. Keep it off the main thread.
        let range = await Task.detached(priority: .userInitiated) {
            service.photoDateRange()
        }.value

        guard let range else {
            earliestDate = nil
            latestDate = nil
            noPhotosAvailable = true
            isReady = true
            return
        }

        noPhotosAvailable = false
        earliestDate = range.earliest
        latestDate = range.latest
        isReady = true

        // Albums and counts only feed the album picker. Load them once the screen is up.
        let excludedIDs = Set(sortedPhotos.map(\.assetIdentifier))
        let extras = await Task.detached(priority: .utility) {
            (albums: service.fetchAlbums(),
             unsorted: service.unsortedPhotoCount(excluding: excludedIDs),
             favorites: service.favoritesPhotoCount())
        }.value
        albums = extras.albums
        unsortedCount = extras.unsorted
        favoritesCount = extras.favorites

        scheduleCalendarWarmUp()
    }

    /// Fills the calendar thumbnail cache in the background. It waits a moment so the
    /// home screen can settle, and it never runs while the first-launch tour is showing:
    /// on a fresh install it has thousands of thumbnails to make, which made the tour stutter.
    private func scheduleCalendarWarmUp() {
        guard hasCompletedWalkthrough, let earliest = earliestDate, let latest = latestDate else { return }
        warmUpTask?.cancel()
        let service = photoService
        warmUpTask = Task.detached(priority: .background) {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await service.warmCalendarCache(from: earliest, to: latest)
        }
    }
}
