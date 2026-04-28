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
                // Layer 1: dim + spotlight cutout (no hit testing)
                Canvas { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.black.opacity(0.58))
                    )
                    if let spot = spotlightRect {
                        var ctx = context
                        ctx.blendMode = .destinationOut
                        let expanded = spot.insetBy(dx: -6, dy: -6)
                        ctx.fill(
                            Path(roundedRect: expanded, cornerRadius: currentStep.spotlightCornerRadius + 6),
                            with: .color(.white.opacity(0.999))
                        )
                    }
                }
                .drawingGroup()
                .allowsHitTesting(false)
                .ignoresSafeArea()

                // Layer 2: pulsing glow ring around spotlight (no hit testing)
                if let spot = spotlightRect {
                    let expanded = spot.insetBy(dx: -6, dy: -6)
                    RoundedRectangle(cornerRadius: currentStep.spotlightCornerRadius + 6)
                        .strokeBorder(accent.opacity(glowing ? 0.85 : 0.3), lineWidth: glowing ? 2.5 : 1.5)
                        .frame(width: expanded.width, height: expanded.height)
                        .position(x: expanded.midX, y: expanded.midY)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowing)
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
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
        .ignoresSafeArea()
        .task(id: currentStep) {
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
