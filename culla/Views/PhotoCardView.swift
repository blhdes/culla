import SwiftUI

struct PhotoCardView: View {
    let assetIdentifier: String
    let photoService: PhotoLibraryService
    let offset: CGSize
    var isZoomed: Bool = false
    /// Set only on the top card — background cards stay poster-frame only.
    var videoPlayer: VideoCardPlayer?
    /// The side the galleries panel opens from: a drag that way docks the
    /// photo, the other way previews Dismiss.
    var panelEdge: SwipePanelEdge = .right
    /// How far the galleries panel is open (0…1). As it opens the card stops
    /// following the finger and the photo shrinks into the free strip beside
    /// the panel, so it stays in view while a gallery is picked.
    var dockProgress: CGFloat = 0

    @State private var loader: PhotoImageLoader

    init(
        assetIdentifier: String,
        photoService: PhotoLibraryService,
        offset: CGSize = .zero,
        isZoomed: Bool = false,
        videoPlayer: VideoCardPlayer? = nil,
        panelEdge: SwipePanelEdge = .right,
        dockProgress: CGFloat = 0
    ) {
        self.assetIdentifier = assetIdentifier
        self.photoService = photoService
        self.offset = offset
        self.isZoomed = isZoomed
        self.videoPlayer = videoPlayer
        self.panelEdge = panelEdge
        self.dockProgress = dockProgress
        self._loader = State(initialValue: PhotoImageLoader(
            service: photoService,
            assetIdentifier: assetIdentifier,
            targetSize: CGSize(width: UIScreen.main.bounds.width * 2, height: UIScreen.main.bounds.height * 2)
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let dock = dockTransform(width: geo.size.width)
            ZStack {
                Group {
                    if let image = loader.image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: isZoomed ? .fill : .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .animation(.easeInOut(duration: 0.3), value: isZoomed)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.35), value: loader.image != nil)

                // Video layer above the poster frame — the poster shows
                // instantly and doubles as the loading state while an
                // iCloud video streams in.
                if let player = videoPlayer?.player,
                   videoPlayer?.activeIdentifier == assetIdentifier {
                    PlayerLayerView(player: player, fillsFrame: isZoomed)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                swipeOverlay
            }
            .clipped()
            // Docking: the photo shrinks and slides into the strip the
            // galleries panel leaves free.
            .scaleEffect(dock.scale)
            .offset(x: dock.x)
            .rotationEffect(.degrees(Double(offset.width / 40 * (1 - dockProgress))))
            .offset(x: cardOffsetX, y: offset.height * 0.4)
        }
        .ignoresSafeArea()
        .task { await loader.load() }
    }

    // MARK: - Docking beside the panel

    /// Horizontal travel toward the panel (negative = toward Dismiss).
    private var towardPanel: CGFloat { offset.width * panelEdge.sign }

    /// Horizontal position of the card. Toward the panel it follows the
    /// finger until the panel starts to open, then slows to
    /// `dockedCardTravel` of the drag. Toward Dismiss it follows 1:1.
    private var cardOffsetX: CGFloat {
        guard towardPanel > 0 else { return offset.width }
        return offset.width * (1 - (1 - SwipeTuning.dockedCardTravel) * dockProgress)
    }

    /// Scale and shift that park the photo in the middle of the free strip
    /// beside the panel, blended in by `dockProgress`. The photo no longer
    /// fades: it sits beside the panel, not under it.
    private func dockTransform(width: CGFloat) -> (scale: CGFloat, x: CGFloat) {
        guard dockProgress > 0, width > 0 else { return (1, 0) }
        let panelWidth = width * SwipeTuning.panelWidthFraction
        let strip = width - panelWidth
        let stripCenter = panelEdge == .right ? strip / 2 : panelWidth + strip / 2
        let targetScale = min(1, max(SwipeTuning.dockMinScale, (strip - SwipeTuning.dockInset) / width))
        // The photo sits at the card's centre; the card itself moves by cardOffsetX.
        let photoCenter = width / 2 + cardOffsetX
        return (1 + (targetScale - 1) * dockProgress, (stripCenter - photoCenter) * dockProgress)
    }

    // MARK: - Directional overlays

    @ViewBuilder
    private var swipeOverlay: some View {
        let isVertical = abs(offset.height) > abs(offset.width)
        let isDraggingTowardGalleries = towardPanel > SwipeTuning.rowHighlightStart

        if towardPanel < 0 && !isVertical {
            // Drag away from the panel — red (dismiss)
            let progress = min(abs(offset.width) / SwipeTuning.commitDistance, 1.0)
            ZStack {
                Color.red
                    .opacity(0.25 * progress)
                Image(systemName: "trash.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.8 * progress))
            }
            .allowsHitTesting(false)
        } else if offset.height < 0 && isVertical && !isDraggingTowardGalleries {
            // Up drag — gold (favorite)
            let progress = min(abs(offset.height) / SwipeTuning.commitDistance, 1.0)
            ZStack {
                Color.yellow
                    .opacity(0.25 * progress)
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.8 * progress))
            }
            .allowsHitTesting(false)
        } else if offset.height > 0 && isVertical && !isDraggingTowardGalleries {
            // Down drag — blue (share)
            let progress = min(abs(offset.height) / SwipeTuning.commitDistance, 1.0)
            ZStack {
                Color.blue
                    .opacity(0.25 * progress)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.8 * progress))
            }
            .allowsHitTesting(false)
        }
    }
}
