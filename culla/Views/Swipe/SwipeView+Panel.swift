import SwiftUI
import SwiftData

// The galleries panel's side of the swipe screen: where the panel sits, which
// row a drag points at, the checks on galleries that already hold the photo,
// and the VoiceOver actions. Split out of SwipeView.swift; reads its state
// directly.
extension SwipeView {

    // MARK: - Drag target

    /// The panel row a drag points at, whether letting go now would drop
    /// the photo there, and the release distance for this drag. Shared by
    /// the drag updates and the release, so the highlight and the drop agree.
    func panelTarget(
        of value: DragGesture.Value,
        in layout: GalleryPanelLayout
    ) -> (row: UUID?, armed: Bool, commit: CGFloat) {
        let toward = value.translation.width * panelEdge.sign
        let commit = SwipeTuning.panelCommitDistance(room: layout.roomToEdge(from: value.startLocation))
        // Highlight the row under the finger once the drag has gone far
        // enough toward the panel. No axis check: top and bottom rows
        // naturally need steep angles. A drag that starts close to the edge
        // has less room, so the highlight starts no later than its release line.
        let highlightStart = min(SwipeTuning.rowHighlightStart, commit)
        let row = toward > highlightStart ? galleryID(at: value.location, in: layout) : nil
        return (row, row != nil && toward > commit, commit)
    }

    /// Moves the highlight and the armed state, with a selection tick each
    /// time the finger lands on another row and one firmer tap when letting
    /// go would drop the photo. Writes only on change: this runs every drag tick.
    func setTarget(_ row: UUID?, armed: Bool) {
        if row != highlightedGalleryID {
            highlightedGalleryID = row
            if row != nil { Haptics.rowTick() }
        }
        if armed != isArmed {
            isArmed = armed
            if armed { Haptics.armed() }
        }
    }

    // MARK: - Panel maths

    var panelEdge: SwipePanelEdge {
        SwipePanelEdge(rawValue: panelEdgeRaw) ?? .right
    }

    /// Drag progress toward the panel, 0…1 over the release distance: the
    /// panel finishes opening where a drop would commit.
    var panelDragProgress: CGFloat {
        min(max(cardOffset.width * panelEdge.sign / SwipeTuning.panelCommitDistance, 0), 1.0)
    }

    /// Fade out UI chrome as the user drags toward galleries,
    /// so gallery names aren't blocked by buttons and labels.
    /// On long-press, fully hide chrome to spotlight the sidebar.
    var chromeOpacity: Double {
        if isLongPressing { return 0 }
        return Double(1.0 - panelDragProgress)
    }

    /// Reveal that drives the panel: the drag's, or fully open during the
    /// long-press peek. The photo docks beside the panel by the same amount.
    var panelProgress: CGFloat {
        isLongPressing ? 1.0 : panelDragProgress
    }

    var panelLayout: GalleryPanelLayout {
        GalleryPanelLayout(
            container: panelGeometry.frame,
            edge: panelEdge,
            rowCount: sidebarGalleries.count,
            progress: panelProgress
        )
    }

    /// The panel gallery under `point`. The current highlight feeds the
    /// layout's hysteresis, so a finger resting on a border doesn't flip
    /// between rows.
    func galleryID(at point: CGPoint, in layout: GalleryPanelLayout) -> UUID? {
        let galleries = sidebarGalleries
        let current = highlightedGalleryID.flatMap { id in galleries.firstIndex { $0.id == id } }
        guard let index = layout.rowIndex(at: point, current: current) else { return nil }
        return galleries.indices.contains(index) ? galleries[index].id : nil
    }

    /// The highlighted gallery and its row colour, for the pill above the finger.
    var targetGallery: (gallery: Gallery, color: Color)? {
        guard let id = highlightedGalleryID else { return nil }
        let galleries = sidebarGalleries
        guard let index = galleries.firstIndex(where: { $0.id == id }) else { return nil }
        let colors = PanelRowColors.colors(
            for: galleries,
            tintMode: sidebarTintMode,
            accent: accent,
            scheme: colorScheme
        )
        return (galleries[index], colors[index])
    }

    /// Reads which galleries already hold `identifier`. Runs once per photo
    /// (when the top card changes), never per drag frame.
    func refreshMemberships(for identifier: String?) {
        guard let identifier else {
            memberGalleryIDs = []
            return
        }
        let descriptor = FetchDescriptor<SortedPhoto>(
            predicate: #Predicate<SortedPhoto> { $0.assetIdentifier == identifier }
        )
        do {
            let records = try modelContext.fetch(descriptor)
            memberGalleryIDs = Set(records.compactMap { $0.gallery?.id })
        } catch {
            print("culla: Failed to read the galleries that hold \(identifier): \(error)")
            memberGalleryIDs = []
        }
    }

    // MARK: - VoiceOver

    /// The photo's date, so VoiceOver says which photo the actions act on.
    func photoAccessibilityLabel(viewModel: SwipeViewModel) -> Text {
        guard let date = viewModel.currentPhotoDate else { return Text(verbatim: "") }
        return Text(date, format: .dateTime.month(.wide).day().year())
    }

    /// VoiceOver actions on the card: one "Add to …" per panel gallery, then
    /// Dismiss, Favourite, Skip and Share. Each runs the same path as its
    /// gesture, daily limit included.
    func sortActions(viewModel: SwipeViewModel) -> [CardSortAction] {
        var actions = sidebarGalleries.map { gallery in
            CardSortAction(
                id: "add-\(gallery.id.uuidString)",
                name: String(localized: "Add to \(gallery.name)")
            ) {
                perform(.assign(galleryID: gallery.id), viewModel: viewModel)
            }
        }
        actions.append(CardSortAction(id: "dismiss", name: String(localized: "Dismiss")) {
            perform(.dismiss, viewModel: viewModel)
        })
        actions.append(CardSortAction(id: "favourite", name: String(localized: "Favourite")) {
            perform(.favorite, viewModel: viewModel)
        })
        actions.append(CardSortAction(id: "skip", name: String(localized: "Skip")) {
            skip(viewModel: viewModel)
        })
        actions.append(CardSortAction(id: "share", name: String(localized: "Share")) {
            perform(.share, viewModel: viewModel)
        })
        return actions
    }
}
