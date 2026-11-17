import Foundation
import SwiftData

/// `nonisolated` so the background `MissingPhotoCleaner` can read and delete records.
/// Without it, the app's main-thread default would tie this type to the screen.
@Model
nonisolated final class DismissedPhoto {
    var id: UUID
    var assetIdentifier: String
    var dismissedAt: Date

    init(assetIdentifier: String) {
        self.id = UUID()
        self.assetIdentifier = assetIdentifier
        self.dismissedAt = .now
    }
}
