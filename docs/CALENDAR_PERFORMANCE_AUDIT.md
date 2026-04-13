# Calendar View Performance Audit

> **Status:** Pending Implementation  
> **Audited:** 2026-04-13  
> **Files analysed:** `culla/Views/CalendarView.swift`, `culla/Services/PhotoLibraryService.swift`

---

## Summary

8 issues found across rendering, data loading, and thread safety. The scroll lag is caused primarily by unstable view identity and a GeometryReader inside each mosaic cell, compounded by several medium-severity threading and re-render issues.

---

## HIGH — Fix First

### 1. Unstable ForEach IDs (`id: \.offset`)
**File:** `CalendarView.swift` lines 70–73  
**Problem:** Weeks and days both use their array position as identity. SwiftUI can't tell which cell is which across scroll frames — it recreates views instead of reusing them. Every scroll causes unnecessary cell teardown and rebuild.  
**Fix:** Replace `id: \.offset` with stable identifiers — use `day?.id` for day cells and a unique computed week ID (e.g. first day of week) for week rows.

---

### 2. `GeometryReader` Inside Each Mosaic Cell
**File:** `CalendarView.swift` lines 243, 261  
**Problem:** The mosaic thumbnail layout calls `mosaic(width: geo.size.width)` inside a `GeometryReader`. The scroll view constantly remeasures geometry, so the entire mosaic tree rebuilds on every scroll frame even when the width hasn't changed.  
**Fix:** Replace the GeometryReader with a fixed calculated width. Since all cells share the same column layout, the width can be computed once and passed down, or derived from a fixed grid constant.

---

## MEDIUM — Fix Next

### 3. `buildMonths()` Runs on the Main Thread
**File:** `CalendarView.swift` line 105  
**Problem:** The background `Task.detached` fetches photo data correctly, but `buildMonths()` — which iterates over every day in the full date range — runs back on the main thread before assigning state. On large libraries this stalls the UI during load and album changes.  
**Fix:** Move `buildMonths()` inside the `Task.detached` block alongside `calendarData()`.

---

### 4. Synchronous `PHAsset` Fetch on the Main Thread
**File:** `PhotoLibraryService.swift` lines 678–687  
**Problem:** `startCachingCalendarThumbnails()` calls `fetchAssets()` synchronously from the main thread. `fetchAssets()` enumerates all matching PHAssets. On large libraries (10k+ photos) this stalls the UI during calendar init.  
**Fix:** Dispatch `fetchAssets()` + `startCachingImages()` to a background queue inside `startCachingCalendarThumbnails()`.

---

### 5. `weeks` Is a Computed Property, Re-sliced Every Render
**File:** `CalendarView.swift` lines 21–25  
**Problem:** `CalendarMonth.weeks` runs `stride + map + Array()` on every access. During scrolling, SwiftUI may access it multiple times per render frame.  
**Fix:** Change `weeks` from a `var` computed property to a `let` stored property, computed once in the `CalendarMonth` initializer.

---

### 6. Per-Thumbnail `.task` Spawning + `withAnimation` Per Image
**File:** `CalendarView.swift` lines 315–339  
**Problem:** Every visible thumbnail spawns its own task and fires a separate `withAnimation` callback when it loads. With 120+ cells visible, this creates a storm of concurrent tasks and animation callbacks on the main thread simultaneously.  
**Fix:** Stagger thumbnail animation or remove `withAnimation` from thumbnail load entirely (the cache pre-warming makes loads near-instant anyway, so the animation adds noise more than delight).

---

### 7. `selectedDay` Causes Full Re-render on Tap
**File:** `CalendarView.swift` lines 51, 73, 122  
**Problem:** `selectedDay` is recomputed in `body` on every render and passed down to every `dayCell()`. Changing `selectedDate` triggers a re-render of every cell in every visible month — not just the two cells whose selection state changed.  
**Fix:** Memoize `selectedDay` as a `@State` property updated via `.onChange(of: selectedDate)`, so only the affected cells redraw.

---

## LOW — Polish Pass

### 8. `scrollTo` Only Fires on `.onAppear`
**File:** `CalendarView.swift` lines 53, 82–84  
**Problem:** `ScrollViewReader` scrolls to the selected month only once, on first appearance. Tapping a day in a different month doesn't scroll to it.  
**Fix:** Add `.onChange(of: selectedDate)` to drive `proxy.scrollTo(...)` whenever the selected date changes to a new month.

---

## Prioritised Fix Order

| Phase | Fix | Expected scroll improvement |
|---|---|---|
| 1 | Stable ForEach IDs | ~30% |
| 1 | Remove GeometryReader from mosaic cells | ~25% |
| 1 | Pre-store `weeks` as `let` in initializer | ~10% |
| 2 | Move `buildMonths()` to background thread | Eliminates initial stall |
| 2 | Move `fetchAssets()` off main thread | Eliminates load stall |
| 2 | Memoize `selectedDay` via `@State` | Eliminates full re-render on tap |
| 3 | Stagger/remove per-thumbnail `withAnimation` | Reduces animation jank |
| 3 | Drive `scrollTo` from `.onChange(of: selectedDate)` | UX fix |
