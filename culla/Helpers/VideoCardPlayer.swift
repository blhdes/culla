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
        didSet { player?.isMuted = isMuted }
    }

    private var looper: AVPlayerLooper?

    /// Call whenever the top card changes. Tears down for images,
    /// loads and auto-plays (muted, looping) for videos.
    func prepare(for identifier: String?, service: PhotoLibraryService) async {
        activeIdentifier = identifier
        stopPlayback()

        guard let identifier,
              service.mediaInfo(for: identifier)?.isVideo == true else { return }

        guard let item = await service.loadPlayerItem(for: identifier) else { return }

        // The user may have swiped on while the video was loading.
        guard activeIdentifier == identifier else { return }

        AudioSessionHelper.prepareForMutedPlayback()

        let queuePlayer = AVQueuePlayer()
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        isMuted = true   // every card starts muted
        queuePlayer.isMuted = true
        queuePlayer.play()
        player = queuePlayer
    }

    func teardown() {
        activeIdentifier = nil
        stopPlayback()
    }

    private func stopPlayback() {
        player?.pause()
        looper = nil
        player = nil
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
    /// silent switch on. Trade-off: this ducks/stops background music —
    /// acceptable because the user explicitly asked to hear the video.
    static func activateForAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            print("culla: failed to activate playback audio session: \(error)")
        }
    }
}
