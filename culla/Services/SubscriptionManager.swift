import Foundation
import RevenueCat
import Observation

@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    static let entitlementID = "pro"
    private static let apiKey = "appl_qkEOEHhjiUplXNbPkjEwMTflFDQ"

    static let dailySwipeLimit = 20
    static let freeGalleryLimit = 3

    private static let swipeCountKey = "dailySwipeCount"
    private static let swipeDateKey  = "dailySwipeDate"

    private(set) var customerInfo: CustomerInfo?
    private(set) var isPro: Bool = false
    private(set) var todaySwipeCount: Int = 0

    /// True if the user has ever activated Culla Pro (trial or paid) but it is now inactive.
    /// This signals that the trial has expired and a hard gate should be shown.
    var trialExpired: Bool {
        guard let entitlement = customerInfo?.entitlements[Self.entitlementID] else { return false }
        return !entitlement.isActive
    }

    /// True when a free user has used all 20 swipes for today.
    var hasReachedDailyLimit: Bool {
        !isPro && todaySwipeCount >= Self.dailySwipeLimit
    }

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
                    self?.isPro = info.entitlements[Self.entitlementID]?.isActive == true
                }
                await self?.reconcileTrialReminder(info: info)
            }
        }
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
        isPro = info.entitlements[Self.entitlementID]?.isActive == true
    }
}
