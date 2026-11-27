#if DEBUG
import PhotosUI
import SwiftUI

/// Part S0 of the iOS 27 kits plan (Debug only, nothing here ships).
///
/// A menu in a gallery's toolbar that runs the two ways Apple's new sheets can
/// share it as an iCloud Shared Album, so he can count the taps:
/// - **Post to a shared album:** Apple's picker opens with the gallery's photos
///   already selected → Add → Apple's posting sheet (he picks the album) → Post.
/// - **New shared album:** Apple's creation sheet, titled like the gallery →
///   the same picker → the posting sheet with the new album already chosen.
///
/// The posting sheet only takes `PHPickerResult`s, which only the picker makes,
/// so the picker step can't be skipped. S1 gets built only if a flow is two taps
/// or fewer for him. Every step logs with `[shared]`. Delete this file and its
/// toolbar item in `GalleryDetailView` once S0 is decided.
@available(iOS 27, *)
struct SharedAlbumSpikeMenu: View {
    let galleryName: String
    let identifiers: [String]

    @State private var flow: SharedAlbumSpikeFlow.Start?

    var body: some View {
        Menu {
            Button {
                flow = .post
            } label: {
                Text(verbatim: "S0 · Post to a shared album")
            }
            Button {
                flow = .createThenPost
            } label: {
                Text(verbatim: "S0 · New shared album")
            }
        } label: {
            Image(systemName: "rectangle.stack.badge.person.crop")
        }
        .sheet(item: $flow) { start in
            SharedAlbumSpikeFlow(
                galleryName: galleryName,
                identifiers: identifiers,
                start: start,
                onFinish: { flow = nil }
            )
            .ignoresSafeArea()
        }
    }
}

/// Apple's sheets, one after the other. The first one is the sheet's own
/// content; each next one is presented on top of the one before.
@available(iOS 27, *)
struct SharedAlbumSpikeFlow: UIViewControllerRepresentable {
    enum Start: String, Identifiable {
        case post, createThenPost
        var id: String { rawValue }
    }

    let galleryName: String
    let identifiers: [String]
    let start: Start
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        context.coordinator.begin()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject,
                             PHPickerViewControllerDelegate,
                             PHSharedAlbumCreationViewController.Delegate,
                             PHSharedAlbumPostingViewController.Delegate {
        private let parent: SharedAlbumSpikeFlow
        private let started = Date()
        private var albumIdentifier: String?

        init(_ parent: SharedAlbumSpikeFlow) {
            self.parent = parent
        }

        func begin() -> UIViewController {
            log("start: \(parent.start.rawValue), gallery \"\(parent.galleryName)\", \(parent.identifiers.count) photos")
            switch parent.start {
            case .post:
                return makePicker()
            case .createThenPost:
                var configuration = PHSharedAlbumCreationConfiguration(photoLibrary: .shared())
                configuration.defaultTitle = parent.galleryName
                let creation = PHSharedAlbumCreationViewController(configuration: configuration)
                creation.delegate = self
                log("creation sheet shown, title \"\(parent.galleryName)\"")
                return creation
            }
        }

        private func makePicker() -> PHPickerViewController {
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.selectionLimit = 0
            configuration.selection = .ordered
            configuration.preselectedAssetIdentifiers = parent.identifiers
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            log("picker shown with \(parent.identifiers.count) photos preselected")
            return picker
        }

        // MARK: Creation

        func sharedAlbumCreationViewController(
            _ creationViewController: PHSharedAlbumCreationViewController,
            didCompleteWithError error: (any Error)?
        ) {
            if let error {
                log("creation failed: \(error)")
                parent.onFinish()
                return
            }
            guard let identifier = creationViewController.creationResult?.albumIdentifier else {
                log("creation cancelled")
                parent.onFinish()
                return
            }
            albumIdentifier = identifier
            log("shared album created: \(identifier)")
            creationViewController.present(makePicker(), animated: true)
        }

        // MARK: Picker

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                log("picker cancelled (or nothing selected)")
                parent.onFinish()
                return
            }
            log("picker returned \(results.count) of \(parent.identifiers.count) photos")
            let posting = PHSharedAlbumPostingViewController(
                items: results,
                defaultAlbumIdentifier: albumIdentifier,
                photoLibrary: .shared()
            )
            posting.delegate = self
            picker.present(posting, animated: true)
            log("posting sheet shown, album \(albumIdentifier == nil ? "to choose" : "preselected")")
        }

        // MARK: Posting

        func sharedAlbumPostingViewController(
            _ postingViewController: PHSharedAlbumPostingViewController,
            didCompleteWithError error: (any Error)?
        ) {
            if let error {
                log("posting failed: \(error)")
            } else if let album = postingViewController.albumIdentifier {
                log("posted to \(album)")
            } else {
                log("posting cancelled")
            }
            parent.onFinish()
        }

        private func log(_ message: String) {
            let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
            print("[shared] +\(seconds) s \(message)")
        }
    }
}
#endif
