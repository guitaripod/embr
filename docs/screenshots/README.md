# App Store screenshots

Ten iPhone 6.9" panels (1320×2868), nine iPad 13" panels (2064×2752) and ten iPhone Duo panels at
the four Duo sizes, in every listing language, plus the text-free Header and Search Results image
(5244×2950). Every panel is the same design: a dark night with ember and violet light drifting
across the whole set, a two-line headline whose second line glows in Embr's ember gradient, a short
line under it, and the capture in its real device frame (`frames`), sometimes with one part of the
screen lifted out and enlarged.

Everything shown comes from the DEBUG demo world (`-embrDemo`): invented channels, procedural stream
art and scripted chat with Twitch, 7TV, BetterTTV and FrankerFaceZ emotes, so every capture is the
same each run, works offline and shows no stranger's message and no real streamer.

| # | Panel | Capture |
|---|-------|---------|
| 1 | watch | `-screenshotRoute channel -screenshotChannel lumenfox` |
| 2 | emotes | `-screenshotRoute chats -screenshotSheet emotes` |
| 3 | chats | `-screenshotRoute chats` (iPad: three chats side by side) |
| 4 | fullscreen | `-screenshotRoute channelfullchat -screenshotChannel lumenfox` (iPhone only) |
| 5 | mentions | `-screenshotRoute chats -screenshotSheet mentions` |
| 6 | usercard | `-screenshotRoute usercard -screenshotChannel lumenfox -screenshotModerator 1` |
| 7 | favorites | `-screenshotRoute favorites` |
| 8 | audio | `-screenshotRoute channelaudio -screenshotChannel quietmoth` |
| 9 | moderate | `-screenshotRoute modqueue -screenshotChannel lumenfox -screenshotModerator 1` |
| 10 | supporter | `-screenshotRoute supporter` |

All routes run with `-embrDemo -screenshotTheme dark -screenshotAuth 1`.

## Run

```bash
scripts/ios-build.sh "platform=iOS Simulator,id=<udid>"     # or xcodebuild into a scratch DerivedData
scripts/capture-store-panels.py --sim <iPhone 17 Pro Max udid> --app <Debug-iphonesimulator/Embr.app>
scripts/capture-store-panels.py --sim <iPad Pro 13" udid> --app <…/Embr.app> --device ipad
scripts/store-panels.py                 # every device and locale into store/shots/<device>/<locale>/
scripts/store-panels.py --creative      # store/creative/<locale>/header.png
midgar shots embr --train ios --apply   # upload
```

Captures land in `marketing/raw/<device>/<language>/` (gitignored), one set per app language;
listing languages the app does not speak use the English captures with their own captions.
Captions are `marketing/captions.json`: two title lines, the line that glows, and the line under it,
per listing locale. Keep a title line within 20 characters (10 in Chinese and Japanese) and never
use a word for "free" (guideline 2.3.7).

iPad captures are portrait: an app that turns its own window to landscape lands in iPadOS's
windowed mode on the simulator, wallpaper and Dock around it.

The iPhone Duo panels come from the `iphone-duo` skill's `capture.py`, one screen per state
(`marketing/raw/duo/<language>/<screen>__<state>.png`).

Other routes: `support` (Settings > Support Embr with fixed US tip prices, the In-App Purchase review
screenshot), `settings` (`-screenshotSettingsPage <page>`), `following`, `moreapps`, and
`open -screenshotURL <url>`.
