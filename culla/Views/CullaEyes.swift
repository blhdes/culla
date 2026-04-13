import SwiftUI
import Combine

struct CullaEyes: View {
    @State private var isClosed = false
    @State private var pupilX: CGFloat = -6

    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 60) {
            eye
            eye
        }
        .onReceive(timer) { _ in blink() }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pupilX = 6
            }
        }
    }

    private var eye: some View {
        ZStack {
            // Fixed tinted pupil — never moves
            Circle()
                .fill(.tint)
                .frame(width: 26, height: 26)

            // Highlight drifts across the pupil surface to suggest rotation
            Circle()
                .fill(.white)
                .frame(width: 6, height: 6)
                .offset(x: pupilX * 0.7, y: -7)
        }
        .scaleEffect(y: isClosed ? 0.05 : 1.0, anchor: .center)
        .animation(.easeInOut(duration: 0.1), value: isClosed)
    }

    private func blink() {
        isClosed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isClosed = false
        }
    }
}
