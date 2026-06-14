import SwiftUI
import StoreKit

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("includeVideos") private var includeVideos = true
    @AppStorage("customPaletteHexes") private var customPaletteHexes = ""
    @AppStorage("dynamicBackgroundMode") private var backgroundMode = "off"
    @AppStorage("dynamicBackgroundStyle") private var backgroundStyle = "stream"
    @AppStorage("backgroundBlur") private var backgroundBlur = 7.0
    @AppStorage("monochromeBackground") private var monochrome = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
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

    // A sheet runs in its own presentation host, so `.preferredColorScheme`
    // set on the presenter doesn't update this view live — only on the next
    // re-presentation. Mirror it here so the toggle takes effect instantly.
    private var sheetColorScheme: ColorScheme? {
        switch colorSchemeString {
        case "light": .light
        case "dark":  .dark
        default:      nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    appearanceCard
                    interfaceCard
                    dynamicBackgroundCard
                    languageCard
                    helpCard
                    versionFooter

                    // MARK: - FREEMIUM HIDDEN — restore in vNext
                    // The Subscription card is hidden while the freemium model is
                    // disabled (everyone is Pro). Original block preserved below.
                    //
                    // SettingsCard(title: "Subscription") {
                    //     if subscriptions.isPro {
                    //         settingsButtonRow("Manage subscription") { showCustomerCenter = true }
                    //     } else {
                    //         settingsButtonRow("Upgrade to Culla Pro") { showPaywall = true }
                    //         settingsButtonRow("Restore purchases") { Task { await restore() } }
                    //     }
                    // }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
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
        .preferredColorScheme(sheetColorScheme)
    }

    // MARK: - Cards

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance") {
            labeledControl("Theme") {
                GlassChipPicker.theme(selection: $colorSchemeString)
            }

            rowDivider

            labeledControl("Accent colour") {
                VStack(spacing: 14) {
                    GlassChipPicker(selection: $accentMode, options: [
                        .init(id: "random", label: "Random", icon: "dice.fill"),
                        .init(id: "custom", label: "Custom", icon: "paintpalette.fill")
                    ])

                    if accentMode == "custom" {
                        LazyVGrid(columns: swatchColumns, spacing: 12) {
                            ForEach(0..<12, id: \.self) { i in
                                colorSwatch(index: i, hex: paletteHexes[i])
                            }
                        }

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
                        .font(.system(.subheadline, design: .rounded))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: accentMode)
        }
    }

    private var interfaceCard: some View {
        SettingsCard(title: "Interface") {
            SettingsToggleRow(title: "Show status bar", isOn: $statusBarVisible)
            // MARK: - CULLA EYES HIDDEN — restore in vNext
            // SettingsToggleRow(title: "Culla Eyes", isOn: $showCullaEyes)
            rowDivider
            SettingsToggleRow(title: "Haptics", isOn: $hapticsEnabled)
            rowDivider
            SettingsToggleRow(title: "Include videos", isOn: $includeVideos)
        }
    }

    private var dynamicBackgroundCard: some View {
        SettingsCard(title: "Dynamic background") {
            labeledControl("Mode") {
                GlassChipPicker(selection: $backgroundMode, options: [
                    .init(id: "off",        label: "Off"),
                    .init(id: "gallery",    label: "Gallery"),
                    .init(id: "favourites", label: "Favourites")
                ])
            }

            if backgroundMode != "off" {
                rowDivider
                labeledControl("Style") {
                    GlassChipPicker(selection: $backgroundStyle, options: [
                        .init(id: "stream", label: "Stream"),
                        .init(id: "mosaic", label: "Mosaic")
                    ])
                }
                rowDivider
                labeledControl("Blur") {
                    Slider(value: $backgroundBlur, in: 0...20)
                        .tint(accent)
                }
                rowDivider
                SettingsToggleRow(title: "Monochrome", isOn: $monochrome)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: backgroundMode)
    }

    // The picker itself lives in the system Settings app — iOS shows a
    // per-app Language row there automatically once the app ships more than
    // one localization, and changing it relaunches the app in that language.
    private var languageCard: some View {
        SettingsCard(title: "Language") {
            settingsButtonRow("App language", icon: "globe") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        }
    }

    private var helpCard: some View {
        SettingsCard(title: "Help") {
            settingsButtonRow("Restart tutorial", icon: "arrow.counterclockwise") {
                restartTutorial()
            }
        }
    }

    private var versionFooter: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let year = Calendar.current.component(.year, from: Date())
        let versionLine = build.isEmpty
            ? String(localized: "Version \(version)")
            : String(localized: "Version \(version) (\(build))")
        return VStack(spacing: 3) {
            Text("Culla")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Text(versionLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("© \(String(year)) Culla")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Row helpers

    /// A small secondary label stacked above a control — the calm-tier
    /// replacement for a Form row's leading label.
    @ViewBuilder
    private func labeledControl<Control: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsButtonRow(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
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
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "No active subscription found on this account.")]
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
                    selectedSwatchIndex = index
                }
                customAccentHex = hex
            }
            .animation(.snappy(duration: 0.22), value: isSelected)
    }
}
