import SwiftUI

/// The clutter deck when no card is ready yet: it just opened, or the user
/// swiped faster than Vision checks. The next card replaces this as soon as
/// the search finds one.
struct ClutterSearchWaitView: View {
    let checkedCount: Int

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Looking for clutter…")
                .font(.headline)
            Text("\(checkedCount) photos checked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
