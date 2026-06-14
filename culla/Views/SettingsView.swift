import SwiftUI
import StoreKit

struct SettingsView: View {
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("sidebarTintMode") private var sidebarTintMode = "gallery"
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("showCullaEyes") private var showCullaEyes = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("includeVideos") private var includeVideos = true
    @AppStorage("dynamicBackgroundMode") private var backgroundMode = "off"
    @AppStorage("dynamicBackgroundStyle") private var backgroundStyle = "stream"
    @AppStorage("backgroundBlur") private var backgroundBlur = 7.0
    @AppStorage("monochromeBackground") private var monochrome = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appAccent) private var accent
    @Environment(SubscriptionManager.self) private var subscriptions

    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var showRestoreError = false
    @State private var restoreError: Error?

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
                    SettingsAppHeader()
                    appearanceCard
                    interfaceCard
                    dynamicBackgroundCard
                    languageCard
                    helpCard

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
            // Custom accent is a Pro feature — bounce non-subscribers back to
            // Random and show the paywall. The swatch picker handles its own
            // selection state once it appears.
            guard newMode == "custom", !subscriptions.isPro else { return }
            accentMode = "random"
            showPaywall = true
        }
        .onChange(of: backgroundMode) { _, newMode in
            guard newMode != "off" && !subscriptions.isPro else { return }
            backgroundMode = "off"
            showPaywall = true
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
                        AccentPalettePicker()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: accentMode)

            rowDivider

            labeledControl("Sidebar colour") {
                GlassChipPicker(selection: $sidebarTintMode, options: [
                    .init(id: "gallery", label: "Per gallery"),
                    .init(id: "accent",  label: "Accent")
                ])
            }
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
                blurControl
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

    /// Blur slider with a live numeric readout. The Slider alone gave no
    /// feedback — you couldn't tell whether you were at 3 or 17. The value
    /// ticks with `.numericText()` as you drag.
    private var blurControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Blur")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(backgroundBlur.rounded()))")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(value: $backgroundBlur, in: 0...20)
                .tint(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: Int(backgroundBlur.rounded()))
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

}
