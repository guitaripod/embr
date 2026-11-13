# Embr

A native UIKit Twitch client for iPhone and iPad: browse, watch and chat. It uses the modern Twitch API surface (EventSub for chat, Helix for everything else), plays video with AVPlayer, and keeps every secret in a Cloudflare Worker.

**[Download on the App Store](https://apps.apple.com/us/app/embr-live-streams/id6784940198)**: free, iPhone and iPad, iOS 18 or later. Founding Member is an optional one-time purchase that unlocks only looks. More at [midgarcorp.cc/embr](https://midgarcorp.cc/embr/).

Inspired by [chatsen](https://github.com/chatsen/chatsen) and [frosty](https://github.com/tommyxchow/frosty), with deliberate departures: EventSub instead of IRC, native AVPlayer instead of a WebView, and a Worker-backed Authorization Code flow instead of the embedded implicit one.

## Features

- **Watch:** AVPlayer with Picture in Picture, audio-only mode and a native screen over ad breaks. On iPad, video and chat sit side by side in wide windows and stack in narrow ones.
- **Chat:** Twitch, 7TV, BetterTTV and FrankerFaceZ emotes, mentions and highlights, swipe to reply, user cards, and VOD chat replay.
- **Chats tab:** several chats open without their video, with unread and mention counts; up to three side by side on iPad. Mentions gathers what mentions you from every open chat.
- **Moderator Tools** (opt-in): AutoMod's held messages, unban requests, the moderation log, and delete, time out or ban from a user card.
- **Safety:** a content filter, report and block on every message.
- **Following and favorites**, with favorites synced between iPhone and iPad through iCloud; search; browse by category.
- **Settings** laid out like the Settings app, with search.
- **Founding Member:** themes, accent colors, chat fonts, app icons, and a flame badge with a founding number that other Embr viewers see. Every look can be tried on first.

## What's here

| Component | Language | Tested |
|---|---|---|
| `EmbrCore` | Swift 6 (SwiftPM) | ✅ `swift build` + `swift test` on Linux/macOS |
| `Embr` (iPhone and iPad) | Swift 6 / UIKit | ✅ Swift Testing on macOS (`scripts/ios-build.sh`) |
| `EmbrTV` (Apple TV, TestFlight only) | Swift 6 / UIKit | ✅ `scripts/tv-build.sh` |
| `services/embr` (Midgar monorepo) | TypeScript (Hono) | ✅ `tsc` + `vitest` |

`EmbrCore` holds the platform-agnostic logic (parsing, emote merge, HLS handling, Helix request specs) and compiles and tests on Linux and macOS. The app layers are Darwin-only. The Worker handles OAuth and stream resolution.

## Architecture

- **Chat receive:** EventSub WebSocket, `channel.chat.message` (+ notification/clear/delete, and the moderator events when Moderator Tools is on). Structured JSON → `ChatMessage`. IRC (`justinfan`) only for the logged-out preview.
- **Chat send:** Helix `POST /helix/chat/messages`, which surfaces `is_sent` / `drop_reason` (AutoMod feedback).
- **Auth:** `ASWebAuthenticationSession` → Worker `/auth/exchange` (Authorization Code; the Worker holds the client secret because Twitch does not support PKCE). Tokens in Keychain. Anonymous browsing via a Worker-minted app token. The Apple TV signs in with Twitch's device code flow.
- **Worker access:** every app call goes through the Midgar gateway (`api.midgarcorp.cc/v1/embr`); the HLS proxy, the embed and the OAuth callback are public routes.
- **Video:** the Worker resolves the stream's HLS playlist; the app plays it with `AVPlayer` + `AVPictureInPictureController`, behind a `VideoPlaying` protocol with a `WebViewPlayer` fallback.
- **Emotes:** Twitch + 7TV (with `events.7tv.io` live updates) + BetterTTV + FrankerFaceZ, merged into a layered `EmoteCatalog`. Animated WebP via SDWebImage.
- **Rendering:** off-main tokenization (`MessageTokenizer`), precomputed layout, a flipped `UICollectionView` with diffable batches, a shared `CADisplayLink` emote animator.
- **Platform:** [MidgarKit](https://github.com/guitaripod/MidgarKit) for the file logger (`Library/Logs/embr.log`), the Founding Member and Studio Pro purchases, and the More Apps card.

See `CONTRACTS.md` for the full type map and `CLAUDE.md` for build instructions.

## Setup (Mac)

```bash
brew install xcodegen
scripts/setup.sh            # writes .env.local + Secrets.swift, runs xcodegen
# edit App/Secrets.swift (twitchClientID) and .env.local (team id, device udid)
scripts/ios-deploy.sh       # build + install on your iPhone
scripts/tv-build.sh         # Apple TV simulator build
```

The Worker is `services/embr` in the Midgar monorepo (`npm install && npm test`, deployed with `npx wrangler deploy`).

## Verify the core (any platform)

```bash
scripts/core-test.sh
```

## License

GPL-3.0. See [LICENSE](LICENSE).

## Independent, third-party app

Embr is an independent, third-party client and is not affiliated with, endorsed by, or connected to Twitch Interactive, Inc. "Twitch" and related marks are trademarks of their respective owners. You sign in with your own Twitch account through Twitch's official OAuth; Embr never sees your password.
