import SwiftUI

/// The custom-accent swatch grid + colour editor, extracted out of
/// `SettingsView` so that screen stays under the extraction threshold and the
/// one "loud" element (a 12-circle wall of colour) lives in its own file.
///
/// Self-contained: it owns the `customAccentHex` / `customPaletteHexes`
/// defaults directly (same `@AppStorage` keys as the rest of the app, so they
/// stay in sync) and tracks its own selected swatch. It only renders while the
/// user is in "Custom" accent mode, so its `onAppear` doubles as the
/// entered-custom-mode initialiser.
struct AccentPalettePicker: View {
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("customPaletteHexes") private var customPaletteHexes = ""

    @State private var selectedIndex = 0

    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    private var paletteHexes: [String] {
        let stored = customPaletteHexes
            .split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        guard stored.count == 12 else { return Array(Color.neonHexes[0..<12]) }
        return stored.enumerated().map { i, hex in
            hex.isEmpty ? Color.neonHexes[i] : hex
        }
    }

    private func savePalette(_ hexes: [String]) {
        customPaletteHexes = hexes.joined(separator: ",")
    }

    var body: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<12, id: \.self) { i in
                    swatch(index: i, hex: paletteHexes[i])
                }
            }

            ColorPicker("Edit colour", selection: Binding(
                get: { Color.adaptiveNeon(hex: paletteHexes[selectedIndex]) },
                set: { newColor in
                    var updated = paletteHexes
                    let newHex = newColor.hexString
                    updated[selectedIndex] = newHex
                    savePalette(updated)
                    customAccentHex = newHex
                }
            ), supportsOpacity: false)
            .font(.system(.subheadline, design: .rounded))
        }
        .onAppear {
            // Entering custom mode: seed the accent on first use, otherwise
            // highlight whichever swatch matches the saved colour.
            if customAccentHex.isEmpty {
                selectedIndex = 0
                customAccentHex = paletteHexes[0]
            } else {
                selectedIndex = paletteHexes.firstIndex(of: customAccentHex) ?? 0
            }
        }
    }

    @ViewBuilder
    private func swatch(index: Int, hex: String) -> some View {
        let isSelected = selectedIndex == index
        let color = Color.adaptiveNeon(hex: hex)
        Circle()
            .fill(color)
            .frame(width: 40, height: 40)
            .overlay {
                Circle()
                    .stroke(.primary, lineWidth: isSelected ? 2 : 0)
                    .padding(-4)
            }
            .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 6)
            .frame(maxWidth: .infinity)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.snappy(duration: 0.22)) {
                    selectedIndex = index
                }
                customAccentHex = hex
            }
            .animation(.snappy(duration: 0.22), value: isSelected)
    }
}
