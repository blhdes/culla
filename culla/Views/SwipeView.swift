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

    @Environment(\.modelContext) var modelContext
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.appAccent) var accent
    @Environment(\.colorScheme) var colorScheme
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]

    @State private var viewModel: SwipeViewModel?
    private let photoService = PhotoLibraryService.shared

    // Video playback — one player, owned by whichever card is on top
    @State var videoPlayer = VideoCardPlayer()

    // Drag state
    @State var cardOffset: CGSize = .zero
    @State var highlightedGalleryID: UUID?
    /// The highlighted row is armed: releasing now drops the photo there.
    @State var isArmed = false
    /// Where the finger is during a drag, for the target pill above it.
    @State var fingerLocation: CGPoint?
    /// The top card is fading into a gallery (see `flyOff`).
    @State private var isDropping = false
    /// Galleries the current photo is already in, read once per photo.
    /// Their panel rows show a check.
    @State var memberGalleryIDs: Set<UUID> = []
    /// Screen rect of the panel's full-screen container. Measured once; it
    /// doesn't move with the drag. Feeds `panelLayout`.
    @State var panelGeometry = PanelGeometry()

    // Long-press preview
    @State var isLongPressing = false

    // Sidebar gallery selection (up to 10)
    @State var showGallerySelector = false
    /// Persisted across SwipeView re-creations so an explicit deselect-all
    /// in the Manage sheet doesn't get silently overwritten next session.
    @AppStorage("hasInitializedSidebar") private var hasInitializedSidebar = false
    /// Settings → Galleries panel. Dismiss takes the other side.
    @AppStorage(SwipePanelEdge.storageKey) var panelEdgeRaw = SwipePanelEdge.right.rawValue
    @AppStorage("sidebarTintMode") var sidebarTintMode = "gallery"

    // Toast state
    @State var toastMessage: String?
    @State var toastTask: Task<Void, Never>?

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
    @AppStorage(OnboardingKey.zoomTooltipSeen) var hasSeenZoomTooltip = false
    @AppStorage(OnboardingKey.swipeHintSeen) var hasSeenSwipeHint = false
    @AppStorage(OnboardingKey.skipTooltipSeen) var hasSeenSkipTooltip = false
    @State var showZoomTooltip = false
    @State var showSwipeHint = false
    @State var showSkipTooltip = false

    // Undo auto-hide
    @State var showUndo = false
    @State var undoHideTask: Task<Void, Never>?

    // Delete state
    @State var isDeleting = false
    @State var deleteMessage: DeleteFeedback?
    @AppStorage("totalDeletedPhotos") var totalDeletedPhotos = 0
    @AppStorage("totalSkippedPhotos") var totalSkippedPhotos = 0
    @AppStorage("totalFavouritedPhotos") private var totalFavouritedPhotos = 0

    private var maxSidebarGalleries: Int {
        subscriptions.isPro ? 10 : SubscriptionManager.freeGalleryLimit
    }

    /// Only galleries the user has selected, in display order (the query
    /// above already sorts by `displayOrder`, and filtering keeps that order).
    var sidebarGalleries: [Gallery] {
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
                refreshMemberships(for: vm.currentIdentifier)

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
            refreshMemberships(for: newID)
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
                .onTapGesture(count: 2) { skip(viewModel: viewModel) }
                .gesture(longPressGesture)
                .highPriorityGesture(dragGesture(viewModel: viewModel))
                .simultaneousGesture(magnifyGesture)

                // Galleries panel: fades in and slides in from the side
                // picked in Settings
                .overlay {
                    let layout = panelLayout
                    GallerySidebarView(
                        galleries: sidebarGalleries,
                        highlightedID: highlightedGalleryID,
                        isArmed: isArmed,
                        dragProgress: layout.progress,
                        isLongPress: isLongPressing,
                        rowHeight: layout.rowHeight,
                        memberIDs: memberGalleryIDs
                    )
                    .frame(width: layout.panelWidth)
                    .offset(x: layout.slideOffset)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: layout.edge == .right ? .trailing : .leading
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .onGeometryChange(for: PanelGeometry.self) { proxy in
                        PanelGeometry(frame: proxy.frame(in: .global))
                    } action: { geometry in
                        panelGeometry = geometry
                    }
                }
                .overlay { hintOverlay }
                .overlay { hintDismissLayer }
                .overlay(alignment: .bottomTrailing) { manageButton }
                .overlay(alignment: .bottomLeading) { deleteButton(viewModel: viewModel) }
                .overlay(alignment: .topTrailing) { speakerButton(viewModel: viewModel) }

                // Navigation buttons (replaces toolbar so they can fade)
                .swipeTopNav(onBack: onBack, opacity: chromeOpacity)

                // The row under the finger, named just above it where the
                // thumb can't cover it.
                .overlay {
                    ZStack {
                        if let target = targetGallery, let finger = fingerLocation {
                            let origin = panelGeometry.frame.origin
                            AboveFingerLayout(
                                finger: CGPoint(x: finger.x - origin.x, y: finger.y - origin.y),
                                topInset: geo.safeAreaInsets.top
                            ) {
                                GalleryTargetLift(
                                    gallery: target.gallery,
                                    color: target.color,
                                    isArmed: isArmed
                                )
                            }
                            .transition(.opacity)
                        }
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    // Scoped to the pill: on the outer chain it would also
                    // animate the card's drag offset in the same transaction.
                    .animation(.easeOut(duration: 0.15), value: highlightedGalleryID)
                }
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
                // Only the top card is offered to VoiceOver, with its actions.
                .accessibilityHidden(true)
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
                    videoPlayer: videoPlayer,
                    panelEdge: panelEdge,
                    dockProgress: panelProgress
                )
                .opacity(isDropping ? 0 : 1)
                .id(currentID)
                // VoiceOver sorts from the card's Actions rotor instead of a drag.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(photoAccessibilityLabel(viewModel: viewModel))
                .accessibilityAddTraits(.isImage)
                .accessibilityActions {
                    ForEach(sortActions(viewModel: viewModel)) { action in
                        Button(action.name, action: action.perform)
                    }
                }
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
                if isShowingHint { dismissHints() }
                cardOffset = value.translation
                fingerLocation = value.location
                let target = panelTarget(of: value, in: panelLayout)
                setTarget(target.row, armed: target.armed)
            }
            .onEnded { value in
                handleSwipeEnd(value, viewModel: viewModel)
            }
    }

    // MARK: - Gesture Handling

    private func handleSwipeEnd(_ value: DragGesture.Value, viewModel: SwipeViewModel) {
        let layout = panelLayout
        let target = panelTarget(of: value, in: layout)
        let toward = value.translation.width * panelEdge.sign
        let outcome = SwipeResolver.resolve(SwipeRelease(
            edge: panelEdge,
            translation: value.translation,
            predictedTranslation: value.predictedEndTranslation,
            isInPanel: layout.isInPanel(value.location, toward: toward),
            galleryUnderFinger: target.row,
            highlightedGallery: highlightedGalleryID,
            panelIsEmpty: sidebarGalleries.isEmpty,
            panelCommit: target.commit
        ))
        perform(outcome, viewModel: viewModel)
    }

    /// Turns the resolver's decision into motion, haptics and the view-model
    /// call. The daily limit is checked here, before a sort or a dismiss.
    func perform(_ outcome: SwipeOutcome, viewModel: SwipeViewModel) {
        switch outcome {
        case .assign(let id):
            guard let gallery = sidebarGalleries.first(where: { $0.id == id }) else {
                snapBack()
                return
            }
            if subscriptions.hasReachedDailyLimit {
                snapBack()
                showPaywall = true
                return
            }
            flyOff(x: 500 * panelEdge.sign, dropping: true) {
                let change = viewModel.assignToGallery(gallery)
                subscriptions.recordSwipe()
                Haptics.swipeRight()
                switch change {
                case .some(.unchanged), .some(.confirmedImport):
                    // Already there (a check on its row): nothing new is added
                    // to the album, and Undo still brings the photo back.
                    showToast(String(localized: "Already in \(gallery.name)"))
                default:
                    let arrow = panelEdge == .right ? "\u{2192}" : "\u{2190}"
                    showToast("\(arrow) \(gallery.name)")
                }
            }

        case .dismiss:
            if subscriptions.hasReachedDailyLimit {
                snapBack()
                showPaywall = true
                return
            }
            flyOff(x: -500 * panelEdge.sign) {
                viewModel.dismissCurrent()
                subscriptions.recordSwipe()
                Haptics.swipeLeft()
                showToast(String(localized: "Dismissed"))
            }

        case .favorite:
            snapBack()
            toggleFavorite(viewModel: viewModel)

        case .share:
            Haptics.swipeDown()
            snapBack()
            presentShare(viewModel: viewModel)

        case .openManage:
            snapBack()
            showToast(String(localized: "Add a gallery first"))
            showGallerySelector = true

        case .snapBack:
            snapBack()
        }
    }

    /// Double-tap: skip without dismissing — it will reappear next session.
    func skip(viewModel: SwipeViewModel) {
        viewModel.skipCurrent()
        totalSkippedPhotos += 1
        DailyStats.upsert(in: modelContext, skippedDelta: 1)
    }

    private func toggleFavorite(viewModel: SwipeViewModel) {
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
    }

    private func presentShare(viewModel: SwipeViewModel) {
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
    }

    /// `dropping`: the photo goes into a gallery. Docked beside the panel it
    /// barely moves with the offset, so it fades out instead.
    private func flyOff(x: CGFloat, y: CGFloat = 0, dropping: Bool = false, action: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.25)) {
            cardOffset = CGSize(width: x, height: y)
            if dropping { isDropping = true }
        }
        fingerLocation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            cardOffset = .zero
            isDropping = false
            highlightedGalleryID = nil
            isArmed = false
            isLongPressing = false
            action()
        }
    }

    private func snapBack() {
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 15)) {
            cardOffset = .zero
        }
        highlightedGalleryID = nil
        isArmed = false
        fingerLocation = nil
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
}
