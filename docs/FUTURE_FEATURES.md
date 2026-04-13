# Future Implementation Features

## Feature #1: Cullaaaaaaaaaa! Sound Effect on Enter Culling Mode

### Overview
Add a cute, animated voice sound effect that plays whenever the user enters culling/photo selection mode. The mascot (CullaEyes) should announce its name with a playful, energetic "Cullaaaaaaaaaa!" sound.

### Implementation Details

#### Audio File Requirements
- **Format:** `.mp3` or `.wav`
- **Duration:** 1-2 seconds
- **Style:** Cute, high-pitched, animated voice
- **Content:** "Cullaaaaaaaaaa!" with emphasis on the long "A" sound
- **Tone:** Playful, energetic, mascot-like

#### Generation Options
1. **Text-to-Speech Services:**
   - Google Translate (free, multiple voice options)
   - Apple Voice Memos app with system voice
   - Online TTS tools (e.g., Natural Reader, Uberduck)
   - AI voice generators (ElevenLabs, Murf)

2. **Recording:**
   - Record yourself with a cute/funny voice
   - Use voice modulation or pitch shifting to create mascot effect

#### Integration Steps

1. **Prepare the audio file:**
   - Save as `cullaa.mp3` or `cullaa.wav`
   - Trim to 1-2 seconds
   - Normalize audio levels for consistent volume

2. **Add to Xcode project:**
   - Option A: Drag file into `Assets.xcassets` as a new dataset
   - Option B: Create a `Sounds/` folder in project root and add file there

3. **Update DatePickerView:**
   - Import `AVFoundation`
   - Add `@State private var audioPlayer: AVAudioPlayer?`
   - Call `playSound()` in `.onAppear` modifier

4. **Code Implementation:**
   ```swift
   import AVFoundation

   // In DatePickerView or appropriate view
   @State private var audioPlayer: AVAudioPlayer?

   var body: some View {
       VStack(spacing: 28) {
           CullaEyes()
               .padding(.top, 8)
           // ... rest of content
       }
       .onAppear {
           playSound()
       }
   }

   private func playSound() {
       if let url = Bundle.main.url(forResource: "cullaa", withExtension: "mp3") {
           do {
               audioPlayer = try AVAudioPlayer(contentsOf: url)
               audioPlayer?.play()
           } catch {
               print("Error playing sound: \(error)")
           }
       }
   }
   ```

#### Important Notes
- **Keep audioPlayer in state:** The `@State` property keeps the AVAudioPlayer alive for the duration of playback. Without it, the player deallocates immediately and no sound plays.
- **Audio permissions:** iOS 14+ requires no special permissions for playing local audio files.
- **Volume control:** Users' device volume/mute switch will affect playback (standard iOS behavior).
- **Accessibility:** Consider adding `.accessibilityHint()` or `.accessibilityLabel()` if needed.

#### Testing Checklist
- [ ] Audio file plays on app launch/entry to culling mode
- [ ] Sound plays at appropriate volume level
- [ ] No crashes or errors in console
- [ ] Works on both simulator and real device
- [ ] Device mute switch respects sound playback
- [ ] Animation/UI remains smooth during playback

#### Future Enhancements
- Add sound toggle/settings to disable audio
- Additional mascot sound effects (error, success, etc.)
- Loop sound on longer operations
- Haptic feedback paired with sound effect

---

**Status:** Pending Implementation  
**Priority:** Nice-to-have (Feature Polish)  
**Complexity:** Low  
**Est. Time:** 15-30 minutes
