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
    var edge: SwipePanelEdge
    var translation: CGSize
    var predictedTranslation: CGSize
    /// The panel has claimed the drag (`GalleryPanelLayout.isInPanel`).
    var isInPanel: Bool
    /// The panel row under the finger right now.
    var galleryUnderFinger: UUID?
    /// The row highlighted by the last drag update.
    var highlightedGallery: UUID?
    /// The user has no galleries in the panel yet.
    var panelIsEmpty: Bool
    /// Release distance toward the panel (`SwipeTuning.panelCommitDistance(room:)`).
    var panelCommit: CGFloat
}

/// Decides what a released drag does. Gesture map with the panel on the
/// right: → galleries · ← Dismiss · ↑ Favourite · ↓ Share. With the panel on
/// the left the two horizontal directions swap.
enum SwipeResolver {
    static func resolve(
        _ release: SwipeRelease,
        threshold: CGFloat = SwipeTuning.commitDistance
    ) -> SwipeOutcome {
        let tx = release.translation.width
        let ty = release.translation.height
        let ptx = release.predictedTranslation.width
        let pty = release.predictedTranslation.height
        // Horizontal travel measured toward the panel (negative = toward Dismiss).
        let toward = tx * release.edge.sign
        let predictedToward = ptx * release.edge.sign
        let reachesPanel = toward > release.panelCommit || predictedToward > threshold
        // Direction lock: the dominant axis comes from whichever value (actual
        // or predicted) went further, so a fast sideways-up flick can't
        // cross-trigger Favourite when the user meant to sort.
        let horizontalDominant = max(abs(tx), abs(ptx)) >= max(abs(ty), abs(pty))

        // No galleries yet: a release past the panel's line opens Manage, as
        // the empty panel promises ("Release to open Manage").
        if release.panelIsEmpty, horizontalDominant, reachesPanel {
            return .openManage
        }

        // The panel claims the drag once the finger is over its rows or past
        // its release line: then only a drop onto a gallery or a snap-back can
        // happen. Vertical motion across rows must not favourite or share.
        if release.isInPanel || toward > release.panelCommit {
            if reachesPanel, let id = release.galleryUnderFinger {
                return .assign(galleryID: id)
            }
            return .snapBack
        }

        if !horizontalDominant, ty < -threshold || pty < -threshold {
            return .favorite
        }
        if !horizontalDominant, ty > threshold || pty > threshold {
            return .share
        }
        if horizontalDominant, reachesPanel {
            // A fling toward the panel: drop on the row it lit up, if any.
            guard let id = release.highlightedGallery else { return .snapBack }
            return .assign(galleryID: id)
        }
        if horizontalDominant, toward < -threshold || predictedToward < -threshold {
            return .dismiss
        }
        return .snapBack
    }
}
