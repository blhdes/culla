import SwiftUI

/// Displays selected galleries as colored panels that split the screen equally.
/// 2 galleries = 50/50, 3 = 33/33/33, etc.
/// The whole panel fades in with the drag, so nothing sits on the photo at rest.
struct GallerySidebarView: View {
    let galleries: [Gallery]
    let highlightedID: UUID?
    let dragProgress: CGFloat
    var isLongPress: Bool = false
    /// From `GalleryPanelLayout`, the same maths the drag hit-tests with.
    /// 0 until the panel's container has been measured: rows then share the
    /// height on their own, which comes to the same split.
    var rowHeight: CGFloat = 0

    @Environment(\.appAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"

    /// Whether the user is actively dragging (any rightward movement).
    private var isDragging: Bool { dragProgress > 0 }

    /// In "accent" mode the sidebar abandons per-gallery colours and instead
    /// renders one accent hue walked from light (top) to dark (bottom). The
    /// brightness range is fixed, so more galleries just means finer steps —
    /// a richer, fuller gradient. Saturation/hue stay locked to the accent.
    private func accentSpectrum(_ accent: Color, count: Int) -> [Color] {
        guard count > 1 else { return [accent] }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(accent).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // On white, a near-1.0 brightness washes out — start lower in light mode.
        let top: CGFloat = colorScheme == .dark ? 0.95 : 0.82
        let bottom: CGFloat = 0.45
        return (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)        // 0…1, top→bottom
            let brightness = top + (bottom - top) * t
            return Color(hue: Double(h), saturation: Double(s), brightness: Double(brightness))
        }
    }

    var body: some View {
        Group {
            if galleries.isEmpty {
                emptyState
            } else {
                let spectrum: [Color] = sidebarTintMode == "accent"
                    ? accentSpectrum(accent, count: galleries.count)
                    : []
                VStack(spacing: 0) {
                    ForEach(Array(galleries.enumerated()), id: \.element.id) { index, gallery in
                        GallerySidebarItem(
                            gallery: gallery,
                            neonColor: spectrum.isEmpty ? gallery.color : spectrum[index],
                            isHighlighted: gallery.id == highlightedID,
                            isDragging: isDragging,
                            dragProgress: dragProgress,
                            isLongPress: isLongPress
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

    /// Veils the photo with ultraThinMaterial as the user commits to a
    /// gallery, but caps at 0.85 so a sliver of the photo always bleeds
    /// through (no full blackout at 100% pull). Long-press keeps the photo
    /// readable behind a much lighter veil.
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
    /// but the sidebar ignores touches: letting go of the drag past halfway
    /// opens Manage (see `SwipeView.handleSwipeEnd`), so the finger never
    /// has to lift and tap.
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
    let isHighlighted: Bool
    let isDragging: Bool
    let dragProgress: CGFloat
    var isLongPress: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            // Flat colour base — tints non-highlighted rows and carries the
            // long-press states. Highlighted rows get the full 0.85 fill.
            neonColor
                .opacity(backgroundOpacity)

            // Signal 1: a directional gradient layered on the highlighted row
            // for richness, without needing a secondary palette colour.
            LinearGradient(
                colors: [neonColor, neonColor.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(isHighlighted ? 0.6 : 0)

            // Signal 2: a 3pt leading bar. Luminance-independent, so even pale
            // neons (#FFE600, #00FFEE) read as an unambiguous "you're here".
            Rectangle()
                .fill(neonColor)
                .frame(width: 3)
                .opacity(isHighlighted ? 1.0 : 0.0)

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
            .foregroundStyle(textColor)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .opacity(textOpacity)
            .scaleEffect(isHighlighted ? 1.06 : 1.0, anchor: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isHighlighted)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }

    /// White only on the drop target. Other rows sit on their own gallery
    /// colour, so they use the shared contrast helper: white on dark tints
    /// (e.g. #3D00CC in light mode), the normal text colour otherwise.
    private var textColor: Color {
        if isHighlighted { return .white }
        guard isDragging else { return .secondary }
        return neonColor.foregroundOnTintedGlass(in: colorScheme)
    }

    private var backgroundOpacity: Double {
        guard isDragging else { return 0 }
        if isLongPress, !isHighlighted { return 0.6 }
        return isHighlighted ? 0.85 : 0.2 + 0.4 * dragProgress
    }

    /// Ramps continuously with dragProgress instead of jumping when isDragging
    /// flips. At rest = 0.5; full drag, non-highlighted = 0.7; full drag,
    /// highlighted = 1.0. Avoids the small pop the step function produced.
    private var textOpacity: Double {
        let p = Double(max(0, min(1, dragProgress)))
        let target: Double = isHighlighted ? 1.0 : 0.7
        return 0.5 + (target - 0.5) * p
    }
}
