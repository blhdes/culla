import SwiftUI

/// Floating glass capsule at the bottom of Import Albums while an import
/// runs: the album being imported, how far the whole import has got, and
/// a "Done" state at the end.
///
/// Variant B from the design workshop (2026-11-12): tint is each new
/// gallery's color, `lineWidth: 10`, `animation: .snappy`.
struct AlbumImportProgressCapsule: View {
    let progress: AlbumImportProgress
    let isFinished: Bool
    /// The album being imported, for the cover on the left.
    let currentAlbumIdentifier: String?
    /// The color of the gallery being created.
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let height: CGFloat = 72
        static let coverSize: CGFloat = 44
        static let coverRadius: CGFloat = 12
        /// Half the workshop's `lineWidth: 10`.
        static let barHeight: CGFloat = 5
        static let washOpacity = 0.16
    }

    private var fraction: Double { isFinished ? 1 : progress.fraction }

    var body: some View {
        HStack(spacing: 12) {
            cover

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    if !isFinished {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: fraction))
                    }
                }
                detail
                bar
                    .padding(.top, 4)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 20)
        .frame(height: Metrics.height)
        .background(alignment: .leading) {
            // A light wash of the gallery color fills the capsule as it goes.
            GeometryReader { proxy in
                color.opacity(Metrics.washOpacity)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .clipShape(Capsule())
        .glassSurface(in: Capsule())
        .animation(reduceMotion ? nil : .snappy, value: progress)
        .animation(reduceMotion ? nil : .snappy, value: isFinished)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    private var cover: some View {
        ZStack {
            if isFinished {
                color
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            } else if let currentAlbumIdentifier {
                // A new identity per album, so each cover loads fresh and crossfades.
                AlbumThumbnailView(albumIdentifier: currentAlbumIdentifier)
                    .id(currentAlbumIdentifier)
                    .transition(.opacity)
            }
        }
        .frame(width: Metrics.coverSize, height: Metrics.coverSize)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.coverRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var title: some View {
        Group {
            if isFinished {
                Text("Done")
            } else {
                Text(verbatim: progress.albumName)
            }
        }
        .font(.system(.subheadline, design: .rounded).weight(.semibold))
        .lineLimit(1)
    }

    private var detail: some View {
        Group {
            if isFinished {
                Text("\(progress.albumCount) new galleries")
            } else {
                // Long translations drop the album position first, then keep the count.
                ViewThatFits(in: .horizontal) {
                    Text("Album \(progress.albumIndex + 1) of \(progress.albumCount) · \(progress.photosDone.formatted()) of \(progress.photosTotal.formatted()) photos")
                    Text("\(progress.photosDone.formatted()) of \(progress.photosTotal.formatted()) photos")
                }
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
        .contentTransition(.numericText())
    }

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(Metrics.barHeight, proxy.size.width * fraction))
            }
        }
        .frame(height: Metrics.barHeight)
        .accessibilityHidden(true)
    }
}
