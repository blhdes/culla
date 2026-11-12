//
//  DeleteGalleryConfirmation.swift
//  culla
//
//  The question asked before a gallery goes. It hangs on what asked for
//  it (the swiped row, the trash button), because iOS 26 draws a
//  confirmation as a popover pointing at the view it hangs from: on the
//  whole list or screen it opens away from the row.
//
//  The answer runs once the question has closed. A row removed at once
//  takes its question with it, still marked open, and iOS shows it again
//  for an instant over the empty place.
//

import SwiftUI

extension View {
    /// Asks whether to delete the gallery called `name`, beside this view.
    /// Each answer closes the question first, then runs its action.
    /// `name` is a plain copy: the gallery may be deleted while this view
    /// is still on its way out, and it must not read a deleted model.
    func deleteGalleryConfirmation(
        name: String,
        isPresented: Binding<Bool>,
        onDeleteWithPhotos: @escaping @MainActor () async -> Void,
        onDeleteKeepPhotos: @escaping @MainActor () async -> Void,
        onUnlink: @escaping @MainActor () async -> Void
    ) -> some View {
        confirmationDialog(
            Text("Delete \"\(name)\"?"),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Gallery & Photos", role: .destructive) {
                DeleteGalleryConfirmation.answer(closing: isPresented, then: onDeleteWithPhotos)
            }
            Button("Delete Gallery, Keep Photos", role: .destructive) {
                DeleteGalleryConfirmation.answer(closing: isPresented, then: onDeleteKeepPhotos)
            }
            Button("Remove from Culla") {
                DeleteGalleryConfirmation.answer(closing: isPresented, then: onUnlink)
            }
        } message: {
            Text("\"Remove from Culla\" just hides it here — your iPhone album stays intact.")
        }
    }
}

private enum DeleteGalleryConfirmation {
    /// About as long as iOS takes to close the question.
    static let closing: Duration = .milliseconds(300)

    /// Closes the question, waits for it to be gone, then runs `action`.
    @MainActor
    static func answer(closing isPresented: Binding<Bool>, then action: @escaping @MainActor () async -> Void) {
        isPresented.wrappedValue = false
        Task {
            do {
                try await Task.sleep(for: closing)
            } catch {
                print("DeleteGalleryConfirmation: the wait for the question to close failed: \(error)")
                return
            }
            await action()
        }
    }
}
