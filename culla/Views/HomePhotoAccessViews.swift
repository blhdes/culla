import Photos
import PhotosUI
import SwiftUI

/// Shown instead of the home controls when Culla can't see any photos:
/// access was denied, or limited access was given with nothing selected.
struct HomePhotoAccessMessage: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") { openAppSettings() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

/// Soft banner shown when the user granted only partial photo access.
/// We can't force full access (Apple policy), so we explain the trade-off
/// and offer two recovery paths: add more photos, or open Settings.
struct HomeLimitedAccessBanner: View {
    /// Runs when the "Select More" picker closes, so the home screen can
    /// reload with the new selection.
    let onSelectionChanged: @MainActor () async -> Void
    let onDismiss: () -> Void

    @Environment(\.appAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Limited photo access")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Culla can only see photos you've selected. Add more or grant full access for the best experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Select More") { presentLimitedPicker() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(accent)

                    Button("Settings") { openAppSettings() }
                        .font(.caption)
                        .fontWeight(.medium)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        // Walk to the topmost presented controller — required so the picker
        // attaches above any sheet/cover currently on screen.
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // The completion handler fires whenever the picker dismisses, with the
        // newly-selected identifiers. Re-run the library load so date range,
        // albums, and the noPhotosAvailable empty-state stay in sync with the
        // user's new selection.
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { _ in
            Task { @MainActor in
                await onSelectionChanged()
            }
        }
    }
}

/// Opens Culla's page in the iPhone Settings app.
private func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
