import Foundation

/// Visual style of the gallery sidebar overlay that appears while dragging
/// a photo right in `SwipeView`.
enum SidebarLayout: String, CaseIterable, Identifiable {
    /// Equal-height colored panels stacked vertically — the default.
    case panels
    /// Same panel stack, clipped into a half-ellipse that bulges left.
    case arc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .panels: return "Panels"
        case .arc:    return "Arc"
        }
    }
}
