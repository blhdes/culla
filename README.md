# Culla

A native iOS app for organizing your photo library. Swipe through your photos and videos one by one — left to dismiss, right to sort into galleries. Think Tinder, but for your camera roll.

## Why Culla?

Most photo organizer apps let you keep or delete. Culla's core experience is **multi-gallery sorting** — drag a photo toward any of your galleries and it's instantly saved there. Your galleries sync with real iPhone Photos albums, so everything stays organized across your device.

- 100% native Swift/SwiftUI — RevenueCat is the only third-party dependency, and it's left dormant (never configured) in the current build
- Privacy-first — no analytics and zero network calls at launch; App Privacy is *Data Not Collected*, declared via a bundled privacy manifest
- Freemium model on the App Store — free tier with limits, one-time unlock for everything (**temporarily disabled in the current build — ships fully unlocked**)
- Syncs with your iPhone Photos library
- Minimalist, HIG-compliant design with a personal accent palette and a reusable Living-Glass surface system
- Localized into 8 languages — English, Spanish, German, French, Italian, Japanese, Brazilian Portuguese, and Simplified Chinese

## Features

### Sorting & swipe
- **Swipe sorting** — left to dismiss, right toward a gallery to sort, double-tap to skip
- **Swipe up** — favorite/unfavorite a photo
- **Swipe down** — share a photo
- **Video sorting** — videos ride the same swipe stack as photos, auto-playing muted and looping on the top card with a duration badge; turn them off with "Include videos" in Settings
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
- **Animated CullaEyes mascot** on the date picker (toggleable) — *temporarily hidden in the current build*
- **Focus Timer** — 2, 5, or 10 minute sessions with a summary and circular progress arc
- **On This Day** — revisit photos from today's date in past years

### Galleries
- **Gallery management** — create, reorder, rename, recolor, import from existing albums
- **Sort galleries** — a glass sort pill on both gallery sheets orders by Custom (manual), Name, Photo Count, Date Created, or Recently Updated; re-tap the active field to flip direction. The choice is shared across both sheets and remembered between launches
- **Custom 18-swatch palette** — fully editable accent colors with adaptive light/dark output
- **Live rename sync** — rename a gallery in-app and the iPhone album updates too
- **Move or copy** — when sorting from an album, choose whether photos stay or get moved
- **Custom delete confirmation** — Messages-style menu with spring animation and three deletion modes (delete + photos, delete keep photos, remove from Culla); shared between the gallery list and gallery detail screen

### Design & theming
- **Living-Glass design system** — a reusable set of glass surfaces (iOS 26 Liquid Glass, with an iOS 18 `.thinMaterial` fallback) shared across destination sheets and Settings; per-gallery color carries the "selected" state
- **Dynamic background, two styles** — a **Stream** wall (rows of photos drifting upward while each row scrolls sideways) or a **Mosaic** wall (Album Artwork–style grid where one tile at a time 3D-flips to a new photo); both adapt to the selected gallery or favourites, with off / monochrome options
- **Adjustable background blur** — tune how soft the carousel backdrop is in Settings; duplicate-pair comparisons sharpen relative to it
- **Sidebar colour modes** — per-gallery neon colours, or a single accent hue walked light→dark across the swipe panels
- **Adaptive scrim** — text stays readable over any photo backdrop
- **Random session accent** — a fresh neon accent on every launch, or pin one in Settings
- **Liquid Glass action buttons** — iOS 26 styling on the toolbar
- **Light/Dark/System** theming with status-bar overrides

### Insights & utilities
- **Sorting Insights** — total sorted, streaks, skipped, favourites, top gallery; opens full-screen
- **Storage reclaimed** — running total of space freed by deleting photos through Culla (e.g. "2.3 GB reclaimed")
- **7-day activity line chart** — track your sorting cadence
- **Duplicate Sweep** — Vision-framework fingerprinting with side-by-side comparison and long-press zoom
- **Dismissed Photos** — review, recover, or batch-delete; trash-icon badge persists across sessions
- **Native zoom transition** for full-resolution photo preview

### Onboarding & monetization

