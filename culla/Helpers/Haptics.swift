import UIKit

// MARK: - Haptic Actions
// All haptic feedback is defined here. To adjust the feel of any action,
// change its implementation below without touching the call site.

enum Haptics {

    // MARK: Date Picker Screen
    static func startCullaing()  { impact(.medium) }
    static func dateWheelTick()  { impact(.light)  }

    // MARK: Swipe Screen
    static func swipeLeft()      { impact(.light)  }  // dismiss
    static func swipeRight()     { impact(.medium) }  // assign to gallery
    static func swipeUp()        { impact(.light)  }  // favourite
    static func swipeDown()      { impact(.light)  }  // share

    // MARK: Trash Screen
    static func deleteConfirm()  { notification(.warning) }

    // MARK: - Engine (private)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
