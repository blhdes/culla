import SwiftUI

/// The big round button in Duplicates mode. Pro users start a sweep; everyone
/// else sees a lock and gets the paywall.
struct HomeDuplicateEntryButton: View {
    let onStart: () -> Void
    let onLocked: () -> Void

    @Environment(\.appAccent) private var accent
    @Environment(SubscriptionManager.self) private var subscriptions

    var body: some View {
        Button {
            if subscriptions.isPro {
                onStart()
            } else {
                onLocked()
            }
        } label: {
            ZStack {
                Color.clear
                    .frame(width: 120, height: 120)
                    .modifier(GlassOrMaterialCircle())
                if subscriptions.isPro {
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(accent)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(accent)
                        Text("Pro")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GlassOrMaterialCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: Circle())
        } else {
            content.background(Circle().fill(.ultraThinMaterial))
        }
    }
}
