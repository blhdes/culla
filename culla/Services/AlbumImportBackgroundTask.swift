import BackgroundTasks
import Foundation

/// Lets a big album import keep going after he leaves Culla (iOS 26+). iOS
/// shows the title, the album and the progress outside the app, and can stop
/// the import when the phone needs the resources (or when he stops it from
/// that UI). Then the importer stops between two records: the albums already
/// saved stay imported. Part B of the iOS 27 kits plan.
///
/// Below iOS 26, or for a small import, `start` returns nil and the import
/// runs in the app only, exactly as before.
final class AlbumImportBackgroundTask {

    /// Below this many photos the import is over before he could leave the
    /// app, so iOS's progress UI would only flash. Provisional: B0's timing
    /// line (`[import] … photos/s`) sets the real number (~5 s of work).
    static let minimumPhotos = 2000

    /// Must match `BGTaskSchedulerPermittedIdentifiers` (`agu.culla.import.*`)
    /// in Info.plist.
    private static let identifierPrefix = "agu.culla.import."

    /// Called when iOS (or he) stops the task. The sheet cancels the import.
    var onExpire: (() -> Void)?

    /// The running `BGContinuedProcessingTask`, once iOS has started it.
    /// Typed as `BGTask` so the class itself needs no availability gate.
    private var task: BGTask?
    private var latest: AlbumImportProgress
    /// Set when the import ended before iOS started the task.
    private var finishedSuccess: Bool?

    private init(progress: AlbumImportProgress) {
        latest = progress
    }

    /// Asks iOS to let this import continue in the background. Nil when it
    /// can't (older iOS, small import, or iOS said no): the import still runs.
    static func start(for progress: AlbumImportProgress) -> AlbumImportBackgroundTask? {
        guard #available(iOS 26, *) else { return nil }
        guard progress.photosTotal >= minimumPhotos else { return nil }

        let identifier = identifierPrefix + UUID().uuidString
        let handle = AlbumImportBackgroundTask(progress: progress)
        // Continued-processing tasks may be registered at any time, not only
        // at launch. On the main queue, so the handler can touch `handle`.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { @Sendable task in
            MainActor.assumeIsolated { handle.attach(task) }
        }
        guard registered else {
            print("[import] couldn't register background task \(identifier): is agu.culla.import.* in Info.plist?")
            return nil
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: subtitle(for: progress)
        )
        // If iOS can't run it right now, don't queue it for later: the import
        // has already started in the app.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[import] iOS didn't allow a background import, it runs in the app only: \(error)")
            return nil
        }
        print("[import] background task submitted: \(progress.photosTotal) photos in \(progress.albumCount) albums")
        return handle
    }

    /// Forwards the importer's progress to iOS's UI.
    func update(_ progress: AlbumImportProgress) {
        let albumChanged = progress.albumIndex != latest.albumIndex || progress.albumName != latest.albumName
        latest = progress
        apply(progress, updatingSubtitle: albumChanged)
    }

    /// The import has ended: tells iOS, which then removes its progress UI.
    func finish(success: Bool) {
        guard let task else {
            finishedSuccess = success   // `attach` completes it if iOS starts it later
            return
        }
        if success, #available(iOS 26, *), let task = task as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        task.setTaskCompleted(success: success)
        self.task = nil
        print("[import] background task completed, success: \(success)")
    }

    // MARK: - Private

    private func attach(_ bgTask: BGTask) {
        guard #available(iOS 26, *), bgTask is BGContinuedProcessingTask else {
            print("[import] unexpected background task: \(bgTask)")
            bgTask.setTaskCompleted(success: false)
            return
        }
        if let finishedSuccess {
            bgTask.setTaskCompleted(success: finishedSuccess)
            return
        }
        // Called on a queue of iOS's choosing.
        bgTask.expirationHandler = { @Sendable [weak self] in
            guard let self else { return }
            Task { @MainActor in self.expire() }
        }
        task = bgTask
        apply(latest, updatingSubtitle: true)
        print("[import] background task started")
    }

    private func expire() {
        print("[import] background import stopped by iOS or from its UI at \(latest.photosDone) of \(latest.photosTotal) photos")
        // The importer stops within a few hundred records; its error then
        // reaches `finish(success: false)`, which completes the task.
        onExpire?()
    }

    private func apply(_ progress: AlbumImportProgress, updatingSubtitle: Bool) {
        guard #available(iOS 26, *), let task = task as? BGContinuedProcessingTask else { return }
        task.progress.totalUnitCount = Int64(progress.photosTotal)
        task.progress.completedUnitCount = Int64(progress.photosDone)
        if updatingSubtitle {
            task.updateTitle(Self.title, subtitle: Self.subtitle(for: progress))
        }
    }

    private static var title: String {
        String(localized: "Importing albums", comment: "Title of iOS's progress UI while albums import in the background")
    }

    private static func subtitle(for progress: AlbumImportProgress) -> String {
        String(
            localized: "\(progress.albumName) · \(progress.albumIndex + 1) of \(progress.albumCount)",
            comment: "Subtitle of iOS's background import progress: album name · position of count"
        )
    }
}
