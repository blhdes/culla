import Foundation
import Observation

/// One photo the clutter deck may show, in date order.
nonisolated struct ClutterCandidate: Sendable {
    let identifier: String
    /// Photos already knows it's a screenshot, so it needs no scoring.
    let isScreenshot: Bool
}

/// Fills the clutter deck while the user swipes (Part Q5 of the iOS 27 kits
/// plan). It walks the photos forward from the deck's start date and pauses
/// once a few found photos are waiting, so a session that ends after five
/// cards never scores the whole library.
///
/// Screenshots count at once. Every other photo is scored by
/// `PhotoQualityService`, which keeps the scores on disk, so a second pass
/// over the same photos is instant. The flag rule is `ClutterFlag.strongest`,
/// the same one the swipe card's chip uses.
@Observable
final class ClutterDeckSearch {

    /// Found photos waiting to be swiped before the search pauses.
    static let lookahead = 8
    /// Photos scored at the same time.
    private static let batchSize = 3

    /// Photos looked at so far, flagged or not.
    private(set) var checkedCount = 0
    /// True once every candidate was looked at.
    private(set) var isFinished = false

    @ObservationIgnored private let candidates: [ClutterCandidate]
    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private var foundCount = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let startedAt = Date.now

    @ObservationIgnored private let wantsMore: () -> Bool
    @ObservationIgnored private let onFound: (String) -> Void
    @ObservationIgnored private let onFinished: () -> Void

    /// - Parameters:
    ///   - wantsMore: asked before each batch; false pauses the search until
    ///     the next `resume()`.
    ///   - onFound: called with each flagged photo, in date order.
    ///   - onFinished: called once, after the last candidate.
    init(
        candidates: [ClutterCandidate],
        wantsMore: @escaping () -> Bool,
        onFound: @escaping (String) -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.candidates = candidates
        self.wantsMore = wantsMore
        self.onFound = onFound
        self.onFinished = onFinished
        self.isFinished = candidates.isEmpty
    }

    /// Starts or continues the search. Does nothing while it runs, once it's
    /// finished, or while enough found photos are waiting.
    func resume() {
        guard loop == nil, !isFinished, wantsMore() else { return }
        loop = Task { await run() }
    }

    /// Stops for good: the deck closed.
    func cancel() {
        guard let loop else { return }
        loop.cancel()
        self.loop = nil
        print("[quality] clutter deck closed: checked \(checkedCount) of \(candidates.count), found \(foundCount) in \(elapsed) s")
    }

    private func run() async {
        while nextIndex < candidates.count, wantsMore() {
            let end = min(nextIndex + Self.batchSize, candidates.count)
            let batch = Array(candidates[nextIndex..<end])
            nextIndex = end

            let flags = await Self.flags(for: batch)
            // Cancelled means the deck closed: nobody wants these any more.
            guard !Task.isCancelled else { return }

            checkedCount += batch.count
            for (candidate, flag) in zip(batch, flags) where flag != nil {
                foundCount += 1
                onFound(candidate.identifier)
            }
        }
        loop = nil

        if nextIndex >= candidates.count {
            isFinished = true
            print("[quality] clutter deck: checked all \(checkedCount), found \(foundCount) in \(elapsed) s")
            onFinished()
        }
    }

    private var elapsed: String {
        String(format: "%.1f", Date.now.timeIntervalSince(startedAt))
    }

    /// Each photo's flag, in the batch's order, scored side by side off the
    /// main thread. A photo that couldn't be scored counts as clean (the
    /// service already logged why).
    @concurrent
    private nonisolated static func flags(for batch: [ClutterCandidate]) async -> [ClutterFlag?] {
        await withTaskGroup(of: (Int, ClutterFlag?).self) { group in
            for (index, candidate) in batch.enumerated() {
                group.addTask {
                    if candidate.isScreenshot {
                        return (index, ClutterFlag.screenshot)
                    }
                    let quality = await PhotoQualityService.shared.quality(for: candidate.identifier)
                    return (index, ClutterFlag.strongest(isScreenshot: false, quality: quality))
                }
            }
            var flags = [ClutterFlag?](repeating: nil, count: batch.count)
            for await (index, flag) in group {
                flags[index] = flag
            }
            return flags
        }
    }
}
