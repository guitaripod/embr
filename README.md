# Embr

A native UIKit Twitch client for iPhone: browse, watch and chat. It uses the modern Twitch API surface (EventSub for chat, Helix for browsing), plays video with AVPlayer, and keeps every secret in a Cloudflare Worker.

**[Download on the App Store](https://apps.apple.com/us/app/embr-live-streams/id6784940198)**: free, with an optional tip jar. iPhone, iOS 18 or later.

Inspired by [chatsen](https://github.com/chatsen/chatsen) and [frosty](https://github.com/tommyxchow/frosty), with deliberate departures: EventSub instead of IRC, native AVPlayer instead of a WebView, and a Worker-backed Authorization Code flow instead of the embedded implicit one.

## What's here

| Component | Language | Tested |
|---|---|---|
| `EmbrCore` | Swift 6 (SwiftPM) | ✅ `swift build` + `swift test` on Linux/macOS |
| `Embr` (app) | Swift 6 / UIKit | ✅ Xcode on macOS (`scripts/ios-build.sh`) |
| `services/embr` (Midgar monorepo) | TypeScript (Hono) | ✅ `tsc` + `vitest` |

`EmbrCore` holds the platform-agnostic logic (parsing, emote merge, HLS handling, Helix request specs) and compiles/tests on Linux and macOS. The `Embr` app layer is Darwin-only. The Worker handles OAuth and stream resolution.

## Architecture

- **Chat receive:** EventSub WebSocket, `channel.chat.message` (+ notification/clear/delete). Structured JSON → `ChatMessage`. No IRC tag parsing.
- **Chat send:** Helix `POST /helix/chat/messages`, which surfaces `is_sent` / `drop_reason` (AutoMod feedback).
- **Auth:** `ASWebAuthenticationSession` → Worker `/auth/exchange` (Authorization Code; the Worker holds the client secret because Twitch does not support PKCE). Tokens in Keychain. Anonymous browsing via a Worker-minted app token.
- **Video:** the Worker resolves the stream's HLS playlist; the app plays it with `AVPlayer` + `AVPictureInPictureController`, behind a `VideoPlaying` protocol with a `WebViewPlayer` fallback.
- **Emotes:** Twitch + 7TV (with `events.7tv.io` live updates) + BetterTTV + FrankerFaceZ, merged into a layered `EmoteCatalog`. Animated WebP via SDWebImage.
- **Rendering:** off-main tokenization (`MessageTokenizer`), precomputed layout, a flipped `UICollectionView` with diffable batches, a shared `CADisplayLink` emote animator.

See `CONTRACTS.md` for the full type map and `CLAUDE.md` for build instructions.

## Setup (Mac)

```bash
brew install xcodegen
scripts/setup.sh            # writes .env.local + Secrets.swift, runs xcodegen
# edit App/Secrets.swift (twitchClientID) and .env.local (team id, device udid)
scripts/ios-deploy.sh       # build + install on your iPhone
```

The Worker is `services/embr` in the Midgar monorepo (`npm install && npm test`, deployed with `npx wrangler deploy`).

## Verify the core (any platform)

```bash
scripts/core-test.sh
```

## Independent, third-party app

Embr is an independent, third-party client and is not affiliated with, endorsed by, or connected to Twitch Interactive, Inc. "Twitch" and related marks are trademarks of their respective owners. You sign in with your own Twitch account through Twitch's official OAuth; Embr never sees your password.
