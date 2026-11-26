import CoreGraphics
import Foundation

/// The screen edge the galleries panel slides in from, picked in Settings.
/// Dismiss always takes the opposite direction; Favourite (up) and Share
/// (down) never move. Physical left/right, not leading/trailing: swipe
/// directions don't flip in right-to-left languages (and the app ships none).
enum SwipePanelEdge: String, CaseIterable, Identifiable {
    case right
    case left

    static let storageKey = "swipePanelEdge"

    /// The saved choice, for code that can't hold an `@AppStorage` (the tour copy).
    static var current: SwipePanelEdge {
        UserDefaults.standard.string(forKey: storageKey).flatMap(SwipePanelEdge.init(rawValue:)) ?? .right
    }

    var id: String { rawValue }

    /// +1 when a drag to the right opens the panel, −1 when a drag to the left does.
    var sign: CGFloat { self == .right ? 1 : -1 }

    var systemImage: String {
        switch self {
        case .right: "rectangle.righthalf.filled"
        case .left:  "rectangle.lefthalf.filled"
        }
    }

    /// One line that says what the setting changes, shown under the picker.
    var gestureSummary: String {
        switch self {
        case .right: String(localized: "Swipe right to sort, left to dismiss")
        case .left:  String(localized: "Swipe left to sort, right to dismiss")
        }
    }
}
