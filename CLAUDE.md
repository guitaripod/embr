# Embr — Agent Instructions

Native UIKit Twitch client for iPhone, iPad and Apple TV (browse + watch + chat), with a Cloudflare Worker backend for OAuth, HLS resolution and the Founding Supporter badges. One App Store record, universal purchase.

See `CONTRACTS.md` for the authoritative architecture, type names, and module map. This file is the working guide.

## Stack

- **EmbrCore** (`Core/EmbrCore/Sources/EmbrCore`): platform-agnostic Swift 6 logic — models, IRC/EventSub parsing, emote merge, HLS handling, Helix request specs, OAuth DTOs. **Compiles and tests on Linux and macOS.** No UIKit/AVFoundation/Combine/Security imports.
- **Embr** (`App/`, `Features/`, `Resources/`, xcodegen): programmatic UIKit, MVVM with Combine `PassthroughSubject`, GRDB, Swift 6 strict concurrency, iOS 18+, iPhone and iPad. Darwin-only — build on a Mac.
- **EmbrTV** (`TV/`, tvOS 18+, same bundle id): the Apple TV app. It ships to TestFlight only (decision D32, guideline 5.2.3): `midgar ship embr --platform tvos --version <next>` uploads and stops, and nothing about it goes into the iPhone and iPad listing. It compiles the shared services, chat engine, `HLSVideoPlayer` and settings straight from `App/` and `Features/` (the list is in `project.yml`); platform differences are `#if os(tvOS)` in those files. Plays in the system `AVPlayerViewController` (PiP and swap, Info tab, transport-bar menus, custom overlay, contextual actions) with chat in `contentOverlayView`. `EmbrTopShelf` (`TopShelf/`, bundle `com.guitaripod.embr.topshelf`) is the Top Shelf carousel; it reads the app's snapshot from a keychain item in the `com.guitaripod.embr.shelf` group (`ShelfShared/`) and looks up who is live itself.
- **Shared/** (both apps): Founding Supporter (`SupporterStore`, `SupporterDirectory`, `SupporterAccent`, `SupporterLook` with the themes, chat fonts and icons, `SupporterChatPreview`, `SupporterTag`, `SupporterCelebration`) and `FavoritesSync`.
- **services/embr** (Worker `embr`; `services/embr-demo-mail` is the App Review mail helper): Cloudflare Workers (Hono, KV). OAuth code exchange/refresh, app-token minting, HLS playlist resolution + proxy. TypeScript, vitest.
- **MidgarKit** (from the monorepo's `packages/MidgarKit` by path, `project.yml`, decision D15): `MidgarCore` (logging, HTTP, Midgar ID), `MidgarCommerce` (the tips), `MidgarUI` (version info), `MidgarPortal` (the More Apps card). `EmbrMidgar` (`App/EmbrMidgar.swift`) is the composition root for all of it.

## The Midgar platform (invariants)

- **Worker behind the gateway.** Every API request to Embr's worker goes to `https://api.midgarcorp.cc/v1/embr/...` through `MidgarGatewayTransport` (MidgarCore.HTTP, `X-App-ID: embr`). The client for it carries no Midgar ID and no `Authorization`: the worker reads no credential. The gateway sends `X-Forwarded-Prefix: /v1/embr`, and the worker builds its HLS proxy links from it. `/hls/proxy`, `/embed` and `/auth/callback` are public gateway calls (AVPlayer, the web view and Twitch cannot send `X-App-ID`).
- **Twitch redirect URI** stays `https://embr.guitaripod.workers.dev/auth/callback` (`Configuration.twitchRedirectURI`), the one registered in the Twitch console. It is a browser navigation inside `ASWebAuthenticationSession`, not an app network call, so it needs neither the gateway nor an ATS exception. It is the only place that host appears in the app; changing it needs a console change first.
- **Purchases** go through one `MidgarStore` (`EmbrMidgar.commerce`) in `Mode.purchases`: the three tip consumables (`TipJarStore`, unlock nothing) and the Founding Supporter non-consumable (`SupporterStore`, entitlement `supporter`). Founding Supporter unlocks only looks: themes (`SupporterTheme`, carried down every window by the `SupporterThemeTrait` trait that `Theme.background`/`surface`/`surfaceElevated` resolve against), accent colors (`SupporterAccent` behind `Theme.accent`), chat fonts (`SupporterChatFont`, read by `MessageLayout` through `SupporterLook.unlocked`), eleven iPhone icons, and for everyone in Embr to see a flame badge in the supporter's color, their name in that color or glowing, and a founding number. The purchase screens are a fitting room: every look can be tried on (a trait override on the screen plus `SupporterChatPreview`, drawn by the real `MessageLayout`), and the purchase keeps what was tried on. Nothing about watching or chat may ever sit behind it (Twitch's developer agreement forbids charging for watching).
- **Supporter badge.** `SupporterStore` posts the signed transaction and the Twitch token once to `POST /supporters/claim`; the worker verifies the JWS to Apple Root CA G3 and the token with Twitch (client id must be Embr's), then stores `supporter:<twitchUserID>` with the founding number (one past the highest, kept when the badge moves) and the badge color and name style as KV metadata. `POST /supporters/style` changes the color and style, proven with the token again. Every app reads `GET /supporters` (`SupporterDirectory`: ids, numbers, colors, styles) and `MessageLayout` draws the badge in the supporter's color and their name in it or glowing, unless the viewer turns off Supporter Name Colors. The token travels in the body, is read once and never stored; this is the one worker route that reads a credential.
- **Favorites sync** through iCloud key-value storage (`FavoritesSync`, `FavoritesLedger` in EmbrCore: later add or removal wins per channel). The Apple TV keeps its database in Caches (tvOS keeps nothing else), so the ledger restores the favorites if the system purges it.
- **Apple TV sign-in** is Twitch's device code flow (`DeviceAuthorization`, `TVSignInViewController`, `AuthService.completeDeviceLogin`), straight from the TV to `id.twitch.tv` with the client id and no secret; refresh goes through the worker like every session. The TV app runs as the current tvOS user (`com.apple.developer.user-management`), so each person has their own sign-in and favorites.
- **Midgar ID** starts at launch (`EmbrMidgar.start()`), in the team keychain group `cc.midgarcorp.shared`. The app's own group stays first in the entitlements so the Twitch tokens already in the Keychain keep resolving. A test host and a DEBUG demo capture start nothing and reach no Midgar service.
- **Privacy** is declared in `Resources/PrivacyInfo.xcprivacy`, `store/privacy-label.md` and `web/midgarcorp/src/content/legal/embr/`: Midgar ID and a supporter's Twitch user id (User ID, linked), tips and Founding Supporter (Purchase History, linked), reports (Other User Content, not linked), More Apps (Product Interaction, not linked). Change one and change all three plus `LegalText.privacy` (one localized string per section).
- **Review prompt** is `MidgarReviewPolicy` (`ReviewPrompt`); the success is 3 minutes of a confirmed live stream.

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

App tests (Swift Testing, `Tests/EmbrTests`, the gateway transport, the tip jar, the review migration):

```bash
export EMBR_BUNDLE_ID=com.guitaripod.embr EMBR_TEAM_ID=P4DQK6SRKR
xcodegen generate
xcodebuild test -project Embr.xcodeproj -scheme Embr -destination 'platform=iOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO
```

### Apple TV app (Mac only)

```bash
scripts/tv-build.sh                 # simulator build (default) or: scripts/tv-build.sh device
xcodebuild test -project Embr.xcodeproj -scheme EmbrTV -destination 'platform=tvOS Simulator,id=<udid>' CODE_SIGNING_ALLOWED=NO
```

`EmbrTVUITests` drives the Siri Remote (`XCUIRemote`) through browsing, the player, settings and sign-in and attaches a screenshot of each screen. App Store and review captures use the invented world: launch with `-embrDemo -tvRoute following|favorites|browse|player|multiview|channel|supporter|supporterowned|signin` (DEBUG only, `TV/App/TVScreenshotRoute.swift`). Device builds sign Debug with the `Embr tvOS Development` and `Embr Top Shelf Development` profiles (`~/.config/midgar/signing/`).

Brand art (TV layered icon, Top Shelf images, the supporter badge and large flame in every color, supporters' iPhone icons including Midnight, Paper, Neon and Pixel) is rendered by `swift scripts/render-brand-art.swift <dir>`. The iPhone supporter screen poses for screenshots with `-screenshotRoute supporter -screenshotLook theme,flame,nameStyle,font,accent -screenshotScroll <points>`; demo chat (`-embrDemo`) has three supporters.

### Worker

```bash
cd workers
npm install
npm run typecheck      # tsc --noEmit
npm test               # vitest
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler dev     # local
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy  # prod
```

Worker secrets: `wrangler secret put TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` (prod) and `services/embr/.dev.vars` (local). KV namespace `TOKENS`.

## Logging — agents read this

`MidgarLog` (MidgarCore) mirrors os_log AND `Library/Logs/embr.log` (rotates at 2 MB, three archives kept). Categories: `app, auth, api, eventsub, chat, emote, playback, persistence, tips` (Embr's, in `LogCategories.swift`) plus MidgarCore's `account, commerce, network, portal, ui`. To pull from a device, use the `ios-device-logs` skill / `devicectl ... copy from --source Library/Logs/embr.log`.

## Secrets / config

`.env.local` (gitignored, made by `setup.sh`): `EMBR_BUNDLE_ID`, `EMBR_TEAM_ID`, `EMBR_DEVICE_UDID`, `EMBR_DEVICE_NAME`. `App/Secrets.swift` (gitignored, copied from `Secrets.example.swift`): `twitchClientID`, `redirectURI`. The worker address is not a secret: it is `Configuration.workerBaseURL`, the gateway route. Never commit either.

## Reality

- The video path resolves the stream's HLS playlist Worker-side and plays it with `AVPlayer`; it can break if Twitch changes upstream playback behavior. The player sits behind `VideoPlaying`, with `WebViewPlayer` (official embed) as the fallback.
- Chat is EventSub-first (`channel.chat.message`); IRC `justinfan` is a logged-out-preview-only leg.
