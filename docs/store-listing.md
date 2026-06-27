# Embr — App Store listing copy

Paste-ready for App Store Connect. Character counts include spaces; capped fields noted.

## App name (≤30)
- **`Embr`** (4) — first choice; carry "Twitch" in the subtitle/keywords, not the name.
- Fallbacks if taken: `Embr • Stream Viewer` (20), `Embr — Live Stream Client` (25).
  (Avoid `Embr for Twitch` — "for Twitch" naming draws the most trademark risk.)

## Subtitle (≤30)
- **`Fast native Twitch client`** (25)
- Alt: `Watch Twitch, chat, no bloat` (28)

## Promotional text (≤170)
> A fast, native Twitch viewer with picture-in-picture, background audio, and real-time chat with 7TV, BTTV & FFZ emotes. Browse, watch, and chat — sign-in optional. (161)

## Keywords (≤100, comma-separated, no spaces, no title/subtitle repeats)
```
stream,streaming,livestream,twitch viewer,7tv,bttv,ffz,emotes,vod,clips,pip,irc,esports,gaming,live
```
(99 — deliberately omits "Embr/Twitch/client/native/fast/chat", already indexed from title/subtitle.)

## Description (≤4000, ~2050 used)
Embr is a fast, native Twitch client built for iPhone — not a wrapped web view. Streams open in a real AVPlayer with picture-in-picture, background audio, and instant quality switching. Chat is rendered natively so it stays smooth even in the busiest channels. No bloat, no clutter, just watch and chat.

Browse without an account. Sign in with Twitch only when you want to follow channels and join the conversation.

WATCH
- Native AVPlayer video — live streams, VODs, and clips
- Picture-in-picture and background audio — keep watching while you use other apps
- Quality selection, latency display, and landscape fullscreen
- Double-tap to seek, and adjustable playback speed on VODs

BROWSE & DISCOVER
- Live channels and top categories at a glance
- Search channels and categories instantly
- A Following tab that surfaces who's live (when signed in)
- Rich channel pages with everything you need to dive in

REAL-TIME CHAT
- Live chat over Twitch EventSub — fast and reliable
- Animated emotes from Twitch, 7TV, BetterTTV, and FrankerFaceZ, all merged together
- Badges, cheermotes, mentions, and threaded replies
- Emote autocomplete and recent-message backfill so you're never lost
- Search the chat, report or block messages, and hide users you'd rather not see
- Moderator tools — delete, timeout, and ban — when you're a mod in the channel

MADE FOR iPhone
- Light and dark themes, with chat readability and text-scale controls
- Haptics, third-party emote toggles, and a blocked-users list
- Built natively in UIKit for speed and a small footprint
- Full guest browsing — an account is optional

Embr is open source.

———————

Embr is an independent, third-party app and is not affiliated with, endorsed by, sponsored by, or connected to Twitch Interactive, Inc. "Twitch" and all related names, marks, and logos are trademarks of their respective owners and are used here only to describe what the app connects to. You sign in with your own Twitch account through Twitch's official OAuth; Embr never sees your password. Use of Twitch is subject to Twitch's own Terms of Service.

## What's New — v1.0.0
Welcome to Embr 1.0 — a fast, native Twitch client for iPhone.
- Browse live channels, top categories, and search
- A Following tab for the channels you care about (sign-in)
- Native AVPlayer video with picture-in-picture, background audio, quality selection, and fullscreen
- VODs and clips, with playback speed and double-tap seek
- Real-time chat over EventSub with 7TV, BTTV, and FFZ emotes merged in
- Badges, cheermotes, replies, emote autocomplete, and chat search
- Moderator actions when you're a mod; report and block when you're not
- Themes, haptics, and chat readability controls

## App Review notes
Embr is an independent, third-party client for Twitch (browse live channels/categories, watch live/VOD/clip in a native AVPlayer, read and join real-time chat).

NO LOGIN REQUIRED TO REVIEW. Guest mode is fully functional without any account and covers the core experience: browse live channels and top categories, search, watch any live stream/VOD/clip, and read live chat. Just open the app and tap any live channel.

SIGN-IN (optional) adds the Following tab, sending chat, and moderator actions, via Twitch's official OAuth in an ASWebAuthenticationSession — we never receive the password; the token lives only in the iOS Keychain on-device. We can provide demo Twitch credentials on request via App Review Messages.

Content note: streams and chat are live, user-generated content from Twitch, not controlled by Embr. The app provides report-message and block-user controls and respects Twitch's own moderation; rated 17+ accordingly. Open source; source available on request.

## Categories
- Primary: **Entertainment**
- Secondary: **Social Networking** (real-time chat, following, replies, moderation)

## Age rating — 17+
Driven mainly by unrestricted user-generated content (live streams + chat Embr does not pre-moderate). Answer: UGC Yes (frequent/intense possible); Profanity/Crude Humor frequent; Mature/Suggestive + Violence infrequent→frequent; Alcohol/Tobacco/Drugs + Simulated Gambling infrequent/mild. Mitigations: in-app report + block + Twitch moderation.

## App Privacy (nutrition label)
- **Data used to track you:** None.
- **Data linked to you:** None (OAuth token is on-device, not collected).
- **Data not linked to you:** "User Content" — only when a user submits a report (App Functionality, not tracking). Otherwise none.

Summary: Embr collects the minimum to work and does not track you — no analytics SDK, no ads, no third-party tracking. Sign-in uses Twitch's official OAuth (Embr never sees your password; token stored only in the device Keychain; sign-out deletes it). Settings and blocked-users list are stored locally. A submitted report (message + channel context) is sent to the developer for moderation handling; not sold or shared.

## Screenshot captions (≤~40 chars)
1. Browse — `Every live channel, at a glance`
2. Player — `Real video. PiP, background, fullscreen`
3. Chat — `7TV, BTTV & FFZ emotes, merged in`
4. Channel — `Dive into any channel instantly`
5. Search — `Find any channel or category fast`
6. Settings — `Themes, haptics, your way`

## Support / URLs
- Support email: guitaripod@gmail.com
- Privacy Policy URL: https://embr.guitaripod.workers.dev/legal/privacy
- Terms of Use URL: https://embr.guitaripod.workers.dev/legal/terms
