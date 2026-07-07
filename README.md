# Embr

A premium native **UIKit** iOS Twitch client — browse, watch, and chat — built on the modern Twitch API surface: **EventSub** for chat, **Helix** for browsing, native **AVPlayer** for video, with a **Cloudflare Worker** holding all secrets.

**[Download on the App Store](https://apps.apple.com/us/app/embr-live-streams/id6784940198)** — free. iPhone, iOS 18+.

Inspired by [chatsen](https://github.com/chatsen/chatsen) and [frosty](https://github.com/tommyxchow/frosty), but neither is copied: the transport (EventSub, not IRC), the player (native AVPlayer, not a WebView), and the auth (Worker-backed Authorization Code, not embedded implicit) are all deliberate departures.

## What's here

| Component | Language | Tested |
|---|---|---|
| `EmbrCore` | Swift 6 (SwiftPM) | ✅ `swift build` + `swift test` on Linux/macOS |
| `Embr` (app) | Swift 6 / UIKit | ✅ Xcode on macOS (`scripts/ios-build.sh`) |
| `workers/` | TypeScript (Hono) | ✅ `tsc` + `vitest` |

`EmbrCore` holds the platform-agnostic logic (parsing, emote merge, HLS handling, Helix request specs) and compiles/tests on Linux and macOS. The `Embr` app layer is Darwin-only. The Worker handles OAuth and stream resolution.

## Architecture

- **Chat receive:** EventSub WebSocket, `channel.chat.message` (+ notification/clear/delete). Structured JSON → `ChatMessage`. No IRC tag parsing.
- **Chat send:** Helix `POST /helix/chat/messages` — surfaces `is_sent` / `drop_reason` (AutoMod feedback).
- **Auth:** `ASWebAuthenticationSession` → Worker `/auth/exchange` (Authorization Code; the Worker holds the client secret because Twitch does not support PKCE). Tokens in Keychain. Anonymous browsing via a Worker-minted app token.
- **Video:** the Worker resolves the stream's HLS playlist; the app plays it with `AVPlayer` + `AVPictureInPictureController`, behind a `VideoPlaying` protocol with a `WebViewPlayer` fallback.
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

## Independent, third-party app

Embr is an independent, third-party client and is not affiliated with, endorsed by, or connected to Twitch Interactive, Inc. "Twitch" and related marks are trademarks of their respective owners. You sign in with your own Twitch account through Twitch's official OAuth; Embr never sees your password.
