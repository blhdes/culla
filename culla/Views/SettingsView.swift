import SwiftUI

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("showCullaEyes") private var showCullaEyes = false

    @Environment(\.dismiss) private var dismiss

    private let swatchColumns = Array(repeating: GridItem(.flexible()), count: 6)

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
                                ForEach(Color.neonHexes, id: \.self) { hex in
                                    colorSwatch(hex: hex)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(.easeInOut(duration: 0.2), value: accentMode)
                }

                Section("Interface") {
                    Toggle("Show status bar", isOn: $statusBarVisible)
                    Toggle("Culla Eyes", isOn: $showCullaEyes)
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
            // Auto-select the first colour when switching to custom with nothing saved yet.
            if newMode == "custom" && customAccentHex.isEmpty {
                customAccentHex = Color.neonHexes[0]
            }
        }
    }

    @ViewBuilder
    private func colorSwatch(hex: String) -> some View {
        let isSelected = customAccentHex == hex
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
                customAccentHex = hex
            }
    }
}
