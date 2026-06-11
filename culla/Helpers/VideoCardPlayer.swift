import AVFoundation
import SwiftUI

/// Owns the looping player for whichever card is currently on top of the
/// swipe stack (and for the full-screen preview). One instance = at most
/// one video playing, which is exactly the behavior we want.
@Observable @MainActor
final class VideoCardPlayer {
    private(set) var player: AVQueuePlayer?

    /// Identifier the current player belongs to — guards against races
    /// when the user swipes faster than a (possibly iCloud) video loads.
    private(set) var activeIdentifier: String?

    var isMuted = true {
        didSet {
            player?.isMuted = isMuted
            if !isMuted {
                AudioSessionHelper.activateForAudio()
            }
            // Re-muting keeps the session escalated until the card changes —
            // restoring here would thrash the session while the video loops.
        }
    }

    private var looper: AVPlayerLooper?

    /// Bumped on every prepare/teardown. An in-flight load compares against it
    /// after its await so a superseded load can never attach its player — even
    /// when the same identifier is in flight twice (undo within the load window).
    private var generation = 0

    /// Call whenever the top card changes. Tears down for images,
    /// loads and auto-plays (muted, looping) for videos.
    func prepare(for identifier: String?, service: PhotoLibraryService) async {
        // Both the initial .task and onChange can request the same card —
        // one load is enough.
        guard identifier != activeIdentifier else { return }

        generation += 1
        let gen = generation
        activeIdentifier = identifier
        stopPlayback()

        // loadPlayerItem rejects non-videos itself — no separate media-type fetch.
        guard let identifier,
              let item = await service.loadPlayerItem(for: identifier) else { return }
        guard gen == generation else { return }   // superseded while loading

        AudioSessionHelper.prepareForMutedPlayback()

        let queuePlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        isMuted = true   // every card starts muted
        queuePlayer.isMuted = true
        queuePlayer.play()
        player = queuePlayer
    }

    func teardown() {
        generation += 1
        activeIdentifier = nil
        stopPlayback()
    }

    private func stopPlayback() {
        player?.pause()
        looper = nil
        player = nil
        // Pause must precede this — deactivating a busy session throws.
        AudioSessionHelper.restoreAmbientAfterAudio()
    }
}

// MARK: - Player Layer Host

/// Chrome-free AVPlayerLayer host. SwiftUI's VideoPlayer shows transport
/// controls and can't switch videoGravity, so we wrap the layer ourselves.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVQueuePlayer
    /// false → .resizeAspect (fit), true → .resizeAspectFill (zoomed card).
    let fillsFrame: Bool

    final class HostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = fillsFrame ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - Audio Session

enum AudioSessionHelper {
    /// True while the session is escalated to .playback by an unmute.
    private static var isEscalated = false

    /// .ambient + mixWithOthers BEFORE first playback — the iOS default
    /// (.soloAmbient) would pause the user's music even for muted video.
    static func prepareForMutedPlayback() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("culla: failed to set ambient audio session: \(error)")
        }
    }

    /// Switch to .playback on unmute so video audio is audible even with the
    /// silent switch on. Trade-off: this stops background music — acceptable
    /// because the user explicitly asked to hear the video.
    static func activateForAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            isEscalated = true
        } catch {
            print("culla: failed to activate playback audio session: \(error)")
        }
    }

    /// Hands audio back to whatever the user was listening to before they
    /// unmuted. Without the notifyOthersOnDeactivation handoff, one unmute
    /// would leave the user's music paused for the rest of the app session.
    static func restoreAmbientAfterAudio() {
        guard isEscalated else { return }
        isEscalated = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            print("culla: failed to restore ambient audio session: \(error)")
        }
    }
}
