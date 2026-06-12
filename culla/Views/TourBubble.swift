import SwiftUI

struct TourBubble: View {
    let step: TourStep
    let onNext: () -> Void
    let onComplete: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            if step.arrowEdge == .top {
                TourArrow()
                    .fill(.background)
                    .frame(width: 22, height: 11)
                    .frame(maxWidth: .infinity, alignment: step.arrowIsTrailing ? .trailing : .center)
                    .padding(.trailing, step.arrowIsTrailing ? 14 : 0)
                    .padding(.bottom, -1)
            }

            cardContent
                .background(.background, in: RoundedRectangle(cornerRadius: 18))

            if step.arrowEdge == .bottom {
                TourArrow()
                    .fill(.background)
                    .rotationEffect(.degrees(180))
                    .frame(width: 22, height: 11)
                    .padding(.top, -1)
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

            Divider()

            HStack {
                Spacer()
                if step == .readyToSwipe {
                    nextButton(label: "Let's Go!", enabled: true)
                        .onTapGesture { onComplete() }
                } else {
                    nextButton(label: "Next", enabled: true)
                        .onTapGesture { onNext() }
                }
            }
        }
        .padding(16)
    }

    private func nextButton(label: LocalizedStringKey, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
            if step != .readyToSwipe {
                Image(systemName: "chevron.right").imageScale(.small)
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
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
