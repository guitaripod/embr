# Embr — Build Contract (authoritative)

A native UIKit iOS Twitch client. This file is the single source of truth for every build agent.
**Do not deviate from the type names, file paths, or conventions here.**

## Repo shape

```
EmbrCore/  (SwiftPM library — Sources/EmbrCore, Tests/EmbrCoreTests)
           Platform-agnostic pure logic. MUST compile + test on Linux.
           NO import UIKit / AVFoundation / Combine / Security here.
Embr/      (xcodegen app target — UIKit, iOS 18+, iPhone-only)
           Imports EmbrCore. Darwin-only. Not compiled in CI on Linux.
workers/   (Cloudflare Worker — Hono + TypeScript. Compiled + vitest on Linux.)
```

`EmbrCore/` files under `Sources/EmbrCore/**` authored by the foundation pass are **FROZEN**: read them, depend on them, never edit them. New EmbrCore subsystems add NEW files only.

## Locked architecture decisions

- **Chat receive:** EventSub WebSocket `wss://eventsub.wss.twitch.tv/ws`, subscription `channel.chat.message` (+ `.notification`, `.clear`, `.clear_user_messages`, `.message_delete`, `chat_settings.update`). Scope `user:read:chat`.
- **Chat send:** Helix `POST /helix/chat/messages` (scope `user:write:chat`). Surface `is_sent`/`drop_reason`.
- **Anonymous chat preview only:** IRC `wss://irc-ws.chat.twitch.tv:443`, `NICK justinfan<random>`. Removable leg.
- **Auth:** Authorization Code via the Worker (holds client secret). `ASWebAuthenticationSession` on device → Worker `/auth/exchange` + `/auth/refresh`. Tokens in **Keychain**. Anonymous browsing uses Worker `/auth/app-token`. `/oauth2/validate` hourly.
- **Video:** native `AVPlayer` fed by Worker-resolved, ad-stripped HLS (`/playback/:login` → m3u8 proxied through `/hls/*`). `AVPictureInPictureController`. `VideoPlaying` protocol with `HLSVideoPlayer` primary + `WebViewPlayer` fallback.
- **Emotes:** Twitch + 7TV (+ `wss://events.7tv.io/v3` live updates) + BetterTTV + FrankerFaceZ. Layered `EmoteCatalog` (channel over global). Animated WebP via SDWebImage.
- **Persistence:** GRDB for domain data, Keychain for tokens, single `Codable` blob for settings.

## EmbrCore public API already available (FROZEN — use these exact symbols)

Models: `ChatMessage`, `ChatUser`, `ChatFragment` (`.text/.emote/.cheermote/.mention`), `TwitchEmoteRef`, `CheermoteRef`, `MentionRef`, `MessageBadge`, `MessageType`, `ReplyContext`, `SharedChatSource`, `ModerationState`, `ChannelNotice`, `NoticeKind`, `ChatColor`, `ChatEvent`, `SystemNotice`, `ConnectionStatus`, `RoomState`, `SendResult`.
Emotes/badges: `Emote`, `EmoteProvider`, `EmoteScale`, `EmoteFormat`, `EmoteImageSet`, `EmoteCDN`, `EmoteCatalog`, `EmoteSetUpdate`, `Badge`, `BadgeProvider`, `BadgeCatalog`.
Render: `RenderToken` (`.text/.emote/.mention/.link/.cheermote`), `MessageTokenizer.tokens(for:catalog:)`.
Twitch domain: `LiveStream`, `GameCategory`, `TwitchUser`, `ChannelInfo`, `VideoOnDemand`, `Clip`, `FollowedChannel`, `Page<Element>`.
Networking: `APIError`, `HTTPMethod`, `HTTPRequest`, `HTTPResponse`, `RateLimit`, `HTTPTransport`, `QueryEncoder`, `TwitchJSON`.
Auth: `StoredCredentials`, `AuthenticatedUser`, `TokenValidation`, `WorkerAPI.{ExchangeRequest,RefreshRequest,TokenResponse,PlaybackResponse,ErrorResponse}`, `TwitchScopes`.
Playback: `PlaybackResolution`, `StreamQuality`, `HLSVariant`, `HLSSegment`.
Protocols: `TwitchAPIProviding`, `ChatSource`, `ThirdPartyEmoteSource`, `EmoteEventStreaming`, `EmoteCataloging`, `PlaybackResolving`, `TokenStoring`, `AuthControlling`, `RecentMessagesProviding`.

