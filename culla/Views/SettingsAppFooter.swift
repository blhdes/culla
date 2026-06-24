import SwiftUI

/// Identity footer for the bottom of Settings: a small app icon beside a single
/// line carrying the wordmark, version, and copyright. It used to sit at the top
/// as a tall stack, but that ate too much of the sheet's header space — so it's
/// now a compact one-line signature at the foot of the screen. Stays in the calm
/// Settings tier: no glass card, just a centred row on the flat background.
struct SettingsAppFooter: View {
    var body: some View {
        HStack(spacing: 8) {
            if let icon = Self.appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                    )
            }

            Text(Self.infoLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Bundle info

    /// Wordmark, version, and copyright collapsed onto one line with middot
    /// separators, e.g. "Culla · Version 1.0 (123) · © 2026".
    private static var infoLine: String {
        "Culla · \(versionLine) · © \(year)"
    }

    private static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty
            ? String(localized: "Version \(version)")
            : String(localized: "Version \(version) (\(build))")
    }

    private static var year: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    /// The app's primary icon, read from the bundle. Returns `nil` if it can't
    /// be resolved (e.g. some preview contexts) so the footer degrades to a
    /// text-only layout instead of rendering a broken image.
    private static var appIcon: UIImage? {
        if
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last,
            let image = UIImage(named: name)
        {
            return image
        }
        // Asset-catalog icons often aren't listed in CFBundleIconFiles —
        // fall back to the conventional asset name.
        return UIImage(named: "AppIcon")
    }
}
