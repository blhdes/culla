import SwiftUI
import Photos

struct PhotoPreviewItem: Identifiable {
    let id: String
}

struct PhotoPreviewOverlay: View {
    let identifier: String
    let photoService: PhotoLibraryService
    let onDismiss: () -> Void

    @State private var loader: PhotoImageLoader
    @State private var videoPlayer = VideoCardPlayer()

    init(identifier: String, photoService: PhotoLibraryService, onDismiss: @escaping () -> Void) {
        self.identifier = identifier
        self.photoService = photoService
        self.onDismiss = onDismiss
        self._loader = State(initialValue: PhotoImageLoader(
            service: photoService,
            assetIdentifier: identifier,
            targetSize: PHImageManagerMaximumSize
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = videoPlayer.player {
                PlayerLayerView(player: player, fillsFrame: false)
            } else if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loader.loadAttempted && !loader.isLoading {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                if videoPlayer.player != nil {
                    Button {
                        videoPlayer.isMuted.toggle()
                    } label: {
                        Image(systemName: videoPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .task {
            // Poster loads either way — it's the fallback if the video can't
            // play. Concurrent, so video start doesn't wait behind a
            // max-size (possibly iCloud) image fetch.
            async let poster: Void = loader.load()
            await videoPlayer.prepare(for: identifier, service: photoService)
            await poster
        }
        .onDisappear { videoPlayer.teardown() }
    }
}
