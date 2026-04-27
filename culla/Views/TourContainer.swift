import SwiftUI
import SwiftData

/// Full-screen tour overlay: dim canvas with spotlight cutout + pulsing ring + floating bubble.
/// The canvas has allowsHitTesting(false) so touches pass through to the app beneath.
/// Only the bubble's buttons capture touches.
struct TourContainer: View {
    @Binding var currentStep: TourStep
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int
    let onComplete: () -> Void

    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @Environment(\.appAccent) private var accent

    @State private var glowing = false
    // geo.safeAreaInsets returns 0 inside an ignoresSafeArea GeometryReader,
    // so we grab both values from UIKit once on appear.
    @State private var realSafeTop: CGFloat = 0
    @State private var realSafeBottom: CGFloat = 0

    private var activeCount: Int {
        sidebarGalleryIDs.filter { id in galleries.contains { $0.id == id } }.count
    }

    private var canContinue: Bool {
        switch currentStep {
        case .setupGallery:    return !galleries.isEmpty
        case .activateGallery: return activeCount > 0
        default:               return true
        }
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
                    if let spot = currentStep.spotlightRect(geo: geo, safeTop: realSafeTop, safeBottom: realSafeBottom) {
                        var ctx = context
                        ctx.blendMode = .destinationOut
                        let expanded = spot.rect.insetBy(dx: -6, dy: -6)
                        ctx.fill(
                            Path(roundedRect: expanded, cornerRadius: spot.cornerRadius + 6),
                            with: .color(.white.opacity(0.999))
                        )
                    }
                }
                .drawingGroup()
                .allowsHitTesting(false)
                .ignoresSafeArea()

                // Layer 2: pulsing glow ring around spotlight (no hit testing)
                if let spot = currentStep.spotlightRect(geo: geo, safeTop: realSafeTop, safeBottom: realSafeBottom) {
                    let expanded = spot.rect.insetBy(dx: -6, dy: -6)
                    RoundedRectangle(cornerRadius: spot.cornerRadius + 6)
                        .strokeBorder(accent.opacity(glowing ? 0.75 : 0.25), lineWidth: 2)
                        .frame(width: expanded.width, height: expanded.height)
                        .shadow(color: accent.opacity(glowing ? 0.5 : 0.1), radius: glowing ? 10 : 3)
                        .position(x: expanded.midX, y: expanded.midY)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowing)
                }

                // Layer 3: bubble (interactive)
                TourBubble(
                    step: currentStep,
                    canContinue: canContinue,
                    galleriesCount: galleries.count,
                    activeCount: activeCount,
                    onNext: advance,
                    onSkip: advance,
                    onComplete: onComplete
                )
                .frame(maxWidth: min(320, geo.size.width - 40))
                .position(currentStep.bubbleCenter(geo: geo, safeTop: realSafeTop, safeBottom: realSafeBottom))
                .id(currentStep)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
        .ignoresSafeArea()
        .task(id: currentStep) {
            if realSafeTop == 0 {
                let insets = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first?.safeAreaInsets
                realSafeTop    = insets?.top    ?? 47
                realSafeBottom = insets?.bottom ?? 34
            }
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
