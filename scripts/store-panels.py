#!/opt/homebrew/bin/python3
"""Compose Embr's App Store panels for iPhone, iPad and iPhone Duo in every listing language.

Each panel is a dark night with ember and violet light drifting across the whole set, so the panels
read as one continuous strip when the App Store scrolls them; a two-line headline whose second line
glows in Embr's ember gradient, a short line under it, and the capture in its real device frame
(drawn by the `frames` CLI), sometimes with one part of the screen lifted out and enlarged beside it.

Raw captures come from scripts/capture-store-panels.py into marketing/raw/<device>/<ui>/<shot>.png,
one set per app language; listing languages the app does not speak use the English captures with
their own captions. Captions live in marketing/captions.json as two title lines, the index of the
line that glows, and the line under it.

Output: store/shots/<device>/<locale>/NN-<panel>.png, opaque sRGB at the store sizes, which
`midgar shots embr --train ios` uploads; the Header and Search Results image goes to
store/creative/<locale>/header.png.

Usage:  scripts/store-panels.py [--device iphone|ipad|duo] [--locale ja] [--panel watch] [--out DIR]
"""
import argparse
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CAPTIONS = ROOT / "marketing" / "captions.json"
RAW = ROOT / "marketing" / "raw"
FRAMED = ROOT / "marketing" / "framed"
SHOTS = ROOT / "store" / "shots"
CREATIVE = ROOT / "store" / "creative"
ICON = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

LOCALES = ["en-US", "en-AU", "en-GB", "ar-SA", "de-DE", "es-ES", "es-MX", "fr-FR", "id", "it", "ja", "ko",
           "pl", "pt-BR", "ru", "th", "tr", "vi", "zh-Hans", "zh-Hant"]
