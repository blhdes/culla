# picsort

A native iOS app for organizing your photo library. Swipe through photos one by one — left to delete, right to sort into galleries. Think Tinder, but for your camera roll.

## Why picsort?

Most photo organizer apps let you keep or delete. picsort's core experience is **multi-gallery sorting** — drag a photo toward any of your galleries and it's instantly saved there. Your galleries sync with real iPhone Photos albums, so everything stays organized across your device.

- 100% native Swift/SwiftUI — zero external dependencies
- Open source and free — no ads, no paywalls
- Syncs with your iPhone Photos library
- Minimalist, HIG-compliant design

## How It Works

1. **Pick a starting date** — choose how far back to go, optionally filter by album
2. **Move or copy** — when sorting from an existing album, choose whether photos stay in the source or get moved out
3. **Swipe through photos** — they appear one at a time, fullscreen, with a progress counter and date label
4. **Swipe left** — marks the photo for deletion (light haptic)
5. **Drag right toward a gallery** — sorts it into that gallery with a confirmation toast (medium haptic)
6. **Double-tap** — skip without sorting or deleting (photo reappears next session)
7. **Long-press** — preview your gallery panels at full opacity
8. **Delete button** — batch-deletes all dismissed photos from your library in one shot
9. **Gallery management** — delete a gallery and choose to permanently remove its photos or keep them safe

## Requirements

- iOS 17.0+
- Xcode 15+
- Photo Library access (read/write)

## Project Structure

```
picsort/
├── picsortApp.swift                    # App entry point, SwiftData container
│
├── Models/
│   ├── Gallery.swift                   # User-created gallery (SwiftData @Model)
│   ├── SortedPhoto.swift               # Links a photo to a gallery
│   ├── DismissedPhoto.swift            # Tracks photos marked for deletion
│   └── PhoneAlbum.swift                # Wrapper for PHAssetCollection
│
├── Services/
│   └── PhotoLibraryService.swift       # PhotoKit wrapper — auth, fetch, cache, sync
│
├── ViewModels/
│   ├── SwipeViewModel.swift            # Swipe queue, actions, undo, batch delete
│   └── GalleryViewModel.swift          # Gallery CRUD and reordering
│
├── Views/
│   ├── ContentView.swift               # Root navigation (date picker → swipe)
│   ├── DatePickerView.swift            # Starting date + album filter selection
│   ├── SwipeView.swift                 # Core swipe screen with gesture handling
│   ├── PhotoCardView.swift             # Single photo card (drag offset, opacity)
│   ├── GallerySidebarView.swift        # Pastel gallery panels on right side
│   ├── GallerySelectionSheet.swift     # Pick which galleries appear in sidebar
│   ├── AlbumPickerView.swift           # Browse phone albums + unsorted filter
│   ├── AlbumImportSheet.swift          # Import phone albums as app galleries
│   ├── GalleriesView.swift             # Gallery list with reorder/delete
│   └── GalleryDetailView.swift         # Photo grid for a single gallery
│
└── Helpers/
    └── PhotoImageLoader.swift          # Per-card async image loader
```

## Architecture

**MVVM + SwiftData + PhotoKit**

- **SwiftData** persists galleries, sorted photos, and dismissed photos. We never copy photo bytes — only store `PHAsset.localIdentifier` strings.
- **PhotoKit** handles all interaction with the iPhone photo library: fetching, caching, album sync, and deletion.
- **PHCachingImageManager** preloads the next 3 photos so transitions feel instant.
- **@Observable** (iOS 17 Observation framework) drives reactive UI updates.

### Data Flow

```
Photo Library (PhotoKit)
       │
       ▼
PhotoLibraryService ──→ SwipeViewModel ──→ SwipeView
       │                      │                │
       │                      ▼                ▼
       │               SwiftData Models   PhotoCardView
       │               (Gallery,          GallerySidebarView
       │                SortedPhoto,
       │                DismissedPhoto)
       │
       ▼
  iPhone Albums (sync)
```

### Swipe Gesture Design

- **100pt threshold** to trigger an action, with velocity-aware detection (`predictedEndTranslation`) so fast flicks work even with shorter drag distance
- **Rotation** follows drag offset (offset / 40 degrees, subtle)
- **Progressive transparency** on right drag (fades to 70%) reveals gallery names
- **Spring animation** for snap-back, **easeIn** for fly-off
- **Haptic feedback** — light on dismiss, medium on gallery sort
- **Confirmation toasts** — "Dismissed" or "→ Gallery Name" after each action
- **Photo counter** — "3 / 47" progress indicator at top
- **Date label** — shows current photo's creation date for context

### Photo Preloading

```
Queue:  [A] [B] [C] [D] [E] ...
         ↑       ↑   ↑ ↑ ↑
      current   next  cache window (3 ahead)
```

Old images are evicted from the cache as the window slides forward.

## Building

1. Clone the repo
2. Open `picsort.xcodeproj` in Xcode
3. Add `NSPhotoLibraryUsageDescription` to Info.plist if not already present
4. Build and run on a device or simulator (add sample photos to the simulator via drag-drop)

## License

Open source. Free forever.