## Swift conventions (NON-NEGOTIABLE — from the owner's house style)

- `final class` for reference types; `nonisolated struct: Sendable` for value types.
- Swift 6 language mode, strict concurrency. Anything crossing actor boundaries is `Sendable`.
- **Programmatic UIKit only.** No storyboards/XIB. `UIStackView` first, then Auto Layout anchors. Chat message cells are the ONE exception: manual frame layout from precomputed rects (Auto Layout is too slow for the chat firehose).
- Every custom `UIView`/`UIViewController` subclass: `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }`.
- **ViewModels expose `PassthroughSubject<T, Never>`** (never `@Published`). On the chat hot path the subject element is a **batch** (`[ChatRow]` / a snapshot), never one event per message.
- View controllers are `@MainActor`, bind in `viewDidLoad`, hold `Set<AnyCancellable>`. Subjects produced off the main actor are delivered `.receive(on: DispatchQueue.main)` before binding.
- Service surfaces are protocols (in EmbrCore where platform-agnostic). Concrete services are `final class`/`actor` singletons `.shared`, injected through inits with default values: `init(api: TwitchAPIProviding = TwitchAPIClient.shared)`.
- GRDB: `nonisolated struct` records conforming to `Codable, FetchableRecord, PersistableRecord`. Migrations via `DatabaseMigrator.registerMigration("v1")`, never edited after the fact.
- `UIBackgroundConfiguration.listCell()` on list cells.
- SF Symbol effects: `.pulse` on the live "reconnecting" row, `.bounce`/`.replace` on send-confirm.
- **No comments, no MARK, no file headers.** `///` doc comments allowed sparingly on public API. SPM only for deps.
- Tests: Swift Testing (`@Test`, `#expect`) only. EmbrCore tests live in `Tests/EmbrCoreTests/**` and MUST pass via `swift test`.
- AppLogger mirrors os_log + a rotating file in `Library/Logs/embr.log`. Categories: `app, auth, api, eventsub, chat, emote, playback, persistence, ui`.

## App-layer cross-cutting contracts (authored in the foundation pass — match these names)

- `AppLogger` (`Embr/App/AppLogger.swift`) — `AppLogger.log(_:_:category:)`, plus `.debug/.info/.warn/.error(_:category:)`.
- `LogCategory` enum: `app, auth, api, eventsub, chat, emote, playback, persistence, ui`.
- `AppContainer` (`Embr/App/AppContainer.swift`) — the DI graph. Lazily exposes: `logger`, `transport: HTTPTransport`, `auth: AuthService`, `api: TwitchAPIClient`, `emotes: EmoteService`, `images: ImageLoading`, `playback: PlaybackResolver`, `database: DatabaseManager`, `settings: SettingsStore`. A module's concrete service MUST be named exactly as referenced here.
- `ImageLoading` protocol (`Embr/Services/ImageLoading.swift`) — `func image(for: URL, targetScale: CGFloat) async -> UIImage?`, `func emoteImage(for: Emote, scale: EmoteScale) async -> UIImage?`, `func badgeImage(for: Badge, scale: EmoteScale) async -> UIImage?`, `func prefetch(_ urls: [URL])`, `func cachedImage(for: URL) -> UIImage?`. (Animated content returns an `SDAnimatedImage` subclass of `UIImage`.)
- `VideoPlaying` protocol (`Embr/Features/Channel/Video/VideoPlaying.swift`) — `var view: UIView { get }`, `func load(_ resolution: PlaybackResolution)`, `func play()/pause()`, `func setQuality(_ quality: StreamQuality)`, `var statePublisher: AnyPublisher<VideoState, Never> { get }`.
- `Theme` (`Embr/App/Theme.swift`) — semantic `UIColor`s.

## Concrete type names per module (create with EXACTLY these names)