UI_LANGUAGE = {"de-DE": "de", "es-ES": "es", "es-MX": "es", "fr-FR": "fr", "it": "it", "ja": "ja", "ko": "ko",
               "pl": "pl", "pt-BR": "pt-BR", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant"}

NIGHT_TOP = np.array([14, 9, 24], dtype=np.float32)
NIGHT_BOTTOM = np.array([6, 4, 11], dtype=np.float32)
EMBER = [(0.0, (255, 138, 61)), (0.5, (255, 79, 135)), (1.0, (176, 112, 255))]
VIOLET = (145, 71, 255)
ORANGE = (255, 106, 42)
MAGENTA = (232, 62, 140)

SF = "/System/Library/Fonts/SFNS.ttf"
FONTS = {
    "ja": (("/System/Library/Fonts/ヒラギノ角ゴシック W8.ttc", 0), ("/System/Library/Fonts/ヒラギノ角ゴシック W5.ttc", 0)),
    "ko": (("/System/Library/Fonts/AppleSDGothicNeo.ttc", 16), ("/System/Library/Fonts/AppleSDGothicNeo.ttc", 2)),
    "zh-Hans": (("/System/Library/Fonts/Hiragino Sans GB.ttc", 2), ("/System/Library/Fonts/Hiragino Sans GB.ttc", 0)),
    "zh-Hant": (("/System/Library/Fonts/STHeiti Medium.ttc", 0), ("/System/Library/Fonts/STHeiti Medium.ttc", 0)),
    "th": (("/System/Library/Fonts/Supplemental/SukhumvitSet.ttc", 5), ("/System/Library/Fonts/Supplemental/SukhumvitSet.ttc", 2)),
    "ar-SA": (("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0), ("/System/Library/Fonts/Supplemental/Arial.ttf", 0)),
}


@dataclass
class Callout:
    """A part of the capture lifted out and enlarged: `crop` in capture pixels, `width` and `center` as
    fractions of the canvas."""

    crop: tuple
    width: float
    center: tuple


@dataclass
class Panel:
    """One store panel: which capture it shows, how the device sits, and an optional callout."""

    key: str
    shot: str
    layout: str = "portrait"
    callout: "Callout | None" = None
    caption: "str | None" = None
    brand: bool = False
    canvas: "Canvas | None" = None



@dataclass
class Canvas:
    width: int
    height: int
    margin: int
    title_size: int
    sub_size: int
    title_top: int
    device_width: float
    landscape_width: float = 0.94
    glows: list = field(default_factory=list)


IPHONE = Canvas(1320, 2868, 64, 166, 56, 200, 0.84)
IPAD = Canvas(2064, 2752, 100, 196, 66, 210, 0.80)

IPHONE_PANELS = [
    Panel("watch", "channel", brand=True),
    Panel("emotes", "chats-emotes", callout=Callout((0, 1850, 1320, 300), 0.95, (0.5, 0.72))),
    Panel("chats", "chats", callout=Callout((0, 385, 1320, 95), 0.97, (0.5, 0.43))),
    Panel("fullscreen", "fullchat", layout="turned", callout=Callout((1712, 40, 1000, 1150), 0.7, (0.5, 0.775))),
    Panel("mentions", "mentions"),
    Panel("usercard", "usercard", callout=Callout((30, 1880, 1260, 240), 0.95, (0.5, 0.80))),
    Panel("favorites", "favorites"),
    Panel("audio", "audio", callout=Callout((0, 335, 1320, 120), 0.97, (0.5, 0.47))),
    Panel("moderate", "moderate", callout=Callout((40, 1660, 1240, 560), 0.93, (0.5, 0.76))),
    Panel("supporter", "supporter"),
]

DUO_INNER_LANDSCAPE = Canvas(2853, 2007, 130, 150, 56, 110, 0.80, landscape_width=0.86)
DUO_INNER_PORTRAIT = Canvas(2007, 2853, 90, 210, 72, 210, 0.86)
DUO_OUTER_PORTRAIT = Canvas(1398, 2034, 60, 136, 48, 140, 0.80)

DUO_PANELS = [
    Panel("watch", "channel__inner-landscape", layout="landscape", canvas=DUO_INNER_LANDSCAPE, brand=True),
    Panel("chats", "chats__inner-landscape", layout="landscape", canvas=DUO_INNER_LANDSCAPE),
    Panel("moderate", "moderate__book-landscape", layout="landscape", canvas=DUO_INNER_LANDSCAPE),
    Panel("emotes", "chats-emotes__inner-portrait", canvas=DUO_INNER_PORTRAIT),
    Panel("mentions", "mentions__inner-portrait", canvas=DUO_INNER_PORTRAIT),
    Panel("usercard", "usercard__laptop-portrait", canvas=DUO_INNER_PORTRAIT),
    Panel("favorites", "favorites__inner-portrait", canvas=DUO_INNER_PORTRAIT),
    Panel("audio", "audio__outer-portrait", canvas=DUO_OUTER_PORTRAIT),
    Panel("supporter", "supporter__outer-portrait", canvas=DUO_OUTER_PORTRAIT),
]

FRAME_COLORS = {"iphone": "Black", "ipad": "default", "duo": "Night Sky"}

IPAD_PANELS = [
    Panel("watch", "channel", brand=True),
    Panel("sidebyside", "chats"),
    Panel("emotes", "chats-emotes"),
    Panel("mentions", "mentions"),
    Panel("usercard", "usercard"),
    Panel("favorites", "favorites"),
    Panel("audio", "audio"),
    Panel("moderate", "moderate"),
    Panel("supporter", "supporter"),
]


def captions():
    with open(CAPTIONS, encoding="utf-8") as handle:
        return json.load(handle)


def for_device(caption, device):
    """A caption names the iPhone, which every language keeps in Latin letters; on iPad panels it names the iPad."""
    if device != "ipad":
        return caption
    return {**caption, "sub": caption["sub"].replace("iPhone", "iPad")}


def caption_for(locale, key, table):
    """The panel's caption in the locale, falling back to English for a locale not translated yet."""
    entry = table.get(locale, {}).get(key) or table["en-US"][key]
    return entry


def fonts(locale, title_size, sub_size):
    """The headline and body faces for a locale: SF Pro for Latin and Cyrillic scripts, the system's own
    faces for Japanese, Korean, Chinese and Thai, and Arial for Arabic, the one face on the system that also
    carries the Latin names (iPhone, 7TV) an Arabic caption keeps."""
    if locale in FONTS:
        (title_path, title_face), (sub_path, sub_face) = FONTS[locale]
        return load(title_path, title_face, title_size), load(sub_path, sub_face, sub_size)
    title = ImageFont.truetype(SF, title_size, layout_engine=ImageFont.Layout.RAQM)
    title.set_variation_by_axes([100, 96, 400, 860])
    sub = ImageFont.truetype(SF, sub_size, layout_engine=ImageFont.Layout.RAQM)
    sub.set_variation_by_axes([100, 28, 400, 520])
    return title, sub


def load(path, face, size):
    if isinstance(face, str):
        font = ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)
        font.set_variation_by_name(face)
        return font
    return ImageFont.truetype(path, size, index=face, layout_engine=ImageFont.Layout.RAQM)


def strip_glows(count, width, height):
    """Light that drifts across the whole strip of panels, so neighbours share their glows at the seams."""
    lights = []
    colors = [VIOLET, ORANGE, MAGENTA, VIOLET, ORANGE]
    for index in range(count * 2 + 2):
        x = (index - 0.5) * width * 0.52
        y = height * (0.16 if index % 2 == 0 else 0.62) + (index % 3) * height * 0.07
        radius = width * (0.62 if index % 2 == 0 else 0.78)
        strength = 0.55 if index % 2 == 0 else 0.42
        lights.append((x, y, radius, colors[index % len(colors)], strength))
    return lights


def background(canvas, index, lights, seed):
    """The panel's slice of the night strip: a vertical gradient, the glows that reach it, and fine grain."""
    width, height = canvas.width, canvas.height
    scale = 4
    small_w, small_h = width // scale, height // scale
    ys, xs = np.mgrid[0:small_h, 0:small_w].astype(np.float32)
    xs = xs * scale + index * width
    ys = ys * scale
    t = (ys / height)[..., None]
    image = NIGHT_TOP * (1 - t) + NIGHT_BOTTOM * t
    for gx, gy, radius, color, strength in lights:
        d2 = ((xs - gx) ** 2 + (ys - gy) ** 2) / (radius * radius)
        falloff = np.exp(-d2 * 2.2)[..., None]
        image = image + np.array(color, dtype=np.float32) * strength * falloff * 0.55
    image = np.clip(image, 0, 255).astype(np.uint8)
    picture = Image.fromarray(image, "RGB").resize((width, height), Image.BICUBIC)
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, 2.4, (height, width, 1)).astype(np.float32)
    noisy = np.clip(np.asarray(picture, dtype=np.float32) + grain, 0, 255).astype(np.uint8)
    return Image.fromarray(noisy, "RGB").convert("RGBA")


def gradient_fill(size):
    """A horizontal ember gradient the size of one headline line."""
    width, height = size
    ramp = np.linspace(0, 1, max(width, 2), dtype=np.float32)
    row = np.zeros((len(ramp), 3), dtype=np.float32)
    for (start, a), (end, b) in zip(EMBER, EMBER[1:]):
        mask = (ramp >= start) & (ramp <= end)
        local = ((ramp[mask] - start) / (end - start))[:, None]
        row[mask] = np.array(a) * (1 - local) + np.array(b) * local
    block = np.repeat(row[None, :, :], max(height, 1), axis=0).astype(np.uint8)
    return Image.fromarray(block, "RGB")


def line_image(text, font, accent):
    """One headline line as an RGBA image, white or filled with the ember gradient."""
    left, top, right, bottom = font.getbbox(text)
    width, height = right - left + 8, bottom - top + 8
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).text((4 - left, 4 - top), text, font=font, fill=255)
    if accent:
        fill = gradient_fill((width, height)).convert("RGBA")
    else:
        fill = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    fill.putalpha(mask)
    return fill, top


