import SwiftUI

/// Every number that shapes how the tour looks and moves, in one place.
/// The line in `current` comes from the design workshop page
/// (https://claude.ai/artifact/UaVzAaimfJwbfn65jUsVXm). Paste a new one to restyle the tour.
/// Only the `.card` layout is built; `.bubble` and `.glance` are kept so a
/// workshop line still pastes in as is.
struct TourStyle {
    enum Layout { case bubble, card, glance }

    var layout: Layout
    var welcomeCard: Bool
    var dimOpacity: Double
    var titleSize: CGFloat
    var cornerRadius: CGFloat
    var ringWidth: CGFloat
    var ringPulse: Bool
    var glass: Bool
    var springResponse: Double
    var springDamping: Double

    static let current = TourStyle(layout: .card, welcomeCard: false, dimOpacity: 0.50, titleSize: 28, cornerRadius: 30, ringWidth: 3, ringPulse: true, glass: true, springResponse: 0.45, springDamping: 0.85)

    var spring: Animation { .spring(response: springResponse, dampingFraction: springDamping) }
}
