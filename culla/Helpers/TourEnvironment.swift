import SwiftUI

private struct ActiveTourStepKey: EnvironmentKey {
    static let defaultValue: TourStep? = nil
}

private struct TourAdvanceKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct TourSetStepKey: EnvironmentKey {
    static let defaultValue: ((TourStep) -> Void)? = nil
}

private struct TourActivateGalleryKey: EnvironmentKey {
    static let defaultValue: ((Gallery) -> Void)? = nil
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

    /// Jump the tour to an arbitrary step. Used when a single user action should
    /// auto-advance through multiple steps (e.g. picking a color also implies
    /// activating that gallery).
    var tourSetStep: ((TourStep) -> Void)? {
        get { self[TourSetStepKey.self] }
        set { self[TourSetStepKey.self] = newValue }
    }

    /// Activate a gallery for swiping (adds it to sidebarGalleryIDs). Provided by
    /// the view that owns the sidebar binding.
    var tourActivateGallery: ((Gallery) -> Void)? {
        get { self[TourActivateGalleryKey.self] }
        set { self[TourActivateGalleryKey.self] = newValue }
    }
}
