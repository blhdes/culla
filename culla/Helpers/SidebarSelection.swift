import SwiftUI

extension Binding where Value == Set<UUID> {
    /// Drops the IDs of galleries that no longer exist from the swipe-sidebar
    /// selection.
    ///
    /// Deleting a gallery used to leave its ID behind in the saved selection.
    /// Those "ghost" IDs still counted toward the selection limit, so the
    /// sheets could read "3 of 10 selected" with two galleries on screen, or
    /// refuse a new selection that should have fit.
    ///
    /// Does nothing while `galleries` is empty, so a list that hasn't loaded
    /// yet can never wipe the user's selection.
    func pruneDeletedGalleries(keeping galleries: [Gallery]) {
        guard !galleries.isEmpty else { return }
        let existing = Set(galleries.map(\.id))
        guard !wrappedValue.isSubset(of: existing) else { return }
        wrappedValue = wrappedValue.intersection(existing)
    }
}
