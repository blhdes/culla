import SwiftUI

/// Displays selected galleries as colored panels that split the screen equally.
/// 2 galleries = 50/50, 3 = 33/33/33, etc.
struct GallerySidebarView: View {
    let galleries: [Gallery]
    let highlightedID: UUID?
    let dragProgress: CGFloat

    /// Whether the user is actively dragging (any rightward movement).
    private var isDragging: Bool { dragProgress > 0 }

    var body: some View {
        if galleries.isEmpty {
            VStack {
                Spacer()
                Text("Tap Manage to\nadd galleries")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isDragging ? 0.4 + 0.6 * dragProgress : 0.4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(galleries.enumerated()), id: \.element.id) { index, gallery in
                    GallerySidebarItem(
                        gallery: gallery,
                        pastelColor: gallery.color,
                        isHighlighted: gallery.id == highlightedID,
                        isDragging: isDragging,
                        dragProgress: dragProgress
                    )
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: GalleryFramePreferenceKey.self,
                                value: [gallery.id: geo.frame(in: .global)]
                            )
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

// MARK: - Shared Pastel Palette & Hex Support

extension Color {
    static let pastels: [Color] = [
        Color(red: 0.95, green: 0.6, blue: 0.6),   // soft pink
        Color(red: 0.6, green: 0.8, blue: 0.95),    // soft blue
        Color(red: 0.7, green: 0.9, blue: 0.7),     // soft green
        Color(red: 0.9, green: 0.75, blue: 0.95),   // soft lavender
        Color(red: 0.95, green: 0.85, blue: 0.55),  // soft yellow
        Color(red: 0.95, green: 0.7, blue: 0.5),    // soft peach
        Color(red: 0.6, green: 0.85, blue: 0.85),   // soft teal
        Color(red: 0.85, green: 0.65, blue: 0.85),  // soft mauve
        Color(red: 0.75, green: 0.85, blue: 0.6),   // soft lime
        Color(red: 0.8, green: 0.7, blue: 0.95),    // soft violet
    ]

    static let pastelHexes: [String] = [
        "#F29999", "#99CCEE", "#B3E6B3", "#E6BFF2",
        "#F2D98C", "#F2B380", "#99D9D9", "#D9A6D9",
        "#BFD999", "#CCB3F2",
    ]

    static func pastel(for index: Int) -> Color {
        pastels[index % pastels.count]
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexString: String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Single Gallery Panel

struct GallerySidebarItem: View {
    let gallery: Gallery
    let pastelColor: Color
    let isHighlighted: Bool
    let isDragging: Bool
    let dragProgress: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            // Pastel background — only visible during drag, fades in with progress
            if isDragging {
                pastelColor
                    .opacity(isHighlighted ? 0.9 : 0.3 + 0.5 * dragProgress)
            }

            // Gallery name — always visible, but subtle at rest
            Text(gallery.name)
                .font(isHighlighted ? .title2 : .title3)
                .fontWeight(isHighlighted ? .bold : .medium)
                .foregroundStyle(isDragging ? .white : .secondary)
                .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: 2, x: 0, y: 1)
                .padding(.leading, 20)
                .opacity(isDragging ? 1.0 : 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}

// MARK: - Preference Key

struct GalleryFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
