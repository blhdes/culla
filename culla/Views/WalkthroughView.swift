import SwiftUI
import SwiftData

struct WalkthroughView: View {
    @Binding var sidebarGalleryIDs: Set<UUID>
    let maxSidebarGalleries: Int
    var onComplete: () -> Void

    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @Environment(\.appAccent) private var accent

    @State private var currentStep: WalkthroughStep = .welcome
    @State private var showGalleries = false

    private var activeGalleryCount: Int {
        sidebarGalleryIDs.filter { id in galleries.contains { $0.id == id } }.count
    }

    private var canContinue: Bool {
        switch currentStep {
        case .setupGallery:    return !galleries.isEmpty
        case .activateGallery: return activeGalleryCount > 0
        default:               return true
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                stepCard
                    .id(currentStep)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))

                Spacer()

                bottomControls
                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showGalleries) {
            NavigationStack {
                GalleriesView(sidebarGalleryIDs: $sidebarGalleryIDs, maxSidebarGalleries: maxSidebarGalleries)
            }
        }
    }

    // MARK: - Step Card

    private var stepCard: some View {
        VStack(spacing: 20) {
            Image(systemName: currentStep.icon)
                .font(.system(size: 52))
                .foregroundStyle(accent)

            VStack(spacing: 10) {
                Text(currentStep.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(currentStep.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status = gateStatus {
                HStack(spacing: 6) {
                    Image(systemName: status.unlocked ? "checkmark.circle.fill" : "lock.fill")
                        .font(.caption)
                    Text(status.label)
                        .font(.caption)
                }
                .foregroundStyle(status.unlocked ? .green : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (status.unlocked ? Color.green : Color.gray).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .animation(.easeInOut(duration: 0.3), value: status.unlocked)
            }

            if currentStep.requiresAction {
                Button {
                    showGalleries = true
                } label: {
                    HStack(spacing: 6) {
                        Text("Open Galleries")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(accent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 20)
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            progressDots

            if currentStep.isSkippable {
                Button("Skip this step") { advance() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                if currentStep == .readyToSwipe {
                    onComplete()
                } else {
                    advance()
                }
            } label: {
                Text(currentStep == .readyToSwipe ? "Let's Go!" : "Continue")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canContinue ? .white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        canContinue ? AnyShapeStyle(accent) : AnyShapeStyle(Color.gray.opacity(0.25)),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .disabled(!canContinue)
            .animation(.easeInOut(duration: 0.2), value: canContinue)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(WalkthroughStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == currentStep ? accent : Color.white.opacity(0.3))
                    .frame(
                        width: step == currentStep ? 8 : 5,
                        height: step == currentStep ? 8 : 5
                    )
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
    }

    // MARK: - Gate Status

    private var gateStatus: (label: String, unlocked: Bool)? {
        switch currentStep {
        case .setupGallery:
            let n = galleries.count
            return n == 0
                ? ("Create or import a gallery to continue", false)
                : ("\(n) \(n == 1 ? "gallery" : "galleries") ready", true)
        case .activateGallery:
            let n = activeGalleryCount
            return n == 0
                ? ("Activate at least one gallery to continue", false)
                : ("\(n) \(n == 1 ? "gallery" : "galleries") active", true)
        default:
            return nil
        }
    }

    // MARK: - Advance

    private func advance() {
        let all = WalkthroughStep.allCases
        guard let i = all.firstIndex(of: currentStep), i + 1 < all.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = all[i + 1]
        }
    }
}

// MARK: - Step Model

enum WalkthroughStep: Int, CaseIterable {
    case welcome
    case pickDate
    case whatAreGalleries
    case setupGallery
    case changeColor
    case activateGallery
    case readyToSwipe

    var icon: String {
        switch self {
        case .welcome:          return "hand.wave.fill"
        case .pickDate:         return "calendar"
        case .whatAreGalleries: return "rectangle.stack.fill"
        case .setupGallery:     return "plus.rectangle.on.rectangle"
        case .changeColor:      return "paintpalette.fill"
        case .activateGallery:  return "checkmark.circle.fill"
        case .readyToSwipe:     return "bolt.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome:          return "Welcome to Culla"
        case .pickDate:         return "Pick a Date"
        case .whatAreGalleries: return "Your Galleries"
        case .setupGallery:     return "Set Up a Gallery"
        case .changeColor:      return "Make It Yours"
        case .activateGallery:  return "Activate for Swiping"
        case .readyToSwipe:     return "You're Ready!"
        }
    }

    var body: String {
        switch self {
        case .welcome:
            return "Culla helps you sort through your photo library — one swipe at a time."
        case .pickDate:
            return "Use the wheel to choose a date. Culla shows photos from that day. Tap the wheel to open a full calendar view."
        case .whatAreGalleries:
            return "Galleries are the destinations for your photos. Swipe right on a photo and it flies into the gallery you pick — each one syncs with an iPhone album."
        case .setupGallery:
            return "You need at least one gallery before you can start swiping. Import an existing iPhone album, or create a new one from scratch."
        case .changeColor:
            return "Tap any gallery in the list, then tap the small color circle at the top to give it a neon color."
        case .activateGallery:
            return "Tap the colored circle next to any gallery to activate it for your session. Active galleries appear as swipe targets when you swipe right."
        case .readyToSwipe:
            return "You're all set. Pick a date, tap Start Cullaing, and swipe. Left to dismiss, right to sort, up to favourite, down to share."
        }
    }

    var requiresAction: Bool {
        switch self {
        case .setupGallery, .changeColor, .activateGallery: return true
        default: return false
        }
    }

    var isSkippable: Bool { self == .changeColor }
}
