import SwiftUI
import SwiftData
import Photos
import Combine

struct SwipeView: View {
    let startDate: Date
    let albumIdentifier: String?
    let sortMode: SortMode
    let focusDuration: TimeInterval?
    let isOnThisDay: Bool
    @Binding var sidebarGalleryIDs: Set<UUID>
    var onBack: (() -> Void)?
    var onSessionEnd: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionManager.self) private var subscriptions
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]

    @State private var viewModel: SwipeViewModel?
    private let photoService = PhotoLibraryService.shared

    // Video playback — one player, owned by whichever card is on top
    @State private var videoPlayer = VideoCardPlayer()

    // Drag state
    @State private var cardOffset: CGSize = .zero
    @State private var highlightedGalleryID: UUID?
    @State private var galleryFrames: [UUID: CGRect] = [:]

    // Long-press preview
    @State private var isLongPressing = false

    // Sidebar gallery selection (up to 10)
    @State private var showGallerySelector = false
    /// Persisted across SwipeView re-creations so an explicit deselect-all
    /// in the Manage sheet doesn't get silently overwritten next session.
    @AppStorage("hasInitializedSidebar") private var hasInitializedSidebar = false

    // Toast state
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    // Focus session timer
    @State private var remainingSeconds: Int = 0
    @State private var timerActive: Bool = false
    @State private var showSessionSummary: Bool = false
    /// One-second tick for the focus timer. Kept in @State so it's created
    /// once: built inline in `body`, the timer was thrown away and restarted
    /// on every redraw — and dragging a card redraws every frame, so the
    /// countdown stalled whenever a finger was on the screen.
    @State private var focusTicker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Share sheet
    @State private var shareItem: ShareItem?

    // Paywall
    @State private var showPaywall = false

    // Pinch-to-zoom full screen
    @State private var isPhotoZoomed = false

    // Onboarding hints
    @AppStorage(OnboardingKey.zoomTooltipSeen) private var hasSeenZoomTooltip = false
    @AppStorage(OnboardingKey.swipeHintSeen) private var hasSeenSwipeHint = false
    @AppStorage(OnboardingKey.skipTooltipSeen) private var hasSeenSkipTooltip = false
    @State private var showZoomTooltip = false
    @State private var showSwipeHint = false
    @State private var showSkipTooltip = false

    // Undo auto-hide
    @State private var showUndo = false
    @State private var undoHideTask: Task<Void, Never>?

    // Delete state
    @State private var isDeleting = false
    @State private var deleteMessage: DeleteFeedback?
    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0
    @AppStorage("totalSkippedPhotos") private var totalSkippedPhotos = 0
    @AppStorage("totalFavouritedPhotos") private var totalFavouritedPhotos = 0

    private let swipeThreshold: CGFloat = 100
    private var maxSidebarGalleries: Int {
        subscriptions.isPro ? 10 : SubscriptionManager.freeGalleryLimit
    }

    /// Only galleries the user has selected, in display order (the query
    /// above already sorts by `displayOrder`, and filtering keeps that order).
    private var sidebarGalleries: [Gallery] {
        galleries.filter { sidebarGalleryIDs.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if let viewModel {
                if viewModel.isLoading {
                    ProgressView("Loading photos...")
                } else if viewModel.isEmpty {
                    SwipeEmptyStateView(
                        dismissedCount: viewModel.dismissedCount,
                        isDeleting: isDeleting,
                        onDelete: { performBatchDelete(viewModel: viewModel) },
                        onBack: onBack
                    )
                    .swipeTopNav(onBack: onBack)
                    .deleteFeedback($deleteMessage)
                } else {
                    swipeContent(viewModel: viewModel)
                }
            } else {
                ProgressView()
            }

        }
        .sheet(isPresented: $showGallerySelector) {
            GallerySelectionSheet(
                selectedIDs: $sidebarGalleryIDs,
                maxSelection: maxSidebarGalleries
            )
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(image: item.image, videoURL: item.videoURL, date: item.date)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(onClose: { showPaywall = false })
        }
        .task {
            subscriptions.refreshDailyCount()
            if viewModel == nil {
                let vm = SwipeViewModel(
                    photoService: photoService,
                    modelContext: modelContext,
                    startDate: startDate,
                    albumIdentifier: albumIdentifier,
                    sortMode: sortMode,
                    isOnThisDay: isOnThisDay
                )
                viewModel = vm
                await vm.loadInitialBatch()
                // onChange below misses the initial value, so kick off here too
                await videoPlayer.prepare(for: vm.currentIdentifier, service: photoService)

                if let duration = focusDuration {
                    remainingSeconds = Int(duration)
                    timerActive = true
                }

                if !vm.isEmpty {
                    try? await Task.sleep(for: .seconds(1))
                    if !hasSeenSwipeHint {
                        withAnimation { showSwipeHint = true }
                    } else if !hasSeenSkipTooltip {
                        withAnimation { showSkipTooltip = true }
                    } else if !hasSeenZoomTooltip {
                        withAnimation { showZoomTooltip = true }
                    }
                }
            }
        }
        .onReceive(focusTicker) { _ in
            guard timerActive, remainingSeconds > 0 else { return }
            remainingSeconds -= 1
            if remainingSeconds == 0 {
                timerActive = false
                showSessionSummary = true
            }
        }
        .onChange(of: viewModel?.currentIdentifier) { _, newID in
            Task { await videoPlayer.prepare(for: newID, service: photoService) }
        }
        .onDisappear {
            videoPlayer.teardown()
        }
        .onChange(of: viewModel?.actionHistory.count) { old, new in
            flashUndo()
            if (old ?? 0) == 0, (new ?? 0) > 0 {
                dismissHints()
            }
        }
        .onChange(of: galleries.count) { initializeSidebarIfNeeded() }
        .onAppear { initializeSidebarIfNeeded() }
    }

    /// On first gallery creation, auto-add galleries to the sidebar
    /// (skipped if the user already picked some).
    private func initializeSidebarIfNeeded() {
        guard !hasInitializedSidebar, !galleries.isEmpty else { return }
        if sidebarGalleryIDs.isEmpty {
            sidebarGalleryIDs = Set(galleries.prefix(maxSidebarGalleries).map(\.id))
        }
        hasInitializedSidebar = true
    }

    // MARK: - Swipe Content

    @ViewBuilder
    private func swipeContent(viewModel: SwipeViewModel) -> some View {
        GeometryReader { geo in
            // Card stack — receives drag, double-tap, and long-press gestures
            cardStack(viewModel: viewModel)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    viewModel.skipCurrent()
                    totalSkippedPhotos += 1
                    DailyStats.upsert(in: modelContext, skippedDelta: 1)
                }
                .gesture(longPressGesture)
                .highPriorityGesture(dragGesture(viewModel: viewModel))
                .simultaneousGesture(magnifyGesture)

                // Sidebar overlay — fades in + subtle slide from right
                .overlay {
                    let progress = isLongPressing ? 1.0 : rightDragProgress
                    HStack(spacing: 0) {
                        Spacer()
                        GallerySidebarView(
                            galleries: sidebarGalleries,
                            highlightedID: highlightedGalleryID,
                            dragProgress: progress,
                            isLongPress: isLongPressing
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: (1.0 - progress) * 30)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onPreferenceChange(GalleryFramePreferenceKey.self) { frames in
                        galleryFrames = frames
                    }
                }

                // Onboarding hints — disappear on first swipe action
                .overlay {
                    if showSwipeHint {
                        SwipeDirectionsHint {
                            hasSeenSwipeHint = true
                            showSwipeHint = false
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else if showSkipTooltip {
                        TooltipBubble(text: "Double-tap to skip a photo")
                            .padding(.horizontal, 48)
                            .transition(.opacity)
                    } else if showZoomTooltip {
                        TooltipBubble(text: "Pinch to zoom in or out on any photo")
                            .padding(.horizontal, 48)
                            .transition(.opacity)
                    }
                }

                // Tap anywhere to dismiss the active hint.
                // Sits above the hints overlay but below the chrome buttons,
                // so Manage / Delete / back stay tappable.
                .overlay {
                    if showSwipeHint || showSkipTooltip || showZoomTooltip {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { dismissHints() }
                    }
                }

                // "Manage" button — bottom right, tappable
                .overlay(alignment: .bottomTrailing) {
                    Button {
                        showGallerySelector = true
                    } label: {
                        Text("Manage")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                    .opacity(chromeOpacity)
                }

                // "Delete All" button — bottom left
                .overlay(alignment: .bottomLeading) {
                    if viewModel.dismissedCount > 0 {
                        Button {
                            performBatchDelete(viewModel: viewModel)
                        } label: {
                            Text("Delete \(viewModel.dismissedCount)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .disabled(isDeleting)
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                        .opacity(chromeOpacity)
                    }
                }

                // Speaker button — top right, only while a video card is playing.
                // Lives here (not inside the card) so the high-priority drag
                // gesture can't swallow its taps.
                .overlay(alignment: .topTrailing) {
                    if videoPlayer.player != nil,
                       videoPlayer.activeIdentifier == viewModel.currentIdentifier {
                        Button {
                            videoPlayer.isMuted.toggle()
                        } label: {
                            Image(systemName: videoPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3)
                                .frame(width: 24, height: 24)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                        .opacity(chromeOpacity)
                    }
                }

                // Navigation buttons (replaces toolbar so they can fade)
                .swipeTopNav(onBack: onBack, opacity: chromeOpacity)
        }
        .deleteFeedback($deleteMessage)
        // Counter + toast at top
        .overlay(alignment: .top) {
            SwipeTopStatus(
                showsFocusTimer: focusDuration != nil && timerActive,
                remainingSeconds: remainingSeconds,
                totalSeconds: Int(focusDuration ?? 0),
                processedCount: viewModel.processedCount,
                totalCount: viewModel.totalCount,
                toastMessage: toastMessage
            )
            .padding(.top, 8)
            .opacity(chromeOpacity)
            .animation(.easeInOut(duration: 0.25), value: toastMessage)
        }
        // Focus session summary
        .overlay {
            if showSessionSummary {
                SessionSummaryView(
                    durationSeconds: Int(focusDuration ?? 0),
                    reviewedCount: viewModel.processedCount,
                    sortedCount: viewModel.sessionSortedCount,
                    dismissedCount: viewModel.sessionDismissedCount,
                    galleriesCount: viewModel.sessionGalleries.count,
                    onKeepGoing: { showSessionSummary = false },
                    onDone: {
                        showSessionSummary = false
                        onSessionEnd?()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSessionSummary)
        // Photo date + undo at bottom
        .overlay(alignment: .bottom) {
            SwipeBottomBar(
                photoDate: viewModel.currentPhotoDate,
                isFavorite: viewModel.currentPhotoIsFavorite,
                showsUndo: viewModel.canUndo && showUndo,
                undoCount: viewModel.actionHistory.count,
                onDateTap: {
                    guard viewModel.canUndo else { return }
                    flashUndo()
                },
                onUndo: { performUndo(viewModel: viewModel) }
            )
            .padding(.bottom, 32)
            .opacity(chromeOpacity)
        }
    }

    // MARK: - Card Stack

    @ViewBuilder
    private func cardStack(viewModel: SwipeViewModel) -> some View {
        ZStack {
            // Next card (behind, no interaction)
            if let nextID = viewModel.nextIdentifier {
                PhotoCardView(
                    assetIdentifier: nextID,
                    photoService: photoService
                )
                .id(nextID)
                .allowsHitTesting(false)
            }

            // Opaque divider — hides next card at rest,
            // revealed as the current card drags away
            Color(.systemBackground)
                .ignoresSafeArea()

            // Current card
            if let currentID = viewModel.currentIdentifier {
                PhotoCardView(
                    assetIdentifier: currentID,
                    photoService: photoService,
                    offset: cardOffset,
                    isZoomed: isPhotoZoomed,
                    videoPlayer: videoPlayer
                )
                .id(currentID)
            }
        }
    }

    // MARK: - Long Press

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLongPressing = true
                }
            }
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onEnded { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isLongPressing = false
                }
            }
    }

    // MARK: - Gesture

    private func dragGesture(viewModel: SwipeViewModel) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                if showSwipeHint || showSkipTooltip || showZoomTooltip { dismissHints() }
                cardOffset = value.translation
                updateHighlight(
                    translation: value.translation,
                    location: value.location
                )
            }
            .onEnded { value in
                handleSwipeEnd(value, viewModel: viewModel)
            }
    }

    // MARK: - Gesture Handling

    private func updateHighlight(translation: CGSize, location: CGPoint) {
        // Highlight galleries whenever there's meaningful rightward movement.
        // No axis dominance check — top/bottom galleries naturally require
        // steep angles, and the highlight should still work.
        if translation.width > 30 {
            highlightedGalleryID = findGallery(at: location)
        } else {
            highlightedGalleryID = nil
        }
    }

    private func handleSwipeEnd(_ value: DragGesture.Value, viewModel: SwipeViewModel) {
        let tx = value.translation.width
        let ty = value.translation.height
        let ptx = value.predictedEndTranslation.width
        let pty = value.predictedEndTranslation.height

        // Right swipe with no galleries set up — guide the user to Manage
        // instead of letting the swipe silently fall through.
        if (tx > swipeThreshold || ptx > swipeThreshold), sidebarGalleries.isEmpty {
            snapBack()
            showToast(String(localized: "Add a gallery first"))
            showGallerySelector = true
            return
        }

        // Right swipe with a highlighted gallery always wins —
        // even if the angle is steep (top/bottom galleries).
        // The highlight means the finger is over a sidebar panel,
        // so the user's intent is clear.
        if tx > swipeThreshold || ptx > swipeThreshold,
           let id = highlightedGalleryID,
           let gallery = sidebarGalleries.first(where: { $0.id == id }) {
            if subscriptions.hasReachedDailyLimit {
                snapBack()
                showPaywall = true
                return
            }
            flyOff(x: 500) {
                viewModel.assignToGallery(gallery)
                subscriptions.recordSwipe()
                Haptics.swipeRight()
                showToast("\u{2192} \(gallery.name)")
            }
            return
        }

        // Vertical swipe: primary axis is vertical
        if abs(ty) > abs(tx) {
            // Swipe UP → favorite
            if ty < -swipeThreshold || pty < -swipeThreshold {
                snapBack()
                Task {
                    guard let identifier = viewModel.currentIdentifier else { return }
                    let isFavorite = await photoService.toggleFavorite(identifier: identifier)
                    viewModel.currentPhotoIsFavorite = isFavorite
                    Haptics.swipeUp()
                    if isFavorite {
                        totalFavouritedPhotos += 1
                        DailyStats.upsert(in: modelContext, favouritedDelta: 1)
                    } else {
                        totalFavouritedPhotos = max(0, totalFavouritedPhotos - 1)
                        DailyStats.upsert(in: modelContext, favouritedDelta: -1)
                    }
                    showToast(isFavorite ? String(localized: "Favorited ♥") : String(localized: "Unfavorited"))
                }
                return
            }
            // Swipe DOWN → share
            if ty > swipeThreshold || pty > swipeThreshold {
                Haptics.swipeDown()
                snapBack()
                Task {
                    guard let identifier = viewModel.currentIdentifier else { return }
                    // Read now: after the loads below, the stack may have moved on.
                    let date = viewModel.currentPhotoDate
                    let screenSize = UIScreen.main.bounds.size
                    let targetSize = CGSize(width: screenSize.width * 2, height: screenSize.height * 2)
                    // nil for images and for iCloud-only videos without a local file —
                    // those fall back to sharing the poster frame below.
                    let videoURL = await photoService.loadVideoURL(for: identifier)
                    if let image = await photoService.loadImage(for: identifier, targetSize: targetSize) {
                        shareItem = ShareItem(image: image, videoURL: videoURL, date: date)
                    }
                }
                return
            }
        }

        // Left swipe: dismiss if actual OR predicted distance exceeds threshold
        if tx < -swipeThreshold || ptx < -swipeThreshold {
            if subscriptions.hasReachedDailyLimit {
                snapBack()
                showPaywall = true
                return
            }
            flyOff(x: -500) {
                viewModel.dismissCurrent()
                subscriptions.recordSwipe()
                Haptics.swipeLeft()
                showToast(String(localized: "Dismissed"))
            }
            return
        }

        // Below threshold and no gallery → snap back
        snapBack()
    }

    private func flyOff(x: CGFloat, y: CGFloat = 0, action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.25)) {
            cardOffset = CGSize(width: x, height: y)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            cardOffset = .zero
            highlightedGalleryID = nil
            isLongPressing = false
            action()
        }
    }

    private func snapBack() {
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 15)) {
            cardOffset = .zero
        }
        highlightedGalleryID = nil
        isLongPressing = false
    }

    // MARK: - Pinch to Zoom

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.3 && !isPhotoZoomed {
                    isPhotoZoomed = true
                } else if value.magnification < 0.8 && isPhotoZoomed {
                    isPhotoZoomed = false
                }
            }
    }

    // MARK: - Toast

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    toastMessage = nil
                }
            }
        }
    }

    // MARK: - Helpers

    private var rightDragProgress: CGFloat {
        min(max(cardOffset.width / swipeThreshold, 0), 1.0)
    }

    /// Fade out UI chrome as the user drags toward galleries,
    /// so gallery names aren't blocked by buttons and labels.
    /// On long-press, fully hide chrome to spotlight the sidebar.
    private var chromeOpacity: Double {
        if isLongPressing { return 0 }
        return Double(1.0 - rightDragProgress)
    }

    private func findGallery(at point: CGPoint) -> UUID? {
        for (id, frame) in galleryFrames {
            if point.x >= frame.minX && point.x <= frame.maxX &&
               point.y >= frame.minY && point.y <= frame.maxY {
                return id
            }
        }
        return nil
    }

    // MARK: - Undo

    private func performUndo(viewModel: SwipeViewModel) {
        if case .skipped = viewModel.actionHistory.last {
            totalSkippedPhotos = max(0, totalSkippedPhotos - 1)
            DailyStats.upsert(in: modelContext, skippedDelta: -1)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.undo()
        }
        flashUndo()
    }

    private func dismissHints() {
        if showSwipeHint { hasSeenSwipeHint = true }
        if showSkipTooltip { hasSeenSkipTooltip = true }
        if showZoomTooltip { hasSeenZoomTooltip = true }
        withAnimation(.easeOut(duration: 0.2)) {
            showZoomTooltip = false
            showSwipeHint = false
            showSkipTooltip = false
        }
    }

    private func flashUndo() {
        undoHideTask?.cancel()
        withAnimation(.spring) { showUndo = true }
        undoHideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) { showUndo = false }
            }
        }
    }

    // MARK: - Batch Delete

    private func performBatchDelete(viewModel: SwipeViewModel) {
        isDeleting = true
        Task {
            let count = await viewModel.batchDeleteDismissed()
            await MainActor.run {
                isDeleting = false
                if count > 0 {
                    totalDeletedPhotos += count
                    DailyStats.upsert(in: modelContext, deletedDelta: count)
                    // The .deleteFeedback modifier hides this again by itself.
                    deleteMessage = DeleteFeedback(
                        sessionCount: count,
                        totalCount: totalDeletedPhotos
                    )
                }
            }
        }
    }
}
