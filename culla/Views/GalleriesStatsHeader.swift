import SwiftUI

/// The card at the top of the Galleries list: photos sorted so far and the
/// current streak. The parent decides what a tap opens (Insights or the paywall).
struct GalleriesStatsHeader: View {
    let sortedCount: Int
    let currentStreak: Int
    let isPro: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sortedCount)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: sortedCount)
                    Text("photos sorted")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStreak > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: currentStreak)
                        Text("\(currentStreak)")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassSurface(in: Capsule())
                }

                Image(systemName: isPro ? "chevron.right" : "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .glassSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
