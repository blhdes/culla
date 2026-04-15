import SwiftUI
import SwiftData

@main
struct CullaApp: App {
    /// Fresh random neon picked once per cold launch — stable for the full session.
    private static let sessionRandomHex: String = Color.neonHexes.randomElement()!

    @AppStorage("accentColorMode") private var accentMode = "random"
    @AppStorage("customAccentHex") private var customAccentHex = ""
    @AppStorage("appColorScheme") private var colorSchemeString = "system"
    @AppStorage("statusBarVisible") private var statusBarVisible = false

    var body: some Scene {
        WindowGroup {
            SplashGate()
                .tint(.primary)
                .environment(\.appAccent, currentAccent)
                .preferredColorScheme(preferredScheme)
                .statusBarHidden(!statusBarVisible)
        }
        .modelContainer(for: [Gallery.self, SortedPhoto.self, DismissedPhoto.self, DailyStats.self])
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
