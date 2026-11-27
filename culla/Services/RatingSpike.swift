#if DEBUG
import Photos
import SwiftUI

/// Part R0 of the iOS 27 kits plan (Debug only, nothing here ships).
///
/// Two small buttons on the swipe screen, under the clutter chip's row:
/// - **★**: sets 3★ on the top card through `PHAssetChangeRequest.rating`
///   (or clears it when the card already has 3★), then reads it back.
/// - **Check**: logs the rating of every photo this spike has rated, so he
///   can see that it survives a relaunch and picks up changes made in Photos,
///   then tries `rating >= 3` as a fetch predicate (the photos he rated here
///   should be counted).
///
/// Answers R0: do Culla's ratings show in Photos, and can decks filter by
/// stars? Delete this file and its one overlay line in `SwipeView` once the
/// device session has answered that.
@available(iOS 27, *)
enum RatingSpike {

    private static let ratedKey = "debug.ratingSpike.ratedIDs"

    static func rating(of identifier: String) -> PHAsset.Rating? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject?.rating
    }

    /// Sets 3★, or clears it if the photo already has 3★. Returns the rating
    /// Photos reports afterwards.
    static func toggleThreeStars(on identifier: String) async -> PHAsset.Rating? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            print("[rating] spike: photo not found, id=\(identifier)")
            return nil
        }
        let target: PHAsset.Rating = asset.rating == .three ? .unset : .three
        let modifiedBefore = asset.modificationDate
        let start = Date()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).rating = target
            }
        } catch {
            print("[rating] spike: setting \(label(target)) failed on id=\(identifier): \(PhotoLibraryService.describe(error))")
            return asset.rating
        }
        let seconds = Date().timeIntervalSince(start)

        let after = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        let modifiedChanged = after?.modificationDate != modifiedBefore
        remember(identifier)
        print("[rating] spike: set \(label(target)) on id=\(identifier) in \(format(seconds))s · read back \(label(after?.rating)) · modificationDate changed: \(modifiedChanged ? "yes" : "no")")
        return after?.rating
    }

    /// Logs the photos rated here, then tests the fetch predicate. The
    /// predicate goes last: if Photos doesn't support the key, it throws an
    /// Objective-C exception, which Swift can't catch, and the app crashes.
    static func check() async {
        let ids = Array(UserDefaults.standard.stringArray(forKey: ratedKey) ?? [])
        var ratedHere = 0
        if ids.isEmpty {
            print("[rating] spike: no photos rated by Culla yet")
        } else {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var lines: [String] = []
            assets.enumerateObjects { asset, _, _ in
                if asset.rating.rawValue >= PHAsset.Rating.three.rawValue { ratedHere += 1 }
                lines.append("\(label(asset.rating)) id=\(asset.localIdentifier)")
            }
            print("[rating] spike: \(assets.count) of \(ids.count) photos rated by Culla still in the library:")
            for line in lines { print("[rating]   \(line)") }
        }

        print("[rating] spike: testing the fetch predicate 'rating >= 3'. If the app crashes right after this line, Photos doesn't support it.")
        let (matched, total, seconds) = await Task.detached { () -> (Int, Int, Double) in
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "rating >= 3")
            let start = Date()
            let matched = PHAsset.fetchAssets(with: .image, options: options).count
            let seconds = Date().timeIntervalSince(start)
            let total = PHAsset.fetchAssets(with: .image, options: nil).count
            return (matched, total, seconds)
        }.value
        print("[rating] spike: predicate works: \(matched) of \(total) photos at 3★ or more (\(ratedHere) of them rated 3★+ by Culla) in \(format(seconds))s")
    }

    private static func remember(_ identifier: String) {
        var ids = UserDefaults.standard.stringArray(forKey: ratedKey) ?? []
        guard !ids.contains(identifier) else { return }
        ids.append(identifier)
        UserDefaults.standard.set(ids, forKey: ratedKey)
    }

    static func label(_ rating: PHAsset.Rating?) -> String {
        guard let rating else { return "unknown" }
        return rating == .unset ? "unrated" : "\(rating.rawValue)★"
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }
}

/// The spike's two buttons. Plain English with `verbatim`, so nothing lands
/// in the string catalog.
@available(iOS 27, *)
struct RatingSpikeButtons: View {
    let identifier: String?

    @State private var rating: PHAsset.Rating?
    @State private var isWorking = false

    var body: some View {
        if let identifier {
            HStack(spacing: 6) {
                Button {
                    isWorking = true
                    Task {
                        rating = await RatingSpike.toggleThreeStars(on: identifier)
                        isWorking = false
                    }
                } label: {
                    capsule(rating == .unset || rating == nil ? "☆ set 3★" : "★ \(RatingSpike.label(rating))")
                }
                Button {
                    isWorking = true
                    Task {
                        await RatingSpike.check()
                        isWorking = false
                    }
                } label: {
                    capsule("Check")
                }
            }
            .disabled(isWorking)
            .task(id: identifier) {
                rating = RatingSpike.rating(of: identifier)
            }
        }
    }

    private func capsule(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

extension SwipeView {
    /// R0 spike buttons, top right under the chip's row. iOS 27 only.
    @ViewBuilder
    func ratingSpike(viewModel: SwipeViewModel) -> some View {
        if #available(iOS 27, *) {
            RatingSpikeButtons(identifier: viewModel.currentIdentifier)
                .padding(.trailing, 16)
                .padding(.top, 60)
                .opacity(chromeOpacity)
        }
    }
}
#endif
