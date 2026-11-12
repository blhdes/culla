import SwiftUI

/// Shown when the swipe stack has no photos left.
struct SwipeEmptyStateView: View {
    let dismissedCount: Int
    let isDeleting: Bool
    let onDelete: () -> Void
    let onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No more photos")
                .font(.title3)
                .fontWeight(.medium)

            Text("All photos from this date have been sorted or dismissed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            VStack(spacing: 12) {
                if dismissedCount > 0 {
                    Button(action: onDelete) {
                        Text("Delete \(dismissedCount)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(isDeleting)
                    .padding(.horizontal, 40)
                }

                Button {
                    onBack?()
                } label: {
                    Text("Back to Calendar")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
        }
    }
}
