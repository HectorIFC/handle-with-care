#!/usr/bin/env python3
"""Generate the UI pixel font (PRD 7's "UI em pixel art").

Emits a BMFont pair — main/ui/pixel.png + main/ui/pixel.fnt — which Defold
consumes through main/ui/pixel.font. Deterministic: every glyph is a literal
5x7 bitmap in this file, so a diff shows exactly which letter changed.

SMALL CAPS BY DESIGN: lowercase ids point at the same glyph regions as their
uppercase counterparts. At 5x7 there is no room for descenders or a
distinguishable 'a' vs 'A' without going to 5x9 and doubling the glyph
count, and small caps is a normal look for an 8-bit UI. It also means the
menu copy can stay in ordinary mixed case in screen_flow.lua.

Run: python3 scripts/generate_font.py   (needs Pillow)
"""
from PIL import Image
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "main", "ui")
W, H = 5, 7
ADVANCE = 6
COLS = 16

# Each glyph is 7 rows of 5 columns. '#' is ink, anything else transparent.
GLYPHS = {
    "A": ".###.|#...#|#...#|#####|#...#|#...#|#...#",
    "B": "####.|#...#|####.|#...#|#...#|#...#|####.",
    "C": ".###.|#...#|#....|#....|#....|#...#|.###.",
    "D": "####.|#...#|#...#|#...#|#...#|#...#|####.",
    "E": "#####|#....|####.|#....|#....|#....|#####",
    "F": "#####|#....|####.|#....|#....|#....|#....",
    "G": ".###.|#...#|#....|#.###|#...#|#...#|.###.",
    "H": "#...#|#...#|#####|#...#|#...#|#...#|#...#",
    "I": "#####|..#..|..#..|..#..|..#..|..#..|#####",
    "J": "..###|...#.|...#.|...#.|...#.|#..#.|.##..",
    "K": "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|#####",
    "M": "#...#|##.##|#.#.#|#...#|#...#|#...#|#...#",
    "N": "#...#|##..#|#.#.#|#..##|#...#|#...#|#...#",
    "O": ".###.|#...#|#...#|#...#|#...#|#...#|.###.",
    "P": "####.|#...#|#...#|####.|#....|#....|#....",
    "Q": ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#",
    "R": "####.|#...#|#...#|####.|#.#..|#..#.|#...#",
    "S": ".####|#....|#....|.###.|....#|....#|####.",
    "T": "#####|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.###.",
    "V": "#...#|#...#|#...#|#...#|#...#|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#...#|#.#.#|##.##|#...#",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "#####|....#|...#.|..#..|.#...|#....|#####",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": "..#..|.##..|..#..|..#..|..#..|..#..|.###.",
    "2": ".###.|#...#|....#|...#.|..#..|.#...|#####",
    "3": "####.|....#|....#|.###.|....#|....#|####.",
    "4": "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.",
    "5": "#####|#....|####.|....#|....#|#...#|.###.",
    "6": ".###.|#...#|#....|####.|#...#|#...#|.###.",
    "7": "#####|....#|...#.|..#..|.#...|.#...|.#...",
    "8": ".###.|#...#|#...#|.###.|#...#|#...#|.###.",
    "9": ".###.|#...#|#...#|.####|....#|#...#|.###.",
    " ": ".....|.....|.....|.....|.....|.....|.....",
    ".": ".....|.....|.....|.....|.....|..##.|..##.",
    ",": ".....|.....|.....|.....|..##.|..##.|.#...",
    ":": ".....|..##.|..##.|.....|..##.|..##.|.....",
    ";": ".....|..##.|..##.|.....|..##.|..##.|.#...",
    "'": "..#..|..#..|.....|.....|.....|.....|.....",
    '"': ".#.#.|.#.#.|.....|.....|.....|.....|.....",
    "!": "..#..|..#..|..#..|..#..|..#..|.....|..#..",
    "?": ".###.|#...#|....#|..##.|..#..|.....|..#..",
    "-": ".....|.....|.....|#####|.....|.....|.....",
    "+": ".....|..#..|..#..|#####|..#..|..#..|.....",
    "/": "....#|...#.|...#.|..#..|.#...|.#...|#....",
    "(": "...#.|..#..|.#...|.#...|.#...|..#..|...#.",
    ")": ".#...|..#..|...#.|...#.|...#.|..#..|.#...",
    "[": "..###|..#..|..#..|..#..|..#..|..#..|..###",
    "]": "###..|..#..|..#..|..#..|..#..|..#..|###..",
    "<": "...#.|..#..|.#...|#....|.#...|..#..|...#.",
    ">": ".#...|..#..|...#.|....#|...#.|..#..|.#...",
    "#": ".#.#.|#####|.#.#.|.#.#.|#####|.#.#.|.....",
    "%": "#...#|...#.|..#..|..#..|.#...|#...#|.....",
    "*": ".....|#.#.#|.###.|#####|.###.|#.#.#|.....",
    "=": ".....|.....|#####|.....|#####|.....|.....",
    "_": ".....|.....|.....|.....|.....|.....|#####",
}

# One transparent pixel between glyphs. The .fnt gives exact source rects,
# so packing them flush would be correct for nearest sampling — but the
# label material's filtering is not something this project can observe (the
# headless suite renders nothing), and a bled edge would show up as faint
# fringes on every letter. A pixel of padding costs nothing and removes the
# question.
PAD = 1

ORDER = list(GLYPHS.keys())
rows = (len(ORDER) + COLS - 1) // COLS
sheet = Image.new("RGBA", (COLS * (W + PAD), rows * (H + PAD)), (0, 0, 0, 0))

placement = {}
for index, ch in enumerate(ORDER):
    col, row = index % COLS, index // COLS
    ox, oy = col * (W + PAD), row * (H + PAD)
    placement[ch] = (ox, oy)
    for y, line in enumerate(GLYPHS[ch].split("|")):
        for x, cell in enumerate(line):
            if cell == "#":
                sheet.putpixel((ox + x, oy + y), (255, 255, 255, 255))

os.makedirs(OUT, exist_ok=True)
sheet.save(os.path.join(OUT, "pixel.png"))

lines = [
    'info face="pixel" size=%d bold=0 italic=0 charset="" unicode=1 '
    'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0' % H,
    # NOTE: raising this does NOT space the menus out — Defold does not lay
    # out label lines from the .fnt's lineHeight. Line spacing is the
    # `leading` multiplier on each .label component; see main/ui/*.label.
    'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0'
    % (H + 2, H, sheet.width, sheet.height),
    'page id=0 file="pixel.png"',
]

entries = []
for ch, (ox, oy) in placement.items():
    codes = [ord(ch)]
    # Small caps: map lowercase onto the same region. See the module
    # docstring for why this is a design choice, not a shortcut.
    if "A" <= ch <= "Z":
        codes.append(ord(ch.lower()))
    for code in codes:
        entries.append(
            "char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 "
            "xadvance=%d page=0 chnl=15" % (code, ox, oy, W, H, ADVANCE))

lines.append("chars count=%d" % len(entries))
lines.extend(entries)

with open(os.path.join(OUT, "pixel.fnt"), "w") as f:
    f.write("\n".join(lines) + "\n")

print("glyphs:", len(ORDER), "chars:", len(entries), "sheet:", sheet.size)
print("wrote", os.path.relpath(os.path.join(OUT, "pixel.png")),
      "and pixel.fnt")
