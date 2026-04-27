import SwiftUI

struct TooltipBubble: View {
    let text: String
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            )
            .scaleEffect(isVisible ? 1 : 0.88)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isVisible = true
                }
            }
            .onTapGesture { dismiss() }
            .task {
                try? await Task.sleep(for: .seconds(4))
                dismiss()
            }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { isVisible = false }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            onDismiss()
        }
    }
}
