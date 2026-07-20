#!/usr/bin/env python3
"""Vita App Store screenshot compositor (M52).

1320x2868 canvases: brand background, kicker + Inter Tight Black headline up
top, the raw capture in an ink-bezel device frame bottom-anchored (cropped at
the canvas edge so the device reads large). No decoration beyond one shadow.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

ROOT = "/Users/advegaf/Desktop/projects/vita"
RAW = "/private/tmp/claude-501/-Users-advegaf-Desktop-projects-vita/add7c808-1438-4dc8-ab04-83b2ef51238a/scratchpad/appstore-raw"
OUT = os.path.join(ROOT, "marketing", "appstore")
FONT = os.path.join(ROOT, "Vita", "Resources", "Fonts", "InterTight.ttf")

W, H = 1320, 2868
CREAM, INK, GRAY = (241, 238, 233), (26, 26, 26), (110, 110, 110)
GRAPHITE, WARMWHITE, WARMGRAY = (20, 19, 18), (243, 238, 231), (181, 174, 165)

def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f

SHOTS = [
    ("01-today",  "today-light",  "light", "EVERY DOSE, TIMED AND TRACKED", ["Your protocol,", "handled."]),
    ("02-diary",  "diary-light",  "light", "SLEEP, HRV AND READINESS FROM YOUR RING", ["Your ring's data,", "one calm page."]),
    ("03-chat",   "chat-light",   "light", "EDUCATIONAL ANSWERS, GROUNDED IN YOUR DATA", ["Ask anything.", "It knows your stack."]),
    ("04-detail", "detail-light", "light", "VIALS, SUPPLY AND HISTORY AT A GLANCE", ["Never lose track", "of a vial."]),
    ("05-calc",   "calc-light",   "light", "U-100, U-50 AND U-40, INSTANTLY", ["Reconstitution math,", "done for you."]),
    ("06-labs",   "labs-light",   "light", "EVERY MARKER, CHARTED OVER TIME", ["Your bloodwork,", "in focus."]),
    ("07-dark",   "today-dark",   "dark",  "A CALM, WARM DARK MODE", ["Gorgeous", "in the dark."]),
    ("08-stack",  "stack-dark",   "dark",  "CYCLES, TITRATION AND REST DAYS",  ["The whole stack,", "at a glance."]),
]

def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m

def tracked_text(draw, y, text, f, fill, tracking=0.0):
    """Center a line horizontally with optional letterspacing (px per gap)."""
    widths = [draw.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x = (W - total) / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=f, fill=fill)
        x += w + tracking
    return total

def compose(out_name, raw_name, mode, kicker, headline):
    bg = CREAM if mode == "light" else GRAPHITE
    fg = INK if mode == "light" else WARMWHITE
    kick_c = GRAY if mode == "light" else WARMGRAY

    canvas = Image.new("RGBA", (W, H), bg + (255,))

    # --- device geometry (needed before text so we know the top) ---
    shot = Image.open(os.path.join(RAW, f"{raw_name}.png")).convert("RGB")
    dev_w = 1064
    dev_h = round(dev_w * shot.height / shot.width)
    shot = shot.resize((dev_w, dev_h), Image.LANCZOS)

    kf = font(42, "SemiBold")
    # Auto-fit the headline: shrink from 132px until the longest line fits
    # inside the side margins (keeps every shot's baseline grid identical).
    margin = 84
    probe = ImageDraw.Draw(canvas)
    hs = 132
    while hs > 80:
        hf = font(hs, "Black")
        if max(probe.textlength(l, font=hf) for l in headline) <= W - 2 * margin:
            break
        hs -= 4
    head_top = 210
    line_h = 148
    text_bottom = head_top + 42 + 48 + line_h * len(headline)
    dev_top = text_bottom + 72
    bezel = 16
    corner = 150
    frame_w, frame_h = dev_w + bezel * 2, dev_h + bezel * 2
    left = (W - frame_w) // 2

    # --- shadow ---
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [left, dev_top + 24, left + frame_w, dev_top + frame_h], corner + bezel, fill=(0, 0, 0, 95))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(38)))

    # --- bezel + screen ---
    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame_w - 1, frame_h - 1], corner + bezel, fill=(26, 26, 26, 255))
    screen = shot.convert("RGBA")
    screen.putalpha(rounded_mask((dev_w, dev_h), corner))
    frame.alpha_composite(screen, (bezel, bezel))
    canvas.alpha_composite(frame, (left, dev_top))

    # --- text (single pass, after all compositing) ---
    draw = ImageDraw.Draw(canvas)
    tracked_text(draw, head_top, kicker, kf, kick_c, tracking=3.0)
    y = head_top + 42 + 48
    for line in headline:
        lw = draw.textlength(line, font=hf)
        draw.text(((W - lw) / 2, y), line, font=hf, fill=fg)
        y += line_h

    out = canvas.convert("RGB")
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, f"{out_name}.png"), "PNG")
    print(out_name, out.size)

for spec in SHOTS:
    compose(*spec)
