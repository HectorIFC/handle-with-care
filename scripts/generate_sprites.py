#!/usr/bin/env python3
"""Generate PLACEHOLDER 8-bit pixel-art sprites for Handle With Care.

Deterministic stand-ins for the [label]-text placeholders the game renders
today. Clearly primitive — flat palettes, simple shapes — for an artist to
replace, but they give the game a real visual identity and a working atlas.
Filenames feed scripts that build the atlas; sizes match PRD 7.1 (player
24x24, package 16x16, tiles 16x16).

Run: python3 scripts/generate_sprites.py   (needs Pillow)
"""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "main", "sprites")
os.makedirs(OUT, exist_ok=True)

def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def rect(im, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if 0 <= x < im.width and 0 <= y < im.height:
                im.putpixel((x, y), color)

def outline(im, color):
    w, h = im.size
    for x in range(w):
        for y in (0, h - 1):
            if im.getpixel((x, y))[3] > 0:
                im.putpixel((x, y), color)
    for y in range(h):
        for x in (0, w - 1):
            if im.getpixel((x, y))[3] > 0:
                im.putpixel((x, y), color)

def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    print("  ", name + ".png", im.size)

INK = (24, 20, 37, 255)

# Player: a little courier, 24x24
p = img(24, 24)
rect(p, 6, 2, 18, 24, (66, 76, 110, 255))   # body
rect(p, 8, 4, 16, 12, (240, 220, 190, 255))  # face
rect(p, 9, 7, 11, 9, INK); rect(p, 13, 7, 15, 9, INK)  # eyes
rect(p, 4, 12, 20, 15, (200, 80, 60, 255))   # satchel strap
rect(p, 6, 20, 10, 24, INK); rect(p, 14, 20, 18, 24, INK)  # legs
outline(p, INK)
save(p, "player")

# Package placeholders, one per state color, 16x16
STATE_COLORS = {
    "package_stable":     (235, 235, 235, 255),
    "package_nervous":    (235, 220, 90, 255),
    "package_panic":      (225, 70, 60, 255),
    "package_explosive":  (245, 140, 40, 255),
    "package_heavy":      (140, 105, 70, 255),
    "package_light":      (160, 210, 245, 255),
    "package_magnetized": (180, 90, 220, 255),
    "package_sleeping":   (95, 95, 120, 255),
}
for name, col in STATE_COLORS.items():
    b = img(16, 16)
    rect(b, 1, 1, 15, 15, col)
    rect(b, 1, 7, 15, 9, (col[0]*7//10, col[1]*7//10, col[2]*7//10, 255))  # tape
    rect(b, 7, 1, 9, 15, (col[0]*7//10, col[1]*7//10, col[2]*7//10, 255))
    outline(b, INK)
    save(b, name)

# Ground / platform tile, 16x16
g = img(16, 16)
rect(g, 0, 0, 16, 16, (70, 120, 80, 255))
rect(g, 0, 0, 16, 4, (110, 170, 110, 255))   # grass top
for x in range(0, 16, 4):
    rect(g, x, 8, x + 1, 16, (55, 95, 65, 255))  # texture
save(g, "tile_ground")

# Spike, 16x16
s = img(16, 16)
for i in range(4):
    bx = i * 4
    for y in range(16):
        half = (y) // 2
        rect(s, bx + (3 - 0) - half, y, bx + half + 1, y + 1, (200, 60, 60, 255)) if False else None
# simpler triangles
for i in range(3):
    cx = 3 + i * 5
    for y in range(16):
        wdt = y // 3
        rect(s, cx - wdt, 15 - y, cx + wdt + 1, 16 - y, (190, 60, 60, 255))
outline(s, INK)
save(s, "spike")

# Delivery zone marker, 40x40 (a glowing goal pad)
d = img(40, 40)
rect(d, 2, 30, 38, 38, (90, 200, 130, 255))
rect(d, 2, 30, 38, 32, (170, 240, 190, 255))
rect(d, 18, 6, 22, 30, (90, 200, 130, 255))    # pole
rect(d, 22, 8, 34, 16, (240, 220, 90, 255))    # flag
outline(d, INK)
save(d, "delivery")

print("generated placeholder sprites ->", os.path.relpath(OUT))
