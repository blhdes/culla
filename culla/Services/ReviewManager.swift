import StoreKit
import UIKit

final class ReviewManager {
    static let shared = ReviewManager()
    private init() {
        if UserDefaults.standard.object(forKey: Keys.firstLaunchDate) == nil {
            UserDefaults.standard.set(Date(), forKey: Keys.firstLaunchDate)
        }
    }

    private enum Keys {
        static let firstLaunchDate = "reviewFirstLaunchDate"
        static let firstPromptDone = "reviewFirstPromptDone"
        static let secondPromptDone = "reviewSecondPromptDone"
    }

    private let firstPhotoThreshold = 30
    private let firstDayThreshold = 3
    private let secondDayThreshold = 10

    func checkAndRequestReview(sortedCount: Int) {
        guard let firstLaunch = UserDefaults.standard.object(forKey: Keys.firstLaunchDate) as? Date else { return }
        let daysUsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: .now).day ?? 0

        let firstDone = UserDefaults.standard.bool(forKey: Keys.firstPromptDone)
        let secondDone = UserDefaults.standard.bool(forKey: Keys.secondPromptDone)

        if !firstDone {
            guard sortedCount >= firstPhotoThreshold, daysUsed >= firstDayThreshold else { return }
            requestReview()
            UserDefaults.standard.set(true, forKey: Keys.firstPromptDone)
        } else if !secondDone {
            guard daysUsed >= secondDayThreshold else { return }
            requestReview()
            UserDefaults.standard.set(true, forKey: Keys.secondPromptDone)
        }
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
