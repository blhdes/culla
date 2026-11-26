import SwiftUI

/// How a panel row reads while the finger slides over the panel.
enum PanelRowState: Equatable {
    case idle
    /// Under the finger, but letting go now wouldn't drop the photo yet.
    case candidate
    /// Letting go now drops the photo here.
    case armed
}

/// The colour each panel row is drawn in. Shared with the target pill, so
/// the pill always matches the row it names.
enum PanelRowColors {
    /// Per-gallery colours, or in "accent" mode one accent hue walked from
    /// light (top) to dark (bottom). The brightness range is fixed, so more
    /// galleries just means finer steps — a richer, fuller gradient.
    /// Saturation and hue stay locked to the accent.
    static func colors(
        for galleries: [Gallery],
        tintMode: String,
        accent: Color,
        scheme: ColorScheme
    ) -> [Color] {
        guard tintMode == "accent" else { return galleries.map(\.color) }
        let count = galleries.count
        guard count > 1 else { return Array(repeating: accent, count: count) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // On white, a near-1.0 brightness washes out — start lower in light mode.
        let top: CGFloat = scheme == .dark ? 0.95 : 0.82
        let bottom: CGFloat = 0.45
        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)        // 0…1, top→bottom
            let brightness = top + (bottom - top) * t
            return Color(hue: Double(h), saturation: Double(s), brightness: Double(brightness))
        }
    }
}

/// The galleries panel that slides in from the edge picked in Settings while
/// the card is dragged toward it. Rows split the screen height equally:
/// 2 galleries = 50/50, 3 = 33/33/33, etc. The whole panel fades in with the
/// drag, so nothing sits on the photo at rest.
struct GallerySidebarView: View {
    let galleries: [Gallery]
    let highlightedID: UUID?
    /// The highlighted row is armed: releasing now drops the photo there.
    var isArmed: Bool = false
    let dragProgress: CGFloat
    var isLongPress: Bool = false
    /// From `GalleryPanelLayout`, the same maths the drag hit-tests with.
    /// 0 until the panel's container has been measured: rows then share the
    /// height on their own, which comes to the same split.
    var rowHeight: CGFloat = 0
    /// Galleries the current photo is already in. Their rows show a check.
    var memberIDs: Set<UUID> = []

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"

    /// Whether the user is actively dragging toward the panel.
    private var isDragging: Bool { dragProgress > 0 }

    var body: some View {
        Group {
            if galleries.isEmpty {
                emptyState
            } else {
                let colors = PanelRowColors.colors(
                    for: galleries,
                    tintMode: sidebarTintMode,
                    accent: accent,
                    scheme: colorScheme
                )
                VStack(spacing: 0) {
                    ForEach(Array(galleries.enumerated()), id: \.element.id) { index, gallery in
                        GallerySidebarItem(
                            gallery: gallery,
                            neonColor: colors[index],
                            state: rowState(for: gallery),
                            isMember: memberIDs.contains(gallery.id),
                            isDragging: isDragging,
                            dragProgress: dragProgress
                        )
                        .frame(height: rowHeight > 0 ? rowHeight : nil)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    // One blur behind the whole panel. Each row used to draw
                    // its own material, up to 10 blurs for the same look.
                    ZStack {
                        panelTint
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(materialOpacity)
                    }
                }
            }
        }
        .opacity(Double(dragProgress))
    }

    private func rowState(for gallery: Gallery) -> PanelRowState {
        guard gallery.id == highlightedID else { return .idle }
        return isArmed ? .armed : .candidate
    }

    /// Veils what sits behind the panel with ultraThinMaterial as the user
    /// commits to a gallery, capped at 0.85. Long-press keeps a much lighter
    /// veil.
    private var materialOpacity: Double {
        isLongPress ? 0.35 : 0.85 * Double(dragProgress)
    }

    /// Very faint top-to-bottom accent wash behind the rows — ties the panel
    /// to the app accent without competing with the drop-target highlight.
    private var panelTint: some View {
        LinearGradient(
            colors: [accent.opacity(0.10), accent.opacity(0.04)],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    /// Shown when no gallery is in the sidebar yet. It looks like a button,
    /// but the sidebar ignores touches: letting go past the panel's release
    /// line opens Manage (see `SwipeResolver`), so the finger never has to
    /// lift and tap.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(accent)
                .symbolEffect(.pulse, options: .repeating, isActive: isDragging)
                .frame(width: 64, height: 64)
                .glassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: accent.opacity(0.35), radius: 14, y: 6)

            Text("Add galleries")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)

            Text("Release to open Manage")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        // Multiplied by the outer fade, so this only finishes the reveal
        // over the back half of the drag (85% → 100%).
        .opacity(0.85 + 0.15 * dragProgress)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Single Gallery Panel

struct GallerySidebarItem: View {
    let gallery: Gallery
    let neonColor: Color
    let state: PanelRowState
    /// The current photo is already in this gallery.
    var isMember: Bool = false
    let isDragging: Bool
    let dragProgress: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // The row's own colour: a soft wash at rest, half strength under
            // the finger, a solid fill once releasing would drop the photo.
            neonColor
                .opacity(fillOpacity)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    GalleryCoverView(
                        albumIdentifier: gallery.albumIdentifier,
                        iconName: gallery.iconName,
                        tint: neonColor
                    )
                    Text(gallery.name)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                // Only the cover and name grow, so the check never pushes
                // past the screen edge.
                .scaleEffect(state == .armed ? 1.06 : 1.0, anchor: .leading)

                Spacer(minLength: 0)

                if isMember {
                    memberCheck
                }
            }
            .foregroundStyle(textColor)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .opacity(textOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    /// "Already in this gallery." Dropping the photo here again only says so.
    private var memberCheck: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                state == .armed ? neonColor : Color(.systemBackground),
                state == .armed ? armedLabel : Color.secondary
            )
            .accessibilityHidden(true)
    }

    /// Black or white on the armed row's solid fill, whichever reads.
    private var armedLabel: Color {
        neonColor.labelOnSolidFill(in: colorScheme)
    }

    /// Resting rows keep a soft tint (25 % at most) so the row under the
    /// finger stands out.
    private var fillOpacity: Double {
        guard isDragging else { return 0 }
        switch state {
        case .idle:      return 0.1 + 0.15 * Double(dragProgress)
        case .candidate: return 0.5
        case .armed:     return 1.0
        }
    }

    private var textColor: Color {
        if state == .armed { return armedLabel }
        return isDragging ? .primary : .secondary
    }

    /// Ramps continuously with dragProgress instead of jumping when isDragging
    /// flips. At rest = 0.5; full drag, idle = 0.7; full drag, under the
    /// finger = 1.0.
    private var textOpacity: Double {
        let p = Double(max(0, min(1, dragProgress)))
        let target: Double = state == .idle ? 0.7 : 1.0
        return 0.5 + (target - 0.5) * p
    }
}
