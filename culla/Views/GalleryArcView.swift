import SwiftUI

/// Arc layout for the gallery sidebar.
///
/// Renders the standard `GallerySidebarView` (same colours, labels, swipe
/// behaviour, CGRect hit-testing) but clips the whole stack into a
/// half-ellipse whose flat side hugs the right screen edge and whose curve
/// bulges LEFT into the screen — like opening a hand of cards.
struct GalleryArcView: View {
    let galleries: [Gallery]
    let highlightedID: UUID?
    let dragProgress: CGFloat
    var isLongPress: Bool = false

    var body: some View {
        GallerySidebarView(
            galleries: galleries,
            highlightedID: highlightedID,
            dragProgress: dragProgress,
            isLongPress: isLongPress
        )
        .clipShape(FanArcShape())
    }
}

// MARK: - Fan Arc Shape

/// Half-ellipse with its diameter flush along the TRAILING (right) edge.
/// The leading side curves outward to the LEFT, peaking at `midY`.
///
/// `bulgeFraction` is the horizontal radius as a fraction of `rect.width`.
/// 0.30 = medium fan — top/bottom panels are pulled right, middle protrudes
/// 30% of the sidebar width further left than the corners.
struct FanArcShape: Shape {
    var bulgeFraction: CGFloat = 0.30

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Bézier "magic" constant for a 90° ellipse-arc approximation.
        let c: CGFloat = 0.5523
        let rx = rect.width * bulgeFraction
        let ry = rect.height / 2

        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let leftMid = CGPoint(x: rect.maxX - rx, y: rect.midY)

        path.move(to: topRight)
        // Top-left quadrant of the ellipse: topRight → leftMid.
        path.addCurve(
            to: leftMid,
            control1: CGPoint(x: rect.maxX - rx * c, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rx,     y: rect.midY - ry * c)
        )
        // Bottom-left quadrant of the ellipse: leftMid → bottomRight.
        path.addCurve(
            to: bottomRight,
            control1: CGPoint(x: rect.maxX - rx,     y: rect.midY + ry * c),
            control2: CGPoint(x: rect.maxX - rx * c, y: rect.maxY)
        )
        // closeSubpath draws the straight diameter back up the right edge.
        path.closeSubpath()
        return path
    }
}
