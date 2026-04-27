import SwiftUI

private struct ActiveTourStepKey: EnvironmentKey {
    static let defaultValue: TourStep? = nil
}

extension EnvironmentValues {
    var activeTourStep: TourStep? {
        get { self[ActiveTourStepKey.self] }
        set { self[ActiveTourStepKey.self] = newValue }
    }
}
