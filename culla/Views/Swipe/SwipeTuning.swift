import CoreGraphics

/// Every distance the swipe screen reacts to, in one place. Before this the
/// commit distance was declared in both `SwipeView` and `PhotoCardView`, and
/// "the start of a drag toward the galleries" was 30 pt in one place and
/// `> 0` in another. Values from the 26 Nov workshop:
/// `edges=right,left panel=0.80 rows=full target=lift marks=check armed=fill idle=soft photo=dock release=50`.
enum SwipeTuning {
    /// Favourite, Share and Dismiss commit once the drag, or its predicted
    /// end, passes this. A fling toward the panel uses it too.
    static let commitDistance: CGFloat = 70
    /// Release distance toward the panel: a drop commits past it, and the
    /// panel finishes opening at the same point.
    static let panelCommitDistance: CGFloat = 50
    /// A drag toward the panel starts highlighting the row under the finger
    /// past this. It is also the gate for "the panel claims the drag", so an
    /// up or down swipe that drifts a few points sideways still favourites
    /// or shares.
    static let rowHighlightStart: CGFloat = 30
    /// Panel width as a share of the screen width.
    static let panelWidthFraction: CGFloat = 0.80
    /// How far past its edge the hidden panel waits; it slides in over this distance.
    static let panelSlideDistance: CGFloat = 80
    /// The finger must go this far past a row's border before the highlight
    /// moves to the next row, so a finger resting on a border doesn't flicker.
    static let rowHysteresis: CGFloat = 10

    /// Release distance toward the panel for a drag that started `room`
    /// points from the panel's edge. A slow drag that starts close to the
    /// edge (where a thumb rests) can't travel the full distance before the
    /// screen runs out, so it shrinks to 80 % of the room left.
    static func panelCommitDistance(room: CGFloat) -> CGFloat {
        min(panelCommitDistance, max(room, 0) * 0.8)
    }

    // MARK: Photo docking

    /// Share of the drag the card still travels once the panel is fully open.
    /// The card barely moves; the photo docks in the free strip instead.
    static let dockedCardTravel: CGFloat = 0.15
    /// Room kept around the docked photo inside the free strip.
    static let dockInset: CGFloat = 20
    /// The docked photo never shrinks below this scale.
    static let dockMinScale: CGFloat = 0.2
}
