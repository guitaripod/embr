# Embr — Agent Instructions

Native UIKit iOS Twitch client (browse + watch + chat), with a Cloudflare Worker backend for OAuth and HLS resolution. Personal / sideload target.

See `CONTRACTS.md` for the authoritative architecture, type names, and module map. This file is the working guide.

## Stack

- **EmbrCore** (`Sources/EmbrCore`): platform-agnostic Swift 6 logic — models, IRC/EventSub parsing, emote merge, HLS ad-stripping, Helix request specs, OAuth DTOs. **Compiles and tests on Linux and macOS.** No UIKit/AVFoundation/Combine/Security imports.
- **Embr** (`Embr/`, xcodegen): programmatic UIKit, MVVM with Combine `PassthroughSubject`, GRDB, Swift 6 strict concurrency, iOS 18+, iPhone-only. Darwin-only — build on a Mac.
- **workers/**: Cloudflare Workers (Hono, jose, KV). OAuth code exchange/refresh, app-token minting, HLS `PlaybackAccessToken` resolution + ad-stripping proxy. TypeScript, vitest.

## Code style (non-negotiable)

- `final class` for classes; `nonisolated struct: Sendable` for value types.
- `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic only — no storyboards/XIB. `UIStackView` first, then anchors. Chat cells use manual frame layout (perf).
- ViewModels expose `PassthroughSubject<T, Never>` (never `@Published`); chat hot path emits batches, not per-message. VCs are `@MainActor`, bind in `viewDidLoad`, hold `Set<AnyCancellable>`.
- Service protocols in EmbrCore where platform-agnostic; concrete singletons (`.shared`) injected through inits with defaults.
- GRDB: `nonisolated struct` records, `DatabaseMigrator.registerMigration("vN")`, never edited after release.
- `UIBackgroundConfiguration.listCell()` on list cells. Symbol effects on live/active states.
- No comments, no MARK, no file headers. `///` doc comments sparingly. SPM only.
- Swift Testing (`@Test`, `#expect`) — never XCTest.

## Build & test

### EmbrCore (works anywhere, including Linux CI)

```bash
scripts/core-test.sh          # swift build + swift test
swift test --filter IRCParser # one suite
```

### iOS app — MANDATORY: use the scripts (Mac only)

xcodegen regenerates `Embr.xcodeproj` from `project.yml` on every build, so:

```bash
scripts/setup.sh         # one-time: .env.local + Secrets.swift + xcodegen + spm
scripts/ios-build.sh     # device build, with staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on EMBR_DEVICE_UDID
```

`ios-build.sh` runs `xcodegen generate` first, captures the real xcodebuild exit code via `pipefail`, surfaces Swift 6 concurrency errors, and asserts no `.swift` is newer than the built binary (catches no-op rebuilds). Adding/removing any file → just run `ios-build.sh` (it regenerates the project). Never call `xcodebuild` raw.

### Worker

```bash
cd workers
npm install
npm run typecheck      # tsc --noEmit
npm test               # vitest
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler dev     # local
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy  # prod
```

Worker secrets: `wrangler secret put TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` (prod) and `workers/.dev.vars` (local). KV namespace `TOKENS`.

## Logging — agents read this

`AppLogger` mirrors os_log AND `Library/Logs/embr.log` (rotates at 2 MB). Categories: `app, auth, api, eventsub, chat, emote, playback, persistence, ui`. To pull from a device, use the `ios-device-logs` skill / `devicectl ... copy from --source Library/Logs/embr.log`.

## Secrets / config

`.env.local` (gitignored, made by `setup.sh`): `EMBR_BUNDLE_ID`, `EMBR_TEAM_ID`, `EMBR_DEVICE_UDID`, `EMBR_DEVICE_NAME`. `Embr/Secrets.swift` (gitignored, copied from `Secrets.example.swift`): `twitchClientID`, `workerBaseURL`, `redirectURI`. Never commit either.

## Reality

- The video path resolves Twitch HLS via the unofficial GQL `PlaybackAccessToken` (Worker-side) and strips stitched ad segments. This violates Twitch's Developer Agreement and can break when Twitch changes the GQL hash or enforces Client-Integrity. Personal/sideload use, eyes open. The player sits behind `VideoPlaying`; `WebViewPlayer` is the compliant fallback.
- Chat is EventSub-first (`channel.chat.message`); IRC `justinfan` is a logged-out-preview-only leg.
