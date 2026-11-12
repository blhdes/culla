import SwiftUI

/// One gallery in the Galleries list. Tapping the circle turns it on or off
/// for swiping; in Edit mode the name becomes a text field.
struct GalleriesRow: View {
    @Bindable var gallery: Gallery
    /// Selected for swiping.
    let isActive: Bool
    /// The gallery's own colour, or the app accent in "accent" sidebar mode.
    let color: Color
    let isEditing: Bool
    let onToggleSelection: () -> Void
    let onSubmitName: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Active = selected for swiping. The card glows with the gallery's own
        // color when active — Culla's per-gallery identity carrying the
        // "selected" state (vs. a generic accent halo).
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        HStack(spacing: 14) {
            if isEditing {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(0.6), radius: 5)
            } else {
                Button { onToggleSelection() } label: {
                    selectionCircle
                }
                .buttonStyle(.plain)
            }

            // When the row is active, the glass picks up the tint colour —
            // some hues are dark enough that .primary text collides.
            // `foregroundOnTintedGlass` flips to white only when needed.
            let labelColor: Color = isActive
                ? color.foregroundOnTintedGlass(in: colorScheme)
                : .primary

            if isEditing {
                TextField("Gallery name", text: $gallery.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor)
                    .onSubmit {
                        onSubmitName()
                    }
            } else {
                Text(gallery.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(labelColor)
            }

            Spacer()

            Text("\(gallery.sortedPhotos.count)")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(isActive ? labelColor.opacity(0.7) : .secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .glassSurface(in: shape, tint: isActive ? color : nil)
        .overlay(
            shape.strokeBorder(
                isActive ? color.opacity(0.5) : .white.opacity(0.06),
                lineWidth: isActive ? 1.4 : 1
            )
        )
        .shadow(color: isActive ? color.opacity(0.3) : .clear, radius: 14, y: 6)
        .animation(.snappy(duration: 0.25), value: isActive)
    }

    private var selectionCircle: some View {
        ZStack {
            Circle()
                .fill(isActive ? color : Color.clear)
                .overlay(
                    Circle().strokeBorder(color.opacity(isActive ? 0 : 0.45), lineWidth: 1.5)
                )
                .frame(width: 24, height: 24)
                .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: 5)
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}
