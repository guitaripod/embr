# App Store screenshots

Nine captioned panels per listing language, iPhone 6.9" (1320×2868). Captions live in
`metadata/screenshot-captions.json`; raw captures and composed panels are generated into the
gitignored `marketing/raw/` and `marketing/panels/`.

| # | Panel | Source |
|---|-------|--------|
| 1 | hero | `marketing/hero.png` — a device capture of live video beside chat, headline repainted per language |
| 2 | favorites | `-screenshotRoute favorites -screenshotFavorites a,b,c` |
| 3 | top | `-screenshotRoute top` |
| 4 | chat | `-screenshotRoute channelchat -screenshotChannel <login>` |
| 5 | audio | `-screenshotRoute channelaudio -screenshotChannel <login>` |
| 6 | categories | `-screenshotRoute categories` |
| 7 | search | `-screenshotRoute search -screenshotQuery "Just Chatting"` |
| 8 | settings | `-screenshotRoute settings` |
| 9 | onboarding | first plain launch of a fresh install |

The hero is the one panel a simulator cannot make: it does not decode live video. To refresh
it, capture the channel screen on a device and replace `marketing/hero.png` with a framed
panel of the same geometry.

## Capture

A DEBUG-only harness (`Embr/App/ScreenshotHarness.swift`, driven by
`SceneDelegate.handleScreenshotRoute`) poses each screen from launch arguments, so nothing is
tapped. Build the Debug app for the simulator, then:

```bash
scripts/ios-build.sh "generic/platform=iOS Simulator"
scripts/capture-store-shots.py --sim <iPhone 17 Pro Max udid> \
  --app ~/Library/Developer/Xcode/DerivedData/Embr-*/Build/Products/Debug-iphonesimulator/Embr.app \
  --chat-channel <live channel> --audio-channel <live channel> --favorites a,b,c
```

Each language starts from a fresh install. Data is live from Twitch, so pick channels that are
live with a calm chat, and read every chat capture before uploading: chat is written by
strangers.

Other routes: `support` (Settings scrolled to the tip jar, with fixed US prices — the In-App
Purchase review screenshot), `following` (seeded follows, signed-in look), `moreapps`, and
`open -screenshotURL <url>`, which sends any deep link (e.g. `embr://favorites`) through the
router without the system's "Open in Embr?" prompt that `simctl openurl` stops at.

## Compose

```bash
scripts/compose-store-shots.py            # every language in the captions file
scripts/compose-store-shots.py --locale ja
```

Headlines are drawn through AppKit, so Japanese, Korean and both Chinese scripts get the
system's own faces and the right Han forms per language. es-MX uses the es-ES panels;
en-GB and en-AU fall back to en-US.
