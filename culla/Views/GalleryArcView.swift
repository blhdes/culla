import SwiftUI

/// Wraparound C-arc layout for the gallery sidebar.
///
/// Galleries are arranged along a 210° arc curving around the right edge.
/// Index 0 is the top of the arc; the last index is the bottom.
/// Hit-testing is angle-based — see `index(forDrag:count:)`. No CGRect / preference key is used.
struct GalleryArcView: View {
    let galleries: [Gallery]
    let highlightedID: UUID?
    let dragProgress: CGFloat
    var isLongPress: Bool = false

    /// 210° span gives the wraparound feel the spec called for.
    static let arcSpanDeg: Double = 210

    private var isDragging: Bool { dragProgress > 0 }

    var body: some View {
        if galleries.isEmpty {
            emptyState
        } else {
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width * 0.9, y: geo.size.height / 2)
                let radius = geo.size.width * 0.3
                ZStack {
                    ForEach(Array(galleries.enumerated()), id: \.element.id) { index, gallery in
                        let offset = Self.labelOffset(index: index, count: galleries.count, radius: radius)
                        GalleryArcLabel(
                            gallery: gallery,
                            neonColor: gallery.color,
                            isHighlighted: gallery.id == highlightedID,
                            isDragging: isDragging,
                            dragProgress: dragProgress,
                            isLongPress: isLongPress
                        )
                        .position(x: center.x + offset.x, y: center.y + offset.y)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Add a gallery\nto sort photos")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 4) {
                Text("Tap Manage")
                    .font(.caption)
                Image(systemName: "arrow.down.right")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isDragging ? 0.6 + 0.4 * dragProgress : 0.55)
    }

    // MARK: - Arc Math

    /// Offset of label `index` from the arc center, in screen y-down coords.
    /// Index 0 ⇒ top of arc; `count - 1` ⇒ bottom.
    static func labelOffset(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        guard count > 0 else { return .zero }
        // t ∈ [-1, +1] spans top→bottom of arc.
        let t = -1.0 + 2.0 * (Double(index) + 0.5) / Double(count)
        // β rotates around arc center: positive β points up (since screen y is flipped).
        let betaRad = (-t * (arcSpanDeg / 2)) * .pi / 180
        // Labels sit on the LEFT semicircle of the arc center (+ 15° tails) — hence the leading minus.
        let dx = -radius * cos(betaRad)
        let dy = -radius * sin(betaRad)
        return CGPoint(x: dx, y: dy)
    }

    /// Returns the highlighted gallery index for a drag translation,
    /// or `nil` if the drag is too small or outside the arc (dismiss territory).
    static func index(forDrag translation: CGSize, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let magnitude = hypot(translation.width, translation.height)
        guard magnitude > 30 else { return nil }

        // Screen y-down: 0° = right, 90° = down, ±180° = left, -90° = up.
        let angleDeg = atan2(translation.height, translation.width) * 180 / .pi
        guard abs(angleDeg) <= arcSpanDeg / 2 else { return nil }

        let segmentDeg = arcSpanDeg / Double(count)
        let normalized = angleDeg + arcSpanDeg / 2
        let idx = Int(normalized / segmentDeg)
        return min(max(idx, 0), count - 1)
    }
}

// MARK: - Single Arc Label

struct GalleryArcLabel: View {
    let gallery: Gallery
    let neonColor: Color
    let isHighlighted: Bool
    let isDragging: Bool
    let dragProgress: CGFloat
    var isLongPress: Bool = false

    var body: some View {
        Text(gallery.name)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(isHighlighted ? .white : .primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(neonColor.opacity(backgroundOpacity)))
            )
            .scaleEffect(isHighlighted ? 1.18 : 1.0)
            .shadow(color: isHighlighted ? neonColor.opacity(0.55) : .clear, radius: 14)
            .opacity(isDragging ? 0.5 + 0.5 * dragProgress : 0.5)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isHighlighted)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    private var backgroundOpacity: Double {
        guard isDragging else { return 0.15 }
        if isLongPress, !isHighlighted { return 0.45 }
        return isHighlighted ? 0.9 : 0.25 + 0.4 * dragProgress
    }
}
