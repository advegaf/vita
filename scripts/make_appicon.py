#!/usr/bin/env python3
"""Renders Vita's app icon: the "V." mark.

The editorial wordmark distilled — a massive Inter Tight Black V in ink on the
app's cream canvas, with the period drawn as a geometric candy-cyan dot (the
app's dot language: DotMeter, adherence dots). Three iOS variants: light, dark
(cream mark on warm charcoal), tinted (grayscale template the system colors).

Deterministic: run it again, get the same pixels.
    python3 scripts/make_appicon.py
"""

from PIL import Image, ImageDraw, ImageFont
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "Vita/Resources/Fonts/InterTight.ttf"
OUT = ROOT / "Vita/Resources/Assets.xcassets/AppIcon.appiconset"

SIZE = 1024
CREAM = (0xF1, 0xEE, 0xE9, 255)
INK = (0x1A, 0x1A, 0x1A, 255)
CYAN = (0x2B, 0xB3, 0xF3, 255)
WHITE = (255, 255, 255, 255)
GRAY = (179, 179, 179, 255)          # the dot's tone in the tinted template

V_HEIGHT = 530                        # cap height of the V on the 1024 canvas
DOT_RATIO = 0.24                      # dot diameter vs V height (≈ stem width)
GAP_RATIO = 0.34                      # air between V terminal and dot, vs dot


def black_font(px: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), px)
    f.set_variation_by_axes([900])    # Inter Tight variable: weight → Black
    return f


def measure_v(px: int):
    f = black_font(px)
    l, t, r, b = f.getbbox("V")
    return f, (l, t, r, b), r - l, b - t


def render(field, mark, dot) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), field)
    draw = ImageDraw.Draw(img)

    # Scale the font so the V's drawn height hits V_HEIGHT exactly.
    probe_px = 600
    _, _, _, probe_h = measure_v(probe_px)
    px = round(probe_px * V_HEIGHT / probe_h)
    font, (l, t, r, b), w, h = measure_v(px)

    dot_d = round(h * DOT_RATIO)
    gap = round(dot_d * GAP_RATIO)
    # The V + dot COMPOSITION is centered: equal whitespace margins left and
    # right, the dot snug at the baseline — one balanced, symmetric mark.
    x0 = (SIZE - (w + gap + dot_d)) / 2
    y0 = (SIZE - h) / 2

    # Draw the V with its bbox pinned to (x0, y0).
    draw.text((x0 - l, y0 - t), "V", font=font, fill=mark)
    # The period: a perfect circle sitting on the V's baseline.
    dx = x0 + w + gap
    dy = y0 + h - dot_d
    draw.ellipse([dx, dy, dx + dot_d, dy + dot_d], fill=dot)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    render(CREAM, INK, CYAN).convert("RGB").save(OUT / "icon-light.png")
    render(INK, CREAM, CYAN).convert("RGB").save(OUT / "icon-dark.png")
    render((0, 0, 0, 0), WHITE, GRAY).save(OUT / "icon-tinted.png")
    print("wrote 3 icons to", OUT)


if __name__ == "__main__":
    main()
