import SwiftUI

/// Top of the swipe screen: focus timer, "N / total" counter and the toast.
struct SwipeTopStatus: View {
    let showsFocusTimer: Bool
    let remainingSeconds: Int
    let totalSeconds: Int
    let processedCount: Int
    let totalCount: Int
    /// The clutter deck is still finding photos, so the total gets a "+".
    var totalIsGrowing = false
    let toastMessage: String?

    var body: some View {
        VStack(spacing: 6) {
            if showsFocusTimer {
                FocusTimerArcView(
                    remainingSeconds: remainingSeconds,
                    totalSeconds: totalSeconds
                )
            }
            if totalCount > 0 {
                Group {
                    if totalIsGrowing {
                        Text("\(processedCount + 1) / \(totalCount)+")
                    } else {
                        Text("\(processedCount + 1) / \(totalCount)")
                    }
                }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            // FREEMIUM HIDDEN — restore in vNext
            // Daily swipe counter hidden while the freemium model is disabled.
            // Restoring it needs `@Environment(SubscriptionManager.self) private var subscriptions` here.
            // if !subscriptions.isPro {
            //     Text("\(subscriptions.todaySwipeCount) / \(SubscriptionManager.dailySwipeLimit) today")
            //         .font(.caption)
            //         .fontWeight(.medium)
            //         .foregroundStyle(.secondary)
            //         .padding(.horizontal, 12)
            //         .padding(.vertical, 6)
            //         .background(.ultraThinMaterial, in: Capsule())
            // }
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
}

/// Bottom of the swipe screen: the photo's date (tap to bring back Undo)
/// and the Undo button.
struct SwipeBottomBar: View {
    let photoDate: Date?
    let isFavorite: Bool
    let showsUndo: Bool
    let undoCount: Int
    let onDateTap: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let photoDate {
                Button(action: onDateTap) {
                    HStack(spacing: 4) {
                        Text(photoDate, format: .dateTime.month(.wide).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.pink)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if showsUndo {
                Button(action: onUndo) {
                    let count = undoCount
                    Label(
                        count > 1 ? "Undo (\(count))" : "Undo",
                        systemImage: "arrow.uturn.backward"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
