#!/usr/bin/env python3
"""Capture Embr's raw App Store screens in every listing language on a 6.9" simulator.

The DEBUG build poses each screen from launch arguments (`SceneDelegate.handleScreenshotRoute`),
so nothing is tapped: the simulator is launched once per screen in the target language and
photographed after the live Twitch data has settled. The results feed
`scripts/compose-store-shots.py`.

The status bar is pinned to 9:41 with full bars. Each language starts from a fresh install, so
onboarding shows on the first plain launch and the Recently Watched row on Top holds only the
channels this run opened; that is why Top is shot after the two channel screens.

Live content is whatever Twitch is showing at capture time, so look at every chat capture
before shipping it: chat is written by strangers.

Usage:
  scripts/capture-store-shots.py --sim <udid> --app <Debug-iphonesimulator/Embr.app>
      [--langs de-DE,ja] [--out marketing/raw]
      [--chat-channel dougdoug] [--audio-channel ironmouse] [--favorites a,b,c] [--skip login]
"""
import argparse
import os
import signal
import subprocess
import time

BUNDLE = "com.guitaripod.embr"
CORE_SIMCTL = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LOCALES = {
    "en-US": ("en", "en_US"), "de-DE": ("de", "de_DE"), "es-ES": ("es", "es_ES"),
    "fr-FR": ("fr", "fr_FR"), "it": ("it", "it_IT"), "ja": ("ja", "ja_JP"),
    "ko": ("ko", "ko_KR"), "pt-BR": ("pt-BR", "pt_BR"), "zh-Hans": ("zh-Hans", "zh_CN"),
    "zh-Hant": ("zh-Hant", "zh_TW"),
}

STATUS_BAR = ["--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
              "--cellularBars", "4", "--wifiBars", "3", "--dataNetwork", "wifi"]


def screens(args):
    """Panel name, launch arguments and settle time, in capture order."""
    return [
        ("favorites", ["-screenshotRoute", "favorites", "-screenshotFavorites", args.favorites], 12),
        ("chat", ["-screenshotRoute", "channelchat", "-screenshotChannel", args.chat_channel], 16),
        ("audio", ["-screenshotRoute", "channelaudio", "-screenshotChannel", args.audio_channel], 12),
        ("top", ["-screenshotRoute", "top", "-screenshotSkip", args.skip], 12),
        ("categories", ["-screenshotRoute", "categories"], 9),
        ("search", ["-screenshotRoute", "search", "-screenshotQuery", "Just Chatting"], 9),
        ("settings", ["-screenshotRoute", "settings"], 6),
    ]


def simctl_command():
    """Xcode's `simctl` is a shell wrapper that re-runs `xcodebuild -runFirstLaunch` whenever the
    installed CoreSimulator is older than the Xcode expects — on a beta Xcode that is every call,
    about 25 seconds each. The CoreSimulator binary it forwards to answers in a tenth of that."""
    return [CORE_SIMCTL] if os.path.exists(CORE_SIMCTL) else ["xcrun", "simctl"]


def simctl(*arguments, timeout=90):
    """Runs one simctl command in its own process group and returns whether it succeeded.

    `simctl` calls on this host sometimes never return. Xcode's `simctl` is a wrapper script
    whose real tool is a grandchild, so a plain timeout kills the wrapper and then waits forever
    on output pipes the orphan still holds; killing the whole group avoids both hangs."""
    process = subprocess.Popen([*simctl_command(), *arguments], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        return False
    return process.returncode == 0


def launch(sim, language, region, extra):
    simctl("launch", "--terminate-running-process", sim, BUNDLE,
           "-AppleLanguages", f"({language})", "-AppleLocale", region, *extra)


def shoot(sim, path):
    for _ in range(4):
        if os.path.exists(path):
            os.remove(path)
        if simctl("io", sim, "screenshot", "--type=png", path, timeout=60) and os.path.getsize(path) > 0:
            return True
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--langs", default=",".join(LOCALES))
    parser.add_argument("--out", default=os.path.join(ROOT, "marketing", "raw"))
    parser.add_argument("--chat-channel", default="dougdoug")
    parser.add_argument("--audio-channel", default="happyhappygal")
    parser.add_argument("--favorites", default="dougdoug,ludwig,ironmouse,k3soju,pokimane,tarik,caedrel")
    parser.add_argument("--only", help="comma-separated panel names to (re)capture")
    parser.add_argument("--skip", default="", help="channels to keep off Top, e.g. one streaming a black screen")
    args = parser.parse_args()

    simctl("status_bar", args.sim, "override", *STATUS_BAR)
    wanted = set(args.only.split(",")) if args.only else None
    for locale in args.langs.split(","):
        language, region = LOCALES[locale]
        folder = os.path.join(args.out, locale)
        os.makedirs(folder, exist_ok=True)
        simctl("uninstall", args.sim, BUNDLE)
        simctl("install", args.sim, args.app, timeout=180)
        if wanted is None or "onboarding" in wanted:
            launch(args.sim, language, region, [])
            time.sleep(6)
            ok = shoot(args.sim, os.path.join(folder, "onboarding.png"))
            print(f"{locale:8} onboarding {'ok' if ok else 'FAILED'}", flush=True)
        for name, extra, settle in screens(args):
            if wanted is not None and name not in wanted:
                continue
            launch(args.sim, language, region, extra)
            time.sleep(settle)
            ok = shoot(args.sim, os.path.join(folder, f"{name}.png"))
            print(f"{locale:8} {name:10} {'ok' if ok else 'FAILED'}", flush=True)
    simctl("terminate", args.sim, BUNDLE)


if __name__ == "__main__":
    main()
