import SwiftUI

// MARK: - Mosaic Background

/// Apple "Album Artwork" screensaver–style wall: a static, edge-to-edge grid of
/// square photo tiles where one random tile 3D-flips to a new photo at a time.
/// The companion style to `PhotoCarouselBackground`'s streaming wall — it draws
/// from the same image pool and gets the same dim/blur/grain treatment from its parent.
struct MosaicBackground: View {
    let images: [UIImage]
    var isPaused: Bool = false

    /// Which image each visible tile is currently showing (index into `images`).
    @State private var tileImageIndices: [Int] = []

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
            // Restarts on rotation, pause toggles, or a pool swap (album switch).
            // The loop captures a value copy of this struct, so it must restart
            // to see new inputs — otherwise it picks indices from the old pool's count.
            .task(id: "\(cols * rows)-\(isPaused)-\(images.count)") {
                await runFlipLoop(tileCount: cols * rows)
            }
        }
    }

    private func image(forTile tile: Int) -> UIImage {
        guard !images.isEmpty else { return UIImage() }
        if tile < tileImageIndices.count {
            return images[tileImageIndices[tile] % images.count]
        }
        return images[tile % images.count]
    }

    private func runFlipLoop(tileCount: Int) async {
        guard !images.isEmpty else { return }
        // Seed every tile with a spread of distinct photos (repeats only if the
        // screen needs more tiles than the pool has images).
        if tileImageIndices.count != tileCount {
            var seed: [Int] = []
            while seed.count < tileCount {
                seed.append(contentsOf: Array(0..<images.count).shuffled())
            }
            tileImageIndices = Array(seed.prefix(tileCount))
        }

        guard !isPaused else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 0.7...1.3)))
            guard !Task.isCancelled else { return }

            let tile = Int.random(in: 0..<tileCount)
            var newIndex = Int.random(in: 0..<images.count)
            if images.count > 1 {
                while newIndex == tileImageIndices[tile] {
                    newIndex = Int.random(in: 0..<images.count)
                }
            }
            tileImageIndices[tile] = newIndex
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
