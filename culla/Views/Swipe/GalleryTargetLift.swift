import SwiftUI

/// Names the panel row under the finger just above the finger, where the
/// thumb can't cover it (`target=lift` in the workshop line). Soft while the
/// row is only a candidate; filled with the gallery's colour once letting go
/// would drop the photo there.
///
/// A flat fill, not glass: it appears and moves mid-drag, and backdrop
/// effects on small shapes have bled past their corners in that situation
/// (seen in Culla Music).
struct GalleryTargetLift: View {
    let gallery: Gallery
    /// The row's colour, so the pill always matches the row it names.
    let color: Color
    let isArmed: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        HStack(spacing: 8) {
            GalleryCoverView(
                albumIdentifier: gallery.albumIdentifier,
                iconName: gallery.iconName,
                tint: color,
                size: 32,
                cornerRadius: 7
            )
            Text(gallery.name)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(isArmed ? color.labelOnSolidFill(in: colorScheme) : Color.primary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(shape.fill(isArmed ? color : Color(.secondarySystemBackground)))
        .overlay(shape.strokeBorder(Color.primary.opacity(isArmed ? 0 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 13, y: 10)
        .animation(.easeOut(duration: 0.15), value: isArmed)
        .accessibilityHidden(true)
    }
}

/// Places its one subview just above `finger`, centred on it, kept inside
/// the screen's sides and below the top safe area. A layout (not a measured
/// size in `@State`), so following the finger costs no extra render.
struct AboveFingerLayout: Layout {
    /// The finger, in this layout's own coordinates.
    var finger: CGPoint
    /// The top safe-area inset: the pill never goes under the Dynamic Island.
    var topInset: CGFloat
    /// Gap between the finger and the pill's bottom edge.
    var gap: CGFloat = 40
    /// Room kept from the screen's sides.
    var margin: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let view = subviews.first else { return }
        let maxWidth = max(bounds.width - 2 * margin, 0)
        let size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        let x = min(max(finger.x - size.width / 2, margin), max(bounds.width - size.width - margin, margin))
        let y = max(topInset + 4, finger.y - size.height - gap)
        view.place(
            at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }
}
