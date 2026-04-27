import SwiftUI

struct TourBubble: View {
    let step: TourStep
    let canContinue: Bool
    let galleriesCount: Int
    let activeCount: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    let onComplete: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            if step.arrowEdge == .top {
                TourArrow().fill(.background).frame(width: 22, height: 11)
            }

            cardContent
                .background(.background, in: RoundedRectangle(cornerRadius: 18))

            if step.arrowEdge == .bottom {
                TourArrow()
                    .fill(.background)
                    .rotationEffect(.degrees(180))
                    .frame(width: 22, height: 11)
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: step.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(step.rawValue + 1) / \(TourStep.allCases.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(step.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if step.isGated {
                gateBadge
            }

            Divider()

            HStack {
                if step.isSkippable {
                    Button("Skip") { onSkip() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if step == .readyToSwipe {
                    nextButton(label: "Let's Go!", enabled: true)
                        .onTapGesture { onComplete() }
                } else {
                    nextButton(label: "Next", enabled: canContinue)
                        .onTapGesture { if canContinue { onNext() } }
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var gateBadge: some View {
        let (label, unlocked) = gateInfo
        HStack(spacing: 5) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : "lock.fill")
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(unlocked ? .green : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            (unlocked ? Color.green : Color.gray).opacity(0.1),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .animation(.easeInOut(duration: 0.25), value: unlocked)
    }

    private var gateInfo: (label: String, unlocked: Bool) {
        switch step {
        case .setupGallery:
            return galleriesCount == 0
                ? ("Open Galleries above to get started", false)
                : ("\(galleriesCount) \(galleriesCount == 1 ? "gallery" : "galleries") ready", true)
        case .activateGallery:
            return activeCount == 0
                ? ("Open Galleries above to activate one", false)
                : ("\(activeCount) \(activeCount == 1 ? "gallery" : "galleries") active", true)
        default:
            return ("", true)
        }
    }

    private func nextButton(label: String, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
            if step != .readyToSwipe {
                Image(systemName: "chevron.right").imageScale(.small)
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            enabled ? AnyShapeStyle(accent) : AnyShapeStyle(Color.gray.opacity(0.25)),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .foregroundStyle(enabled ? .white : Color.secondary)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }
}

private struct TourArrow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
