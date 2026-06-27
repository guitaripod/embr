# Embr — App Store Submission

This branch is the **full native Embr** (native `AVPlayer`, Worker-resolved ad-stripped
HLS — exactly as `master`) **plus** the App Store additions below. The decision (eyes
open) is to submit the real app and see how review responds, betting on the precedent of
other third-party Twitch clients already on the store.

## ⚠️ Honest risk

The native playback path (unofficial Twitch GQL `PlaybackAccessToken` + usher + ad
segment stripping) **violates the Twitch Developer Services Agreement** and is the most
likely trigger for an App Store rejection (Guideline 5.2.5 / 5.0) **and** for a Twitch
ban on the client-id `YOUR_TWITCH_CLIENT_ID` — which would break this app *and*
the sideload. The additions below make the app pass the *other* guidelines (1.2 UGC,
5.1.1 privacy), but they do not address the ad-stripping itself. Submitting anyway is a
deliberate experiment.

## What was added on top of master (done & verified)

- **UGC moderation (1.2):** every non-own chat message has a **Report** action (reason
  picker → submits to Worker `/report`, stores in KV for review, hides the author
  locally), plus the existing Block.
- **Legal / agreement:** first-launch onboarding shows a Terms/Privacy acceptance notice
  with tappable in-app docs; Settings → About has **Terms of Use**, **Privacy Policy**,
  **Contact Support**. Same docs served at `embr.guitaripod.workers.dev/legal/{terms,privacy}`
  (the Privacy Policy URL for App Store Connect).
- **Privacy:** `Embr/PrivacyInfo.xcprivacy` (no tracking; `UserDefaults` CA92.1,
  `FileTimestamp` C617.1) and `ITSAppUsesNonExemptEncryption=false`.
- **Cleanup / fixes:** removed dead Settings toggles; fixed the chat-composer keyboard
  inset ballooning on foreground; EventSub now backs off on Twitch 429s instead of
  hammering and giving up.

**Backend:** single Worker `embr` (`embr.guitaripod.workers.dev`) — master's routes
(`/auth/*`, `/playback`, `/hls`, `/events`, `/embed`) **plus** `/report` and
`/legal/*`. Verified live. The separate `embr-appstore` worker was deleted.

### Verified
- EmbrCore `swift test` — **100 tests pass**.
- Worker `tsc` clean + **38 vitest tests pass**.
- iOS app compiles clean (Swift 6 strict concurrency, 0 warnings in changed files);
  deployed + running on the iPhone Air.

## What you must do (account-gated)

1. **App Store Connect record** for `com.guitaripod.embr` (none exists yet): name,
   category Entertainment, age rating **17+**. Privacy Policy URL →
   `https://embr.guitaripod.workers.dev/legal/privacy`; Support → `guitaripod@gmail.com`.
   App Privacy labels: no tracking; "User Content (Other)" → App Functionality, not
   linked, not for tracking (covers reports).
2. **Register the App ID + mint an App Store distribution profile** for the bundle id
   (Midgar team `P4DQK6SRKR`; distribution cert is in the keychain / `~/.config/midgar`).
3. **Build the upload on stable macOS.** This Mac is on macOS 27.0 **beta** (`26A5368g`)
   → Apple rejects beta-built binaries (ITMS-90111). Build on a stable-macOS GitHub
   Actions runner with manual signing (p12 + profile + ASC API key secrets),
   `altool --upload-app`. Reference: `guitaripod/master-of-flags` `testflight.yml`.
4. **Screenshots, demo Twitch account (2FA off), and Submit for Review.**
