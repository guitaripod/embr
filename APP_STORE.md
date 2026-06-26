# Embr — App Store Submission (branch `app-store-ready`)

This branch is the App Store–compliant build. The non-compliant core of `master`
(undocumented-GQL playback, usher resolution, ad-stripping, spoofed web client-id,
GQL polls/predictions) is **deleted**, not disabled. Streams play through Twitch's
official embedded player. `master` is untouched and remains the personal sideload build.

## What changed in code (done & verified)

- **Playback** — sole player is Twitch's official embed (`embed.twitch.tv` for live/VOD,
  `clips.twitch.tv` for clips) via the Worker `/embed` route in a `WKWebView`. No native
  HLS, no GQL, no usher, no ad-stripping anywhere in the app, EmbrCore, or the Worker.
- **UGC moderation (Guideline 1.2)** — every non-own chat message has **Report** (reason
  picker → submits to the Worker `/report` sink and hides the author locally) plus the
  existing **Block**. Report works for guests too.
- **Agreement / legal** — first-launch onboarding shows a "By continuing, you agree to our
  Terms of Use and Privacy Policy" notice with tappable in-app docs; Settings → About has
  **Terms of Use**, **Privacy Policy**, and **Contact Support** (mailto). Same docs are
  served at `/legal/terms` and `/legal/privacy` for the public Privacy Policy URL.
- **Privacy** — `Embr/PrivacyInfo.xcprivacy`: `NSPrivacyTracking=false`, no tracking
  domains, required-reason APIs declared (`UserDefaults` CA92.1, `FileTimestamp` C617.1).
  No analytics/tracking/IDFA SDKs. Tokens stay in the Keychain; app data stays on device.
- **Least privilege** — dropped the unused `user:read:blocked_users` /
  `user:manage:blocked_users` OAuth scopes (block is local). Sign in with Twitch is the
  only login (4.8 carve-out — no Sign in with Apple required).
- **Cleanup** — removed dead Settings toggles (Show Deleted Messages, Share Crash Logs,
  Default Quality, Default To Highest) that did nothing / no longer apply.

### Verified
- `scripts/core-test.sh` — EmbrCore builds, **82 tests pass**.
- `workers/`: `npm run typecheck` clean, **20 vitest tests pass**.
- App compiles clean for iOS (Swift 6 strict concurrency, 0 warnings in changed files);
  privacy manifest is bundled at the app root.

## What you must do (account-gated — not done autonomously)

1. **Deploy the Worker to a *separate* environment.** Do **not** `wrangler deploy` over the
   prod Worker your sideload (`master`) build uses — that prod Worker still serves
   `/playback`,`/hls`,`/events`, and this branch removes them, which would break the
   installed sideload app. Deploy this branch's Worker to a new name/route, then set
   `Embr/Secrets.swift` `workerBaseURL` on this branch to that URL. Register the new
   `/auth/callback` redirect on the Twitch app if the host changes.
2. **App Store Connect record:** bundle id `com.guitaripod.embr`, category Entertainment,
   age rating **17+** (unrestricted web/UGC).
   - **Privacy Policy URL** → `https://<worker>/legal/privacy`. **Support URL / email** →
     `guitaripod@gmail.com` (or a support page).
   - **App Privacy "nutrition" labels:** no tracking, no third-party analytics. Declare
     "User Content (Other)" → *App Functionality*, *not linked to identity*, *not used for
     tracking* (covers reports). Twitch auth token is not collected by you (Keychain only).
   - **App Review notes / demo:** guest mode covers browse + watch + read chat; for
     send-chat, supply a throwaway Twitch account (2FA off) in App Review Information.
3. **Build & upload on stable macOS.** Per the ITMS-90111 rule, build the distribution
   binary on a non-beta macOS (GitHub Actions `macos-*` runner) with manual signing
   (dist p12 + provisioning profile + ASC API key), `altool --upload-app`.
4. **Screenshots & description** — required iPhone sizes; describe it as an independent,
   unofficial Twitch viewer ("not affiliated with Twitch").

## Residual review risk (can't be fixed in code)

- **Guideline 4.2 (minimum functionality):** what remains is a native browse + chat shell
  around Twitch's official web embed. Lean on the substantive native chat (emotes from
  4 providers, moderation, search, EventSub) and browse/following experience in the
  description to clear the "is it more than a web wrapper?" bar.
- **4.1 / 5.2.1 (unofficial client of a major platform):** third-party clients of large
  platforms are sometimes rejected absent the platform's written blessing. Lowest risk
  with the official embed + clear "not affiliated" framing; full clearance needs Twitch's
  authorization.
