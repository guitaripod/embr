# App Store screenshots

Screenshots are captured from the running app on a 6.9" simulator (iPhone 17 Pro Max,
1320×2868), then framed with a headline + gradient for the App Store and landing page.

## Capture (tap-free, deterministic)

A DEBUG-only harness (`Embr/App/ScreenshotHarness.swift`, wired through
`SceneDelegate.handleScreenshotRoute`) poses each screen from launch arguments, so no
UI automation is needed. Build the Debug app onto the simulator, then launch per shot:

```bash
SIM=<6.9" simulator udid>; B=com.guitaripod.embr
xcrun simctl status_bar $SIM override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3
xcrun simctl launch $SIM $B -screenshotRoute top
xcrun simctl launch $SIM $B -screenshotRoute categories
xcrun simctl launch $SIM $B -screenshotRoute search   -screenshotQuery "Just Chatting"
xcrun simctl launch $SIM $B -screenshotRoute following
xcrun simctl launch $SIM $B -screenshotRoute channel      -screenshotChannel <live-login>
xcrun simctl launch $SIM $B -screenshotRoute channelaudio  -screenshotChannel <live-login>
xcrun simctl launch $SIM $B -screenshotRoute channelchat   -screenshotChannel <live-login>
xcrun simctl launch $SIM $B -screenshotRoute settings -screenshotTheme dark
# onboarding: fresh install, launch with no route
xcrun simctl io $SIM screenshot <name>.png
```

Data is live from the Twitch API, so pick a currently-live channel with busy chat.
Note: the simulator does not decode the live video layer — capture the video-forward
"watch" hero on a physical device.

## Frame

`scripts/frame-shots.mjs` composites the raw captures into the store style (purple
gradient, headline, rounded device). It uses the `canvas` module from a sibling Node
project; adjust the paths at the top of the script for your machine.
