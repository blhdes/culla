import SwiftUI
import RevenueCat
import RevenueCatUI

struct PaywallSheet: View {
    let onClose: () -> Void
    var dismissible: Bool = true

    @State private var offering: Offering?

    var body: some View {
        Group {
            if let offering {
                PaywallView(offering: offering, displayCloseButton: dismissible)
                    .onPurchaseCompleted { _ in onClose() }
                    .onRestoreCompleted { info in
                        if info.entitlements[SubscriptionManager.entitlementID]?.isActive == true {
                            onClose()
                        }
                    }
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let offerings = try await Purchases.shared.offerings()
                offering = offerings.offering(identifier: "Culla Pro") ?? offerings.current
            } catch {
                print("[PaywallSheet] Failed to fetch offerings: \(error)")
            }
        }
    }
}
