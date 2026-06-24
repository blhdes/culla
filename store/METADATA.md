# App Store Connect — Culla metadata

Copy-paste sources for the App Store listing. Character limits noted in `[brackets]`.
Fill the `<<…>>` placeholders before submitting.

> **This is an update** (version 3.0.0, build 4) to an app that already exists on the
> Store — bundle `agu.culla`. You're editing the existing record, not creating a new one.
> The paywall is dormant this release, so the listing is written as a **free, fully
> unlocked app** — there is no mention of "Pro", unlocks, or subscriptions on purpose.

---

## App information

- **Name** `[30]`: `Culla`
  - *Alt (if you want a keyword in the name):* `Culla: Photo Organizer`
- **Subtitle** `[30]`: `Swipe to sort your photos`
  - *Alt:* `Tidy your camera roll, fast`
- **Bundle ID**: `agu.culla`
- **SKU** (internal, unchanged from the existing record): `<<your existing SKU>>`
- **Primary language**: English (U.S.)
- **Primary category**: **Photo & Video**
- **Secondary category**: **Productivity** (optional)
- **Copyright**: `© 2026 <<your name or company>>`
- **Age rating**: **4+** (no objectionable content — all "None" in the questionnaire)

## URLs

Live at the `culla-web` project (custom domain `culla.app`). The privacy policy is an
in-page section, not a separate file.

- **Marketing URL** (optional): `https://culla.app`
- **Support URL** (required): `https://culla.app`  *(footer has the contact email; a `mailto:` alone isn't accepted, an https page is)*
- **Privacy Policy URL** (required): `https://culla.app/#privacy`

---

## Promotional text `[170]`
*(Editable any time without a new review — use it for timely notes.)*

```
Swipe right to file a photo into a gallery; left to let it go. Culla makes tidying your camera roll fast and tactile — and every gallery becomes a real Photos album.
```

## Keywords `[100]`
*(Comma-separated, no spaces. Don't repeat words already in the name/subtitle — Apple indexes those too, so "photo", "swipe", "sort" are intentionally left out.)*

```
gallery,album,organizer,declutter,duplicate,cleanup,camera roll,tidy,storage,organize,delete,clean
```

## Description `[4000]`

```
Culla is the fastest way to tidy your camera roll — one photo at a time, by feel.

Swipe right to file a photo into one of your galleries. Swipe left to let it go. That's the whole idea: instead of scrolling an endless grid, you make one clean decision per photo and move on. It's quick, tactile, and oddly satisfying — and because your galleries are real iPhone Photos albums, everything you sort stays organized across your device.

SORTING BY FEEL
• Swipe right toward any gallery to file the photo there; swipe left to dismiss it.
• Swipe up to favorite, swipe down to share, pinch to zoom, double-tap to skip.
• A full undo history — step back through every action in a session, not just the last one. Tap the date pill to bring undo back anytime.
• Gentle haptics and confirmation toasts, so every decision feels registered.
• Photos and videos both flow through the stack; videos auto-play muted.

GALLERIES THAT ARE REAL ALBUMS
• Create, rename, recolor, and reorder galleries — each one syncs to a real Photos album.
• Rename a gallery in Culla and the iPhone album updates too.
• Import albums you already have, and choose whether sorting moves a photo or copies it.
• Order your galleries by name, photo count, date, or recently updated — or arrange them by hand.

FIND, REVISIT, AND CLEAN UP
• Duplicate Sweep uses on-device Vision to find near-identical shots and shows them side by side, so you can clear them with confidence.
• On This Day resurfaces photos from today's date in past years.
• A photo-mosaic calendar and a full grid picker let you jump to any moment in your library.
• Dismissed photos wait in a review tray — recover them or batch-delete to reclaim storage.

SEE YOUR PROGRESS
• Insights tracks everything you've sorted: totals, streaks, favorites, your top gallery, a 7-day activity chart, and how much storage you've reclaimed.

MAKE IT YOURS
• A new Living-Glass design built on iOS 26's Liquid Glass, with a clean fallback on iOS 18.
• A dynamic mosaic background that breathes with your galleries, with adjustable blur — or turn it off entirely.
• An 18-color accent palette, light / dark / system themes, and a fresh accent on every launch if you like a little surprise.
• Available in 8 languages: English, Spanish, German, French, Italian, Japanese, Brazilian Portuguese, and Simplified Chinese.

PRIVATE BY DESIGN
Your photos never leave your device. Culla only stores lightweight references to them — never copies of the images — with no ads and no tracking.

Works on iPhone and iPad.
```

## Description — short alternative `[4000]`
*(Same pitch, trimmed for skimming — the first two lines carry it.)*

```
Culla is the fastest way to tidy your camera roll — one photo at a time, by feel.

Swipe right to file a photo into a gallery, left to let it go. Your galleries are real iPhone Photos albums, so everything you sort stays organized.

• Swipe up to favorite, down to share, pinch to zoom
• Full undo history — step back through the whole session
• Duplicate Sweep finds near-identical shots, side by side
• On This Day, a photo-mosaic calendar, and Insights with reclaimed-storage stats
• New Living-Glass look · dynamic backgrounds · 8 languages

Your photos never leave your device. No ads, no tracking. Works on iPhone and iPad.
```

## What's New (version 3.0) `[4000]`
*(⚠️ Trim this to what's genuinely new since your **last public build**. It's written for the full 3.0 jump — if some of these already shipped, drop those lines.)*

```
Culla 3.0 is a big one.

• A whole new Living-Glass look, rebuilt on iOS 26's Liquid Glass.
• Videos now flow through the swipe stack alongside photos, auto-playing muted.
• A dynamic mosaic background that adapts to your galleries, with adjustable blur.
• Sort your galleries by name, count, date, or recently updated — on both gallery screens.
• Insights now shows how much storage you've reclaimed, full-screen.
• The whole app is now localized into 8 languages.
• Plus a redesigned Settings, smoother swiping, and dozens of fixes.

Thanks for using Culla. Questions or ideas? Email agomezurrea@gmail.com.
```

---

## Privacy (App Store Connect → App Privacy)

RevenueCat's `configure()` is **disabled** in this build (`CullaApp.swift`), so the app makes
no network calls and creates no anonymous ID. Nothing leaves the device — which matches the
published privacy policy at `culla.app/#privacy` ("no third-party SDKs, nothing leaves your
device").

- **"Do you collect data?"** → **No**
- Resulting privacy label: **Data Not Collected**
- **Photos**: accessed read/write, but images never leave the device → not "collected."
- **Tracking** → **No** (matches the in-app `PrivacyInfo.xcprivacy`: `NSPrivacyTracking = false`).

> When freemium returns (a later version re-enables `configure()`), revisit this: that build
> *will* run RevenueCat, so it would need a "Data Not Linked to You" label (*Identifiers*,
> *Purchases*) and a privacy-policy update disclosing the SDK.

## Build / version

- **Marketing version**: `3.0.0`  •  **Build**: `4`  (Xcode → target → General)
- **Min iOS**: `18.0`  •  **Devices**: Universal (iPhone + iPad)  •  **Orientation**: Portrait
- **Encryption**: `ITSAppUsesNonExemptEncryption = false` is in the build, so the export-compliance question is auto-answered as exempt.
- **Team**: `56BK7T2JG7` (automatic signing).
- ⚠️ **Do not attach the subscription / in-app-purchase products to this version's review** — the paywall is unreachable in this build, so a reviewer can't trigger a purchase and would reject the IAP. Ship the binary as free; leave the IAPs un-submitted until the release that turns freemium back on.
