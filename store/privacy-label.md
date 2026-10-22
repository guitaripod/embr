# Embr App Privacy label

Answers for App Store Connect, App Privacy section. Apple does not expose this section through the API, so the founder enters it by hand. It matches `Embr/PrivacyInfo.xcprivacy` and the policy at https://midgarcorp.cc/legal/embr/privacy (source: `web/midgarcorp/src/content/legal/embr/privacy.html`, last updated 23 October 2026). The Privacy Policy URL on the app info (`store/metadata/ios/app-info/*.json`) moves from the worker page to that address with this release; `midgar listing` pushes it and, under the `metadata_edit` policy, only with the founder at a terminal.

This replaces the earlier label, "Data Not Linked to You: User Content only", which no longer holds once the app keeps a Midgar ID and tips are reported to the Midgar ledger.

## Top-level answers

- Do you or your third-party partners collect data from this app: Yes.
- Data used to track you: none. No data type is used for tracking. The app asks for no tracking permission and `NSPrivacyTracking` is false with no tracking domains.
- Privacy policy URL: https://midgarcorp.cc/legal/embr/privacy

## Data types collected

| Data type (Apple) | Linked to the user | Used to track | Purpose | What it is in Embr |
| --- | --- | --- | --- | --- |
| Identifiers, User ID | Yes | No | App Functionality | The random Midgar ID: sent as the sign-in token to `api.midgarcorp.cc` for the purchase ledger and for "Your Midgar" in the More Apps screen; carried by tips as Apple's app account token. It is never sent with playback, report, sign-in or config requests to Embr's own worker. |
| Purchases, Purchase History | Yes | No | App Functionality | The App Store transactions of the three tips (consumables, unlock nothing), sent to the Midgar ledger with the Midgar ID. RevenueCat has no SDK in the app (registry `rc_mode` is notifications-only). |
| Usage Data, Product Interaction | No | No | Analytics | The anonymous More Apps events (opened, shown, tapped) sent by MidgarKit with no identifier. |
| User Content, Other User Content | No | No | App Functionality | The chat message, its author, the channel and the reason of a chat report the person submits (App Store Guideline 1.2), and the same for a block. Sent to Embr's worker without the Midgar ID or any Twitch token. This is unchanged from the earlier label. |

Everything else is "Data Not Collected".

## Twitch and the other services the app talks to

- Sign in with Twitch is optional. The authorization code and refresh token pass through Embr's worker (a Cloudflare Worker behind `api.midgarcorp.cc`), which exchanges them with Twitch and keeps no copy; the access token lives only in the device Keychain. Apple's label covers what the developer collects, and nothing here is stored by us, so it adds no data type.
- Video, chat, follows and channel data come straight from Twitch (`api.twitch.tv`, `irc-ws.chat.twitch.tv`, `eventsub.wss.twitch.tv`, `usher.ttvnw.net`, `player.twitch.tv`). The emote sets come from 7TV, BetterTTV and FrankerFaceZ and recent chat from `recent-messages.robotty.de`. These are third-party services the person reaches through the app; they receive the channel name or id and the IP address. Embr sends none of them the Midgar ID.
- The worker sees an IP address like any server and stores none. Cloudflare may keep standard request logs for a limited time; IP address is not a data type in the label.

## Data types answered "not collected", and why

- Contact Info, Contacts, Browsing History, Search History, Sensitive Info, Financial Info, Health & Fitness, Location: none.
- Identifiers, Device ID: the app reads no advertising identifier and no vendor identifier. MidgarKit's App Attest key id, if the device creates one, is per app and per device and proves the app is genuine when the Midgar ID is created or joined. If App Review reads it as a Device ID, the fallback is Device ID, App Functionality, linked.
- Diagnostics: the session log stays on the device and is shared only when the person exports it. MetricKit is not collected.
- User Content, Customer Support: nothing beyond the report row above.

## Third-party SDK notes

- MidgarKit: `MidgarPortal` ships a manifest that declares Product Interaction for Analytics, not linked, matching the row above.
- SDWebImage and GRDB: no data collected.

## Required-reason APIs (in the manifest, not in the label)

- UserDefaults `CA92.1` (own settings and caches), File timestamp `C617.1`.
