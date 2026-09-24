#!/opt/homebrew/bin/python3
"""Compose Embr's App Store panels from raw captures, in every listing language.

Each panel keeps the style the listing launched with: a violet-to-night gradient, a bold centred
headline of at most two lines, and the capture floated below it with rounded top corners,
running off the bottom. Headlines come from metadata/screenshot-captions.json and are drawn
through AppKit, so kana, hangul and han fall back to the system's own faces.

The hero panel (a live stream playing beside chat) cannot be captured on a simulator, which does
not decode live video. It is the device-captured panel already on the store (marketing/hero.png),
reused with only its headline repainted: every row above the device is refilled with that row's
own background colour, sampled at the panel's left edge, so the repaint leaves no seam.

Raw captures: marketing/raw/<locale>/<panel>.png from scripts/capture-store-shots.py
Panels:       marketing/panels/<locale>/NN-<panel>.png, 1320x2868 sRGB without alpha

Usage:  scripts/compose-store-shots.py [--locale ja]
"""
import argparse
import io
import json
import math
import os

import AppKit
import Foundation
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTIONS = os.path.join(ROOT, "metadata", "screenshot-captions.json")
RAW = os.path.join(ROOT, "marketing", "raw")
OUT = os.path.join(ROOT, "marketing", "panels")
HERO = os.path.join(ROOT, "marketing", "hero.png")

W, H = 1320, 2868
PANELS = ["hero", "favorites", "top", "chat", "audio", "categories", "search", "settings", "onboarding"]
GRADIENT = [(0.0, (0x6A, 0x32, 0xC8)), (0.32, (0x3C, 0x23, 0x74)), (0.62, (0x1E, 0x14, 0x40)),
            (1.0, (0x14, 0x0E, 0x26))]
HEADLINE_SIZE = 96
LINE_STEP = 116
FIRST_LINE_TOP = 213
DEVICE_WIDTH = 1096
DEVICE_TOP = 470
DEVICE_RADIUS = 52
HERO_REPAINT_END = 540


def gradient_color(y):
    t = y / (H - 1)
    for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return GRADIENT[-1][1]


def background():
    column = Image.new("RGB", (1, H))
    for y in range(H):
        column.putpixel((0, y), gradient_color(y))
    return column.resize((W, H))


def render_line(text, language="en"):
    """One headline line through AppKit, cropped to its inked pixels, with the ink's offset from
    the drawing origin so lines in any script share baselines. The language attribute picks the
    right Han forms: the same character is drawn differently for zh-Hans, zh-Hant and ja."""
    font = AppKit.NSFont.systemFontOfSize_weight_(HEADLINE_SIZE, AppKit.NSFontWeightBold)
    attributes = {
        AppKit.NSFontAttributeName: font,
        AppKit.NSForegroundColorAttributeName: AppKit.NSColor.whiteColor(),
        "NSLanguage": language,
    }
    string = Foundation.NSAttributedString.alloc().initWithString_attributes_(text, attributes)
    width, height = W * 2, HEADLINE_SIZE * 3
    rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, width, height, 8, 4, True, False, AppKit.NSCalibratedRGBColorSpace, 0, 0)
    context = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(context)
    baseline = HEADLINE_SIZE * 2
    string.drawAtPoint_((HEADLINE_SIZE, height - baseline))
    context.flushGraphics()
    AppKit.NSGraphicsContext.restoreGraphicsState()
    png = rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    image = Image.open(io.BytesIO(bytes(png))).convert("RGBA")
    box = image.getchannel("A").getbbox()
    return image.crop(box), box[1] - baseline


def headline_offset():
    """Where the ascender of a reference line lands relative to the baseline, so the first line's
    tallest letters meet FIRST_LINE_TOP exactly as the original framing did."""
    _, top = render_line("Hl")
    return FIRST_LINE_TOP - top


def draw_headline(canvas, text, language):
    baseline0 = headline_offset()
    for index, line in enumerate(text.split("\n")):
        ink, top = render_line(line, language)
        scale = min(1.0, (W - 96) / ink.width)
        if scale < 1.0:
            ink = ink.resize((round(ink.width * scale), round(ink.height * scale)), Image.LANCZOS)
            top = round(top * scale)
        x = (W - ink.width) // 2
        y = baseline0 + index * LINE_STEP + top
        canvas.paste(ink, (x, y), ink)


def device(canvas, shot):
    scale = DEVICE_WIDTH / shot.width
    shot = shot.resize((DEVICE_WIDTH, round(shot.height * scale)), Image.LANCZOS)
    x = (W - DEVICE_WIDTH) // 2
    visible = min(shot.height, H - DEVICE_TOP)

    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, DEVICE_TOP + 24, x + DEVICE_WIDTH, DEVICE_TOP + 24 + visible + DEVICE_RADIUS],
        radius=DEVICE_RADIUS, fill=round(255 * 0.45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), shadow)

    mask = Image.new("L", (DEVICE_WIDTH, visible), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, DEVICE_WIDTH - 1, visible + DEVICE_RADIUS], radius=DEVICE_RADIUS, fill=255)
    canvas.paste(shot.crop((0, 0, DEVICE_WIDTH, visible)), (x, DEVICE_TOP), mask)


def compose(raw_path, headline, language):
    canvas = background()
    device(canvas, Image.open(raw_path).convert("RGB"))
    draw_headline(canvas, headline, language)
    return canvas


def compose_hero(headline, language):
    """Clears the old headline by keeping, per pixel, the darker of the original and that row's
    background colour: text is lighter than the background, the device's shadow darker, so the
    words go and the shadow stays."""
    canvas = Image.open(HERO).convert("RGB")
    band = canvas.crop((0, 0, W, HERO_REPAINT_END))
    rows = Image.new("RGB", (1, HERO_REPAINT_END))
    for y in range(HERO_REPAINT_END):
        rows.putpixel((0, y), canvas.getpixel((10, y)))
    canvas.paste(ImageChops.darker(band, rows.resize((W, HERO_REPAINT_END))), (0, 0))
    draw_headline(canvas, headline, language)
    return canvas


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--locale")
    args = parser.parse_args()
    book = json.load(open(CAPTIONS))
    for locale in [args.locale] if args.locale else sorted(book):
        language = locale.split("-")[0] if locale in ("en-US", "de-DE", "es-ES", "fr-FR") else locale
        folder = os.path.join(OUT, locale)
        os.makedirs(folder, exist_ok=True)
        made = 0
        for number, panel in enumerate(PANELS, start=1):
            headline = book[locale][panel]
            if panel == "hero":
                image = compose_hero(headline, language)
            else:
                raw = os.path.join(RAW, locale, f"{panel}.png")
                if not os.path.exists(raw):
                    print(f"{locale:8} missing raw {panel}")
                    continue
                image = compose(raw, headline, language)
            image.save(os.path.join(folder, f"{number:02d}-{panel}.png"), "PNG")
            made += 1
        print(f"{locale:8} {made} panels")


if __name__ == "__main__":
    main()
