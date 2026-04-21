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

    func load(albumIdentifier: String? = nil, showFavourites: Bool = false) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 36
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        var assets: [PHAsset] = []

        if showFavourites {
            // Fetch only favorited photos
            let favOptions = PHFetchOptions()
            favOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            favOptions.fetchLimit = 36
            favOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
                NSPredicate(format: "favorite == YES")
            ])
            let favResult = PHAsset.fetchAssets(with: favOptions)
            favResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        } else if let albumID = albumIdentifier {
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
            if loaded.count == 18 { images = loaded }
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
    var isPaused: Bool = false

    @AppStorage("dynamicBackgroundMode") private var backgroundMode = "gallery"
    @AppStorage("monochromeBackground") private var monochrome = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var manager = PhotoBackgroundManager()
    @State private var noiseImage: UIImage?
    @State private var pausedAt: Date? = nil
    @State private var timeOffset: TimeInterval = 0

    // Rows scroll horizontally (alternating direction) while the whole wall drifts upward.
    // X and Y are completely independent so no row ever moves faster/slower than another.
    private let photoSize: CGFloat = 110
    private let photosPerTile = 6           // 6×6 = 36 unique photos, 1:1 square tile
    private var tileSize: CGFloat { CGFloat(photosPerTile) * photoSize }   // 660 pt
    private let verticalSpeed: Double = 14  // pt/s — whole wall drifts upward
    private let rowSpeed: Double = 20       // pt/s — per-row horizontal stream

    var body: some View {
        ZStack {
            // Fallback gradient is always the base — never a dark void during loading or when disabled
            fallbackGradient
            if backgroundMode != "off" {
                if !manager.images.isEmpty {
                    photoCanvas
                        .transition(.opacity)
                }
                Rectangle().fill(Color(.systemBackground).opacity(colorScheme == .light ? 0.55 : 0.25))
                grainLayer
            }
        }
        .ignoresSafeArea(.all)
        .animation(.easeIn(duration: 0.8), value: manager.images.isEmpty)
        .task(id: "\(backgroundMode)-\(backgroundMode == "favourites" ? "" : (albumIdentifier ?? ""))") {
            guard backgroundMode != "off" else { return }
            let showFavourites = backgroundMode == "favourites"
            await manager.load(albumIdentifier: albumIdentifier, showFavourites: showFavourites)
            noiseImage = await Task.detached(priority: .background) {
                makeNoiseTexture()
            }.value
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                pausedAt = Date()
            } else if let p = pausedAt {
                timeOffset += Date().timeIntervalSince(p)
                pausedAt = nil
            }
        }
        .onDisappear { manager.stopCaching() }
    }

    // MARK: - Photo canvas

    /// Rows stream horizontally in alternating directions while the whole wall scrolls up.
    /// Y and X offsets are fully decoupled — no coupling between row speed and vertical speed.
    /// Each row uses a unique slice of the image pool so no photo repeats across visible rows.
    private var photoCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isPaused)) { timeline in
            Canvas { context, size in
                let tRaw = timeline.date.timeIntervalSinceReferenceDate - timeOffset

                // Vertical: whole wall drifts upward, resets seamlessly at tileSize
                let verticalOffset = -CGFloat(tRaw * verticalSpeed)
                    .truncatingRemainder(dividingBy: tileSize)

                // Horizontal: rows stream — base offset shared, direction flips per row
                let rowScrollBase = CGFloat(tRaw * rowSpeed)
                    .truncatingRemainder(dividingBy: tileSize)

                // Enough Y tiles to always cover the screen whatever the vertical offset
                let rowTilesNeeded = Int(ceil(size.height / tileSize)) + 2
                // Enough X tiles to always cover the screen whatever the horizontal offset
                let colTilesNeeded = Int(ceil(size.width / tileSize)) + 2

                for tileRow in (-1)..<rowTilesNeeded {
                    for row in 0..<photosPerTile {
                        let y = CGFloat(tileRow) * tileSize
                            + CGFloat(row) * photoSize
                            + verticalOffset

                        guard y + photoSize > 0, y < size.height else { continue }

                        // Even rows scroll right, odd rows scroll left — continuous, no oscillation
                        let rowDir: CGFloat = row % 2 == 0 ? 1 : -1
                        let rowScroll = rowDir * rowScrollBase

                        for tileCol in (-1)..<colTilesNeeded {
                            for col in 0..<photosPerTile {
                                let x = CGFloat(tileCol) * tileSize
                                    + CGFloat(col) * photoSize
                                    + rowScroll

                                guard x + photoSize > 0, x < size.width else { continue }

                                // Each row uses a unique photo slice: row 0 → 0‥5, row 1 → 6‥11, …
                                let idx = (row * photosPerTile + col) % manager.images.count
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
            .blur(radius: 6)
            .opacity(0.9)
            .saturation(monochrome ? 0 : 1)
            .contrast(monochrome ? 1.3 : 1)
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
