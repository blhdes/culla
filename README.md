# Culla

A native iOS app for organizing your photo library. Swipe through photos one by one — left to dismiss, right to sort into galleries. Think Tinder, but for your camera roll.

## Why Culla?

Most photo organizer apps let you keep or delete. Culla's core experience is **multi-gallery sorting** — drag a photo toward any of your galleries and it's instantly saved there. Your galleries sync with real iPhone Photos albums, so everything stays organized across your device.

- 100% native Swift/SwiftUI — RevenueCat is the only third-party dependency
- Freemium on the App Store — free tier with limits, one-time unlock for everything
- Syncs with your iPhone Photos library
- Minimalist, HIG-compliant design with a personal accent palette

## Features

### Sorting & swipe
- **Swipe sorting** — left to dismiss, right toward a gallery to sort, double-tap to skip
- **Swipe up** — favorite/unfavorite a photo
- **Swipe down** — share a photo
- **Pinch to zoom** — magnify the current photo
- **Long-press** — preview gallery panels at full opacity
- **Full undo history** — undo every action in a session, not just the last one
- **Tap-to-restore undo** — tap the date pill to bring the undo button back at any time
- **Confirmation toasts** — "Dismissed" or "→ Gallery Name" after each action
- **Haptic feedback** — toggleable in Settings; light on dismiss, medium on gallery sort

### Modes & navigation
- **Segmented mode picker** — switch between Cullaing, This Day, and Duplicates from a native bottom toolbar
- **Custom calendar** — scrollable photo-mosaic calendar that reflects the selected album
- **Photo grid picker** — tap the photo icon in the calendar sheet to browse all photos as a scrollable grid; tapping a photo jumps the date wheel to that photo's date
- **Smart date defaults** — jumps to the earliest available photo when you change albums
- **Animated CullaEyes mascot** on the date picker (toggleable)
- **Focus Timer** — 2, 5, or 10 minute sessions with a summary and circular progress arc
- **On This Day** — revisit photos from today's date in past years

### Galleries
- **Gallery management** — create, reorder, rename, recolor, import from existing albums
- **Custom 18-swatch palette** — fully editable accent colors with adaptive light/dark output
- **Live rename sync** — rename a gallery in-app and the iPhone album updates too
- **Move or copy** — when sorting from an album, choose whether photos stay or get moved
- **Custom delete confirmation** — Messages-style menu with spring animation and three deletion modes (delete + photos, delete keep photos, remove from Culla); shared between the gallery list and gallery detail screen

### Background & theming
- **Dynamic photo carousel background** — animated mosaic adapts to the selected gallery or favourites, with off / monochrome options
- **Adaptive scrim** — text stays readable over any photo backdrop
- **Random session accent** — a fresh neon accent on every launch, or pin one in Settings
- **Liquid Glass action buttons** — iOS 26 styling on the toolbar
- **Light/Dark/System** theming with status-bar overrides

### Insights & utilities
- **Sorting Insights** — total sorted, streaks, skipped, favourites, top gallery
- **7-day activity line chart** — track your sorting cadence
- **Duplicate Sweep** — Vision-framework fingerprinting with side-by-side comparison and long-press zoom
- **Dismissed Photos** — review, recover, or batch-delete; trash-icon badge persists across sessions
- **Native zoom transition** for full-resolution photo preview

### Onboarding & monetization
- **In-app spotlight tour** — anchored, auto-advancing walkthrough that introduces sorting, galleries, color picking, and swipe directions
- **Two-phase review prompt** — `AppStore.requestReview(in:)` on iOS 18+, falls back to `SKStoreReviewController`
- **Custom paywall** — staggered animations, soft + hard gating via RevenueCat
- **Freemium gates** — free tier limits enforced for unauthenticated users; trial reminders for lapsing trials

## Requirements

- iOS 18.0+
- Xcode 16+
- Photo Library access (read/write)

## Project Structure

