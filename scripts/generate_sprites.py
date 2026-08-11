#!/usr/bin/env python3
"""Generate PLACEHOLDER 8-bit pixel-art sprites for Handle With Care.

Deterministic stand-ins for the [label]-text placeholders the game used to
render. Clearly primitive — flat palettes, simple shapes — for an artist to
replace, but they give the game a real visual identity and a working atlas.
Filenames feed main/sprites/game.atlas; sizes match PRD 7.1 (player 24x24,
package 16x16, tiles 16x16).

Two constraints shape the drawings, and both matter if you edit this file:

1. The ground and platform tiles are drawn with HORIZONTAL BANDS ONLY —
   every rect spans the full 0..W width. Levels author platform width as
   `half_width` (24..80 across the ten levels), and the adapters scale a
   single 16x16 sprite to match rather than tiling. A tile with any vertical
   detail would visibly smear under that stretch; a band-only tile stretches
   losslessly. Do not add vertical texture to `tile_ground`/`tile_platform`.

2. The player's animation states are separate FILES, not frames. Defold
   names a single-image atlas entry after its filename, so `player_idle` etc.
   become one-frame flipbook animations that player.script can play by name.
   The five names must stay in sync with player_movement.animation_state's
   return values (plus "land").

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

def band(im, y0, y1, color):
    """A full-width horizontal band — the only primitive the stretched
    tiles are allowed to use. See constraint 1 in the module docstring."""
    rect(im, 0, y0, im.width, y1, color)

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

SAVED = []

def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    SAVED.append(name)
    print("  ", name + ".png", im.size)


def write_atlas():
    """Emit game.atlas from exactly what this run saved.

    Generated rather than hand-maintained so an image can never exist
    without an atlas entry (or an entry without an image, which fails the
    build). Each single-image entry becomes a one-frame flipbook animation
    named after the file — that is how player.script and package.script
    address them.
    """
    lines = []
    for name in sorted(SAVED):
        lines.append("images {")
        lines.append('  image: "/main/sprites/%s.png"' % name)
        lines.append("  sprite_trim_mode: SPRITE_TRIM_MODE_OFF")
        lines.append("}")
    lines += ["margin: 0", "extrude_borders: 2", "inner_padding: 0", ""]
    path = os.path.join(OUT, "game.atlas")
    with open(path, "w") as f:
        f.write("\n".join(lines))
    print("  ", "game.atlas", "(%d images)" % len(SAVED))

INK = (24, 20, 37, 255)
SKIN = (240, 220, 190, 255)
CLOTH = (66, 76, 110, 255)
STRAP = (200, 80, 60, 255)


def player_base():
    """The courier's shared silhouette: body, face, eyes, satchel strap.
    Each animation state draws its own legs/arms on top."""
    p = img(24, 24)
    rect(p, 6, 2, 18, 20, CLOTH)          # body
    rect(p, 8, 4, 16, 12, SKIN)           # face
    rect(p, 9, 7, 11, 9, INK)             # eyes
    rect(p, 13, 7, 15, 9, INK)
    rect(p, 4, 12, 20, 15, STRAP)         # satchel strap
    return p


# Player animation states. The names are the contract with
# player_movement.animation_state (idle/run/jump/fall) plus "land", which
# player.script substitutes on the landing frame.
p = player_base()
rect(p, 7, 20, 11, 24, INK)               # legs together
rect(p, 13, 20, 17, 24, INK)
outline(p, INK)
save(p, "player_idle")

p = player_base()
rect(p, 4, 20, 9, 24, INK)                # legs mid-stride
rect(p, 15, 18, 20, 22, INK)
rect(p, 18, 10, 22, 14, SKIN)             # trailing arm
outline(p, INK)
save(p, "player_run")

p = player_base()
rect(p, 7, 19, 11, 22, INK)               # legs tucked up
rect(p, 13, 19, 17, 22, INK)
rect(p, 2, 6, 6, 10, SKIN)                # arms raised
rect(p, 18, 6, 22, 10, SKIN)
outline(p, INK)
save(p, "player_jump")

p = player_base()
rect(p, 5, 20, 10, 24, INK)               # legs splayed
rect(p, 14, 20, 19, 24, INK)
rect(p, 1, 13, 5, 17, SKIN)               # arms out for balance
rect(p, 19, 13, 23, 17, SKIN)
outline(p, INK)
save(p, "player_fall")

p = img(24, 24)                           # squashed on impact
rect(p, 5, 8, 19, 21, CLOTH)
rect(p, 7, 10, 17, 16, SKIN)
rect(p, 9, 12, 11, 14, INK)
rect(p, 13, 12, 15, 14, INK)
rect(p, 3, 16, 21, 19, STRAP)
rect(p, 6, 21, 11, 24, INK)
rect(p, 13, 21, 18, 24, INK)
outline(p, INK)
save(p, "player_land")

# Package placeholders, one per state color, 16x16. The name after
# "package_" is exactly package_state_machine's state name, so
# package.script can play the right image straight from current_state.
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
    shade = (col[0] * 7 // 10, col[1] * 7 // 10, col[2] * 7 // 10, 255)
    b = img(16, 16)
    rect(b, 1, 1, 15, 15, col)
    rect(b, 1, 7, 15, 9, shade)           # tape, horizontal
    rect(b, 7, 1, 9, 15, shade)           # tape, vertical
    outline(b, INK)
    save(b, name)

# Ground tile, 16x16 — bands only, see constraint 1.
g = img(16, 16)
band(g, 0, 3, (120, 180, 115, 255))       # lit grass edge
band(g, 3, 6, (85, 140, 90, 255))
band(g, 6, 13, (70, 120, 80, 255))        # body
band(g, 13, 16, (48, 84, 58, 255))        # shadowed underside
save(g, "tile_ground")

# Platform tile, 16x16 — bands only, distinct from ground so a player can
# tell a level's floor from something they have to climb onto.
t = img(16, 16)
band(t, 0, 3, (176, 168, 150, 255))       # lit top edge
band(t, 3, 6, (140, 132, 116, 255))
band(t, 6, 13, (108, 100, 88, 255))       # body
band(t, 13, 16, (72, 66, 58, 255))        # shadowed underside
save(t, "tile_platform")

# Spike, 16x16 — three teeth. Not stretched in practice (hazards are
# authored at the sprite's native half-extents), so vertical detail is fine.
s = img(16, 16)
for i in range(3):
    cx = 3 + i * 5
    for y in range(16):
        wdt = y // 3
        rect(s, cx - wdt, 15 - y, cx + wdt + 1, 16 - y, (190, 60, 60, 255))
outline(s, INK)
save(s, "spike")

# Delivery zone marker, 40x40 (a goal pad with a flag)
d = img(40, 40)
rect(d, 2, 30, 38, 38, (90, 200, 130, 255))
rect(d, 2, 30, 38, 32, (170, 240, 190, 255))
rect(d, 18, 6, 22, 30, (90, 200, 130, 255))    # pole
rect(d, 22, 8, 34, 16, (240, 220, 90, 255))    # flag
outline(d, INK)
save(d, "delivery")

write_atlas()

print("generated placeholder sprites ->", os.path.relpath(OUT))
