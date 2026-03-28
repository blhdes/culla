# Ship Culla to the App Store

## Pre-submission tasks (before you start)

### 1. Privacy Policy (hosted URL)

Apple requires a privacy policy URL. Since Culla works entirely on-device, it's simple. Host it anywhere (GitHub Pages, Notion, a simple HTML page). It should state:

- Photos are accessed and organized locally on the device
- No data leaves the device — no cloud, no analytics, no tracking
- SwiftData stores sorting metadata only (asset identifiers, gallery names)

### 2. App Store screenshots

- Minimum 3 screenshots per device size
- Required sizes: 6.9" iPhone (1290 × 2796) and 13" iPad (2064 × 2752)
- Apple auto-scales these to all older device sizes — no need to upload 5.5" or other legacy sizes separately
- Take them in both light and dark mode for best impression
- Tip: use the Simulator (Device > Screenshot) for pixel-perfect captures

### 3. App Store listing copy

Prepare these before you start the submission flow:
- **App name**: Culla
- **Subtitle** (30 chars max): e.g. "Swipe to sort your photos"
- **Description**: what the app does, key features
- **Keywords** (100 chars max): e.g. "photo,organizer,sort,swipe,gallery,cull,cleanup,duplicate"
- **Category**: Photo & Video
- **Support URL**: your website, GitHub repo, or email link

---

## Step-by-step submission guide

Once you have the Apple Developer license ($99/year), follow these steps in order:

### Step 1 — Set up your Developer account in Xcode

1. Open Xcode > Settings > Accounts
2. Tap **+** and sign in with your Apple Developer account
3. Xcode will download your certificates and provisioning profiles automatically

### Step 2 — Update the signing configuration

1. Open `culla.xcodeproj` in Xcode
2. Select the **culla** target > **Signing & Capabilities** tab
3. Check **"Automatically manage signing"**
4. Select your **Team** (your developer account name)
5. The bundle identifier `agu.culla` will be registered automatically
6. Make sure there are no signing errors (red warnings)

### Step 3 — Set the version number

1. In the target's **General** tab, confirm:
   - **Version**: `1.0.0`
   - **Build**: `1`
2. For future updates, bump version (1.1.0, 1.2.0) and always increment the build number

### Step 4 — Create an Archive

1. In Xcode, select your physical device (or "Any iOS Device") as the build target — **not** a simulator
2. Menu: **Product > Archive**
3. Wait for the build to complete — the Organizer window will open
4. If the archive fails, check for code signing or build errors first

### Step 5 — Create the app in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps > +** > **New App**
3. Fill in:
   - **Platform**: iOS
   - **Name**: Culla
   - **Primary language**: English
   - **Bundle ID**: select `agu.culla` from the dropdown
   - **SKU**: `culla-ios` (internal reference, users never see this)
4. Click **Create**

### Step 6 — Fill in App Store listing

In App Store Connect, under your app's page:

1. **App Information** tab:
   - Category: Photo & Video
   - Privacy Policy URL: paste your hosted URL
   - Age Rating: fill out the questionnaire (all "No" for Culla)

2. **Pricing and Availability** tab:
   - Price: Free (or set a price)
   - Availability: select countries

3. **App Store** tab (under the version):
   - Upload screenshots for each required device size
   - Write the description, keywords, subtitle
   - Add the support URL
   - Set "What's New" text (for v1.0: leave blank or "Initial release")

### Step 7 — Upload the build

1. Back in Xcode's **Organizer** (Window > Organizer)
2. Select your archive and click **"Distribute App"**
3. Choose **"App Store Connect"** > **Upload**
4. Follow the prompts (accept defaults for bitcode, symbols, etc.)
5. Wait for upload to complete (can take a few minutes)

### Step 8 — Select the build in App Store Connect

1. In App Store Connect, go to your app's version page
2. Under **Build**, click **+** and select the build you just uploaded
   - Note: builds take 5-30 minutes to process after upload before they appear
3. If it doesn't appear yet, wait and refresh

### Step 9 — Submit for Review

1. Make sure all required fields are filled (App Store Connect will show warnings if anything is missing)
2. Answer the **Export Compliance** question: select "No" (Culla doesn't use custom encryption)
3. Answer the **Content Rights** question: select "No" (you own all content)
4. Click **"Submit for Review"**

### Step 10 — Wait for review

- First submissions typically take 24-48 hours
- You'll get an email when it's approved (or if they request changes)
- Common rejection reasons:
  - Missing privacy policy URL
  - Screenshots don't match actual app
  - Permission descriptions too vague
  - App crashes during review (test on a clean install first!)

---

## Pre-submission checklist

- [ ] Apple Developer account active ($99/year)
- [ ] Privacy policy hosted and accessible via URL
- [ ] Screenshots captured for required device sizes
- [ ] App Store description, subtitle, and keywords written
- [ ] Support URL ready
- [ ] Tested on a real device with a clean install (delete app, reinstall)
- [ ] Archive builds successfully
- [ ] No crash on first launch (permission prompt works)
- [ ] No crash when permission is denied

## Verification

1. Build with no warnings
2. Archive succeeds
3. App icon visible on home screen and in Settings
4. Photo library permission prompt shows both read and write descriptions
5. Denying permission shows helpful message instead of blank screen
