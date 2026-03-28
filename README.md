# Culla

A native iOS app for organizing your photo library. Swipe through photos one by one — left to dismiss, right to sort into galleries. Think Tinder, but for your camera roll.

## Why Culla?

Most photo organizer apps let you keep or delete. Culla's core experience is **multi-gallery sorting** — drag a photo toward any of your galleries and it's instantly saved there. Your galleries sync with real iPhone Photos albums, so everything stays organized across your device.

- 100% native Swift/SwiftUI — zero external dependencies
- Open source and free — no ads, no paywalls
- Syncs with your iPhone Photos library
- Minimalist, HIG-compliant design

## Features

- **Swipe sorting** — left to dismiss, right toward a gallery to sort, double-tap to skip
- **Full undo history** — undo every action in a session, not just the last one
- **Duplicate Sweep** — finds visually similar photos using Vision framework fingerprinting
- **Favorites sorting** — sort through your favorited photos as a dedicated collection
- **Unsorted photos** — filter to photos not in any album
- **On This Day** — revisit photos from today's date in past years
- **Focus Timer** — 2, 5, or 10 minute sorting sessions with a summary at the end
- **Dismissed Photos** — review, recover, or permanently delete dismissed photos
- **Adaptive neon palette** — gallery colors auto-adapt for readability in light and dark mode
- **Random session accent** — a fresh neon accent color on every app launch
- **Batch delete** — delete all dismissed photos from your library in one shot
- **Gallery management** — create, reorder, rename, recolor, import from existing albums
- **Move or copy** — when sorting from an album, choose whether photos stay or get moved
- **Swipe up** — favorite/unfavorite a photo
- **Swipe down** — share a photo
- **Pinch to zoom** — magnify the current photo
- **Long-press** — preview gallery panels at full opacity

## Requirements

- iOS 17.0+
- Xcode 15+
- Photo Library access (read/write)

## Project Structure

```
culla/
├── CullaApp.swift                      # App entry point, splash screen, random accent
│
├── Models/
│   ├── Gallery.swift                   # User-created gallery (SwiftData @Model)
│   ├── SortedPhoto.swift               # Links a photo to a gallery
│   ├── DismissedPhoto.swift            # Tracks photos marked for deletion
│   └── PhoneAlbum.swift                # Wrapper for PHAssetCollection + virtual albums
│
├── Services/
│   ├── PhotoLibraryService.swift       # PhotoKit wrapper — auth, fetch, cache, sync
│   └── DuplicateScannerService.swift   # Vision framework fingerprint-based duplicate finder
│
├── ViewModels/
│   ├── SwipeViewModel.swift            # Swipe queue, actions, full undo history, batch delete
│   ├── GalleryViewModel.swift          # Gallery CRUD and reordering
│   └── DismissedPhotosViewModel.swift  # Load, select, recover, delete dismissed photos
│
├── Views/
│   ├── ContentView.swift               # Root navigation (date picker → swipe / duplicate sweep)
│   ├── DatePickerView.swift            # Starting date + album filter + feature buttons
│   ├── SwipeView.swift                 # Core swipe screen with gesture handling
│   ├── PhotoCardView.swift             # Single photo card (drag offset, opacity)
│   ├── GallerySidebarView.swift        # Neon gallery panels + adaptive color palette
│   ├── GallerySelectionSheet.swift     # Pick which galleries appear in sidebar
│   ├── AlbumPickerView.swift           # Browse phone albums + unsorted + favorites
│   ├── AlbumImportSheet.swift          # Import phone albums as app galleries
│   ├── GalleriesView.swift             # Gallery list with reorder/delete
│   ├── GalleryDetailView.swift         # Photo grid for a single gallery
│   ├── DuplicateSweepView.swift        # Side-by-side duplicate comparison
│   ├── DismissedPhotosView.swift       # Grid of dismissed photos with batch actions
│   ├── DeleteFeedbackOverlay.swift     # Shared delete confirmation with running total
│   ├── PhotoPreviewOverlay.swift       # Shared full-screen photo preview (long-press)
│   └── CalendarView.swift              # Pure SwiftUI calendar grid
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
- **Vision framework** powers duplicate detection via `VNGenerateImageFeaturePrintRequest`.

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
- **Progressive transparency** on right drag reveals gallery names
- **Scale-based highlight** (1.08x) on the active gallery — no jarring font changes
- **Spring animation** for snap-back, **easeIn** for fly-off
- **Haptic feedback** — light on dismiss, medium on gallery sort
- **Confirmation toasts** — "Dismissed" or "→ Gallery Name" after each action
- **Auto-hiding undo** — appears for 2 seconds after each action, shows stack depth
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
2. Open `culla.xcodeproj` in Xcode
3. Select your team under Signing & Capabilities
4. Build and run on a device or simulator

## License

Open source. Free forever.
