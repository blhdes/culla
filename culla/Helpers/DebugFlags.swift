import Foundation

/// Switches for short-lived spikes. Every flag is `false` in Release builds,
/// and the code behind it sits in `#if DEBUG`, so none of it ships.
nonisolated enum DebugFlags {
    #if DEBUG
    /// Part V0 of the iOS 27 kits plan: for each duplicate scan, also run the
    /// old `VNGenerateImageFeaturePrintRequest` on the same thumbnails and log
    /// both distances (`[dupes] old=0.41 new=0.41`). Remove once the device
    /// session confirms the two match.
    static let logDuplicateDistances = true
    #else
    static let logDuplicateDistances = false
    #endif
}
