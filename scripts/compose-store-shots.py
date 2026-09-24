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

iPad panels (--device ipad) are landscape, 2752x2064, from marketing/raw-ipad into
marketing/panels-ipad. The capture floats whole below a one-line headline where the headline
fits on one line. The simulator shows the player black, so the hero and chat captures have the
stream's preview frame, saved alongside at capture time, laid into the black of the player.

Usage:  scripts/compose-store-shots.py [--locale ja] [--device ipad]
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
PAD_PANELS = PANELS[:-1]
GRADIENT = [(0.0, (0x6A, 0x32, 0xC8)), (0.32, (0x3C, 0x23, 0x74)), (0.62, (0x1E, 0x14, 0x40)),
            (1.0, (0x14, 0x0E, 0x26))]
HEADLINE_SIZE = 96
LINE_STEP = 116
FIRST_LINE_TOP = 213
DEVICE_WIDTH = 1096
DEVICE_TOP = 470
DEVICE_RADIUS = 52
HERO_REPAINT_END = 540


class Geometry:
    """Canvas and framing for one device family. The phone values are the listing's original
    framing and stay exactly as they were; the iPad values scale the same look to a landscape
    13" panel, where a headline may sit on one line and the capture then moves up to meet it."""

    def __init__(self, width, height, headline_size, line_step, first_line_top, device_width,
                 device_top, device_radius, adaptive):
        self.width, self.height = width, height
        self.headline_size, self.line_step, self.first_line_top = headline_size, line_step, first_line_top
        self.device_width, self.device_top, self.device_radius = device_width, device_top, device_radius
        self.adaptive = adaptive


PHONE = Geometry(W, H, HEADLINE_SIZE, LINE_STEP, FIRST_LINE_TOP, DEVICE_WIDTH, DEVICE_TOP,
                 DEVICE_RADIUS, adaptive=False)
PAD = Geometry(2752, 2064, 104, 124, 150, 2300, 330, 44, adaptive=True)


def gradient_color(y, height=H):
    t = y / (height - 1)
    for (t0, c0), (t1, c1) in zip(GRADIENT, GRADIENT[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return GRADIENT[-1][1]


def background(geometry=PHONE):
    column = Image.new("RGB", (1, geometry.height))
    for y in range(geometry.height):
        column.putpixel((0, y), gradient_color(y, geometry.height))
    return column.resize((geometry.width, geometry.height))


def render_line(text, language="en", size=HEADLINE_SIZE):
    """One headline line through AppKit, cropped to its inked pixels, with the ink's offset from
    the drawing origin so lines in any script share baselines. The language attribute picks the
    right Han forms: the same character is drawn differently for zh-Hans, zh-Hant and ja."""
    font = AppKit.NSFont.systemFontOfSize_weight_(size, AppKit.NSFontWeightBold)
    attributes = {
        AppKit.NSFontAttributeName: font,
        AppKit.NSForegroundColorAttributeName: AppKit.NSColor.whiteColor(),
        "NSLanguage": language,
    }
    string = Foundation.NSAttributedString.alloc().initWithString_attributes_(text, attributes)
    width, height = W * 3, size * 3
    rep = AppKit.NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
        None, width, height, 8, 4, True, False, AppKit.NSCalibratedRGBColorSpace, 0, 0)
    context = AppKit.NSGraphicsContext.graphicsContextWithBitmapImageRep_(rep)
    AppKit.NSGraphicsContext.saveGraphicsState()
    AppKit.NSGraphicsContext.setCurrentContext_(context)
    baseline = size * 2
    string.drawAtPoint_((size, height - baseline))
    context.flushGraphics()
    AppKit.NSGraphicsContext.restoreGraphicsState()
    png = rep.representationUsingType_properties_(AppKit.NSBitmapImageFileTypePNG, None)
    image = Image.open(io.BytesIO(bytes(png))).convert("RGBA")
    box = image.getchannel("A").getbbox()
    return image.crop(box), box[1] - baseline


def headline_offset(geometry=PHONE):
    """Where the ascender of a reference line lands relative to the baseline, so the first line's
    tallest letters meet the first line's top exactly as the original framing did."""
    _, top = render_line("Hl", size=geometry.headline_size)
    return geometry.first_line_top - top


def headline_lines(text, language, geometry):
    """The caption's own line breaks, except that the wide iPad panel joins them onto one line
    whenever the whole headline fits across it."""
    lines = text.split("\n")
    if geometry.adaptive and len(lines) > 1:
        joiner = "" if language in ("ja", "zh-Hans", "zh-Hant") else " "
        joined = joiner.join(line.strip() for line in lines)
        ink, _ = render_line(joined, language, geometry.headline_size)
        if ink.width <= geometry.width - 240:
            return [joined]
    return lines


def draw_headline(canvas, text, language, geometry=PHONE):
    baseline0 = headline_offset(geometry)
    lines = headline_lines(text, language, geometry)
    for index, line in enumerate(lines):
        ink, top = render_line(line, language, geometry.headline_size)
        scale = min(1.0, (geometry.width - 96) / ink.width)
        if scale < 1.0:
            ink = ink.resize((round(ink.width * scale), round(ink.height * scale)), Image.LANCZOS)
            top = round(top * scale)
        x = (geometry.width - ink.width) // 2
        y = baseline0 + index * geometry.line_step + top
        canvas.paste(ink, (x, y), ink)
    return len(lines)


def device(canvas, shot, geometry=PHONE, top=None):
    """The capture floated with rounded corners and a soft shadow. A capture that fits is shown
    whole with all four corners rounded; one that does not runs off the bottom edge."""
    top = geometry.device_top if top is None else top
    width, height, radius = geometry.device_width, geometry.height, geometry.device_radius
    scale = width / shot.width
    shot = shot.resize((width, round(shot.height * scale)), Image.LANCZOS)
    x = (geometry.width - width) // 2
    visible = min(shot.height, height - top)
    whole = geometry.adaptive and visible == shot.height
    bottom_extent = visible if whole else visible + radius

    shadow = Image.new("L", (geometry.width, height), 0)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, top + 24, x + width, top + 24 + bottom_extent], radius=radius, fill=round(255 * 0.45))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(Image.new("RGB", (geometry.width, height), (0, 0, 0)), (0, 0), shadow)

    mask = Image.new("L", (width, visible), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, bottom_extent - 1], radius=radius, fill=255)
    canvas.paste(shot.crop((0, 0, width, visible)), (x, top), mask)


