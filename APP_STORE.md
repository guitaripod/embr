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

## Done autonomously

- **App ID** `com.guitaripod.embr` registered (ASC id `XQ5LJ7TX5Y`, team `P4DQK6SRKR`).
- **App Store distribution profile** "Embr App Store" minted (signed by the Midgar
  distribution cert).
- **TestFlight CI** (`.github/workflows/testflight.yml`) — stable-macOS runner with a
  beta-host guard, xcodegen, manual signing, archive → export → altool. Repo secrets set.
  A run **built, signed (Midgar dist cert), and exported a valid `Embr.ipa`**; the only
  failure was the upload — altool: "Cannot determine the Apple ID from Bundle ID" — i.e.
  it just needs the app record below.
- **Listing copy** (`docs/store-listing.md`) + two 6.9" screenshots (`docs/screenshots/`).

## What you must do (account-gated)

1. **Create the App Store Connect app record** (the one step the ASC API forbids — it
   returns 403 on `apps` CREATE). In ASC → My Apps → **+** → New App → iOS → select
   bundle id **`com.guitaripod.embr`** → name + primary language + SKU. (≈1 min.)
2. **Re-run the CI** (`gh workflow run testflight.yml --ref app-store-ready`) — the
   altool upload now succeeds and the build lands in TestFlight.
3. **Fill metadata** from `docs/store-listing.md` (I can push most of it via the ASC API
   once the record exists), finish **screenshots** (player/chat/search/settings need
   on-device capture or an XCUITest harness — offer stands), set age rating **17+**,
   Privacy Policy URL `…/legal/privacy`, support email, and **Submit for Review**.
   Provide a demo Twitch account (2FA off) in App Review notes if asked.
