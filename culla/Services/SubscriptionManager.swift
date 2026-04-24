import Foundation
import RevenueCat
import Observation

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    static let entitlementID = "Culla Pro"
    private static let apiKey = "test_GjXIFqeHrLYHRHwcQHMhqeZgOPZ"

    private(set) var customerInfo: CustomerInfo?
    private(set) var isPro: Bool = false

    /// True if the user has ever activated Culla Pro (trial or paid) but it is now inactive.
    /// This signals that the trial has expired and a hard gate should be shown.
    var trialExpired: Bool {
        guard let entitlement = customerInfo?.entitlements[Self.entitlementID] else { return false }
        return !entitlement.isActive
    }

    private var streamTask: Task<Void, Never>?
    /// The expiration date we've already scheduled a reminder for — prevents re-prompting
    /// the user every time the customerInfo stream emits.
    private var scheduledReminderFor: Date?

    private init() {}

    func configure() {
        Purchases.logLevel = .info
        Purchases.configure(withAPIKey: Self.apiKey)

        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    self?.customerInfo = info
                    self?.isPro = info.entitlements[Self.entitlementID]?.isActive == true
                }
                await self?.reconcileTrialReminder(info: info)
            }
        }
    }

    private func reconcileTrialReminder(info: CustomerInfo) async {
        guard
            let entitlement = info.entitlements[Self.entitlementID],
            entitlement.isActive,
            entitlement.periodType == .trial,
            let expires = entitlement.expirationDate
        else {
            TrialReminderService.cancelReminder()
            scheduledReminderFor = nil
            return
        }

        guard scheduledReminderFor != expires else { return }
        scheduledReminderFor = expires
        await TrialReminderService.scheduleReminder(for: expires)
    }

    @MainActor
    func restorePurchases() async throws {
        let info = try await Purchases.shared.restorePurchases()
        customerInfo = info
        isPro = info.entitlements[Self.entitlementID]?.isActive == true
    }
}
