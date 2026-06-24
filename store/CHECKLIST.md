# Culla — submission runbook (version 3.0.0, build 4)

This is an **update** to an app that's already on the Store (builds 1–2 shipped as a paid
app). You're uploading a new build and refreshing the existing listing — not creating a new
app record. ✅ = already done in the repo. 👉 = you do it.

## 0. Status

- ✅ App builds green in Release and passes Xcode's store validation.
- ✅ Privacy manifest (`culla/PrivacyInfo.xcprivacy`) — UserDefaults required-reason (`CA92.1`), tracking off.
- ✅ `ITSAppUsesNonExemptEncryption = false` (in `Info.plist`) — export-compliance auto-exempt.
- ✅ Version `3.0.0`, build `4`; portrait-locked; **universal (iPhone + iPad)**.
- ✅ App icon present (1024).
- ✅ App localized into 8 languages in-app.
- ✅ Listing text ready in `store/METADATA.md` (English) and `store/METADATA-es.md` (Spanish).
- ✅ Website live at `culla.app` (the `culla-web` project) — privacy policy at `culla.app/#privacy`.
- ✅ RevenueCat `configure()` disabled this build → no network calls → **Data Not Collected** (matches the policy).
- ⚠️ Paywall is **dormant** this release — everyone is unlocked. The listing is written as a free app.

## 1. Confirm the website is live 👉

URLs already wired into both `METADATA.md` files:

- **Privacy Policy**: `https://culla.app/#privacy`
- **Support**: `https://culla.app`  •  **Marketing**: `https://culla.app`

Just confirm those load. The published policy ("no third-party SDKs, nothing leaves your
device") is now accurate because RevenueCat is disabled — keep it that way.

## 2. Screenshots 👉

Follow `store/SCREENSHOTS.md`. Because Culla is **universal**, App Store Connect needs **two**
sets: **iPhone 6.9"** and **iPad 13"**. Capture on your devices. (Offer: I can resize them to
the exact pixels.)

## 3. Build & upload 👉 (on your Mac)

1. Open `culla.xcodeproj`. Confirm version `3.0.0`, build `4` (bump the build number if `4`
   was already uploaded once — every upload needs a higher build number).
2. Signing team is `56BK7T2JG7`, automatic signing.
3. Destination: **Any iOS Device (arm64)**.
4. **Product → Archive**.
5. **Organizer** → select the archive → **Distribute App → App Store Connect → Upload**.
   - The export-compliance question won't appear (handled by the encryption flag).

## 4. Update the listing 👉 (appstoreconnect.apple.com)

1. Open the existing **Culla** app → **(+) Version or Platform** → new iOS version **3.0.0**.
2. Paste from `store/METADATA.md` (English, U.S.): subtitle, promotional text, description,
   keywords, **What's New** (trim it to what's genuinely new since your last public build).
3. **Add Spanish:** in the version's localization dropdown, add **Spanish** (and/or Spanish
   (Spain)), then paste everything from `store/METADATA-es.md`.
4. Set/confirm **Support URL** and **Privacy Policy URL** (from step 1).
5. Category: **Photo & Video**. Re-confirm the age rating questionnaire → **4+**.
6. **App Privacy**: answer **No** to data collection → label becomes **Data Not Collected**,
   **tracking = No** (RevenueCat is disabled this build — see the Privacy section in `METADATA.md`).
   Set the Privacy Policy URL (`https://culla.app/#privacy`) here too.
7. Upload the **iPhone 6.9"** and **iPad 13"** screenshots.
8. **Build**: select build `4` once it finishes processing (~15 min after upload).
9. Pricing: **Free**.

## 5. Submit 👉

- ⚠️ **Do NOT add the subscription / in-app-purchase products to this version.** The paywall is
  unreachable in this build, so a reviewer can't trigger a purchase — attaching the IAPs would
  get them rejected ("unable to locate the in-app purchase"). Submit the binary only.
- **Add for Review → Submit**.

## 6. After approval 👉

- If you built the `docs/` site, confirm the App Store badge/link points to Culla.
- When you're ready to monetize again (a later version): restore the real `isPro` /
  `hasReachedDailyLimit` / `subscriptionExpired` logic in `SubscriptionManager.swift` (the
  original bodies are preserved in comments), un-hide the Settings subscription card, point the
  paywall's "Privacy" link at *your own* policy, and only then submit the IAPs for review.

---

### Quick reference
- Bundle ID: `agu.culla` • Team: `56BK7T2JG7` • Version/build: `3.0.0 (4)`
- Devices: iPhone + iPad • Orientation: Portrait • Min iOS: 18.0
- Category: Photo & Video • Age: 4+ • Price: Free (paywall dormant)
- Privacy: **Data Not Collected** • Tracking: No • RevenueCat disabled this build
- Languages in listing: English (U.S.) + Spanish
- App Store ID: `6761316914` (existing record — this is an update)
