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

    // MARK: - Layout

    struct Spotlight {
        let rect: CGRect
        let cornerRadius: CGFloat
    }

    func spotlightRect(geo: GeometryProxy) -> Spotlight? {
        let w = geo.size.width
        let h = geo.size.height

        switch self {
        case .welcome:
            return nil

        case .pickDate:
            let spotW = w * 0.82
            let spotH = h * 0.29
            let spotY = h * 0.24
            return Spotlight(
                rect: CGRect(x: (w - spotW) / 2, y: spotY, width: spotW, height: spotH),
                cornerRadius: 16
            )

        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery:
            return nil  // toolbar button frame can't be reliably pinned without a coordinate pass

        case .readyToSwipe:
            return nil  // button is inside a VStack with dynamic content above it — position can't be reliably approximated
        }
    }

    func bubbleCenter(geo: GeometryProxy) -> CGPoint {
        let w = geo.size.width
        let h = geo.size.height
        let safeTop = geo.safeAreaInsets.top
        let safeBottom = geo.safeAreaInsets.bottom

        switch self {
        case .welcome:
            return CGPoint(x: w / 2, y: h / 2)

        case .pickDate:
            let spotBottom = h * 0.24 + h * 0.29
            return CGPoint(x: w / 2, y: min(spotBottom + 140, h - safeBottom - 49 - 90))

        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery:
            // Right-align the bubble so the trailing arrow tip lands over the toolbar icon
            let bw = min(320, w - 40)
            return CGPoint(x: w - bw / 2 - 16, y: safeTop + 44 + 155)

        case .readyToSwipe:
            let btnTop = h - safeBottom - 49 - 54 - 16
            return CGPoint(x: w / 2, y: btnTop - 160)
        }
    }

    var arrowIsTrailing: Bool {
        switch self {
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery: return true
        default: return false
        }
    }

    // Arrow edge on the bubble pointing toward the spotlight
    var arrowEdge: Edge? {
        switch self {
        case .welcome:          return nil
        case .pickDate:         return .top
        case .whatAreGalleries, .setupGallery, .changeColor, .activateGallery: return .top
        case .readyToSwipe:     return .bottom
        }
    }
}
