import SwiftUI

/// One sortable field — a single column the menu lists once. Direction lives
/// outside the field (the chip flips it when you re-pick the active field), so
/// the menu shows N fields instead of N×2 (field, direction) rows. Concrete
/// enums (e.g. `GallerySortField`) conform to this so the chip can render any of
/// them with one generic implementation.
protocol SortFieldProtocol: CaseIterable, Identifiable, Hashable {
    var label: String { get }
    /// The direction a field lands on the first time you switch to it — Name
    /// reads best A→Z (`false`), dates and counts best newest/biggest first
    /// (`true`). `nil` marks a field with no direction (e.g. a fixed manual
    /// order); the chip then shows a checkmark instead of an arrow and re-picking
    /// it is a no-op.
    var defaultDescending: Bool? { get }
}

/// Compact glass icon button that opens a menu of sort **fields**. Shared by the
/// gallery sheets so they all sort with the exact same control.
///
/// **One row per field, re-tap to flip.** Instead of listing every
/// (field, direction) pair — "Name (A→Z)", "Name (Z→A)", … — the menu lists
/// each field once; picking the field that's already active flips its direction
/// instead (the active row shows a ↑/↓ arrow). This is the native iOS sort idiom
/// (Files, Mail, Photos) and halves the menu.
///
/// **Icon-only on purpose.** Showing the active label inline would resize the
/// chip whenever a different-length label became active, which flickers. A
/// fixed-size icon can't resize. The current selection still reaches VoiceOver
/// via `accessibilityValue`, and the open menu shows the active field's arrow.
///
/// **Press chrome.** A `Menu` with a custom label makes iOS draw its own lift
/// platter on touch, which crops under a non-rectangular shape. On iOS 26 the
/// native `.glass` button style + a `.circle` border shape means the button *is*
/// the glass, so iOS morphs that exact circle into the menu — no platter to
/// crop. Pre-26 falls back to a flat `.thinMaterial` circle.
struct SortChip<Field: SortFieldProtocol>: View where Field.AllCases: RandomAccessCollection {
    @Binding var field: Field
    @Binding var descending: Bool

    var body: some View {
        Menu {
            ForEach(Field.allCases) { option in
                Button {
                    select(option)
                } label: {
                    if let symbol = trailingSymbol(for: option) {
                        Label(option.label, systemImage: symbol)
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .modifier(SortChipChrome())
        .accessibilityLabel("Sort")
        .accessibilityValue(accessibilityValue)
    }

    /// Re-picking the active field flips its direction — the "double use" that
    /// lets one row replace the old asc/desc pair. Picking a different field
    /// switches to it and lands on that field's natural direction. A field with
    /// no direction (`defaultDescending == nil`, e.g. "Custom") just selects;
    /// there's nothing to flip.
    private func select(_ option: Field) {
        if option == field {
            guard option.defaultDescending != nil else { return }
            descending.toggle()
        } else {
            field = option
            descending = option.defaultDescending ?? false
        }
    }

    /// Trailing glyph in the menu: an up/down arrow on the active directional
    /// field (showing which way it points), a checkmark on an active
    /// directionless field, and nothing on the rest.
    private func trailingSymbol(for option: Field) -> String? {
        guard option == field else { return nil }
        guard option.defaultDescending != nil else { return "checkmark" }
        return descending ? "arrow.down" : "arrow.up"
    }

    private var accessibilityValue: String {
        field.defaultDescending != nil
            ? "\(field.label), \(descending ? String(localized: "descending") : String(localized: "ascending"))"
            : field.label
    }
}

/// Applies the menu/button chrome that suppresses iOS's lift platter, branching
/// on OS so the iOS 26 glass morph is used where available and a flat circle
/// fallback elsewhere.
private struct SortChipChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                // Keep the interactive glass neutral, not accent-tinted —
                // matches the app's restrained-accent treatment on chrome.
                .tint(.secondary)
        } else {
            content
                .menuStyle(.button)
                .buttonStyle(.plain)
                .padding(8)
                .background(.thinMaterial, in: Circle())
        }
    }
}
