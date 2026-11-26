import SwiftUI

/// Where the galleries panel and each of its rows sit on screen, worked out
/// with plain maths. Rows used to measure themselves with a `GeometryReader`
/// and report their frames up, which made the swipe screen render twice per
/// drag frame. The panel now draws its rows at `rowHeight`, and the drag
/// hit-tests with `rowIndex(at:current:)`, so what you see and what you hit
/// share one source.
///
/// Global (screen) coordinates, the same space as the card's drag gesture.
struct GalleryPanelLayout {
    /// The full-screen area the panel lives in (safe area ignored). Measured
    /// once from the panel's container, which doesn't move with the drag.
    let container: CGRect
    let edge: SwipePanelEdge
    let rowCount: Int
    /// 0 = parked past its edge, 1 = fully revealed (or long-press peek).
    let progress: CGFloat

    var panelWidth: CGFloat { container.width * SwipeTuning.panelWidthFraction }

    /// Signed distance the panel still sits past its resting position
    /// (positive = to the right).
    var slideOffset: CGFloat { edge.sign * (1 - progress) * SwipeTuning.panelSlideDistance }

    /// Rows split the full height evenly (`rows=full` in the workshop line:
    /// with 8 or more galleries the first row sits under the Dynamic Island,
    /// and its hit area runs to the screen's top edge).
    var rowHeight: CGFloat {
        rowCount > 0 ? container.height / CGFloat(rowCount) : 0
    }

    var panelRect: CGRect {
        let x = edge == .right
            ? container.maxX - panelWidth + slideOffset
            : container.minX + slideOffset
        return CGRect(x: x, y: container.minY, width: panelWidth, height: container.height)
    }

    /// True when the panel has claimed the drag: it is revealed, the finger
    /// is over it, and the drag has gone past `rowHighlightStart` toward it
    /// (`toward`). The distance gate is essential: the panel covers 80 % of
    /// the width and reveals with no dead zone, so without it an up-swipe
    /// that drifts a few points sideways would land "in the panel" and snap
    /// back instead of favouriting. Only the horizontal position counts.
    func isInPanel(_ point: CGPoint, toward: CGFloat) -> Bool {
        guard rowCount > 0, progress > 0, toward > SwipeTuning.rowHighlightStart else { return false }
        let rect = panelRect
        return edge == .right ? point.x >= rect.minX : point.x <= rect.maxX
    }

    /// The row under `point`, or nil when it's outside the panel. Above the
    /// first row or below the last one still counts as that row. `current`
    /// adds hysteresis: the highlight only leaves it once the finger is
    /// `rowHysteresis` past its border.
    func rowIndex(at point: CGPoint, current: Int?) -> Int? {
        guard rowCount > 0, rowHeight > 0 else { return nil }
        let rect = panelRect
        guard point.x >= rect.minX, point.x <= rect.maxX else { return nil }
        let raw = min(max(Int((point.y - rect.minY) / rowHeight), 0), rowCount - 1)
        guard let current, current != raw, (0..<rowCount).contains(current) else { return raw }
        let top = rect.minY + CGFloat(current) * rowHeight
        let bottom = top + rowHeight
        let pastBorder = point.y < top - SwipeTuning.rowHysteresis
            || point.y > bottom + SwipeTuning.rowHysteresis
        return pastBorder ? raw : current
    }

    /// Distance from `point` to the screen edge the panel comes from.
    func roomToEdge(from point: CGPoint) -> CGFloat {
        edge == .right ? container.maxX - point.x : point.x - container.minX
    }
}

/// What `SwipeView` measures once from the panel's full-screen container.
nonisolated struct PanelGeometry: Equatable, Sendable {
    var frame: CGRect = .zero
}