def fit_title(lines, locale, canvas, max_width):
    """The largest headline size, down to two thirds of the design size, at which every line fits."""
    size = canvas.title_size
    while size > canvas.title_size * 0.62:
        title, _ = fonts(locale, size, canvas.sub_size)
        if all(title.getlength(line) <= max_width for line in lines):
            return title, size
        size -= 4
    return fonts(locale, size, canvas.sub_size)[0], size


CJK = ("ja", "zh-Hans", "zh-Hant")
NO_LINE_START = set("。、，．,.!?！？）」』】〕ー・：；%")


def tokens(text):
    """Text cut where a line may break: Latin words and numbers stay whole, every other character stands alone."""
    pieces, word = [], ""
    for character in text:
        if character.isascii() and (character.isalnum() or character in "-'"):
            word += character
            continue
        if word:
            pieces.append(word)
            word = ""
        pieces.append(character)
    if word:
        pieces.append(word)
    return pieces


def wrap(text, font, max_width, locale):
    """Lines of at most `max_width`, broken at spaces, or for Chinese and Japanese between characters,
    never inside a Latin word and never starting a line with closing punctuation or a long-vowel mark. Korean
    breaks at spaces like the Latin scripts."""
    if locale not in CJK:
        words, lines, current = text.split(), [], ""
        for word in words:
            candidate = word if not current else current + " " + word
            if font.getlength(candidate) <= max_width:
                current = candidate
            else:
                if current:
                    lines.append(current)
                current = word
        if current:
            lines.append(current)
        return lines
    lines, current = [], ""
    for piece in tokens(text):
        if font.getlength(current + piece) <= max_width or not current:
            current += piece
            continue
        if piece[0] in NO_LINE_START and len(current) > 1:
            lines.append(current[:-1])
            current = current[-1] + piece
        else:
            lines.append(current.rstrip())
            current = piece.lstrip()
    if current:
        lines.append(current)
    return lines


