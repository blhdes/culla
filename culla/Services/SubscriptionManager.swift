import Foundation
import RevenueCat
import Observation
import StoreKit

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    static let entitlementID = "pro"
    private static let apiKey = "appl_qkEOEHhjiUplXNbPkjEwMTflFDQ"

    static let dailySwipeLimit = 20
    static let freeGalleryLimit = 3

    /// Builds 1 and 2 shipped as a paid app. Anyone who purchased then keeps Pro for life.
    private static let legacyPaidBuildCutoff = 2

    private static let swipeCountKey  = "dailySwipeCount"
    private static let swipeDateKey   = "dailySwipeDate"
    private static let legacyGrantKey = "isLegacyPaidUser"

    private(set) var customerInfo: CustomerInfo?
    private(set) var todaySwipeCount: Int = 0

    private var revenueIsPro: Bool = false
    private(set) var isLegacyGranted: Bool = UserDefaults.standard.bool(forKey: SubscriptionManager.legacyGrantKey)

    // MARK: - FREEMIUM HIDDEN — restore in vNext
    //
    // The freemium model is temporarily disabled: everyone is treated as Pro,
    // no paywalls are gated, no daily swipe limit applies. Each property below
    // is hard-coded to the "unlocked" branch so every `if !isPro` / `if hasReachedDailyLimit`
    // / `if subscriptionExpired` check across the codebase resolves to the unlocked path
    // without having to touch every call site. The original logic is preserved
    // verbatim in the commented blocks — to restore freemium, swap each return for
    // the commented body.

    var isPro: Bool { true }
    // var isPro: Bool { revenueIsPro || isLegacyGranted }

    /// True if the user has ever activated Culla Pro (trial or paid) but it is now inactive.
    /// Legacy paid-app users are excluded — their entitlement never expires.
    var subscriptionExpired: Bool { false }
    // var subscriptionExpired: Bool {
    //     guard !isLegacyGranted else { return false }
    //     guard let entitlement = customerInfo?.entitlements[Self.entitlementID] else { return false }
    //     return !entitlement.isActive
    // }

    /// True when a free user has used all 20 swipes for today.
    var hasReachedDailyLimit: Bool { false }
    // var hasReachedDailyLimit: Bool {
    //     !isPro && todaySwipeCount >= Self.dailySwipeLimit
    // }

    private var streamTask: Task<Void, Never>?
    /// The expiration date we've already scheduled a reminder for — prevents re-prompting
    /// the user every time the customerInfo stream emits.
    private var scheduledReminderFor: Date?

    private init() {}

    func configure() {
        Purchases.logLevel = .info
        Purchases.configure(withAPIKey: Self.apiKey)
        refreshDailyCount()

        streamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    self?.customerInfo = info
                    self?.revenueIsPro = info.entitlements[Self.entitlementID]?.isActive == true
                }
                await self?.reconcileTrialReminder(info: info)
            }
        }

        Task { await checkLegacyPaidUser() }
    }

    /// Grants lifetime Pro to anyone who originally purchased Culla as a paid app
    /// (builds 1–2). Result is cached in UserDefaults so we only verify the App Store
    /// receipt once per device.
    private func checkLegacyPaidUser() async {
        guard !isLegacyGranted else { return }
        guard let result = try? await AppTransaction.shared else { return }
        guard case .verified(let transaction) = result else { return }
        guard let originalBuild = Int(transaction.originalAppVersion) else { return }
        guard originalBuild <= Self.legacyPaidBuildCutoff else { return }

        UserDefaults.standard.set(true, forKey: Self.legacyGrantKey)
        await MainActor.run { isLegacyGranted = true }
    }

    /// Syncs `todaySwipeCount` with UserDefaults, resetting it if the calendar day has rolled over.
    func refreshDailyCount() {
        todaySwipeCount = liveSwipeCount()
    }

    /// Increments the daily swipe counter. No-op for Pro users.
    func recordSwipe() {
        guard !isPro else { return }
        let today = Self.todayString()
        let stored = UserDefaults.standard.string(forKey: Self.swipeDateKey) ?? ""
        if stored != today {
            UserDefaults.standard.set(today, forKey: Self.swipeDateKey)
            UserDefaults.standard.set(1, forKey: Self.swipeCountKey)
            todaySwipeCount = 1
        } else {
            let newCount = UserDefaults.standard.integer(forKey: Self.swipeCountKey) + 1
            UserDefaults.standard.set(newCount, forKey: Self.swipeCountKey)
            todaySwipeCount = newCount
        }
    }

    private func liveSwipeCount() -> Int {
        let today = Self.todayString()
        let stored = UserDefaults.standard.string(forKey: Self.swipeDateKey) ?? ""
        guard stored == today else { return 0 }
        return UserDefaults.standard.integer(forKey: Self.swipeCountKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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
        revenueIsPro = info.entitlements[Self.entitlementID]?.isActive == true
        await checkLegacyPaidUser()
    }
}
