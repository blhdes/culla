import SwiftUI

/// The back button in the swipe screen's top-left corner. It's an overlay
/// (not a toolbar item) so it can fade with the rest of the chrome while
/// a card is dragged toward the galleries.
struct SwipeTopNavButtons: ViewModifier {
    let onBack: (() -> Void)?
    var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                circleButton("chevron.left", action: onBack)
                    .padding(.leading, 16)
                    .padding(.top, 8)
                    .opacity(opacity)
            }
    }

    private func circleButton(_ icon: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 24, height: 24)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

extension View {
    func swipeTopNav(onBack: (() -> Void)?, opacity: Double = 1.0) -> some View {
        modifier(SwipeTopNavButtons(onBack: onBack, opacity: opacity))
    }
}
