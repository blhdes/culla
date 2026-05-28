import SwiftUI

/// Big glass-framed SF symbol used as the "identity block" on screens that
/// don't have artwork of their own (empty states, the Duplicate Sweep
/// scanning / done states). Replaces the bare
/// `Image(systemName:).font(.system(size: 48))` pattern those screens used.
///
/// Supports two motion modes:
/// - `pulse` (continuous) — for inviting/expectant states like a scan in
///   progress. Reads as "the app is alive and working."
/// - `bounceOnAppear` (one-shot) — for celebratory states like an
///   "all caught up" checkmark. Fires once when the tile mounts.
///
/// Both motion modes respect `accessibilityReduceMotion` automatically because
/// `symbolEffect` honors it at the system level.
struct HeroIconTile: View {
    let systemName: String
    var size: CGFloat = 112
    var foreground: Color = .secondary
    var pulse: Bool = false
    var bounceOnAppear: Bool = false

    @State private var appeared: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .light))
            .foregroundStyle(foreground)
            .symbolEffect(.pulse, options: .repeating, isActive: pulse)
            .symbolEffect(.bounce, value: bounceOnAppear ? appeared : false)
            .frame(width: size, height: size)
            .glassSurface(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .onAppear {
                // Defer one tick so the bounce fires *after* the tile has been
                // laid out — firing on the same frame as mount sometimes
                // doesn't register with SwiftUI's symbol-effect coordinator.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    appeared = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 32) {
        HeroIconTile(systemName: "square.on.square", pulse: true)
        HeroIconTile(systemName: "checkmark.circle.fill", foreground: .green, bounceOnAppear: true)
    }
    .padding(40)
    .environment(\.appAccent, .blue)
}
