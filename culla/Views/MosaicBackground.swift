import SwiftUI

// MARK: - Mosaic Background

/// Apple "Album Artwork" screensaver–style wall: a static, edge-to-edge grid of
/// square photo tiles where one random tile 3D-flips to a new photo at a time.
/// The companion style to `PhotoCarouselBackground`'s streaming wall — seeded
/// from the same image pool, then each flip pulls the next photo from a shuffled
/// walk of the entire gallery via `nextImage`.
struct MosaicBackground: View {
    /// Seed pool for the initial grid. Galleries smaller than the tile count
    /// repeat photos — the intended fallback.
    let images: [UIImage]
    var isPaused: Bool = false
    /// Next photo in the gallery-wide walk; nil skips the flip.
    let nextImage: () async -> UIImage?

    @State private var tileImages: [UIImage] = []

    // Matches the carousel's 110 pt photo size so both styles feel related.
    private let tileSize: CGFloat = 110
    private let tileGap: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let step = tileSize + tileGap
            let cols = Int(ceil(geo.size.width / step))
            let rows = Int(ceil(geo.size.height / step))
            // Center the grid so the overflow past the screen edges splits evenly —
            // no visible border on any side.
            let gridWidth = CGFloat(cols) * step - tileGap
            let gridHeight = CGFloat(rows) * step - tileGap
            let xInset = (geo.size.width - gridWidth) / 2
            let yInset = (geo.size.height - gridHeight) / 2

            ZStack(alignment: .topLeading) {
                ForEach(0..<(cols * rows), id: \.self) { tile in
                    MosaicFlipTile(image: image(forTile: tile), size: tileSize)
                        .offset(
                            x: xInset + CGFloat(tile % cols) * step,
                            y: yInset + CGFloat(tile / cols) * step
                        )
                }
            }
            // Restarts on rotation or pause toggles. The loop captures a value
            // copy of this struct, but its only live inputs — tileImages and the
            // manager behind nextImage — are reference-backed, so they stay current.
            .task(id: "\(cols * rows)-\(isPaused)") {
                await runFlipLoop(tileCount: cols * rows)
            }
            // Album switch: a fresh seed pool arrives — rebuild the grid from it.
            .onChange(of: images) { _, newSeed in
                seed(from: newSeed, tileCount: cols * rows)
            }
        }
    }

    private func image(forTile tile: Int) -> UIImage {
        guard !images.isEmpty else { return UIImage() }
        if tile < tileImages.count {
            return tileImages[tile]
        }
        return images[tile % images.count]
    }

    /// Fills every tile with a spread of distinct seed photos (repeats only if
    /// the screen needs more tiles than the seed pool has images).
    private func seed(from pool: [UIImage], tileCount: Int) {
        guard !pool.isEmpty else { return }
        var fill: [UIImage] = []
        while fill.count < tileCount {
            fill.append(contentsOf: pool.shuffled())
        }
        tileImages = Array(fill.prefix(tileCount))
    }

    private func runFlipLoop(tileCount: Int) async {
        guard !images.isEmpty else { return }
        if tileImages.count != tileCount {
            seed(from: images, tileCount: tileCount)
        }

        guard !isPaused else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 0.7...1.3)))
            guard !Task.isCancelled else { return }

            guard let fresh = await nextImage() else { continue }
            guard !Task.isCancelled else { return }

            tileImages[Int.random(in: 0..<tileCount)] = fresh
        }
    }
}

// MARK: - Flip Tile

/// One square tile. When its image changes it rotates to 90° (edge-on),
/// swaps the photo while invisible, then rotates back in from the other side —
/// reads as a single continuous 3D flip.
private struct MosaicFlipTile: View {
    let image: UIImage
    let size: CGFloat

    @State private var shownImage: UIImage?
    @State private var angle: Double = 0

    var body: some View {
        Image(uiImage: shownImage ?? image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipped()
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onChange(of: image) { _, newImage in
                Task { @MainActor in
                    withAnimation(.easeIn(duration: 0.25)) { angle = 90 }
                    try? await Task.sleep(for: .seconds(0.25))
                    shownImage = newImage
                    angle = -90
                    withAnimation(.easeOut(duration: 0.25)) { angle = 0 }
                }
            }
    }
}
