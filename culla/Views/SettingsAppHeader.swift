import SwiftUI

/// Identity header for the top of Settings: app icon + "Culla" wordmark +
/// version line. Replaces the old version footer that was stranded alone at the
/// bottom, so the screen opens with a face — matching iOS's own per-app header
/// convention. Stays in the calm Settings tier: no glass card, just a centred
/// stack on the flat background.
struct SettingsAppHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            if let icon = Self.appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }

            VStack(spacing: 3) {
                Text("Culla")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Self.versionLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("© \(Self.year) Culla")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Bundle info

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
    /// be resolved (e.g. some preview contexts) so the header degrades to a
    /// wordmark-only layout instead of rendering a broken image.
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
