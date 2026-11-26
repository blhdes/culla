import SwiftUI
import UIKit

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = .primary
}

extension EnvironmentValues {
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

extension Color {
    /// Picks a readable label color for text sitting on a glass surface that
    /// is tinted with `self`. Several of our light-mode neons are quite dark
    /// (e.g. #3D00CC, #008877) — `.primary` text on top reads as black-on-dark.
    /// This flips to white when the tint is too dark for the current scheme,
    /// otherwise returns `.primary` so the system's adaptive color still wins.
    func foregroundOnTintedGlass(in scheme: ColorScheme) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .primary }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        switch scheme {
        case .dark:
            return luminance > 0.75 ? .black : .primary
        default:
            return luminance < 0.55 ? .white : .primary
        }
    }

    /// Black or white, whichever has more contrast on a solid fill of `self`
    /// as drawn in `scheme` (WCAG relative luminance; the two tie near 0.18).
    /// Resolves adaptive colours (the gallery neons) for that scheme, not the
    /// app-wide one. Used by the armed panel row and the target pill, where
    /// pale neons like dark-mode #FFCC00 need black text.
    func labelOnSolidFill(in scheme: ColorScheme) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let ui = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        func linear(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.179 ? .black : .white
    }
}
