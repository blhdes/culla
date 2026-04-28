import SwiftUI
import SwiftData
import Photos

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

/// Shows the app icon until the content is ready, then gates paywall and walkthrough.
private struct SplashGate: View {
    @State private var isReady = false
    @AppStorage("hasSeenPaywall") private var hasSeenPaywall = false
    @AppStorage(OnboardingKey.walkthroughComplete) private var hasCompletedWalkthrough = false
    @State private var showPaywall = false
    @State private var showWalkthrough = false
    @State private var currentTourStep: TourStep = .welcome
    @State private var paywallDismissible = true
    @State private var sidebarGalleryIDs: Set<UUID> = {
        guard let data = UserDefaults.standard.data(forKey: "sidebarGalleryIDs"),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data)
        else { return [] }
        return ids
    }()

    @Environment(SubscriptionManager.self) private var subscriptions

    private var maxSidebarGalleries: Int {
        subscriptions.isPro ? 10 : SubscriptionManager.freeGalleryLimit
    }

    var body: some View {
        ZStack {
            ContentView(isReady: $isReady, sidebarGalleryIDs: $sidebarGalleryIDs, maxSidebarGalleries: maxSidebarGalleries)
                .opacity(isReady ? 1 : 0)

            if !isReady {
                splashView
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: isReady)
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(
                onClose: { showPaywall = false },
                dismissible: paywallDismissible
            )
            .interactiveDismissDisabled(!paywallDismissible)
        }
        .onChange(of: showPaywall) { _, isShowing in
            guard !isShowing else { return }
            // Fires for every dismiss path: X button, swipe, purchase, restore
            hasSeenPaywall = true
            scheduleWalkthroughIfNeeded()
        }
        .overlayPreferenceValue(TourAnchorsKey.self) { anchors in
            // ignoresSafeArea is critical: the GeometryReader's origin must sit at
            // screen-(0,0) so that `proxy[anchor]` returns rects in the same
            // full-screen coordinate space the TourContainer renders into.
            // Otherwise spotlights drift up by safeTop and down by safeBottom.
            GeometryReader { proxy in
                if showWalkthrough {
                    TourContainer(
                        currentStep: $currentTourStep,
                        targetFrame: { target in
                            anchors[target].map { proxy[$0] }
                        },
                        onComplete: {
                            hasCompletedWalkthrough = true
                            showWalkthrough = false
                        }
                    )
                }
            }
            .ignoresSafeArea()
        }
        .environment(\.activeTourStep, showWalkthrough ? currentTourStep : nil)
        .environment(\.tourAdvance, showWalkthrough ? { advanceTour() } : nil)
        .environment(\.tourSetStep, showWalkthrough ? { newStep in
            withAnimation(.easeInOut(duration: 0.25)) {
                currentTourStep = newStep
            }
        } : nil)
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            if subscriptions.trialExpired {
                paywallDismissible = false
                showPaywall = true
            } else if !hasSeenPaywall {
                paywallDismissible = true
                showPaywall = true
            } else {
                // App update: paywall already seen but walkthrough not yet done
                scheduleWalkthroughIfNeeded()
            }
        }
        .onChange(of: subscriptions.trialExpired) { _, expired in
            if expired && !showPaywall {
                paywallDismissible = false
                showPaywall = true
            }
        }
        .onChange(of: PhotoLibraryService.shared.authorizationStatus) { _, newStatus in
            if newStatus == .authorized || newStatus == .limited {
                scheduleWalkthroughIfNeeded()
            }
        }
        .onChange(of: sidebarGalleryIDs) { _, newValue in
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "sidebarGalleryIDs")
            }
        }
    }

    private func advanceTour() {
        let all = TourStep.allCases
        guard let i = all.firstIndex(of: currentTourStep), i + 1 < all.count else {
            hasCompletedWalkthrough = true
            showWalkthrough = false
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentTourStep = all[i + 1]
        }
    }

    private func scheduleWalkthroughIfNeeded() {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard !hasCompletedWalkthrough,
              !subscriptions.trialExpired,
              photoStatus == .authorized || photoStatus == .limited else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            currentTourStep = .welcome
            showWalkthrough = true
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
