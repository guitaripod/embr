#!/opt/homebrew/bin/python3
"""Capture the raw screens behind Embr's App Store panels, in every app language, from the demo world.

`-embrDemo` runs the DEBUG build against an invented, offline Twitch: fictional channels, procedural
stream art and scripted chat, so every capture is the same each run, safe to publish and free of
strangers' messages. Each screen is posed by launch arguments (`App/ScreenshotRouter.swift`), so
nothing is tapped. The simulator is launched once per screen in the target language, given time to
settle, and photographed; a capture of the wrong size or a blank screen is retaken once and then
fails the run.

iPad captures are portrait. An app that turns its own window to landscape lands in iPadOS's windowed
mode on the simulator, wallpaper and Dock around it, so the iPad runs a copy of the build marked
UIRequiresFullScreen and stays upright.

Output: marketing/raw/<device>/<language>/<shot>.png, opaque RGB, for scripts/store-panels.py.

Usage:
  scripts/capture-store-panels.py --sim <udid> --app <Debug-iphonesimulator/Embr.app>
      [--device iphone|ipad] [--languages en,de] [--shot channel]
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "marketing" / "raw"
BUNDLE = "com.guitaripod.embr"
LANGUAGES = {"en": "en_US", "de": "de_DE", "es": "es_ES", "fr": "fr_FR", "it": "it_IT", "ja": "ja_JP", "ko": "ko_KR",
             "pl": "pl_PL", "pt-BR": "pt_BR", "zh-Hans": "zh_CN", "zh-Hant": "zh_TW"}
COMMON = ["-embrDemo", "-screenshotTheme", "dark", "-screenshotAuth", "1"]
STATUS_BAR = ["--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
              "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100",
              "--operatorName", ""]

PHONE = [
    ("channel", ["-screenshotRoute", "channel", "-screenshotChannel", "lumenfox"], 8),
    ("chats-emotes", ["-screenshotRoute", "chats", "-screenshotSheet", "emotes"], 12),
    ("chats", ["-screenshotRoute", "chats"], 11),
    ("fullchat", ["-screenshotRoute", "channelfullchat", "-screenshotChannel", "lumenfox"], 10),
    ("mentions", ["-screenshotRoute", "chats", "-screenshotSheet", "mentions"], 13),
    ("usercard", ["-screenshotRoute", "usercard", "-screenshotChannel", "lumenfox", "-screenshotModerator", "1"], 9),
    ("favorites", ["-screenshotRoute", "favorites"], 6),
    ("audio", ["-screenshotRoute", "channelaudio", "-screenshotChannel", "quietmoth"], 8),
    ("moderate", ["-screenshotRoute", "modqueue", "-screenshotChannel", "lumenfox", "-screenshotModerator", "1"], 9),
    ("supporter", ["-screenshotRoute", "supporter"], 6),
]
TABLET = [(name, arguments, wait + 2) for name, arguments, wait in PHONE if name != "fullchat"]
SIZES = {"iphone": {(1320, 2868), (2868, 1320)}, "ipad": {(2064, 2752)}}


def simctl(*arguments, check=True, timeout=120):
    return subprocess.run(["xcrun", "simctl", *arguments], capture_output=True, text=True, check=check, timeout=timeout)


def full_screen_copy(app, scratch):
    """A copy of the build marked UIRequiresFullScreen, the only kind of iPad app that may turn its own window."""
    copy = Path(scratch) / "Embr.app"
    shutil.copytree(app, copy, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Add :UIRequiresFullScreen bool true", str(copy / "Info.plist")],
                   check=True, capture_output=True)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(copy)], check=True, capture_output=True)
    return copy


def blank(image):
    """True for a capture that is one colour, the simulator's answer while a scene is not drawn yet."""
    pixels = np.asarray(image.convert("L").resize((200, 400)), dtype=np.float32)
    return float(pixels.std()) < 6


def shoot(sim, device, language, name, arguments, wait, folder):
    region = LANGUAGES[language]
    target = folder / f"{name}.png"
    for attempt in range(2):
        simctl("terminate", sim, BUNDLE, check=False)
        time.sleep(1)
        simctl("launch", sim, BUNDLE, *COMMON, "-AppleLanguages", f"({language})", "-AppleLocale", region, *arguments)
        time.sleep(wait + attempt * 4)
        with tempfile.TemporaryDirectory() as scratch:
            path = Path(scratch) / "shot.png"
            simctl("io", sim, "screenshot", str(path))
            image = Image.open(path).convert("RGB")
        if image.size in SIZES[device] and not blank(image):
            image.save(target)
            return
        print(f"  retaking {language}/{name}: {image.size}{' blank' if blank(image) else ''}")
    sys.exit(f"capture failed: {device} {language} {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sim", required=True)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--device", choices=["iphone", "ipad"], default="iphone")
    parser.add_argument("--languages", default=",".join(LANGUAGES))
    parser.add_argument("--shot", action="append")
    args = parser.parse_args()
    shots = PHONE if args.device == "iphone" else TABLET
    simctl("boot", args.sim, check=False)
    simctl("bootstatus", args.sim, "-b", timeout=600)
    simctl("status_bar", args.sim, "override", *STATUS_BAR)
    with tempfile.TemporaryDirectory() as scratch:
        app = full_screen_copy(args.app, scratch) if args.device == "ipad" else args.app
        simctl("install", args.sim, str(app))
        for language in args.languages.split(","):
            folder = RAW / args.device / language
            folder.mkdir(parents=True, exist_ok=True)
            for name, arguments, wait in shots:
                if args.shot and name not in args.shot:
                    continue
                shoot(args.sim, args.device, language, name, arguments, wait, folder)
            print(f"{args.device} {language}: done")
    simctl("terminate", args.sim, BUNDLE, check=False)


if __name__ == "__main__":
    main()
