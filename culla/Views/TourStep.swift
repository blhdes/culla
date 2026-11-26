import SwiftUI

/// The stops of the first-launch tour, in order.
enum TourStep: Int, CaseIterable {
    case welcome      // optional opening card, no spotlight
    case pickDate
    case galleries
    case start

    /// The stops actually shown. The welcome card is a style choice.
    static var flow: [TourStep] {
        TourStyle.current.welcomeCard ? allCases : allCases.filter { $0 != .welcome }
    }

    /// The stop after this one, or nil when this is the last.
    var next: TourStep? {
        let flow = Self.flow
        guard let index = flow.firstIndex(of: self), index + 1 < flow.count else { return nil }
        return flow[index + 1]
    }

    // MARK: - Content

    /// Used by the banner inside the Galleries sheet.
    var icon: String {
        switch self {
        case .welcome:   return "hand.wave.fill"
        case .pickDate:  return "calendar"
        case .galleries: return "plus.rectangle.on.rectangle"
        case .start:     return "bolt.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome:   return String(localized: "Welcome to Culla")
        case .pickDate:  return String(localized: "Pick a day")
        case .galleries: return String(localized: "Make a gallery")
        case .start:     return String(localized: "Start swiping")
        }
    }

    var body: String {
        switch self {
        case .welcome:   return String(localized: "Sort your photos, one swipe at a time.")
        case .pickDate:  return String(localized: "Spin the wheel, or tap it for the calendar. Culla starts from that day.")
        case .galleries:
            // Follows Settings → Galleries panel: the panel can open from either side.
            return SwipePanelEdge.current == .left
                ? String(localized: "Galleries are where photos land when you swipe left. Tap Galleries to make your first one.")
                : String(localized: "Galleries are where photos land when you swipe right. Tap Galleries to make your first one.")
        case .start:     return String(localized: "Tap Start. The first photos show you how each swipe works.")
        }
    }

    var buttonLabel: LocalizedStringKey {
        switch self {
        case .welcome: return "Show me"
        case .start:   return "Got it"
        default:       return "Next"
        }
    }

    // MARK: - Spotlight

    var spotlightTarget: TourTarget? {
        switch self {
        case .welcome:   return nil
        case .pickDate:  return .datePicker
        case .galleries: return .galleriesButton
        case .start:     return .startButton
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .welcome:   return 12
        case .pickDate:  return 16
        case .galleries: return 22
        case .start:     return 26   // the Start button is a capsule on iOS 26
        }
    }
}
