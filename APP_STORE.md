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

## Done autonomously

- **App ID** `com.guitaripod.embr` (ASC id `XQ5LJ7TX5Y`) + **App Store distribution
  profile** "Embr App Store" — minted via the ASC API.
- **TestFlight CI** (`.github/workflows/testflight.yml`): stable-macOS runner, beta-host
  guard, xcodegen, manual signing, archive → export → altool. Repo secrets set.
- **Build 1 uploaded and `VALID` in App Store Connect, attached to the 1.0 version.**
- **Listing metadata pushed via API** to the en-US localizations: name
  `Embr — Live Streams`, subtitle, description (2085 chars), keywords, promotional text,
  support URL. (`whatsNew` is left blank — Apple disallows it on a first version.)
- **Listing copy** (`docs/store-listing.md`) + two 6.9" screenshots (`docs/screenshots/`).

## What you must do (account-gated, all guided UI)

1. **Screenshots** — at least one per size is required; only 2 of 6 are captured (the
   rest — player/chat/search/settings — need in-app taps). Either capture on-device, or
   I can stand up an **XCUITest snapshot harness** for clean reproducible captures.
2. **Age rating** questionnaire → **17+** (answers in `docs/store-listing.md`).
3. **App Privacy** questionnaire (no tracking; "User Content" for reports) + **Privacy
   Policy URL** `https://embr.guitaripod.workers.dev/legal/privacy`. Both guided in ASC;
   answers documented.
4. **Submit for Review** (provide a demo Twitch account, 2FA off, in App Review notes if
   asked). Export compliance is already declared (`ITSAppUsesNonExemptEncryption=false`).
