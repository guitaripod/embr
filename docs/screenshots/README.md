# Screenshots (6.9" / iPhone 17 Pro Max, 1320×2868)

Auto-captured from the simulator (`xcrun simctl io screenshot`):
- `01-onboarding-6.9.png` — first-launch agreement + value prop (caption: "Watch Twitch, natively")
- `02-browse-6.9.png` — live browse grid (caption: "Every live channel, at a glance")

The remaining shots (player, chat, channel, search, settings) need in-app taps to reach.
`simctl` can't tap without `idb`; capture them on-device (Side+Volume Up) or via an
XCUITest snapshot harness. Captions for all six are in `../store-listing.md`.
