import SwiftUI
import Photos

// MARK: - Noise Texture

private func makeNoiseTexture() -> UIImage? {
    guard let filter = CIFilter(name: "CIRandomGenerator"),
          let output = filter.outputImage else { return nil }
    let size = CGSize(width: 400, height: 900)
    let cropped = output.cropped(to: CGRect(origin: .zero, size: size))
    let context = CIContext()
    guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else { return nil }
    return UIImage(cgImage: cgImage)
}

// MARK: - Photo Background Manager

@Observable
final class PhotoBackgroundManager {
    var images: [UIImage] = []

    private let cacheManager = PHCachingImageManager()
    private static let thumbSize = CGSize(width: 150, height: 150)

    func load() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 28
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        var assets: [PHAsset] = []
        let result = PHAsset.fetchAssets(with: fetchOptions)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        assets.shuffle()
        guard !assets.isEmpty else { return }

        let imgOptions = PHImageRequestOptions()
        imgOptions.deliveryMode = .fastFormat
        imgOptions.isNetworkAccessAllowed = true
        imgOptions.resizeMode = .fast
        cacheManager.startCachingImages(
            for: assets,
            targetSize: Self.thumbSize,
            contentMode: .aspectFill,
            options: imgOptions
        )

        var loaded: [UIImage] = []
        for asset in assets {
            if let img = await fetch(asset) {
                loaded.append(img)
            }
            // Show first batch immediately so the carousel starts early
            if loaded.count == 8 { images = loaded }
        }
        images = loaded
    }

    func stopCaching() { cacheManager.stopCachingImagesForAllAssets() }

    private func fetch(_ asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return await withCheckedContinuation { continuation in
            cacheManager.requestImage(
                for: asset,
                targetSize: PhotoBackgroundManager.thumbSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Carousel Background View

struct PhotoCarouselBackground: View {
    @AppStorage("dynamicGalleryBackground") private var isEnabled = true
    @State private var manager = PhotoBackgroundManager()
    @State private var noiseImage: UIImage?

    // Each "tile" is a photosPerTile × photosPerTile grid that repeats seamlessly.
    // Moving the offset by exactly -tileSize in both X and Y looks identical to 0 → seamless loop.
    private let photoSize: CGFloat = 130
    private let photosPerTile = 4               // 4×4 = 16 photos per tile
    private var tileSize: CGFloat { CGFloat(photosPerTile) * photoSize }  // 520 pt
    private let cycleDuration: Double = 20      // seconds per full loop

    var body: some View {
        ZStack {
            if !isEnabled {
                fallbackGradient
            } else {
                if !manager.images.isEmpty {
                    diagonalCanvas
                        .transition(.opacity)
                }
                Rectangle().fill(Color(.systemBackground).opacity(0.25))
                grainLayer
            }
        }
        .ignoresSafeArea(.all)
        .animation(.easeIn(duration: 0.8), value: manager.images.isEmpty)
        .task(id: isEnabled) {
            guard isEnabled else { return }
            await manager.load()
            noiseImage = await Task.detached(priority: .background) {
                makeNoiseTexture()
            }.value
        }
        .onDisappear { manager.stopCaching() }
    }

    // MARK: - Diagonal canvas

    /// Single-layer photo wall scrolling at 45°.
    /// Canvas only draws photos that intersect the visible frame, so GPU work scales
    /// with screen area (~20 photos drawn per frame) not with total grid size.
    private var diagonalCanvas: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycleDuration)
                // shift moves 0 → -tileSize over one cycle, then instantly resets
                let shift = -CGFloat(t / cycleDuration) * tileSize

                // Enough tile repetitions to cover the screen at any offset
                let tilesNeeded = Int(ceil(max(size.width, size.height) / tileSize)) + 2

                for tileRow in (-1)..<tilesNeeded {
                    for tileCol in (-1)..<tilesNeeded {
                        // NE direction: X increases (right), Y decreases (up)
                        let originX = CGFloat(tileCol) * tileSize - shift
                        let originY = CGFloat(tileRow) * tileSize + shift

                        for row in 0..<photosPerTile {
                            for col in 0..<photosPerTile {
                                let x = originX + CGFloat(col) * photoSize
                                let y = originY + CGFloat(row) * photoSize

                                // Cull photos outside the visible area
                                guard x + photoSize > 0, y + photoSize > 0,
                                      x < size.width, y < size.height else { continue }

                                let idx = (row * photosPerTile + col) % manager.images.count
                                let img = manager.images[idx]

                                // Center-crop to fill the square without distortion
                                let imgSize = img.size
                                let scale = max(photoSize / imgSize.width, photoSize / imgSize.height)
                                let drawW = imgSize.width * scale
                                let drawH = imgSize.height * scale
                                let drawRect = CGRect(
                                    x: x + (photoSize - drawW) / 2,
                                    y: y + (photoSize - drawH) / 2,
                                    width: drawW,
                                    height: drawH
                                )

                                // Clip to the cell square so overflow from aspect-fill doesn't bleed
                                var clipped = context
                                clipped.clip(to: Path(CGRect(x: x, y: y, width: photoSize, height: photoSize)))
                                clipped.draw(Image(uiImage: img), in: drawRect)
                            }
                        }
                    }
                }
            }
            .blur(radius: 6)
            .opacity(0.9)
        }
    }

    // MARK: - Supporting views

    @ViewBuilder
    private var grainLayer: some View {
        if let noiseImage {
            Image(uiImage: noiseImage)
                .resizable()
                .scaledToFill()
                .opacity(0.04)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