def compose(raw_path, headline, language, geometry=PHONE, frame_path=None, frame_fills_window=False):
    canvas = background(geometry)
    shot = Image.open(raw_path).convert("RGB")
    if frame_path and os.path.exists(frame_path):
        shot = with_stream_frame(shot, Image.open(frame_path).convert("RGB"), frame_fills_window)
    top = geometry.device_top
    if geometry.adaptive:
        top += (len(headline_lines(headline, language, geometry)) - 1) * geometry.line_step
    device(canvas, shot, geometry, top)
    draw_headline(canvas, headline, language, geometry)
    return canvas


def with_stream_frame(shot, frame, fills_window):
    """Lays the stream's preview frame into the black of the simulator's player, where a device
    would show the stream playing. The player is the largest black region of the capture, or the
    whole window when the video is full screen; the frame is fitted to it at 16:9 and shows only
    where the capture is black, so the controls and any chat over the video stay on top."""
    black = shot.convert("L").point(lambda value: 255 if value < 6 else 0)
    if fills_window:
        box = (0, 0, shot.width, shot.height)
    else:
        box = black.crop((0, 0, round(shot.width * 0.8), shot.height)).getbbox()
        if box is None:
            return shot
    left, top, right, bottom = box
    width, height = right - left, bottom - top
    fitted_width = min(width, round(height * 16 / 9))
    fitted_height = round(fitted_width * 9 / 16)
    x = left + (width - fitted_width) // 2
    y = top + (height - fitted_height) // 2
    placed = Image.new("RGB", shot.size, (0, 0, 0))
    placed.paste(frame.resize((fitted_width, fitted_height), Image.LANCZOS), (x, y))
    region = Image.new("L", shot.size, 0)
    region.paste(255, (x, y, x + fitted_width, y + fitted_height))
    mask = ImageChops.multiply(black, region)
    result = shot.copy()
    result.paste(placed, (0, 0), mask)
    return result


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
    parser.add_argument("--device", choices=["iphone", "ipad"], default="iphone")
    args = parser.parse_args()
    ipad = args.device == "ipad"
    geometry = PAD if ipad else PHONE
    raw_root = os.path.join(ROOT, "marketing", "raw-ipad") if ipad else RAW
    out_root = os.path.join(ROOT, "marketing", "panels-ipad") if ipad else OUT
    book = json.load(open(CAPTIONS))
    for locale in [args.locale] if args.locale else sorted(book):
        language = locale.split("-")[0] if locale in ("en-US", "de-DE", "es-ES", "fr-FR") else locale
        folder = os.path.join(out_root, locale)
        os.makedirs(folder, exist_ok=True)
        made = 0
        for number, panel in enumerate(PAD_PANELS if ipad else PANELS, start=1):
            headline = book[locale][panel]
            if panel == "hero" and not ipad:
                image = compose_hero(headline, language)
            else:
                raw = os.path.join(raw_root, locale, f"{panel}.png")
                if not os.path.exists(raw):
                    print(f"{locale:8} missing raw {panel}")
                    continue
                frame = os.path.join(raw_root, locale, f"{panel}-frame.jpg") if panel in ("hero", "chat") else None
                image = compose(raw, headline, language, geometry, frame, frame_fills_window=panel == "chat")
            image.save(os.path.join(folder, f"{number:02d}-{panel}.png"), "PNG")
            made += 1
        print(f"{locale:8} {made} panels")


if __name__ == "__main__":
    main()
