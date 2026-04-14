# Calendar View Performance Audit

> **Status:** Pending Implementation  
> **Audited:** 2026-04-13  
> **Revised:** 2026-04-14  
> **Files analysed:** `culla/Views/CalendarView.swift`, `culla/Services/PhotoLibraryService.swift`

---

## Summary

9 issues found across rendering, data loading, and thread safety. The scroll lag is caused primarily by unstable view identity and a GeometryReader inside each mosaic cell, compounded by several medium-severity threading and re-render issues.

---

## HIGH — Fix First

### 1. Unstable ForEach IDs on Week Rows and Day Cells
**File:** `CalendarView.swift` lines 70–72  
**Problem:** The outer `ForEach(viewData.months)` correctly uses stable `CalendarMonth.id`, but the **week rows** (line 70) and **day cells** (line 72) still use `id: \.offset`. SwiftUI can't tell which cell is which across scroll frames — it recreates views instead of reusing them.  
**Fix:** For day cells, use `day?.id ?? UUID()` or a positional stable key. For week rows, derive a stable ID from the first non-nil day in the week (e.g. `week.compactMap(\.self).first?.id`). Each `DayInfo` already has a stable `id` property (the `Date`), so this is straightforward.

---

### 2. `GeometryReader` Inside Each Mosaic Cell
**File:** `CalendarView.swift` lines 243, 261  
**Problem:** The mosaic thumbnail layout calls `mosaic(width: geo.size.width)` inside a `GeometryReader`. The scroll view constantly remeasures geometry, so the entire mosaic tree rebuilds on every scroll frame even when the width hasn't changed.  
**Fix:** Replace the GeometryReader with a fixed calculated width. Since all cells share the same column layout, the width can be computed once and passed down, or derived from a fixed grid constant.

---

### 3. Views Lack `Equatable` Conformance
**File:** `CalendarView.swift` — `CalendarMosaicView` (line 237), `dayCell` (line 120)  
**Problem:** `CalendarMosaicView` and the day cell are redrawn on every scroll frame because SwiftUI can't cheaply diff them. All their inputs (`assetIdentifiers`, `totalCount`, `isSelected`, `dayNumber`, etc.) are value types, so equality checks would be trivial.  
**Fix:** Extract `dayCell` into its own `struct DayCellView: View, Equatable` and add `Equatable` conformance to `CalendarMosaicView`. This lets SwiftUI skip re-rendering cells whose inputs haven't changed. This also addresses the issue described in #7 — once each cell is `Equatable`, changing `selectedDate` only redraws the two cells whose `isSelected` actually flipped, not the entire grid.

---

## MEDIUM — Fix Next

### 4. `buildMonths()` Runs on the Main Thread
**File:** `CalendarView.swift` line 105  
**Problem:** The background `Task.detached` fetches photo data correctly, but `buildMonths()` — which iterates over every day in the full date range — runs back on the main thread (after `await` returns to `@MainActor`) before assigning state. On large libraries this stalls the UI during load and album changes.  
**Fix:** Capture `let cal = calendar` before the detached task, then call a static or free-function version of `buildMonths(calendar:earliest:latest:)` inside the `Task.detached` block alongside `calendarData()`. The current implementation references `self.calendar`, which prevents calling it directly inside the detached task.

---

### 5. Synchronous `PHAsset` Fetch on the Main Thread
**File:** `PhotoLibraryService.swift` lines 652–666, called from `CalendarView.swift` line 102  
**Problem:** `startCachingCalendarThumbnails()` calls `fetchAssets()` synchronously. This call happens on the main thread (line 102 in CalendarView runs after `await`, back on `@MainActor`). `fetchAssets()` enumerates all matching PHAssets. On large libraries (10k+ photos) this stalls the UI during calendar init.  
**Fix:** Either move the `startCachingCalendarThumbnails()` call inside the `Task.detached` block (alongside the fix for #4), or dispatch `fetchAssets()` + `startCachingImages()` to a background queue inside `startCachingCalendarThumbnails()` itself. The first option is simpler since you're already moving work into the detached task.

---

### 6. `weeks` Is a Computed Property, Re-sliced Every Render
**File:** `CalendarView.swift` lines 21–25  
**Problem:** `CalendarMonth.weeks` runs `stride + map + Array()` on every access. During scrolling, SwiftUI may access it multiple times per render frame.  
**Fix:** Change `weeks` from a `var` computed property to a `let` stored property, computed once in the `CalendarMonth` initializer.

---

### 7. Per-Thumbnail `.task` Spawning + `withAnimation` Per Image
**File:** `CalendarView.swift` lines 315–339  
**Problem:** Every visible thumbnail spawns its own task and fires a separate `withAnimation` callback when it loads. With 120+ cells visible, this creates a storm of concurrent tasks and animation callbacks on the main thread simultaneously.  
**Fix:** Stagger thumbnail animation or remove `withAnimation` from thumbnail load entirely (the cache pre-warming makes loads near-instant anyway, so the animation adds noise more than delight).

---

## LOW — Polish Pass

### 8. `selectedDay` Re-render Scope
**File:** `CalendarView.swift` lines 51, 73, 122  
**Problem:** `selectedDay` is computed in `body` and passed to every `dayCell()`. Changing `selectedDate` triggers a re-render of every cell — not just the two whose selection state changed.  
**Fix:** This is largely addressed by fix #3. Once each day cell is an `Equatable` struct, SwiftUI will skip cells where `isSelected` didn't change. No separate `@State` / `.onChange` workaround needed.

---

### 9. `scrollTo` Only Fires on `.onAppear`
**File:** `CalendarView.swift` lines 53, 82–84  
**Decision:** Not implemented. Adding `.onChange(of:)` to scroll on every date selection caused jarring jumps — if the user taps a cell that's already visible, the view scrolls to put the month title at the top unnecessarily. The `.onAppear` scroll (initial position on load) is sufficient.

---

## Prioritised Fix Order

| Phase | Fix | Expected Impact |
|---|---|---|
| 1 | #1 — Stable ForEach IDs for week rows + day cells | ~30% scroll improvement |
| 1 | #2 — Remove GeometryReader from mosaic cells | ~25% scroll improvement |
| 1 | #3 — `Equatable` on day cell + mosaic views | ~15% scroll improvement |
| 1 | #6 — Pre-store `weeks` as `let` in initializer | ~10% scroll improvement |
| 2 | #4 — Move `buildMonths()` to background thread | Eliminates initial load stall |
| 2 | #5 — Move `fetchAssets()` off main thread | Eliminates cache-warming stall |
| 3 | #7 — Stagger/remove per-thumbnail `withAnimation` | Reduces animation jank |
| 3 | #8 — `selectedDay` re-render scope (covered by #3) | Eliminates full re-render on tap |
| 3 | #9 — Drive `scrollTo` from `.onChange(of: selectedDate)` | UX fix |
