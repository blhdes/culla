import Foundation

// MARK: - Gallery sort field

/// Sort options offered by the `SortChip` on the gallery sheets. Persisted via
/// `@AppStorage` as the raw string, with a sibling `…Descending` bool for
/// direction. Lives here, not inside a sheet, because both gallery sheets read
/// the same choice so they stay in sync.
///
/// `custom` is the manual drag order (`displayOrder`) — a directionless default,
/// so opening a sheet never reshuffles what the user arranged by hand, and the
/// chip shows a checkmark instead of an arrow.
enum GallerySortField: String, CaseIterable, Identifiable, SortFieldProtocol {
    case custom
    case name
    case photoCount
    case dateCreated
    case recentlyUpdated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:          String(localized: "Custom")
        case .name:            String(localized: "Name")
        case .photoCount:      String(localized: "Photo Count")
        case .dateCreated:     String(localized: "Date Created")
        case .recentlyUpdated: String(localized: "Recently Updated")
        }
    }

    /// `nil` for `custom` — the manual drag order has no direction, so the chip
    /// shows a checkmark and re-picking it is a no-op.
    var defaultDescending: Bool? {
        switch self {
        case .custom:          nil
        case .name:            false  // A→Z reads best first
        case .photoCount:      true   // biggest first
        case .dateCreated:     true   // newest first
        case .recentlyUpdated: true   // most recently touched first
        }
    }
}

// MARK: - Shared gallery sort

extension Array where Element == Gallery {
    /// Orders galleries by a sort field — the one implementation both gallery
    /// sheets share, so they sort identically. `custom` keeps the source order
    /// (the `@Query(sort: \.displayOrder)` the callers already use), which is
    /// also what makes manual drag-reordering possible.
    ///
    /// Galleries with no photos have no "recently updated" date; they sink to
    /// the bottom while ascending, and the `descending` reverse then floats them
    /// to the top — the standard "missing dates last" behaviour.
    func sortedBy(field: GallerySortField, descending: Bool) -> [Gallery] {
        guard field != .custom else { return self }
        var rows = self
        rows.sort { lhs, rhs in
            switch field {
            case .custom:
                return false  // unreachable — guarded above
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .photoCount:
                return lhs.sortedPhotos.count < rhs.sortedPhotos.count
            case .dateCreated:
                return lhs.createdAt < rhs.createdAt
            case .recentlyUpdated:
                let l = lhs.lastSortedAt
                let r = rhs.lastSortedAt
                switch (l, r) {
                case let (l?, r?): return l < r
                case (nil, _?):    return false
                case (_?, nil):    return true
                case (nil, nil):
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
        if descending { rows.reverse() }
        return rows
    }
}

private extension Gallery {
    /// The newest moment a photo landed in this gallery, or `nil` if it's empty.
    /// Drives the "Recently Updated" sort.
    var lastSortedAt: Date? {
        sortedPhotos.map(\.sortedAt).max()
    }
}
