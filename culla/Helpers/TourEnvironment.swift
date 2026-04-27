import SwiftUI

private struct ActiveTourStepKey: EnvironmentKey {
    static let defaultValue: TourStep? = nil
}

private struct TourAdvanceKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var activeTourStep: TourStep? {
        get { self[ActiveTourStepKey.self] }
        set { self[ActiveTourStepKey.self] = newValue }
    }

    /// Call to advance the tour to the next step from anywhere in the hierarchy.
    var tourAdvance: (() -> Void)? {
        get { self[TourAdvanceKey.self] }
        set { self[TourAdvanceKey.self] = newValue }
    }
}
