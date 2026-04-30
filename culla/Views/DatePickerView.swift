import SwiftUI
import SwiftData
import Photos
import PhotosUI

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
    @Environment(SubscriptionManager.self) private var subscriptions

    @State private var showPaywall = false

    @AppStorage("lastSelectedDate") private var pickerDate = Date()
    @AppStorage("lastSelectedAlbumID") private var lastSelectedAlbumID: String = ""
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("duplicateTimeWindow") private var duplicateTimeWindowSeconds: Double = 3600

    private let photoService = PhotoLibraryService.shared
    @State private var earliestDate: Date?
    @State private var latestDate: Date?
    @State private var albums: [PhoneAlbum] = []
    @State private var unsortedCount: Int = 0
    @State private var favoritesCount: Int = 0
    @State private var showAlbumPicker = false
    @State private var showFullCalendar = false
    @State private var showPhotoGrid = false
    @State private var showDismissedPhotos = false
    @State private var showSettings = false
    @State private var permissionDenied = false
    @State private var noPhotosAvailable = false
    @State private var limitedBannerDismissed = false
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
                if showCullaEyes {
                    CullaEyes()
                        .tint(accent)
                        .padding(.top, 8)
                }

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
                    .opacity(selectedMode != .duplicates ? 1 : 0)
                    .allowsHitTesting(selectedMode != .duplicates)

                    duplicateEntryButton
                        .opacity(selectedMode == .duplicates ? 1 : 0)
                        .allowsHitTesting(selectedMode == .duplicates)
                }
                .animation(.easeInOut(duration: 0.25), value: selectedMode)

                Spacer()

                // Album + sort mode + start button — anchored just above the bottom toolbar
                VStack(spacing: 12) {
                    if selectedMode == .cullaing {
                        albumFilterButton
                    }

                    if selectedMode == .thisDay {
                        sortModePicker
                            .transition(.opacity)
                    }

                    if selectedMode == .cullaing && selectedAlbum.map({ !$0.isUnsorted && !$0.isFavorites }) == true {
                        sortModePicker
                            .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                    }

                    if selectedMode != .duplicates {
                        actionButtonRow
                    }
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
        .background { PhotoCarouselBackground(albumIdentifier: selectedAlbum?.collectionIdentifier, isSharpened: selectedMode == .duplicates) }
        .animation(.easeInOut(duration: 0.25), value: selectedMode)
        .animation(.easeIn(duration: 0.2), value: earliestDate != nil)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedAlbum?.collectionIdentifier)
        .safeAreaInset(edge: .top) {
            if photoService.authorizationStatus == .limited && !limitedBannerDismissed {
                limitedAccessBanner
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
                    Image(systemName: "rectangle.stack")
                }
                .tint(accent)
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
            selectedDate = pickerDate
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

    private var actionButtonIcon: String? {
        switch selectedMode {
        case .cullaing: return nil
        case .thisDay: return "clock.arrow.circlepath"
        case .duplicates: return "doc.on.doc"
        }
    }

    @ViewBuilder
    private var actionButtonRow: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer {
                actionButtonsContent
                    .buttonStyle(.glass)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        } else {
            actionButtonsContent
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var actionButtonsContent: some View {
        HStack(spacing: 12) {
            if selectedMode == .cullaing {
                timerMenu
            }
            Button {
                startAction()
            } label: {
                HStack(spacing: 8) {
                    if let icon = actionButtonIcon {
                        Image(systemName: icon).imageScale(.medium)
                    }
                    Text(actionButtonLabel)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.primary)
            }
            .controlSize(.large)
            .animation(.easeInOut(duration: 0.2), value: selectedMode)
        }
        .tourTarget(.startButton)
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

            Text(selectedMode == .thisDay
                 ? "* Photos already sorted into other galleries will also appear here."
                 : sortMode == .copy
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showPhotoGrid = true
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFullCalendar = false }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPhotoGrid) {
                if let earliestDate, let latestDate {
                    PhotoGridPickerView(
                        albumIdentifier: selectedAlbum?.collectionIdentifier,
                        earliest: earliestDate,
                        latest: latestDate,
                        selectedDate: $pickerDate,
                        onPick: { showFullCalendar = false }
                    )
                }
            }
        }
    }

    // MARK: - Duplicate Entry Button

    private var duplicateEntryButton: some View {
        Button {
            if subscriptions.isPro {
                startAction()
            } else {
                showPaywall = true
            }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: 120, height: 120)
                    .modifier(GlassOrMaterialCircle())
                if subscriptions.isPro {
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(accent)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(accent)
                        Text("Pro")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Duplicate Time Window Slider

    private var duplicateTimeSlider: some View {
        VStack(spacing: 6) {
            Slider(value: $duplicateTimeWindowSeconds, in: 720...18000)
                .tint(accent)
            Text("Search window: \(formatTimeWindow(duplicateTimeWindowSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func formatTimeWindow(_ seconds: Double) -> String {
        if seconds < 3600 {
            return "\(Int(seconds / 60)) min"
        } else {
            let hours = seconds / 3600
            return hours == hours.rounded() ? "\(Int(hours)) hr" : String(format: "%.1f hr", hours)
        }
    }

    // MARK: - Limited Access Banner

    /// Soft banner shown when the user granted only partial photo access.
    /// We can't force full access (Apple policy), so we explain the trade-off
    /// and offer two recovery paths: add more photos, or open Settings.
    private var limitedAccessBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Limited photo access")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Culla can only see photos you've selected. Add more or grant full access for the best experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Select More") { presentLimitedPicker() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(accent)

                    Button("Settings") { openAppSettings() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                limitedBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        // Walk to the topmost presented controller — required so the picker
        // attaches above any sheet/cover currently on screen.
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // The completion handler fires whenever the picker dismisses, with the
        // newly-selected identifiers. Re-run the library load so date range,
        // albums, and the noPhotosAvailable empty-state stay in sync with the
        // user's new selection.
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in
                await loadLibrary()
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Fetches date range, albums, and counts. Resets empty/error states
    /// so the view reflects the current authorized photo set.
    @MainActor
    private func loadLibrary() async {
        guard let range = photoService.photoDateRange() else {
            earliestDate = nil
            latestDate = nil
            noPhotosAvailable = true
            isReady = true
            return
        }

        noPhotosAvailable = false
        earliestDate = range.earliest
        latestDate = range.latest

        albums = photoService.fetchAlbums()
        let excludedIDs = Set(sortedPhotos.map(\.assetIdentifier))
        unsortedCount = photoService.unsortedPhotoCount(excluding: excludedIDs)
        favoritesCount = photoService.favoritesPhotoCount()

        // Fire background pre-warm of calendar thumbnails — don't await
        let service = photoService
        let warmEarliest = range.earliest
        let warmLatest = range.latest
        Task.detached(priority: .background) {
            await service.warmCalendarCache(from: warmEarliest, to: warmLatest)
        }

        isReady = true
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
            .modifier(GlassOrQuaternaryRounded())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

}

private struct GlassOrMaterialCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: Circle())
        } else {
            content.background(Circle().fill(.ultraThinMaterial))
        }
    }
}

private struct GlassOrQuaternaryRounded: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 10))
        } else {
            content.background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
