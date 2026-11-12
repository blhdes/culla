import SwiftUI

private struct DeleteMenuGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content.background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct DeleteGalleryMenu: View {
    let galleryName: String
    let onDeleteWithPhotos: () -> Void
    let onDeleteKeepPhotos: () -> Void
    let onUnlink: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("Delete \"\(galleryName)\"?")
                    .font(.subheadline.weight(.semibold))
                Text("\"Remove from Culla\" just hides it here — your iPhone album stays intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)

            menuButton(title: "Delete Gallery & Photos", color: .red, action: onDeleteWithPhotos)
            menuButton(title: "Delete Gallery, Keep Photos", color: .red, action: onDeleteKeepPhotos)
            menuButton(title: "Remove from Culla", color: .primary, action: onUnlink)
            menuButton(title: "Cancel", color: .primary, action: onCancel)
        }
        .padding(8)
        .modifier(DeleteMenuGlass())
        .shadow(color: .black.opacity(0.15), radius: 24, y: 6)
    }

    @ViewBuilder
    private func menuButton(title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
