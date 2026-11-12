import SwiftUI

/// The first-launch tour: the screen dims, a cutout and a ring mark one control,
/// and a card explains it. The dim and the ring ignore touches, so the app
/// underneath stays usable the whole time.
///
/// The spotlight rect comes from `targetFrame`, which reads the real on-screen
/// frames from anchor preferences, so it always sits on the actual control.
struct TourContainer: View {
    @Binding var currentStep: TourStep
    let targetFrame: (TourTarget) -> CGRect?
    let onComplete: () -> Void

    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringBright = false
    @State private var cardShown = false

    private let style = TourStyle.current

    /// The highlighted control's frame, with a little air around it.
    private var spotlightRect: CGRect? {
        guard let target = currentStep.spotlightTarget else { return nil }
        return targetFrame(target)?.insetBy(dx: -6, dy: -6)
    }

    private var spotlightShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: currentStep.spotlightCornerRadius + 6, style: .continuous)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                dim
                ring
                TourCard(step: currentStep, onNext: advance, onSkip: onComplete)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, cardBottomPadding(screenHeight: geo.size.height))
                    .offset(y: cardShown ? 0 : 28)
                    .opacity(cardShown ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        // One spring moves the cutout, the ring and the card together.
        .animation(style.spring, value: currentStep)
        .onAppear {
            withAnimation(style.spring.delay(0.15)) { cardShown = true }
            guard style.ringPulse, !reduceMotion else { ringBright = true; return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { ringBright = true }
        }
        .onChange(of: spotlightRect == nil) { _, isMissing in
            // The highlighted control is gone: the user tapped it and left the home
            // screen (Start began a session, for example). The tour's job is done.
            if isMissing, currentStep.spotlightTarget != nil { onComplete() }
        }
    }

    /// Dims everything except the highlighted control. Drawn as one group so the
    /// cutout moves and resizes with the same animation as the ring.
    private var dim: some View {
        ZStack {
            Color.black.opacity(style.dimOpacity)
            if let spot = spotlightRect {
                spotlightShape
                    .frame(width: spot.width, height: spot.height)
                    .position(x: spot.midX, y: spot.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    /// Only the ring's opacity pulses. Animating its line width redraws the shape
    /// on every frame, and opacity does not.
    @ViewBuilder
    private var ring: some View {
        if let spot = spotlightRect {
            spotlightShape
                .strokeBorder(accent, lineWidth: style.ringWidth)
                .frame(width: spot.width, height: spot.height)
                .position(x: spot.midX, y: spot.midY)
                .opacity(ringBright ? 1 : 0.4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The card rests at the bottom of the screen. On the last stop it steps up
    /// so it sits just above the Start button it is talking about.
    private func cardBottomPadding(screenHeight: CGFloat) -> CGFloat {
        guard currentStep == .start, let spot = spotlightRect else { return 12 }
        return screenHeight - spot.minY + 16
    }

    private func advance() {
        Haptics.tourStep()
        guard let next = currentStep.next else { onComplete(); return }
        currentStep = next
    }
}