- Transport: `URLSessionTransport: HTTPTransport` (`Embr/Services/URLSessionTransport.swift`).
- Twitch API: `final class TwitchAPIClient: TwitchAPIProviding` (`Embr/Services/TwitchAPIClient.swift`) — `static let shared`. Uses `HelixEndpoints` (EmbrCore) for request specs + `HelixDTO` decoding.
- Auth: `actor AuthService: AuthControlling` (`Embr/Services/Auth/AuthService.swift`), `final class KeychainTokenStore: TokenStoring`, `final class WorkerAuthClient`, `final class TwitchLoginCoordinator` (ASWebAuthenticationSession).
- Chat: `actor EventSubChatSource: ChatSource`, `actor IRCChatSource: ChatSource`, `actor ChatRoom` (`Embr/Features/Channel/Chat/`). `ChatRoom` batches at 200ms, merges recent-message backfill, exposes events.
- Emotes: `actor EmoteService: EmoteCataloging` (`Embr/Services/Emotes/EmoteService.swift`), `final class SevenTVSource/BetterTTVSource/FrankerFaceZSource: ThirdPartyEmoteSource`, `actor SevenTVEventClient: EmoteEventStreaming`.
- Images: `final class ImageLoader: ImageLoading` (SDWebImage-backed).
- Playback: `actor PlaybackResolver: PlaybackResolving`.
- Video: `final class HLSVideoPlayer: VideoPlaying`, `final class WebViewPlayer: VideoPlaying`, `VideoState` enum, `VideoViewController`, `VideoOverlayView`.
- Rendering: `MessageLayout` (struct, computes `LaidOutMessage`), `MessageCell: UICollectionViewCell`, `EmoteAnimator` (shared `CADisplayLink`), `BadgeStripView`.
- Chat UI: `ChatViewController`, `ChatViewModel`, `ChatInputView`, `EmoteAutocompleteView`, `ChatRow` (cell model).
- Browse: `RootTabBarController`, `HomeViewController`, `FollowingViewController`, `TopViewController`, `SearchViewController`, `ChannelViewController`, `StreamListViewModel`, `StreamCell`, `CategoryCell`.
- Settings/Persistence: `SettingsStore` (Codable blob in UserDefaults, debounced), `Settings` struct, `DatabaseManager` (GRDB), records `AccountRecord`, `JoinedChannelRecord`, `RecentEmoteRecord`, `BlockedUserRecord`, `CustomCommandRecord`.

## Worker API JSON contract (must match EmbrCore `WorkerAPI` DTOs)

Base: the app sends `Authorization: Bearer <user-or-app-token>` where required. JSON in/out, camelCase keys.

- `POST /auth/exchange` ← `{ "code": string, "redirectURI": string }` → `TokenResponse { accessToken, refreshToken?, expiresIn, scope?, userID?, login? }`
- `POST /auth/refresh` ← `{ "refreshToken": string }` → `TokenResponse`
- `GET  /auth/app-token` → `{ "accessToken": string, "expiresIn": number }`
- `GET  /auth/login-url?redirectURI=...&state=...` → `{ "url": string }` (builds the Twitch authorize URL with scopes)
- `GET  /playback/:login` (live) → `PlaybackResponse { url, expiresAt? }` where `url` points at this Worker's `/hls/...` ad-stripped master proxy
- `GET  /playback/vod/:id` → `PlaybackResponse`
- `GET  /hls/*` → proxied + ad-segment-stripped m3u8/playlist passthrough
- Errors → non-2xx + `ErrorResponse { error }`

Secrets (wrangler): `TWITCH_CLIENT_ID`, `TWITCH_CLIENT_SECRET`. KV namespace `TOKENS` caches the app token. The GQL `PlaybackAccessToken` call uses the public web client-id `kimne78kx3ncx6brgo4mv6wki5h1ko` (separate from the registered dev client-id used for Helix/OAuth).

## Ad-strip rule (shared by Worker `/hls` and EmbrCore `HLSAdStripper`)

In a media playlist, drop segments belonging to stitched ads: `#EXT-X-DATERANGE` with `CLASS="twitch-stitched-ad"` or an `ID` beginning `stitched-ad-`, segments whose preceding `#EXTINF` title contains `Amazon`, and any `#EXT-X-DISCONTINUITY` bracketing them. Preserve `#EXT-X-TWITCH-PREFETCH` (low-latency) tags. Keep the playlist valid (consistent media sequence).
