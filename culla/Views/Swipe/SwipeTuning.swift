import CoreGraphics

/// Every distance the swipe screen reacts to, in one place. Before this the
/// commit distance was declared in both `SwipeView` and `PhotoCardView`, and
/// "the start of a drag toward the galleries" was 30 pt in one place and
/// `> 0` in another.
enum SwipeTuning {
    /// Favourite, Share and Dismiss commit once the drag, or its predicted
    /// end, passes this.
    static let commitDistance: CGFloat = 100
    /// A drag toward the panel starts highlighting the row under the finger past this.
    static let rowHighlightStart: CGFloat = 30
    /// Panel width as a share of the screen width.
    static let panelWidthFraction: CGFloat = 0.80
    /// How far past its edge the hidden panel waits; it slides in over this distance.
    static let panelSlideDistance: CGFloat = 80
    /// The finger must go this far past a row's border before the highlight
    /// moves to the next row, so a finger resting on a border doesn't flicker.
    static let rowHysteresis: CGFloat = 10

    // MARK: Photo docking

    /// Share of the drag the card still travels once the panel is fully open.
    static let dockedCardTravel: CGFloat = 0.15
    /// Room kept around the docked photo inside the free strip.
    static let dockInset: CGFloat = 20
    /// The docked photo never shrinks below this scale.
    static let dockMinScale: CGFloat = 0.2
}