def balanced_cjk(text, font, max_width):
    """Two lines of nearly equal width for a Chinese or Japanese line that needs two."""
    pieces = tokens(text)
    best = None
    for cut in range(1, len(pieces)):
        first, second = "".join(pieces[:cut]).rstrip(), "".join(pieces[cut:]).lstrip()
        if not second or second[0] in NO_LINE_START:
            continue
        widths = (font.getlength(first), font.getlength(second))
        if max(widths) > max_width:
            continue
        score = abs(widths[0] - widths[1])
        if best is None or score < best[0]:
            best = (score, [first, second])
    return best[1] if best else None


def balanced_sub(text, locale, canvas, max_width):
    """The line under the headline in at most two balanced lines, shrinking the size when it would need three."""
    size = canvas.sub_size
    while True:
        _, sub = fonts(locale, canvas.title_size, size)
        lines = wrap(text, sub, max_width, locale)
        if len(lines) <= 2 or size <= canvas.sub_size * 0.72:
            break
        size -= 2
    if len(lines) == 2 and locale in CJK:
        lines = balanced_cjk(text, sub, max_width) or lines
    elif len(lines) == 2:
        words = text.split()
        best = None
        for cut in range(1, len(words)):
            first, second = " ".join(words[:cut]), " ".join(words[cut:])
            widths = (sub.getlength(first), sub.getlength(second))
            if max(widths) > max_width:
                continue
            score = abs(widths[0] - widths[1])
            if best is None or score < best[0]:
                best = (score, [first, second])
        if best:
            lines = best[1]
    return sub, lines


