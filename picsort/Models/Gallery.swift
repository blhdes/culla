import Foundation
import SwiftData
import SwiftUI

@Model
final class Gallery {
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
    var color: Color {
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
        // Pick a neon default based on position if no color was provided
        let neonHexes = Color.neonHexes
        self.colorHex = colorHex ?? neonHexes[displayOrder % neonHexes.count]
        self.displayOrder = displayOrder
        self.colorIndex = displayOrder
        self.createdAt = .now
        self.albumIdentifier = albumIdentifier
        self.sortedPhotos = []
    }
}
