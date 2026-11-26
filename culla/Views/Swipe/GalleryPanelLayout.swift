import SwiftUI

/// Where the galleries panel and each of its rows sit on screen, worked out
/// with plain maths. Rows used to measure themselves with a `GeometryReader`
/// and report their frames up, which made the swipe screen render twice per
/// drag frame. The panel now draws its rows at `rowHeight`, and the drag
/// hit-tests with `rowIndex(at:)`, so what you see and what you hit share
/// one source.
///
/// Global (screen) coordinates, the same space as the card's drag gesture.
struct GalleryPanelLayout {
    /// The full-screen area the panel lives in (safe area ignored). Measured
    /// once from the panel's container, which doesn't move with the drag.
    let container: CGRect
    let rowCount: Int
    /// 0 = parked past its edge, 1 = fully revealed (or long-press peek).
    let progress: CGFloat

    var panelWidth: CGFloat { container.width * SwipeTuning.panelWidthFraction }

    /// How far the panel still sits past its resting position.
    var slideOffset: CGFloat { (1 - progress) * SwipeTuning.panelSlideDistance }

    /// Rows split the full height evenly.
    var rowHeight: CGFloat {
        rowCount > 0 ? container.height / CGFloat(rowCount) : 0
    }

    var panelRect: CGRect {
        CGRect(
            x: container.maxX - panelWidth + slideOffset,
            y: container.minY,
            width: panelWidth,
            height: container.height
        )
    }

    /// The row under `point`, or nil when it's outside the panel.
    func rowIndex(at point: CGPoint) -> Int? {
        guard rowCount > 0, rowHeight > 0 else { return nil }
        let rect = panelRect
        guard point.x >= rect.minX, point.x <= rect.maxX,
              point.y >= rect.minY, point.y <= rect.maxY else { return nil }
        return min(max(Int((point.y - rect.minY) / rowHeight), 0), rowCount - 1)
    }
}

/// What `SwipeView` measures once from the panel's full-screen container.
nonisolated struct PanelGeometry: Equatable, Sendable {
    var frame: CGRect = .zero
}
