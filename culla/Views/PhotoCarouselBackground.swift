import SwiftUI
import Photos

// MARK: - Noise Texture

private nonisolated func makeNoiseTexture() -> UIImage? {
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

    func load(albumIdentifier: String? = nil) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 32
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        var assets: [PHAsset] = []

        if let albumID = albumIdentifier {
            let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            if let collection = collections.firstObject {
                let albumResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)
                albumResult.enumerateObjects { asset, _, _ in assets.append(asset) }
            }
        } else {
            let allResult = PHAsset.fetchAssets(with: fetchOptions)
            allResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        }

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
            if loaded.count == 16 { images = loaded }
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
    var albumIdentifier: String?

    @AppStorage("dynamicGalleryBackground") private var isEnabled = true
    @State private var manager = PhotoBackgroundManager()
    @State private var noiseImage: UIImage?

    // Rows scroll horizontally (alternating direction) while the whole wall drifts upward.
    // X and Y are completely independent so no row ever moves faster/slower than another.
    private let photoSize: CGFloat = 110
    private let colsPerTile = 4              // 4 columns
    private let rowsPerTile = 8              // 8 rows → 32 total unique photos
    private var tileSizeX: CGFloat { CGFloat(colsPerTile) * photoSize }   // 440 pt
    private var tileSizeY: CGFloat { CGFloat(rowsPerTile) * photoSize }   // 880 pt
    private let verticalSpeed: Double = 14  // pt/s — whole wall drifts upward
    private let rowSpeed: Double = 20       // pt/s — per-row horizontal stream

    var body: some View {
        ZStack {
            // Fallback gradient is always the base — never a dark void during loading or when disabled
            fallbackGradient
            if isEnabled {
                if !manager.images.isEmpty {
                    photoCanvas
                        .transition(.opacity)
                }
                Rectangle().fill(Color(.systemBackground).opacity(0.25))
                grainLayer
            }
        }
        .ignoresSafeArea(.all)
        .animation(.easeIn(duration: 0.8), value: manager.images.isEmpty)
        .task(id: "\(isEnabled)-\(albumIdentifier ?? "")") {
            guard isEnabled else { return }
            await manager.load(albumIdentifier: albumIdentifier)
            noiseImage = await Task.detached(priority: .background) {
                makeNoiseTexture()
            }.value
        }
        .onDisappear { manager.stopCaching() }
    }

    // MARK: - Photo canvas

    /// Rows stream horizontally in alternating directions while the whole wall scrolls up.
    /// Y and X offsets are fully decoupled — no coupling between row speed and vertical speed.
    /// Each row uses a unique slice of the image pool so no photo repeats across visible rows.
    private var photoCanvas: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            Canvas { context, size in
                let tRaw = timeline.date.timeIntervalSinceReferenceDate

                // Vertical: whole wall drifts upward, resets seamlessly at tileSizeY
                let verticalOffset = -CGFloat(tRaw * verticalSpeed)
                    .truncatingRemainder(dividingBy: tileSizeY)

                // Horizontal: rows stream — base offset shared, direction flips per row
                let rowScrollBase = CGFloat(tRaw * rowSpeed)
                    .truncatingRemainder(dividingBy: tileSizeX)

                // Enough Y tiles to always cover the screen whatever the vertical offset
                let rowTilesNeeded = Int(ceil(size.height / tileSizeY)) + 2
                // Enough X tiles to always cover the screen whatever the horizontal offset
                let colTilesNeeded = Int(ceil(size.width / tileSizeX)) + 2

                for tileRow in (-1)..<rowTilesNeeded {
                    for row in 0..<rowsPerTile {
                        let y = CGFloat(tileRow) * tileSizeY
                            + CGFloat(row) * photoSize
                            + verticalOffset

                        guard y + photoSize > 0, y < size.height else { continue }

                        // Even rows scroll right, odd rows scroll left — continuous, no oscillation
                        let rowDir: CGFloat = row % 2 == 0 ? 1 : -1
                        let rowScroll = rowDir * rowScrollBase

                        for tileCol in (-1)..<colTilesNeeded {
                            for col in 0..<colsPerTile {
                                let x = CGFloat(tileCol) * tileSizeX
                                    + CGFloat(col) * photoSize
                                    + rowScroll

                                guard x + photoSize > 0, x < size.width else { continue }

                                // Each row uses a unique photo slice: row 0 → 0‥3, row 1 → 4‥7, …, row 7 → 28‥31
                                let idx = (row * colsPerTile + col) % manager.images.count
                                let img = manager.images[idx]

                                let imgSize = img.size
                                let scale = max(photoSize / imgSize.width, photoSize / imgSize.height)
                                let drawW = imgSize.width * scale
                                let drawH = imgSize.height * scale
                                let drawRect = CGRect(
                                    x: x + (photoSize - drawW) / 2,
                                    y: y + (photoSize - drawH) / 2,
                                    width: drawW, height: drawH
                                )

                                var clipped = context
                                clipped.clip(to: Path(CGRect(x: x, y: y,
                                                             width: photoSize, height: photoSize)))
                                clipped.draw(Image(uiImage: img), in: drawRect)
                            }
                        }
                    }
                }
            }
            .blur(radius: 3)
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
