import SwiftUI

enum TourStep: Int, CaseIterable {
    case welcome
    case pickDate
    case whatAreGalleries
    case setupGallery       // gated: user must create at least one gallery
    case changeColor        // optional; picking a color auto-advances to readyToSwipe
    case readyToSwipe

    // MARK: - Content

    var icon: String {
        switch self {
        case .welcome:          return "hand.wave.fill"
        case .pickDate:         return "calendar"
        case .whatAreGalleries: return "rectangle.stack.fill"
        case .setupGallery:     return "plus.rectangle.on.rectangle"
        case .changeColor:      return "paintpalette.fill"
        case .readyToSwipe:     return "bolt.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome:          return String(localized: "Welcome to Culla")
        case .pickDate:         return String(localized: "Pick a Date")
        case .whatAreGalleries: return String(localized: "Your Galleries")
        case .setupGallery:     return String(localized: "Set Up a Gallery")
        case .changeColor:      return String(localized: "Make It Yours")
        case .readyToSwipe:     return String(localized: "You're All Set")
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return String(localized: "Culla helps you sort your photo library one swipe at a time. Let's take a quick tour.")
        case .pickDate:
            return String(localized: "Spin the wheel to choose a date. Culla shows your photos from that day. Tap the wheel to open a full calendar.")
        case .whatAreGalleries:
            return String(localized: "Tap that icon to open your Galleries — the destinations photos fly into when you swipe right.")
        case .setupGallery:
            return String(localized: "Tap the icon above to open Galleries, then create a new one or import an existing iPhone album.")
        case .changeColor:
            return String(localized: "Open any gallery from the list. Inside, tap the small color circle at the top to give it a neon color.")
        case .readyToSwipe:
            return String(localized: "Pick a date, tap Start, and swipe. Left to dismiss, right to sort, up to favourite, down to share.")
        }
    }

    // MARK: - Spotlight

    var spotlightTarget: TourTarget? {
        switch self {
        case .welcome:          return nil
        case .pickDate:         return .datePicker
        case .whatAreGalleries, .setupGallery, .changeColor:
            return .galleriesButton
        case .readyToSwipe:     return .startButton
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .pickDate:         return 16
        case .whatAreGalleries, .setupGallery, .changeColor:
            return 22
        case .readyToSwipe:     return 14
        default:                return 12
        }
    }

    // MARK: - Bubble layout

    func bubbleCenter(geo: GeometryProxy, spotlight: CGRect?) -> CGPoint {
        let w = geo.size.width
        let h = geo.size.height
        let bw = min(320, w - 40)
        let halfBubble: CGFloat = 100

        switch self {
        case .welcome:
            return CGPoint(x: w / 2, y: h / 2)

        case .pickDate:
            guard let spot = spotlight else { return CGPoint(x: w / 2, y: h / 2) }
            return CGPoint(x: w / 2, y: spot.maxY + halfBubble + 16)

        case .whatAreGalleries, .setupGallery, .changeColor:
            guard let spot = spotlight else { return CGPoint(x: w - bw / 2 - 16, y: 200) }
            let desiredRight = spot.midX + 25
            let minRight = bw / 2 + 16
            let maxRight = w - 16
            let bubbleRight = min(maxRight, max(minRight + bw / 2, desiredRight))
            let centerX = bubbleRight - bw / 2
            return CGPoint(x: centerX, y: spot.maxY + halfBubble + 16)

        case .readyToSwipe:
            guard let spot = spotlight else { return CGPoint(x: w / 2, y: h / 2) }
            return CGPoint(x: w / 2, y: spot.minY - halfBubble - 16)
        }
    }

    var arrowIsTrailing: Bool {
        switch self {
        case .whatAreGalleries, .setupGallery, .changeColor: return true
        default: return false
        }
    }

    /// Arrow edge on the bubble pointing toward the spotlight.
    var arrowEdge: Edge? {
        switch self {
        case .welcome:          return nil
        case .pickDate:         return .top
        case .whatAreGalleries, .setupGallery, .changeColor: return .top
        case .readyToSwipe:     return .bottom
        }
    }
}
