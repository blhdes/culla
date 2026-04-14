# Future Features

A running list of features intentionally deferred from the current build. Each entry explains what the feature is, why it was skipped for now, and the technical context needed to implement it later.

---

## Feature 2 — CullaEyes Enhancements

### What's deferred

- **Gesture-based eye tracking** — pupil follows the user's finger or device tilt
- **Randomised blink interval** — blinks occur at unpredictable intervals instead of a fixed rhythm
- **Gravity simulation** — pupil drifts or settles based on device orientation
- **Vertical pupil movement** — pupil currently only moves horizontally (X-axis)
- **Double-blink / wink** — expressive blink variations for personality

### Why it's deferred

These are personality/polish additions. They don't contribute to the core app workflow, so they're being saved for a future pass once the main feature set is stable.

### Current implementation (what we have now)

The pupil oscillation is driven by a single `CGFloat` property (`pupilX`) that animates from −4 to +4 and back using:

```swift
.withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true))
```

This hands off all rendering to **Core Animation** (GPU-level), meaning:

- SwiftUI declares the animation once and steps out of the way
- The GPU interpolates the value smoothly across frames
- Zero CPU cost between keyframes

### Why we don't use TimelineView

`TimelineView` is a SwiftUI container that re-renders the view on every frame — typically 60 times per second. It's the right tool when something needs to react to the current time constantly (e.g. a real-time clock, a live progress bar, a curve that changes every frame).

For the eyes, it would be the wrong choice:

| Approach | Cost | Who does the work |
|---|---|---|
| `withAnimation` + Core Animation | Near zero CPU | GPU interpolates automatically |
| `TimelineView` (per-frame redraws) | ~60 view rebuilds/sec | CPU recalculates every frame |

Using `TimelineView` here would mean:
1. Re-running the view code 60× per second
2. Manually calculating the pupil position at each frame
3. Burning CPU cycles on something Core Animation does for free

The eyes stay "light and fast" because we use **declarative animation** (tell the system what you want, let it figure out the frames) instead of an **imperative loop** (recalculate every frame yourself).

### Notes for future implementation

- Gesture tracking will require reading `DragGesture` or `CoreMotion` data and mapping it to the pupil offset — keep the animation layer separate from the input layer to avoid jank
- Randomised blink intervals can be done with a `Task` that sleeps for a random duration and then triggers a one-shot blink animation, no `TimelineView` needed
- Vertical movement is just adding a `pupilY: CGFloat` alongside `pupilX` — low effort

---
