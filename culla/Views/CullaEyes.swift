import SwiftUI
import Combine

struct CullaEyes: View {
    @State private var isClosed = false
    @State private var pupilX: CGFloat = 0

    private let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            eye
            eye
        }
        .onReceive(timer) { _ in
            blink()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pupilX = 4
            }
        }
    }

    private var eye: some View {
        ZStack {
            // Sclera
            Ellipse()
                .fill(.white)
                .overlay(
                    Ellipse().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1.5)
                )
                .frame(width: 28, height: 36)

            // Iris
            Circle()
                .fill(.tint.opacity(0.9))
                .frame(width: 16, height: 16)
                .offset(x: pupilX)

            // Pupil
            Circle()
                .fill(.black)
                .frame(width: 8, height: 8)
                .offset(x: pupilX)

            // Specular highlight
            Circle()
                .fill(.white)
                .frame(width: 3.5, height: 3.5)
                .offset(x: pupilX + 3, y: -3.5)
        }
        .frame(width: 28, height: 36)
        .clipShape(Ellipse())                                      // clean blink collapse
        .scaleEffect(y: isClosed ? 0.05 : 1.0, anchor: .center)
        .animation(.easeInOut(duration: 0.08), value: isClosed)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }

    private func blink() {
        isClosed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isClosed = false
        }
    }
}