> **Note:** Freemium gating and the paywall are **temporarily disabled** in the current build — every user is treated as Pro (fully unlocked). The code is retained, and the items below describe the intended model.

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
├── Localizable.xcstrings               # String Catalog — all UI strings in 8 languages
├── InfoPlist.xcstrings                 # Localized photo-permission prompts
├── PrivacyInfo.xcprivacy               # Privacy manifest — declares the UserDefaults API reason; no tracking
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
│   ├── PhotoCarouselBackground.swift   # Dynamic background — streaming photo wall (Stream style)
│   ├── MosaicBackground.swift          # Dynamic background — Album Artwork-style flip-tile wall (Mosaic style)
│   ├── GallerySidebarView.swift        # Neon gallery panels + adaptive color palette
│   ├── GallerySelectionSheet.swift     # Pick which galleries appear in sidebar (search + sort)
│   ├── AlbumPickerView.swift           # Browse phone albums + unsorted + favourites
│   ├── AlbumImportSheet.swift          # Import phone albums as app galleries
│   ├── GalleriesView.swift             # Gallery list with sort, reorder + custom delete menu
│   ├── GalleryDetailView.swift         # Photo grid for a single gallery
│   ├── DuplicateSweepView.swift        # Side-by-side duplicate comparison + zoom preview
│   ├── DismissedPhotosView.swift       # Grid of dismissed photos with batch actions
│   ├── DeleteFeedbackOverlay.swift     # Shared delete confirmation with running total
│   ├── PhotoPreviewOverlay.swift       # Full-screen photo preview (long-press / zoom)
│   ├── FocusTimerArcView.swift         # Circular progress timer for focus sessions
│   ├── InsightsView.swift              # Stats dashboard + 7-day activity chart
│   ├── SettingsView.swift              # Theme, accent, haptics, status bar, videos, sidebar colour, dynamic background, language
│   ├── SettingsAppFooter.swift         # App icon + version/copyright signature line at the foot of Settings
│   ├── AccentPalettePicker.swift       # Custom-accent swatch grid + colour editor (extracted from Settings)
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
    ├── VideoCardPlayer.swift           # Looping AVQueuePlayer for the top swipe card / preview
    ├── VideoDurationBadge.swift        # "0:42"-style duration label for video thumbnails
    ├── AccentEnvironment.swift         # @Environment accent + on-tinted-glass text contrast
    ├── Haptics.swift                   # Centralized haptic generator + settings toggle
    ├── GlassSurface.swift              # .glassSurface() modifier + GlassStack (iOS 26 glass, iOS 18 fallback)
    ├── GlassPanel.swift                # "Loud" destination panel + SettingsToggleRow + GlassChipPicker
    ├── SettingsCard.swift              # "Calm" card surface for Settings/utility screens
    ├── GradientCapsuleButton.swift     # Gradient capsule CTA (tint/role for destructive actions)
    ├── HeroIconTile.swift              # Glass hero icon tile
    ├── SortChip.swift                  # Reusable glass sort-menu pill + SortFieldProtocol
    ├── GallerySorting.swift            # GallerySortField + shared Array<Gallery>.sortedBy
    ├── OnboardingManager.swift         # Tracks onboarding/tour completion
    ├── TourEnvironment.swift           # Active tour step + advance closure plumbing
    └── TourTarget.swift                # SwiftUI preferences for spotlight anchoring
```

## Architecture

**MVVM + SwiftData + PhotoKit + AVFoundation**

- **SwiftData** persists galleries, sorted photos, dismissed photos, and daily stats. We never copy photo bytes — only store `PHAsset.localIdentifier` strings.
- **PhotoKit** handles all interaction with the iPhone photo library: fetching, caching, album sync, and deletion.
- **PHCachingImageManager** preloads the next 3 photos so transitions feel instant.
- **@Observable** (iOS 17 Observation framework) drives reactive UI updates.
- **Vision framework** powers duplicate detection via `VNGenerateImageFeaturePrintRequest`.
- **AVFoundation** plays videos in the swipe stack — a single looping `AVQueuePlayer` owned by `VideoCardPlayer`, so at most one video ever plays at a time.
- **RevenueCat** handles entitlements and the paywall UI is fully custom — but in the current build it's **never configured** (gating is disabled, `SubscriptionManager.isPro` returns `true` for everyone), so the app makes no network calls and App Privacy is *Data Not Collected*.
- **Living-Glass design system** — shared glass surfaces in `Helpers/` (Liquid Glass on iOS 26, `.thinMaterial` fallback on iOS 18). Two tiers: *calm* (`SettingsCard`) for utility screens, *loud* (`GlassPanel`) for destination sheets; per-gallery color carries the selected state instead of a generic accent.
- **Tour anchoring** uses SwiftUI `PreferenceKey` so spotlights track real on-screen elements through layout changes.
- **Localization** via String Catalogs (`Localizable.xcstrings` + `InfoPlist.xcstrings`). Display text flows through `LocalizedStringKey` / `String(localized:)`; persisted identifiers (enum raw values, storage keys) stay English so translations never affect logic.

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

Open source. Freemium on the App Store — free tier with limits, one-time unlock for everything else, no subscriptions. *(Freemium gating is temporarily disabled in the current build.)*
