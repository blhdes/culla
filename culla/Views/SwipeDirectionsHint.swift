import SwiftUI

struct SwipeDirectionsHint: View {
    var onDismiss: () -> Void

    @Environment(\.appAccent) private var accent
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 20) {
            directionItem(
                icon: "heart.fill", label: "Favourite",
                color: .yellow, chevron: "chevron.up", chevronOnTop: true
            )

            HStack(spacing: 36) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    iconBubble(icon: "trash.fill", color: .red)
                    Text("Dismiss")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Text("Sort")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    iconBubble(icon: "rectangle.stack.fill", color: accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }

            directionItem(
                icon: "square.and.arrow.up.fill", label: "Share",
                color: .blue, chevron: "chevron.down", chevronOnTop: false
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.14), radius: 22, y: 8)
        .scaleEffect(isVisible ? 1 : 0.88)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isVisible = true
            }
        }
        .onTapGesture { dismiss() }
        .task {
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
    }

    // Top / bottom direction items (chevron above or below)
    private func directionItem(
        icon: String, label: String,
        color: Color, chevron: String, chevronOnTop: Bool
    ) -> some View {
        VStack(spacing: 5) {
            if chevronOnTop {
                Image(systemName: chevron)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                iconBubble(icon: icon, color: color)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if !chevronOnTop {
                Image(systemName: chevron)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func iconBubble(icon: String, color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            )
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            onDismiss()
        }
    }
}
