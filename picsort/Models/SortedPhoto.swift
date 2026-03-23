import Foundation
import SwiftData

@Model
final class SortedPhoto {
    var id: UUID
    var assetIdentifier: String
    var sortedAt: Date
    var gallery: Gallery?

    /// True when the photo came from an album import or gallery sync,
    /// not from the user actually sorting it in the app.
    var isImported: Bool

    init(assetIdentifier: String, gallery: Gallery, isImported: Bool = false) {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.sortedAt = .now
        self.gallery = gallery
        self.isImported = isImported
    }
}
