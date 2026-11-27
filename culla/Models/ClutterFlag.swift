import Foundation

/// The label a swipe card can carry when its photo looks like clutter
/// (Part Q of the iOS 27 kits plan). A photo shows at most one: the first
/// case below that applies.
nonisolated enum ClutterFlag: String, Sendable {
    case screenshot
    case document
    case dirtyLens
    case lowQuality

    /// The Settings switch. On by default.
    static let settingKey = "showsClutterChip"

    // Provisional cut-offs: the device session's `[quality]` spike summary
    // sets the real ones.

    /// Vision's overall score (−1…1) below this counts as a low-quality shot.
    static let lowQualityBelow: Float = -0.3
    /// Lens-smudge confidence (0…1) from this up counts as a dirty lens.
    static let dirtyLensFrom: Float = 0.8

    /// The one flag to show, or nil for a photo that looks fine.
    /// Screenshots are known exactly from Photos, so they need no scores.
    static func strongest(isScreenshot: Bool, quality: PhotoQuality?) -> ClutterFlag? {
        if isScreenshot { return .screenshot }
        guard let quality else { return nil }
        if quality.isUtility { return .document }
        if let smudge = quality.smudge, smudge >= dirtyLensFrom { return .dirtyLens }
        if quality.score < lowQualityBelow { return .lowQuality }
        return nil
    }

    var systemImage: String {
        switch self {
        case .screenshot: "camera.viewfinder"
        case .document: "doc.text.viewfinder"
        case .dirtyLens: "hand.raised.fingers.spread"
        case .lowQuality: "camera.aperture"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .screenshot:
            LocalizedStringResource("Screenshot", comment: "Clutter chip on a swipe card: the photo is a screenshot.")
        case .document:
            LocalizedStringResource("Document", comment: "Clutter chip on a swipe card: a photo of a receipt, document or whiteboard.")
        case .dirtyLens:
            LocalizedStringResource("Dirty lens", comment: "Clutter chip on a swipe card: the camera lens was smudged when the photo was taken.")
        case .lowQuality:
            LocalizedStringResource("Low quality", comment: "Clutter chip on a swipe card: the photo is blurry, badly exposed or badly framed.")
        }
    }
}