def draw_brand(base, canvas, top):
    """Embr's icon and name above the first panel's headline, and where they end."""
    side = int(canvas.title_size * 0.86)
    icon = Image.open(ICON).convert("RGBA").resize((side, side), Image.LANCZOS)
    mask = Image.new("L", (side * 4, side * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side * 4 - 1, side * 4 - 1), int(side * 4 * 0.225), fill=255)
    icon.putalpha(mask.resize((side, side), Image.LANCZOS))
    name = ImageFont.truetype(SF, int(side * 0.62), layout_engine=ImageFont.Layout.RAQM)
    name.set_variation_by_axes([100, 96, 400, 760])
    label = "Embr"
    gap = int(side * 0.26)
    total = side + gap + int(name.getlength(label))
    x = (canvas.width - total) // 2
    base.alpha_composite(icon, (x, top))
    left, upper, right, lower = name.getbbox(label)
    ImageDraw.Draw(base).text((x + side + gap, top + (side - (lower - upper)) // 2 - upper), label, font=name, fill=(255, 255, 255, 235))
    return top + side + int(canvas.title_size * 0.42)


def headline_lines(caption, locale):
    """The two headline lines, without the full stop or comma a Chinese or Japanese line ends on, which in a
    centred headline only pushes the words off centre."""
    if locale in ("ja", "zh-Hans", "zh-Hant"):
        return [line.rstrip("。，、") for line in caption["title"]]
    return caption["title"]


def draw_text(base, caption, locale, canvas, top):
    """Paints the headline and the line under it centred from `top`, and returns where the text ends."""
    max_width = canvas.width - canvas.margin * 2
    lines = headline_lines(caption, locale)
    title, size = fit_title(lines, locale, canvas, max_width)
    y = top
    step = int(size * 1.08)
    for number, line in enumerate(lines):
        image, offset = line_image(line, title, number == caption.get("accent", 1))
        x = (canvas.width - image.width) // 2
        base.alpha_composite(image, (x, y + offset - 4))
        y += step
    sub, lines = balanced_sub(caption["sub"], locale, canvas, max_width * 0.9)
    y += int(canvas.sub_size * 0.62)
    draw = ImageDraw.Draw(base)
    for line in lines:
        width = sub.getlength(line)
        draw.text(((canvas.width - width) / 2, y), line, font=sub, fill=(255, 255, 255, 178))
        y += int(sub.size * 1.3)
    return y


def framed(raw, device, ui, shot, color):
    """The capture in its device frame, cached until the capture changes."""
    target = FRAMED / device / ui / f"{shot}.png"
    if target.exists() and target.stat().st_mtime >= raw.stat().st_mtime:
        return Image.open(target).convert("RGBA")
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        command = ["frames", "--json", "-c", color, "-o", scratch, str(raw)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"frames failed for {raw}: {result.stderr.strip()}")
        output = json.loads(result.stdout)["output"]
        Image.open(output).save(target)
    return Image.open(target).convert("RGBA")


def shadowed(base, device, position, halo):
    """Places the device with a soft shadow under it and a coloured halo around it."""
    alpha = device.split()[3]
    x, y = position
    pad = 160
    field_size = (device.width + pad * 2, device.height + pad * 2)
    shadow = Image.new("L", field_size, 0)
    shadow.paste(alpha, (pad, pad + 40))
    shadow = shadow.filter(ImageFilter.GaussianBlur(60))
    black = Image.new("RGBA", field_size, (0, 0, 0, 0))
    black.putalpha(shadow.point(lambda value: int(value * 0.7)))
    paste_clipped(base, black, (x - pad, y - pad))
    glow = Image.new("L", field_size, 0)
    glow.paste(alpha, (pad, pad))
    glow = glow.filter(ImageFilter.GaussianBlur(110))
    tint = Image.new("RGBA", field_size, halo + (0,))
    tint.putalpha(glow.point(lambda value: int(value * 0.38)))
    paste_clipped(base, tint, (x - pad, y - pad))
    paste_clipped(base, device, (x, y))


def paste_clipped(base, layer, position):
    """Alpha-composites a layer that may hang off the canvas."""
    x, y = position
    left, top = max(0, -x), max(0, -y)
    right = min(layer.width, base.width - x)
    bottom = min(layer.height, base.height - y)
    if right <= left or bottom <= top:
        return
    base.alpha_composite(layer.crop((left, top, right, bottom)), (x + left, y + top))


def callout_card(raw, callout, canvas):
    """A part of the capture, enlarged on a rounded glass card with a thin light edge and a deep shadow."""
    crop = raw.crop((callout.crop[0], callout.crop[1], callout.crop[0] + callout.crop[2], callout.crop[1] + callout.crop[3]))
    width = int(canvas.width * callout.width)
    height = int(crop.height * width / crop.width)
    card = crop.resize((width, height), Image.LANCZOS).convert("RGBA")
    radius = int(min(height, 120) * 0.42)
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius, fill=255)
    card.putalpha(mask)
    edge = Image.new("RGBA", card.size, (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((1, 1, width - 2, height - 2), radius, outline=(255, 255, 255, 70), width=3)
    card.alpha_composite(edge)
    return card


def place_callout(base, card, callout, canvas):
    x = int(canvas.width * callout.center[0] - card.width / 2)
    y = int(canvas.height * callout.center[1] - card.height / 2)
    pad = 120
    shadow = Image.new("L", (card.width + pad * 2, card.height + pad * 2), 0)
    shadow.paste(card.split()[3], (pad, pad + 30))
    shadow = shadow.filter(ImageFilter.GaussianBlur(45))
    layer = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    layer.putalpha(shadow.point(lambda value: int(value * 0.8)))
    paste_clipped(base, layer, (x - pad, y - pad))
    paste_clipped(base, card, (x, y))


def raw_for(device, ui, shot):
    """The capture of a shot in the app language, or the English one for a language not captured."""
    for language in (ui, "en"):
        path = RAW / device / language / f"{shot}.png"
        if path.exists():
            return path
    sys.exit(f"missing capture {RAW / device / ui / (shot + '.png')}")


def compose(panel, number, total, locale, device, canvas, table):
    ui = UI_LANGUAGE.get(locale, "en")
    raw_path = raw_for(device, ui, panel.shot)
    raw = Image.open(raw_path).convert("RGB")
    canvas = panel.canvas or canvas
    lights = canvas.glows or strip_glows(total, canvas.width, canvas.height)
    base = background(canvas, number, lights, seed=number * 31 + 7)
    caption = for_device(caption_for(locale, panel.caption or panel.key, table), device)
    top = draw_brand(base, canvas, canvas.title_top - 40) if panel.brand else canvas.title_top
    text_bottom = draw_text(base, caption, locale, canvas, top)
    device_image = framed(raw_path, device, ui, panel.shot, FRAME_COLORS[device])
    halo = VIOLET if number % 2 == 0 else ORANGE
    if panel.layout == "turned":
        device_image = device_image.rotate(-90, expand=True)
    if panel.layout == "landscape":
        room_top = text_bottom + int(canvas.height * 0.03)
        room = canvas.height - room_top + int(canvas.height * 0.05)
        width = min(int(canvas.width * canvas.landscape_width), int(room * device_image.width / device_image.height))
        scaled = device_image.resize((width, int(device_image.height * width / device_image.width)), Image.LANCZOS)
        y = room_top + max(0, (canvas.height - room_top - scaled.height) // 2)
        shadowed(base, scaled, ((canvas.width - width) // 2, y), halo)
    else:
        width = int(canvas.width * canvas.device_width)
        scaled = device_image.resize((width, int(device_image.height * width / device_image.width)), Image.LANCZOS)
        y = text_bottom + int(canvas.height * 0.035)
        shadowed(base, scaled, ((canvas.width - width) // 2, y), halo)
    if panel.callout:
        place_callout(base, callout_card(raw, panel.callout, canvas), panel.callout, canvas)
    return base.convert("RGB")


def creative(locale):
    """The product page Header and Search Results image (5244x2950, iOS 27): three phones fanned across the
    ember night, no text, the middle one playing a stream beside its chat, so it reads at any crop the store
    takes, 21:9 included."""
    ui = UI_LANGUAGE.get(locale, "en")
    canvas = Canvas(5244, 2950, 0, 0, 0, 0, 0)
    lights = [(5244 * 0.18, 2950 * 0.78, 2600, ORANGE, 0.75), (5244 * 0.82, 2950 * 0.2, 2800, VIOLET, 0.85),
              (5244 * 0.5, 2950 * 0.55, 1900, MAGENTA, 0.45)]
    base = background(canvas, 0, lights, seed=1709)
    height = int(2950 * 0.66)
    for shot, center, angle, scale in (("chats-emotes", 0.31, 7, 0.86), ("mentions", 0.69, -7, 0.86), ("channel", 0.5, 0, 1.0)):
        device = framed(raw_for("iphone", ui, shot), "iphone", ui, shot, FRAME_COLORS["iphone"])
        tall = int(height * scale)
        scaled = device.resize((int(device.width * tall / device.height), tall), Image.LANCZOS)
        if angle:
            scaled = scaled.rotate(angle, expand=True, resample=Image.BICUBIC)
        x = int(5244 * center - scaled.width / 2)
        y = int(2950 * 0.53 - scaled.height / 2)
        shadowed(base, scaled, (x, y), VIOLET if angle else ORANGE)
    return base.convert("RGB")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", choices=["iphone", "ipad", "duo"], action="append")
    parser.add_argument("--locale", action="append")
    parser.add_argument("--panel", action="append")
    parser.add_argument("--out", type=Path, default=SHOTS)
    parser.add_argument("--creative", action="store_true", help="write only the Header and Search Results image")
    args = parser.parse_args()
    if args.creative:
        for locale in args.locale or LOCALES:
            folder = CREATIVE / locale
            folder.mkdir(parents=True, exist_ok=True)
            creative(locale).save(folder / "header.png", optimize=True)
            print(f"creative {locale}")
        return
    table = captions()
    plans = {"iphone": (IPHONE, IPHONE_PANELS), "ipad": (IPAD, IPAD_PANELS), "duo": (DUO_INNER_PORTRAIT, DUO_PANELS)}
    for device in args.device or ["iphone", "ipad", "duo"]:
        canvas, panels = plans[device]
        for locale in args.locale or LOCALES:
            folder = args.out / device / locale
            folder.mkdir(parents=True, exist_ok=True)
            for number, panel in enumerate(panels):
                if args.panel and panel.key not in args.panel:
                    continue
                image = compose(panel, number, len(panels), locale, device, canvas, table)
                image.save(folder / f"{number + 1:02d}-{panel.key}.png", optimize=True)
            print(f"{device} {locale}: {len(panels)} panels")


if __name__ == "__main__":
    main()
