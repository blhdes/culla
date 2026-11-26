import CoreGraphics
import Foundation

/// What a released card drag should do. Pure data: the view turns it into
/// animations, haptics and view-model calls (and checks the daily limit
/// before acting on `assign` or `dismiss`).
enum SwipeOutcome: Equatable {
    case assign(galleryID: UUID)
    case dismiss
    case favorite
    case share
    case openManage
    case snapBack
}

/// Everything the decision needs, captured at release.
struct SwipeRelease {
    var translation: CGSize
    var predictedTranslation: CGSize
    /// The row highlighted by the last drag update.
    var highlightedGallery: UUID?
    /// The user has no galleries in the panel yet.
    var panelIsEmpty: Bool
}

/// Decides what a released drag does. Gesture map:
/// → galleries · ← Dismiss · ↑ Favourite · ↓ Share.
enum SwipeResolver {
    static func resolve(
        _ release: SwipeRelease,
        threshold: CGFloat = SwipeTuning.commitDistance
    ) -> SwipeOutcome {
        let tx = release.translation.width
        let ty = release.translation.height
        let ptx = release.predictedTranslation.width
        let pty = release.predictedTranslation.height

        // Right swipe with no galleries set up: guide the user to Manage
        // instead of letting the swipe silently fall through. Halfway is
        // enough, as the empty panel promises ("Release to open Manage"), as
        // long as the drag is mostly sideways so a swipe up still favourites.
        let releasedHalfway = tx > threshold / 2 && tx > abs(ty)
        if release.panelIsEmpty, releasedHalfway || tx > threshold || ptx > threshold {
            return .openManage
        }

        // Right swipe with a highlighted gallery always wins, even at a steep
        // angle (top and bottom rows): the highlight means the finger is over
        // the panel, so the intent is clear.
        if tx > threshold || ptx > threshold, let id = release.highlightedGallery {
            return .assign(galleryID: id)
        }

        // Vertical swipe: the primary axis is vertical.
        if abs(ty) > abs(tx) {
            if ty < -threshold || pty < -threshold { return .favorite }
            if ty > threshold || pty > threshold { return .share }
        }

        if tx < -threshold || ptx < -threshold { return .dismiss }

        return .snapBack
    }
}
