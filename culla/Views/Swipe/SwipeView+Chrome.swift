import SwiftUI

// The swipe screen's floating chrome: Manage, Delete N, the speaker button,
// the first-run hints, the toast and Undo. Split out of SwipeView.swift;
// reads its state directly.
extension SwipeView {

    // MARK: - Buttons

    /// "Manage", bottom right.
    var manageButton: some View {
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

    /// "Delete N", bottom left, once something has been dismissed.
    @ViewBuilder
    func deleteButton(viewModel: SwipeViewModel) -> some View {
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

    /// Speaker, top right, only while a video card is playing. Lives here
    /// (not inside the card) so the high-priority drag gesture can't swallow
    /// its taps.
    @ViewBuilder
    func speakerButton(viewModel: SwipeViewModel) -> some View {
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

    // MARK: - Hints

    var isShowingHint: Bool {
        showSwipeHint || showSkipTooltip || showZoomTooltip
    }

    /// Onboarding hints. They disappear on the first swipe action.
    @ViewBuilder
    var hintOverlay: some View {
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

    /// Tap anywhere to dismiss the active hint. Sits above the hints but
    /// below the chrome buttons, so Manage, Delete and back stay tappable.
    @ViewBuilder
    var hintDismissLayer: some View {
        if isShowingHint {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissHints() }
        }
    }

    func dismissHints() {
        if showSwipeHint { hasSeenSwipeHint = true }
        if showSkipTooltip { hasSeenSkipTooltip = true }
        if showZoomTooltip { hasSeenZoomTooltip = true }
        withAnimation(.easeOut(duration: 0.2)) {
            showZoomTooltip = false
            showSwipeHint = false
            showSkipTooltip = false
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
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

    // MARK: - Undo

    func performUndo(viewModel: SwipeViewModel) {
        if case .skipped = viewModel.actionHistory.last {
            totalSkippedPhotos = max(0, totalSkippedPhotos - 1)
            DailyStats.upsert(in: modelContext, skippedDelta: -1)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.undo()
        }
        flashUndo()
    }

    func flashUndo() {
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

    func performBatchDelete(viewModel: SwipeViewModel) {
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
