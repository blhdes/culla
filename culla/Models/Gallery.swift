import Foundation
import SwiftData
import SwiftUI

/// `nonisolated` so the background `AlbumImporter` can create galleries too.
/// Without it, the app's main-thread default would tie this type to the screen.
@Model
nonisolated final class Gallery {
    var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var displayOrder: Int
    var colorIndex: Int
    var createdAt: Date

    /// Links to a real iPhone Photos album. Nil until the album is created.
    var albumIdentifier: String?

    @Relationship(deleteRule: .cascade, inverse: \SortedPhoto.gallery)
    var sortedPhotos: [SortedPhoto]

    /// The gallery's display color — adapts automatically for light/dark mode.
    /// Only drawn on screen, so it stays on the main thread.
    @MainActor var color: Color {
        Color.adaptiveNeon(hex: colorHex)
    }

    init(
        name: String,
        iconName: String = "folder.fill",
        colorHex: String? = nil,
        displayOrder: Int = 0,
        albumIdentifier: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex ?? Self.defaultColorHex(forDisplayOrder: displayOrder)
        self.displayOrder = displayOrder
        self.colorIndex = displayOrder
        self.createdAt = .now
        self.albumIdentifier = albumIdentifier
        self.sortedPhotos = []
    }

    /// The neon a new gallery gets when no color is chosen: one per position,
    /// in palette order. The import screen uses it too, so each album's
    /// progress shows in the color its gallery is about to get.
    static func defaultColorHex(forDisplayOrder displayOrder: Int) -> String {
        let neonHexes = Color.neonHexes
        return neonHexes[displayOrder % neonHexes.count]
    }
}
