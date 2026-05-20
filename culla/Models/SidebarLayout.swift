import Foundation

/// Choice of layout for the gallery sidebar overlay in `SwipeView`.
/// Persisted as a raw string in `@AppStorage("gallerySidebarLayout")`.
enum SidebarLayout: String, CaseIterable, Identifiable {
    case panels
    case arc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .panels: return "Panels"
        case .arc: return "Arc"
        }
    }
}
