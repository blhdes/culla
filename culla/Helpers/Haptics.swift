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

    // MARK: Duplicate Sweep
    static func keepPhoto()      { impact(.medium) }  // tap the photo to keep

    // MARK: Trash Screen
    static func deleteConfirm()  { notification(.warning) }

    // MARK: Album Import
    static func importFinished() { notification(.success) }

    // MARK: - Engine (private)

    /// Mirrors the Settings "Haptics" toggle, which is ON by default.
    /// Uses object(forKey:) because bool(forKey:) returns false for a key
    /// that was never written, which silently turned haptics OFF on a fresh
    /// install while the toggle showed ON.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
