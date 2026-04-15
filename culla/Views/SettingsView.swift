import SwiftUI

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("customPaletteHexes") private var customPaletteHexes = ""
    @AppStorage("dynamicBackgroundMode") private var backgroundMode = "gallery"

    @Environment(\.dismiss) private var dismiss

    @State private var selectedSwatchIndex: Int = 0

    private let swatchColumns = Array(repeating: GridItem(.flexible()), count: 6)

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
        NavigationStack {
            Form {
                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Theme", selection: $colorSchemeString) {
                            Text("System").tag("system")
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accent colour")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Accent colour", selection: $accentMode) {
                            Text("Random").tag("random")
                            Text("Custom").tag("custom")
                        }
                        .pickerStyle(.segmented)

                        if accentMode == "custom" {
                            LazyVGrid(columns: swatchColumns, spacing: 12) {
                                ForEach(0..<12, id: \.self) { i in
                                    colorSwatch(index: i, hex: paletteHexes[i])
                                }
                            }
                            .padding(.top, 4)

                            ColorPicker("Edit colour", selection: Binding(
                                get: { Color.adaptiveNeon(hex: paletteHexes[selectedSwatchIndex]) },
                                set: { newColor in
                                    var updated = paletteHexes
                                    let newHex = newColor.hexString
                                    updated[selectedSwatchIndex] = newHex
                                    savePalette(updated)
                                    customAccentHex = newHex
                                }
                            ), supportsOpacity: false)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.easeInOut(duration: 0.2), value: accentMode)
                }

                Section("Interface") {
                    Toggle("Show status bar", isOn: $statusBarVisible)
                    Toggle("Culla Eyes", isOn: $showCullaEyes)
                    Toggle("Haptics", isOn: $hapticsEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dynamic background")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Dynamic background", selection: $backgroundMode) {
                            Text("Off").tag("off")
                            Text("Gallery").tag("gallery")
                            Text("Favourites").tag("favourites")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: accentMode) { _, newMode in
            guard newMode == "custom" else { return }
            if customAccentHex.isEmpty {
                selectedSwatchIndex = 0
                customAccentHex = paletteHexes[0]
            } else {
                selectedSwatchIndex = paletteHexes.firstIndex(of: customAccentHex) ?? 0
            }
        }
        .onAppear {
            if accentMode == "custom" && !customAccentHex.isEmpty {
                selectedSwatchIndex = paletteHexes.firstIndex(of: customAccentHex) ?? 0
            }
        }
    }

    @ViewBuilder
    private func colorSwatch(index: Int, hex: String) -> some View {
        let isSelected = selectedSwatchIndex == index
        Circle()
            .fill(Color.adaptiveNeon(hex: hex))
            .frame(width: 40, height: 40)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .onTapGesture {
                selectedSwatchIndex = index
                customAccentHex = hex
            }
    }
}
