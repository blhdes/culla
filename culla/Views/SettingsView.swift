import SwiftUI
import StoreKit

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("customPaletteHexes") private var customPaletteHexes = ""
    @AppStorage("dynamicBackgroundMode") private var backgroundMode = "off"
    @AppStorage("monochromeBackground") private var monochrome = false

    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionManager.self) private var subscriptions

    @State private var selectedSwatchIndex: Int = 0
    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var showRestoreError = false
    @State private var restoreError: Error?

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
                }

                Section("Dynamic background") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Mode", selection: $backgroundMode) {
                            Text("Off").tag("off")
                            Text("Gallery").tag("gallery")
                            Text("Favourites").tag("favourites")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)

                    if backgroundMode != "off" {
                        Toggle("Monochrome", isOn: $monochrome)
                    }
                }

                Section("Help") {
                    Button("Restart tutorial") {
                        restartTutorial()
                    }
                    .foregroundStyle(.primary)
                }

                // MARK: - FREEMIUM HIDDEN — restore in vNext
                // The Subscription section is hidden while the freemium model is
                // disabled (everyone is Pro). Original block preserved below.
                //
                // Section("Subscription") {
                //     if subscriptions.isPro {
                //         Button("Manage subscription") { showCustomerCenter = true }
                //             .foregroundStyle(.primary)
                //     } else {
                //         Button("Upgrade to Culla Pro") { showPaywall = true }
                //             .foregroundStyle(.primary)
                //         Button("Restore purchases") {
                //             Task { await restore() }
                //         }
                //         .foregroundStyle(.primary)
                //     }
                // }
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
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(onClose: { showPaywall = false })
        }
        .manageSubscriptionsSheet(isPresented: $showCustomerCenter)
        .alert("Restore failed", isPresented: $showRestoreError, presenting: restoreError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .onChange(of: accentMode) { _, newMode in
            guard newMode == "custom" else { return }
            guard subscriptions.isPro else {
                accentMode = "random"
                showPaywall = true
                return
            }
            if customAccentHex.isEmpty {
                selectedSwatchIndex = 0
                customAccentHex = paletteHexes[0]
            } else {
                selectedSwatchIndex = paletteHexes.firstIndex(of: customAccentHex) ?? 0
            }
        }
        .onChange(of: backgroundMode) { _, newMode in
            guard newMode != "off" && !subscriptions.isPro else { return }
            backgroundMode = "off"
            showPaywall = true
        }
        .onAppear {
            if accentMode == "custom" && !customAccentHex.isEmpty {
                selectedSwatchIndex = paletteHexes.firstIndex(of: customAccentHex) ?? 0
            }
        }
    }

    private func restartTutorial() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: OnboardingKey.walkthroughComplete)
        defaults.set(false, forKey: OnboardingKey.calendarTooltipSeen)
        defaults.set(false, forKey: OnboardingKey.zoomTooltipSeen)
        defaults.set(false, forKey: OnboardingKey.swipeHintSeen)
        defaults.set(false, forKey: OnboardingKey.skipTooltipSeen)
        dismiss()
    }

    private func restore() async {
        do {
            try await subscriptions.restorePurchases()
            if !subscriptions.isPro {
                restoreError = NSError(
                    domain: "Culla",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "No active subscription found on this account."]
                )
                showRestoreError = true
            }
        } catch {
            restoreError = error
            showRestoreError = true
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
