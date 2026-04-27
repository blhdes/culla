import SwiftUI

enum TourStep: Int, CaseIterable {
    case welcome
    case pickDate
    case whatAreGalleries
    case setupGallery       // gated: galleries.count > 0
    case changeColor        // skippable
    case activateGallery    // gated: sidebarGalleryIDs active count > 0
    case readyToSwipe

    // MARK: - Content

    var icon: String {
        switch self {
        case .welcome:          return "hand.wave.fill"
        case .pickDate:         return "calendar"
        case .whatAreGalleries: return "rectangle.stack.fill"
        case .setupGallery:     return "plus.rectangle.on.rectangle"
        case .changeColor:      return "paintpalette.fill"
        case .activateGallery:  return "checkmark.circle.fill"
        case .readyToSwipe:     return "bolt.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome:          return "Welcome to Culla"
        case .pickDate:         return "Pick a Date"
        case .whatAreGalleries: return "Your Galleries"
        case .setupGallery:     return "Set Up a Gallery"
        case .changeColor:      return "Make It Yours"
        case .activateGallery:  return "Activate for Swiping"
        case .readyToSwipe:     return "You're All Set"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "Culla helps you sort your photo library one swipe at a time. Let's take a quick tour."
        case .pickDate:
            return "Spin the wheel to choose a date. Culla shows your photos from that day. Tap the wheel to open a full calendar."
        case .whatAreGalleries:
            return "Tap that icon to open your Galleries — the destinations photos fly into when you swipe right."
        case .setupGallery:
            return "Tap the icon above to open Galleries, then create a new one or import an existing iPhone album."
        case .changeColor:
            return "Open any gallery from the list. Inside, tap the small color circle at the top to give it a neon color."
        case .activateGallery:
            return "Open Galleries and tap the colored circle next to a gallery to activate it for your swipe session."
        case .readyToSwipe:
            return "Pick a date, tap Start, and swipe. Left to dismiss, right to sort, up to favourite, down to share."
        }
    }

    var isSkippable: Bool { self == .changeColor }
    var isGated: Bool     { self == .setupGallery || self == .activateGallery }

    // MARK: - Spotlight

    /// Which on-screen element this step's spotlight should highlight.
    /// Nil = no spotlight (e.g. the welcome step).
    var spotlightTarget: TourTarget? {
        switch self {
        case .welcome:          return nil
        case .pickDate:         return .datePicker
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery:
            return .galleriesButton
        case .readyToSwipe:     return .startButton
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .pickDate:         return 16
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery:
            return 22
        case .readyToSwipe:     return 14
        default:                return 12
        }
    }

    // MARK: - Bubble layout

    /// Bubble center, computed from the resolved spotlight rect when available.
    func bubbleCenter(geo: GeometryProxy, spotlight: CGRect?) -> CGPoint {
        let w = geo.size.width
        let h = geo.size.height
        let bw = min(320, w - 40)
        // Rough half-height of the bubble; the bubble shrinks/grows with text but
        // 100pt keeps a reasonable gap between the arrow tip and the spotlight.
        let halfBubble: CGFloat = 100

        switch self {
        case .welcome:
            return CGPoint(x: w / 2, y: h / 2)

        case .pickDate:
            guard let spot = spotlight else { return CGPoint(x: w / 2, y: h / 2) }
            return CGPoint(x: w / 2, y: spot.maxY + halfBubble + 16)

        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery:
            guard let spot = spotlight else { return CGPoint(x: w - bw / 2 - 16, y: 200) }
            // Arrow sits at the trailing edge of the bubble: 14pt trailing padding +
            // 11pt to the arrow's center. Align the arrow tip with the spotlight center.
            let desiredRight = spot.midX + 25
            let minRight = bw / 2 + 16   // keep bubble on screen (left edge >= 16)
            let maxRight = w - 16        // keep bubble on screen (right edge <= w-16)
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
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery: return true
        default: return false
        }
    }

    /// Arrow edge on the bubble pointing toward the spotlight.
    var arrowEdge: Edge? {
        switch self {
        case .welcome:          return nil
        case .pickDate:         return .top
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery: return .top
        case .readyToSwipe:     return .bottom
        }
    }
}
