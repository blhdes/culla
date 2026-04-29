import SwiftUI

/// Full-screen tour overlay: dim canvas with spotlight cutout + pulsing ring + floating bubble.
/// The canvas has allowsHitTesting(false) so touches pass through to the app beneath.
/// Only the bubble's buttons capture touches.
///
/// The spotlight rect comes from `targetFrame` — a closure that resolves real on-screen
/// frames from anchor preferences, so the spotlight always sits on the actual element
/// regardless of iOS layout changes.
struct TourContainer: View {
    @Binding var currentStep: TourStep
    let targetFrame: (TourTarget) -> CGRect?
    let onComplete: () -> Void

    @Environment(\.appAccent) private var accent
    @State private var glowing = false

    private var spotlightRect: CGRect? {
        guard let target = currentStep.spotlightTarget else { return nil }
        return targetFrame(target)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: animatable dim + spotlight cutout (no hit testing).
                // Using ZStack + compositingGroup instead of Canvas so the cutout
                // position/size interpolates with the same easing as the bubble,
                // eliminating the ghost-frame mismatch during step transitions.
                ZStack {
                    Color.black.opacity(0.58)
                    if let spot = spotlightRect {
                        let expanded = spot.insetBy(dx: -6, dy: -6)
                        RoundedRectangle(cornerRadius: currentStep.spotlightCornerRadius + 6)
                            .frame(width: expanded.width, height: expanded.height)
                            .position(x: expanded.midX, y: expanded.midY)
                            .blendMode(.destinationOut)
                            .transition(.opacity)
                    }
                }
                .compositingGroup()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: currentStep)

                // Layer 2: pulsing glow ring around spotlight (no hit testing)
                if let spot = spotlightRect {
                    let expanded = spot.insetBy(dx: -6, dy: -6)
                    RoundedRectangle(cornerRadius: currentStep.spotlightCornerRadius + 6)
                        .strokeBorder(accent.opacity(glowing ? 0.85 : 0.3), lineWidth: glowing ? 2.5 : 1.5)
                        .frame(width: expanded.width, height: expanded.height)
                        .position(x: expanded.midX, y: expanded.midY)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowing)
                        .animation(.easeInOut(duration: 0.25), value: currentStep)
                }

                // Layer 3: bubble (interactive)
                TourBubble(
                    step: currentStep,
                    onNext: advance,
                    onComplete: onComplete
                )
                .frame(maxWidth: min(320, geo.size.width - 40))
                .position(currentStep.bubbleCenter(geo: geo, spotlight: spotlightRect))
                .id(currentStep)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
        .ignoresSafeArea()
        // Key on spotlightTarget so the glow only resets when the actual target
        // changes — consecutive steps pointing at the same element stay still.
        .task(id: currentStep.spotlightTarget) {
            glowing = false
            try? await Task.sleep(for: .milliseconds(120))
            glowing = true
        }
    }

    private func advance() {
        let all = TourStep.allCases
        guard let i = all.firstIndex(of: currentStep), i + 1 < all.count else {
            onComplete()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = all[i + 1]
        }
    }
}
