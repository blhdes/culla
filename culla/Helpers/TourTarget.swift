import SwiftUI

/// Tour-targetable elements. Views mark themselves with `.tourTarget(_:)` and the
/// TourContainer reads their real frames via anchor preferences, so spotlights
/// always sit on the actual on-screen element regardless of iOS layout changes.
enum TourTarget: Hashable {
    case datePicker
    case galleriesButton
    case startButton
}

struct TourAnchorsKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TourTarget: Anchor<CGRect>],
        nextValue: () -> [TourTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as the target for a given tour step. The TourContainer
    /// reads the resulting anchor to position its spotlight precisely.
    func tourTarget(_ target: TourTarget) -> some View {
        anchorPreference(key: TourAnchorsKey.self, value: .bounds) { anchor in
            [target: anchor]
        }
    }
}
