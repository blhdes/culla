import Foundation

/// A named action VoiceOver offers on the swipe card (Add to a gallery,
/// Dismiss, Favourite, Skip, Share). Each one calls the same path as its
/// gesture, daily limit included, so sorting works without dragging.
struct CardSortAction: Identifiable {
    let id: String
    let name: String
    let perform: () -> Void
}
