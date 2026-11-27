#if DEBUG
import AVFoundation
import MediaIntelligence
import Photos

/// Part H0 of the iOS 27 kits plan (Debug only, nothing here ships).
///
/// Each time a video becomes the top swipe card, MediaIntelligence finds its
/// highlights and its best single frame, and the console gets one line:
/// `[video] #3 62.0 s · local · file 0.12 s · analysis 1.84 s · highlights
/// 12.4–18.0 s (0.83), 40.1–44.0 s (0.61) · keyframe 13.0 s`.
///
/// Answers H0: is it fast enough (under ~2 s for a 1-minute clip), do iCloud
/// videos give a file at all, and do the moments look right to him (he scrubs
/// to them in Photos). Every 10 videos it prints a summary. Delete this file,
/// its flag and its call in `SwipeViewModel` once H1 is decided.
final class VideoHighlightSpike {

    static let shared = VideoHighlightSpike()

    private static let summaryEvery = 10

    private struct Sample {
        let duration: Double
        let analysisSeconds: Double
    }

    private var started: Set<String> = []
    private var number = 0
    private var samples: [Sample] = []
    private var iCloudOnlyCount = 0
    private var failureCount = 0

    func cardShown(_ identifier: String) {
        guard DebugFlags.logVideoHighlights, #available(iOS 27, *) else { return }
        guard !started.contains(identifier),
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              asset.mediaType == .video else { return }
        started.insert(identifier)
        number += 1
        let number = number
        let duration = asset.duration

        Task {
            let line = await Task.detached(priority: .utility) {
                await Self.analyze(asset, number: number)
            }.value
            record(line, duration: duration)
        }
    }

    // MARK: - Analysis (off the main thread)

    private enum Outcome: Sendable {
        case analyzed(String, seconds: Double)
        case noFile(String)
        case failed(String)
    }

    @available(iOS 27, *)
    private nonisolated static func analyze(_ asset: PHAsset, number: Int) async -> Outcome {
        let head = "[video] #\(number) \(format(asset.duration)) s"

        // Try without the network first, so the log can tell local from iCloud.
        var fileStart = Date()
        var source = "local"
        var url = await fileURL(for: asset, networkAllowed: false)
        if url == nil {
            source = "icloud"
            fileStart = Date()
            url = await fileURL(for: asset, networkAllowed: true)
        }
        let fileSeconds = Date().timeIntervalSince(fileStart)
        guard let url else {
            return .noFile("\(head) · \(source) · no file URL after \(format(fileSeconds)) s, not analyzed")
        }

        let video = MediaIntelligenceVideoAsset(id: .init(asset.localIdentifier), kind: .url(url))
        let start = Date()
        let highlights: Result<HighlightAnalysisRequest.Result, any Error>
        let keyFrame: Result<KeyFrameAnalysisRequest.Result, any Error>
        do {
            (highlights, keyFrame) = try await VideoAnalyzer.shared.analyze(
                video, for: HighlightAnalysisRequest(), KeyFrameAnalysisRequest()
            )
        } catch {
            return .failed("\(head) · \(source) · analysis failed: \(error)")
        }
        let seconds = Date().timeIntervalSince(start)

        var parts = [head, source, "file \(format(fileSeconds)) s", "analysis \(format(seconds)) s"]
        switch highlights {
        case .success(let result):
            let levelByStart = Dictionary(
                result.levels.map { ($0.timeRange.start.seconds, $0.level) },
                uniquingKeysWith: max
            )
            let ranges = result.highlights.map { range -> String in
                let level = levelByStart[range.start.seconds].map { " (\(format($0, digits: 2)))" } ?? ""
                return "\(format(range.start.seconds))–\(format(range.end.seconds)) s\(level)"
            }
            parts.append(ranges.isEmpty ? "no highlights" : "highlights " + ranges.joined(separator: ", "))
            if let best = result.levels.max(by: { $0.level < $1.level }) {
                parts.append("top level \(format(best.level, digits: 2)) at \(format(best.timeRange.start.seconds))–\(format(best.timeRange.end.seconds)) s")
            }
        case .failure(let error):
            parts.append("highlights failed: \(error)")
        }
        switch keyFrame {
        case .success(let result):
            parts.append("keyframe \(format(result.timestamp.seconds)) s")
        case .failure(let error):
            parts.append("keyframe failed: \(error)")
        }
        return .analyzed(parts.joined(separator: " · "), seconds: seconds)
    }

    private nonisolated static func fileURL(for asset: PHAsset, networkAllowed: Bool) async -> URL? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = networkAllowed
        options.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { continuation in
            // Same guard as `loadVideoURL`: resuming a continuation twice crashes.
            var resumed = false
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
            }
        }
    }

    // MARK: - Log and summary

    private func record(_ outcome: Outcome, duration: Double) {
        switch outcome {
        case .analyzed(let line, let seconds):
            print(line)
            samples.append(Sample(duration: duration, analysisSeconds: seconds))
        case .noFile(let line):
            print(line)
            iCloudOnlyCount += 1
        case .failed(let line):
            print(line)
            failureCount += 1
        }
        let total = samples.count + iCloudOnlyCount + failureCount
        if total.isMultiple(of: Self.summaryEvery) { printSummary() }
    }

    private func printSummary() {
        let perMinute = samples
            .filter { $0.duration > 0 }
            .map { $0.analysisSeconds / ($0.duration / 60) }
            .sorted()
        let median = perMinute.isEmpty ? 0 : perMinute[perMinute.count / 2]
        let slowest = samples.max { $0.analysisSeconds < $1.analysisSeconds }
        print("[video] ── spike summary ──")
        print("[video] analyzed \(samples.count), no file \(iCloudOnlyCount), failed \(failureCount)")
        print("[video] analysis seconds per minute of video: median \(Self.format(median, digits: 2)), max \(Self.format(perMinute.last ?? 0, digits: 2))")
        if let slowest {
            print("[video] slowest: \(Self.format(slowest.analysisSeconds)) s for a \(Self.format(slowest.duration)) s video")
        }
    }

    private nonisolated static func format(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    private nonisolated static func format(_ value: Float, digits: Int = 1) -> String {
        format(Double(value), digits: digits)
    }
}
#endif