```
culla/
├── CullaApp.swift                      # Entry point, splash gate, random accent, model container
│
├── Models/
│   ├── Gallery.swift                   # User-created gallery (SwiftData @Model)
│   ├── SortedPhoto.swift               # Links a photo to a gallery
│   ├── DismissedPhoto.swift            # Tracks photos marked for deletion
│   ├── DailyStats.swift                # Per-day counters for the activity chart
│   └── PhoneAlbum.swift                # Wrapper for PHAssetCollection + virtual albums
│
├── Services/
│   ├── PhotoLibraryService.swift       # PhotoKit wrapper — auth, fetch, cache, sync
│   ├── DuplicateScannerService.swift   # Vision-based duplicate finder
│   ├── SubscriptionManager.swift       # RevenueCat entitlement state
│   ├── TrialReminderService.swift      # Local notifications for trial lifecycle
│   └── ReviewManager.swift             # Two-phase App Store review prompt
│
├── ViewModels/
│   ├── SwipeViewModel.swift            # Swipe queue, actions, full undo history, batch delete
│   ├── GalleryViewModel.swift          # Gallery CRUD and reordering
│   ├── DismissedPhotosViewModel.swift  # Load, select, recover, delete dismissed photos
│   ├── DuplicateSweepViewModel.swift   # Duplicate scanning state machine with undo
│   └── InsightsViewModel.swift         # Stats, streaks, daily-counter rollups
│
├── Views/
│   ├── ContentView.swift               # Root navigation (date picker → swipe / duplicate sweep)
│   ├── DatePickerView.swift            # Wheel + calendar + segmented mode picker
│   ├── CalendarView.swift              # Custom photo-mosaic calendar (UIKit-backed grid)
│   ├── PhotoGridPickerView.swift       # Scrollable photo grid for picking a start date
│   ├── SwipeView.swift                 # Core swipe screen with gesture handling
│   ├── PhotoCardView.swift             # Single photo card (drag offset, opacity)
│   ├── PhotoCarouselBackground.swift   # Dynamic mosaic background, adapts to mode
│   ├── GallerySidebarView.swift        # Neon gallery panels + adaptive color palette
│   ├── GallerySelectionSheet.swift     # Pick which galleries appear in sidebar
│   ├── AlbumPickerView.swift           # Browse phone albums + unsorted + favourites
│   ├── AlbumImportSheet.swift          # Import phone albums as app galleries
│   ├── GalleriesView.swift             # Gallery list with reorder + custom delete menu
│   ├── GalleryDetailView.swift         # Photo grid for a single gallery
│   ├── DuplicateSweepView.swift        # Side-by-side duplicate comparison + zoom preview
│   ├── DismissedPhotosView.swift       # Grid of dismissed photos with batch actions
│   ├── DeleteFeedbackOverlay.swift     # Shared delete confirmation with running total
│   ├── PhotoPreviewOverlay.swift       # Full-screen photo preview (long-press / zoom)
│   ├── FocusTimerArcView.swift         # Circular progress timer for focus sessions
│   ├── InsightsView.swift              # Stats dashboard + 7-day activity chart
│   ├── SettingsView.swift              # Theme, accent, haptics, status bar, monochrome
│   ├── PaywallSheet.swift              # Custom paywall with staggered animations
│   ├── CullaEyes.swift                 # Animated mascot on the date picker
│   ├── SwipeDirectionsHint.swift       # Tooltip explaining swipe gestures
│   ├── TooltipBubble.swift             # Shared rounded tooltip bubble
│   ├── TourContainer.swift             # Hosts the in-app spotlight tour
│   ├── TourBubble.swift                # Tour explanation bubble
│   ├── TourSheetBanner.swift           # Banner pinned to the galleries sheet during tour
│   └── TourStep.swift                  # Tour step enum + copy
│
└── Helpers/
    ├── PhotoImageLoader.swift          # Per-card async image loader
    ├── AccentEnvironment.swift         # @Environment-driven accent color
    ├── Haptics.swift                   # Centralized haptic generator + settings toggle
    ├── OnboardingManager.swift         # Tracks onboarding/tour completion
    ├── TourEnvironment.swift           # Active tour step + advance closure plumbing
    └── TourTarget.swift                # SwiftUI preferences for spotlight anchoring
```

## Architecture

**MVVM + SwiftData + PhotoKit + RevenueCat**

- **SwiftData** persists galleries, sorted photos, dismissed photos, and daily stats. We never copy photo bytes — only store `PHAsset.localIdentifier` strings.
- **PhotoKit** handles all interaction with the iPhone photo library: fetching, caching, album sync, and deletion.
- **PHCachingImageManager** preloads the next 3 photos so transitions feel instant.
- **@Observable** (iOS 17 Observation framework) drives reactive UI updates.
- **Vision framework** powers duplicate detection via `VNGenerateImageFeaturePrintRequest`.
- **RevenueCat** handles entitlements; the paywall UI is fully custom.
- **Tour anchoring** uses SwiftUI `PreferenceKey` so spotlights track real on-screen elements through layout changes.

### Data Flow

```
Photo Library (PhotoKit)
       │
       ▼
PhotoLibraryService ──→ SwipeViewModel ────────→ SwipeView
       │                      │                      │
       │                      ▼                      ▼
       │               SwiftData Models          PhotoCardView
       │               (Gallery,                 GallerySidebarView
       │                SortedPhoto,             FocusTimerArcView
       │                DismissedPhoto,          PhotoCarouselBackground
       │                DailyStats)
       │                      │
       │          ┌───────────┼───────────┐
       │          ▼           ▼           ▼
       │   GalleryViewModel  DismissedPhotosVM  InsightsViewModel
       │          │           │                    │
       │          ▼           ▼                    ▼
       │   GalleriesView  DismissedPhotosView  InsightsView
       │
       ▼
DuplicateScannerService ──→ DuplicateSweepVM ──→ DuplicateSweepView
       │
       ├──→ iPhone Albums (sync)
       │
SubscriptionManager (RevenueCat) ──→ PaywallSheet / freemium gates
```

### Swipe Gesture Design

- **100pt threshold** to trigger an action, with velocity-aware detection (`predictedEndTranslation`) so fast flicks work even with shorter drag distance
- **Progressive transparency** on right drag reveals gallery names
- **Scale-based highlight** (1.08x) on the active gallery — no jarring font changes
- **Spring animation** for snap-back, **easeIn** for fly-off
- **Auto-hiding undo** — appears for 2 seconds after each action; tap the date pill to restore it
- **Photo counter** — "3 / 47" progress indicator at top
- **Date label** — shows current photo's creation date for context

### Photo Preloading & Caching

```
Queue:  [A] [B] [C] [D] [E] ...
         ↑       ↑   ↑ ↑ ↑
      current   next  cache window (3 ahead)
```

Old images are evicted from the cache as the window slides forward. Calendar mosaic thumbnails use a separate **disk cache** (PNG, atomic writes) so the calendar warms instantly on relaunch.

## Building

1. Clone the repo
2. Open `culla.xcodeproj` in Xcode
3. Select your team under Signing & Capabilities
4. Build and run on a device or simulator

## License

Open source. Freemium on the App Store — free tier with limits, one-time unlock for everything else, no subscriptions.
