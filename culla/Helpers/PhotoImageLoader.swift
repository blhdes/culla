import SwiftUI

@Observable
final class PhotoImageLoader {
    var image: UIImage?
    var isLoading = false
    /// True once a load attempt has started, even if it returned nil.
    /// Used to distinguish "still pending" from "finished with no image".
    var loadAttempted = false

    private let service: PhotoLibraryService
    private let assetIdentifier: String
    private let targetSize: CGSize

    init(service: PhotoLibraryService, assetIdentifier: String, targetSize: CGSize) {
        self.service = service
        self.assetIdentifier = assetIdentifier
        self.targetSize = targetSize
    }

    @MainActor
    func load() async {
        guard image == nil, !isLoading else { return }
        isLoading = true
        loadAttempted = true
        image = await service.loadImage(for: assetIdentifier, targetSize: targetSize)
        isLoading = false
    }
}
