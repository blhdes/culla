import SwiftUI
import LinkPresentation

struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    var videoURL: URL? = nil
    let date: Date?
}

final class SharePhotoItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    var videoURL: URL? = nil
    let date: Date?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Videos share the actual movie file; images keep the rich-preview source.
        if let videoURL {
            return UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        }
        let source = SharePhotoItem(image: image, title: Self.title(for: date))
        return UIActivityViewController(activityItems: [source], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    private static func title(for date: Date?) -> String {
        guard let date else { return "Culla" }
        return String(localized: "Culla · \(date.formatted(date: .abbreviated, time: .omitted))")
    }
}
