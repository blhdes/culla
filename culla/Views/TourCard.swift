import SwiftUI

/// The tour's card: step dots, Skip, a big title, a short text and one button.
struct TourCard: View {
    let step: TourStep
    let onNext: () -> Void
    let onSkip: () -> Void

    @Environment(\.appAccent) private var accent
    private let style = TourStyle.current

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
    }

    var body: some View {
        surfaced(
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    dots
                    Spacer()
                    Button("Skip", action: onSkip)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                Text(step.title)
                    .font(.system(size: style.titleSize, weight: .heavy, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)

                Text(step.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .padding(.top, 8)

                GradientCapsuleButton(title: step.buttonLabel, action: onNext)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 18)
        )
        .overlay { shape.strokeBorder(.white.opacity(0.08), lineWidth: 1) }
    }

    /// Glass like the app's other "loud" surfaces, or a solid card when glass is off.
    @ViewBuilder
    private func surfaced<Content: View>(_ content: Content) -> some View {
        if style.glass {
            content.glassSurface(in: shape)
        } else {
            content.background(.background, in: shape)
        }
    }

    /// One dot per stop. The current one is wider and takes the accent colour.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(TourStep.flow.filter { $0 != .welcome }, id: \.self) { stop in
                Capsule()
                    .fill(stop == step ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                    .frame(width: stop == step ? 20 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
