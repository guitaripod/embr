# Embr

A premium native **UIKit** iOS Twitch client — browse, watch, and chat — built on the modern (2026) Twitch API surface: **EventSub** for chat, **Helix** for browsing, native **AVPlayer** for video, with a **Cloudflare Worker** holding all secrets.

Inspired by [chatsen](https://github.com/chatsen/chatsen) and [frosty](https://github.com/tommyxchow/frosty), but neither is copied: the transport (EventSub, not IRC), the player (native AVPlayer, not a WebView), and the auth (Worker-backed Authorization Code, not embedded implicit) are all deliberate departures.

## What's here

| Component | Language | Verified? |
|---|---|---|
| `EmbrCore` | Swift 6 (SwiftPM) | ✅ `swift build` + `swift test` on Linux/macOS |
| `Embr` (app) | Swift 6 / UIKit | ⚠️ Darwin-only — needs Xcode on a Mac to compile |
| `workers/` | TypeScript (Hono) | ✅ `tsc` + `vitest` |

This repo was built on Linux, so **the UIKit app layer is written but unverified** — it has not been compiled. `EmbrCore` (the parsing/merge/HLS logic) and the Worker are verified.

### Status (at initial build)

- `EmbrCore` — ~3.8k LOC, **95 tests / 14 suites green** (`swift test`, Linux).
- `Embr` app — ~8.5k LOC across 56 files, **syntax-clean** (`swiftc -parse`), house-style clean (0 `@Published`, 0 storyboards, programmatic UIKit). **Not yet type-checked** — open in Xcode 26 on a Mac (`scripts/ios-build.sh`) and expect to resolve a first round of cross-module/concurrency errors. Known item to watch: `@MainActor` players conforming to the non-isolated `VideoPlaying` protocol (relies on Swift 6.2 isolated conformances).
- `workers/` — Hono Worker, **tsc clean + 22 vitest tests green**.

## Architecture

- **Chat receive:** EventSub WebSocket, `channel.chat.message` (+ notification/clear/delete). Structured JSON → `ChatMessage`. No IRC tag parsing.
- **Chat send:** Helix `POST /helix/chat/messages` — surfaces `is_sent` / `drop_reason` (AutoMod feedback).
- **Auth:** `ASWebAuthenticationSession` → Worker `/auth/exchange` (Authorization Code; the Worker holds the client secret because Twitch does not support PKCE). Tokens in Keychain. Anonymous browsing via a Worker-minted app token.
- **Video:** Worker resolves the HLS playlist (GQL `PlaybackAccessToken` → usher) and strips stitched ad segments; the app plays it with `AVPlayer` + `AVPictureInPictureController`. Behind a `VideoPlaying` protocol with a `WebViewPlayer` fallback.
- **Emotes:** Twitch + 7TV (with `events.7tv.io` live updates) + BetterTTV + FrankerFaceZ, merged into a layered `EmoteCatalog`. Animated WebP via SDWebImage.
- **Rendering:** off-main tokenization (`MessageTokenizer`), precomputed layout, a flipped `UICollectionView` with diffable batches, a shared `CADisplayLink` emote animator.

See `CONTRACTS.md` for the full type map and `CLAUDE.md` for build instructions.

## Setup (Mac)

```bash
brew install xcodegen
scripts/setup.sh            # writes .env.local + Secrets.swift, runs xcodegen
# edit Embr/Secrets.swift (twitchClientID, workerBaseURL) and .env.local (team id, device udid)
scripts/ios-deploy.sh       # build + install on your iPhone
```

Worker:

```bash
cd workers && npm install && npm test
npx wrangler deploy
```

## Verify the core (any platform)

```bash
scripts/core-test.sh
```

## Legal

The native video path uses Twitch's **undocumented** GraphQL playback endpoint and strips ads, which violates the Twitch Developer Services Agreement and can break without notice. This is a **personal, sideloaded** project. Do not distribute it. The compliant alternative is the `WebViewPlayer` (official embed), already stubbed behind the same protocol.
