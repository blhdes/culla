import SwiftUI
import SwiftData

@main
struct CullaApp: App {
    /// Fresh random neon picked once per cold launch — stable for the full session.
    private static let sessionRandomHex: String = Color.neonHexes.randomElement()!

    /// Single container created once at launch — shared by every view, including sheets.
    let container: ModelContainer

    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("statusBarVisible") private var statusBarVisible = false

    init() {
        do {
            container = try ModelContainer(
                for: Gallery.self, SortedPhoto.self, DismissedPhoto.self, DailyStats.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SubscriptionManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            SplashGate()
                .modelContainer(container)
                .tint(.primary)
                .environment(\.appAccent, currentAccent)
                .environment(SubscriptionManager.shared)
                .preferredColorScheme(preferredScheme)
                .statusBarHidden(!statusBarVisible)
        }
    }

    private var currentAccent: Color {
        if accentMode == "custom" && !customAccentHex.isEmpty {
            return Color.adaptiveNeon(hex: customAccentHex)
        }
        return Color.adaptiveNeon(hex: Self.sessionRandomHex)
    }

    private var preferredScheme: ColorScheme? {
        switch colorSchemeString {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

/// Shows the app icon until the content is ready, then fades in.
private struct SplashGate: View {
    @State private var isReady = false
    @AppStorage("hasSeenPaywall") private var hasSeenPaywall = false
    @State private var showPaywall = false
    @State private var paywallDismissible = true

    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        ZStack {
            ContentView(isReady: $isReady)
                .opacity(isReady ? 1 : 0)

            if !isReady {
                splashView
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: isReady)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(
                onClose: {
                    hasSeenPaywall = true
                    showPaywall = false
                },
                dismissible: paywallDismissible
            )
            .interactiveDismissDisabled(!paywallDismissible)
        }
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            if subscriptions.trialExpired {
                // Trial has ended — force the paywall, no way out
                paywallDismissible = false
                showPaywall = true
            } else if !hasSeenPaywall {
                // First launch — soft paywall, user can dismiss
                paywallDismissible = true
                showPaywall = true
            }
        }
        .onChange(of: subscriptions.trialExpired) { _, expired in
            if expired && !showPaywall {
                paywallDismissible = false
                showPaywall = true
            }
        }
    }

    private var splashView: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text("culla")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.primary)
            }
        }
    }
}
