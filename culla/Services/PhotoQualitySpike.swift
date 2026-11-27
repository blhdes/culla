#if DEBUG
import Photos

/// Part Q0 of the iOS 27 kits plan (Debug only, nothing here ships).
///
/// Each time a photo becomes the top swipe card, Vision scores it: how good
/// it looks (`overallScore`, −1…1), whether it's a screenshot/receipt/document
/// (`isUtility`) and, on iOS 26+, how sure it is the lens was dirty. Then it
/// logs what he did with the card. His own swipe is the "is it junk?" label:
/// a dismissed photo counts as junk, a sorted or skipped one as kept.
///
/// Every 30 photos with both a score and a decision it prints a summary, so
/// the device session can pick the badge thresholds. It skips the service's
/// cache on purpose, to time a fresh analysis every time. Delete this file,
/// and its calls in `SwipeViewModel`, once the thresholds are set.
final class PhotoQualitySpike {

    static let shared = PhotoQualitySpike()

    enum Decision: String {
        case dismissed, sorted, skipped
    }

    private struct Entry {
        let number: Int
        var score: Float?
        var isUtility = false
        var smudge: Float?
        var loadSeconds = 0.0
        var visionSeconds = 0.0
        var decision: Decision?

        var isComplete: Bool { score != nil && decision != nil }
    }

    private static let summaryEvery = 30
    private static let scoreCutoffs: [Float] = [-0.5, -0.3, -0.1, 0, 0.1]
    private static let smudgeCutoffs: [Float] = [0.5, 0.8]

    private var entries: [String: Entry] = [:]
    private var shownCount = 0
    private var summarizedCount = 0

    private init() {}

    // MARK: - Hooks from SwipeViewModel

    /// A photo became the top card. Each photo is scored once per launch, so
    /// a card brought back by undo isn't counted twice.
    func cardShown(_ identifier: String) {
        guard DebugFlags.logPhotoQuality, entries[identifier] == nil else { return }
        shownCount += 1
        entries[identifier] = Entry(number: shownCount)
        Task { await score(identifier) }
    }

    /// He dismissed, sorted or skipped the card.
    func record(_ decision: Decision, for identifier: String) {
        guard DebugFlags.logPhotoQuality, entries[identifier] != nil else { return }
        entries[identifier]?.decision = decision
        print("[quality] #\(entries[identifier]?.number ?? 0) → \(decision.rawValue)")
        summarizeIfDue()
    }

    /// He undid the last action on this card.
    func undo(_ identifier: String) {
        guard DebugFlags.logPhotoQuality, entries[identifier]?.decision != nil else { return }
        entries[identifier]?.decision = nil
        print("[quality] #\(entries[identifier]?.number ?? 0) → undone")
    }

    // MARK: - Scoring

    private func score(_ identifier: String) async {
        guard let number = entries[identifier]?.number else { return }

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            print("[quality] #\(number) asset not found")
            entries[identifier] = nil
            return
        }
        guard asset.mediaType == .image else {
            // Videos get no badge, so they don't count toward the summary.
            print("[quality] #\(number) video, not scored")
            entries[identifier] = nil
            return
        }

        // The same two steps as `PhotoQualityService`, timed one by one.
        let clock = ContinuousClock()
        let loadStart = clock.now
        guard let image = await PhotoQualityService.loadAnalysisImage(for: asset) else {
            print("[quality] #\(number) no image")
            entries[identifier] = nil
            return
        }
        let loadSeconds = Self.seconds(clock.now - loadStart)

        let visionStart = clock.now
        do {
            let quality = try await PhotoQualityService.measure(image)
            let visionSeconds = Self.seconds(clock.now - visionStart)

            entries[identifier]?.score = quality.score
            entries[identifier]?.isUtility = quality.isUtility
            entries[identifier]?.smudge = quality.smudge
            entries[identifier]?.loadSeconds = loadSeconds
            entries[identifier]?.visionSeconds = visionSeconds

            let smudgeText = quality.smudge.map { Self.format($0) } ?? "n/a"
            print("[quality] #\(number) score=\(Self.format(quality.score)) utility=\(quality.isUtility) smudge=\(smudgeText) load=\(Self.format(loadSeconds))s vision=\(Self.format(visionSeconds))s \(image.cgImage.width)×\(image.cgImage.height) id=\(identifier.prefix(8))")
            summarizeIfDue()
        } catch {
            print("[quality] #\(number) Vision failed: \(error)")
            entries[identifier] = nil
        }
    }

    // MARK: - Summary

    /// Prints one block each time another 30 photos have a score and a decision.
    private func summarizeIfDue() {
        let complete = entries.values.filter(\.isComplete).sorted { $0.number < $1.number }
        guard complete.count >= summarizedCount + Self.summaryEvery else { return }
        summarizedCount = complete.count

        let junk = complete.filter { $0.decision == .dismissed }
        let kept = complete.filter { $0.decision != .dismissed }
        print("[quality] ── spike summary, \(complete.count) photos ──")
        print("[quality] dismissed \(junk.count): score \(Self.range(junk)) · kept \(kept.count): score \(Self.range(kept))")

        let utility = complete.filter(\.isUtility)
        print("[quality] utility=true: \(utility.count), \(utility.count(where: { $0.decision == .dismissed })) of them dismissed")

        let scoreLine = Self.scoreCutoffs.map { cutoff in
            let flagged = complete.filter { ($0.score ?? 1) < cutoff }
            return "<\(Self.format(cutoff)): \(flagged.count) (\(flagged.count(where: { $0.decision == .dismissed })) dismissed)"
        }
        print("[quality] score " + scoreLine.joined(separator: " · "))

        if complete.contains(where: { $0.smudge != nil }) {
            let smudgeLine = Self.smudgeCutoffs.map { cutoff in
                let flagged = complete.filter { ($0.smudge ?? 0) >= cutoff }
                return "≥\(Self.format(cutoff)): \(flagged.count) (\(flagged.count(where: { $0.decision == .dismissed })) dismissed)"
            }
            print("[quality] smudge " + smudgeLine.joined(separator: " · "))
        }

        print("[quality] vision median=\(Self.format(Self.median(complete.map(\.visionSeconds))))s max=\(Self.format(complete.map(\.visionSeconds).max() ?? 0))s · load median=\(Self.format(Self.median(complete.map(\.loadSeconds))))s max=\(Self.format(complete.map(\.loadSeconds).max() ?? 0))s")
    }

    // MARK: - Formatting

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func format(_ value: Float) -> String { String(format: "%.2f", value) }
    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// "mean −0.21 (−0.80…0.35)", or "—" when there are none.
    private static func range(_ group: [Entry]) -> String {
        let scores = group.compactMap(\.score)
        guard let low = scores.min(), let high = scores.max() else { return "—" }
        let mean = scores.reduce(0, +) / Float(scores.count)
        return "mean \(format(mean)) (\(format(low))…\(format(high)))"
    }
}

#endif
