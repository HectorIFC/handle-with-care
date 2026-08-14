#!/usr/bin/env python3
"""Generate PLACEHOLDER 8-bit pixel-art sprites for Handle With Care.

Deterministic — no randomness at all, every pixel is placed explicitly — so
regenerating produces byte-identical files and a diff means someone actually
changed the art. Still placeholders for an artist to replace, but they aim at
PRD section 7's direction: limited palette, "fofo + ameaçador", readable at
384x216.

Sizes follow PRD 7.1: player 24x24, package 16x16, tiles 16x16.

THREE CONSTRAINTS, all of which will silently produce bad output if broken:

1. The ground and platform tiles use HORIZONTAL BANDS ONLY — every drawing
   call spans the full width. Levels author platform width as `half_width`
   (24..80 across the ten levels) and the adapters scale one 16x16 sprite to
   match rather than tiling, so any vertical detail would smear under that
   stretch. Use band() for those two tiles and nothing else.

2. Animation names are a contract with the scripts. `player_<state>` must
   cover exactly what player_movement.animation_state returns (idle, run,
   jump, fall) plus "land"; `package_<state>` must cover every state name in
   package_state_machine. A missing name means play_flipbook errors at
   runtime, which headless tests cannot catch.

3. The atlas is generated from what this script emits (see write_atlas), so
   an image can never exist without an entry or vice versa. Multi-frame
   animations go in `animations` blocks; everything else stays a bare image
   whose filename becomes a one-frame animation of the same name.

Run: python3 scripts/generate_sprites.py   (needs Pillow)
"""
from PIL import Image
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "main", "sprites")
os.makedirs(OUT, exist_ok=True)

# --- Palette -----------------------------------------------------------
# Deliberately small (PRD 7.1 asks for ~32-48). Cute shapes, sour colors.
INK        = (26, 20, 34, 255)      # one near-black for every outline
INK_SOFT   = (58, 48, 68, 255)      # interior lines that should not shout

SKIN       = (246, 214, 178, 255)
SKIN_SHADE = (214, 172, 138, 255)
CLOTH      = (62, 74, 112, 255)
CLOTH_LIT  = (92, 106, 150, 255)
STRAP      = (198, 74, 62, 255)
STRAP_DARK = (146, 48, 44, 255)

GRASS_LIT  = (132, 200, 114, 255)
GRASS      = (88, 158, 92, 255)
DIRT       = (104, 76, 56, 255)
DIRT_DARK  = (70, 50, 38, 255)

STONE_LIT  = (178, 174, 160, 255)
STONE      = (134, 130, 118, 255)
STONE_DARK = (94, 90, 82, 255)
STONE_DEEP = (62, 58, 54, 255)

METAL_LIT  = (214, 218, 228, 255)
METAL      = (152, 160, 174, 255)
METAL_DARK = (98, 106, 122, 255)

PAD_LIT    = (172, 240, 192, 255)
PAD        = (98, 200, 130, 255)
PAD_DARK   = (58, 148, 92, 255)
FLAG       = (246, 220, 96, 255)

WHITE      = (250, 248, 244, 255)
SPARK      = (255, 236, 150, 255)


def img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(im, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if 0 <= x < im.width and 0 <= y < im.height:
                im.putpixel((x, y), color)


def px(im, x, y, color):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), color)


def band(im, y0, y1, color):
    """A full-width horizontal band — the ONLY primitive the stretched tiles
    may use. See constraint 1 in the module docstring."""
    rect(im, 0, y0, im.width, y1, color)


def outline(im, color=INK):
    """Traces a 1px border around every opaque region. Done last, so shading
    never bleeds past the silhouette."""
    w, h = im.size
    src = im.copy()
    for y in range(h):
        for x in range(w):
            if src.getpixel((x, y))[3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src.getpixel((nx, ny))[3] != 0:
                    im.putpixel((x, y), color)
                    break


SINGLES = []
ANIMS = []


def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    return name


def emit_single(im, name):
    save(im, name)
    SINGLES.append(name)
    print("  ", name + ".png", im.size)


def emit_anim(frames, anim_id, fps, playback="PLAYBACK_LOOP_FORWARD"):
    """frames: list of images. Written as <anim_id>_<n>.png and grouped into
    one atlas animation, so the scripts still address it as `anim_id`."""
    names = []
    for index, frame in enumerate(frames):
        names.append(save(frame, "%s_%d" % (anim_id, index)))
    ANIMS.append({"id": anim_id, "frames": names, "fps": fps, "playback": playback})
    print("  ", anim_id, "(%d frames @ %dfps)" % (len(frames), fps))


# --- Player ------------------------------------------------------------
# A small courier: round head, oversized satchel strap, stubby legs. The
# silhouette is what has to read at this size, so the head is deliberately
# big and the body narrow.

# The torso spans x=7..16, so an arm has to cover x=6 (left) or x=17 (right)
# to actually touch it. Getting this wrong leaves a 1px gap that outline()
# fills with near-black, and the hands read as detached blocks floating
# beside the body — which is exactly how the first version looked.
ARM_LEFT_X = 4
ARM_RIGHT_X = 17


def courier(body_top=5, arm_left=None, arm_right=None, squash=0):
    """Shared body. body_top shifts the torso for the breathing/jump poses;
    arm_left/arm_right are the arm's TOP Y (x is fixed, see above), or None
    to tuck it in."""
    p = img(24, 24)
    head_top = body_top - 3 + squash
    # Torso
    rect(p, 7, body_top + 3, 17, 20, CLOTH)
    rect(p, 7, body_top + 3, 11, 20, CLOTH_LIT)     # lit side
    # Head
    rect(p, 6, head_top, 18, body_top + 4, SKIN)
    rect(p, 6, head_top, 10, body_top + 4, SKIN)
    rect(p, 14, head_top + 1, 18, body_top + 4, SKIN_SHADE)  # shaded cheek
    # Eyes — two dark pixels, wide apart. Cheap, and the whole "cute" read.
    px(p, 9, head_top + 3, INK)
    px(p, 9, head_top + 4, INK)
    px(p, 14, head_top + 3, INK)
    px(p, 14, head_top + 4, INK)
    # Satchel strap, corner to hip
    rect(p, 6, body_top + 5, 18, body_top + 7, STRAP)
    rect(p, 6, body_top + 6, 18, body_top + 7, STRAP_DARK)
    if arm_left is not None:
        rect(p, ARM_LEFT_X, arm_left, ARM_LEFT_X + 3, arm_left + 3, SKIN)
    if arm_right is not None:
        rect(p, ARM_RIGHT_X, arm_right, ARM_RIGHT_X + 3, arm_right + 3, SKIN_SHADE)
    return p


def legs(p, left, right):
    """left/right are (x, top, height) for each leg."""
    for x, top, height in (left, right):
        rect(p, x, top, x + 4, top + height, CLOTH)
        rect(p, x, top + height - 2, x + 4, top + height, INK_SOFT)  # boot


# Idle: four frames (PRD 7.1 asks 4-6). A breath in and out rather than a
# two-frame flicker — the pause at each extreme is what makes it read as
# breathing instead of vibrating, so the sequence goes 0,1,1,0 in effect via
# the lift values below.
idle_frames = []
for lift in (0, 1, 1, 0):
    p = courier(body_top=5 + lift)
    legs(p, (7, 20, 4), (13, 20, 4))
    outline(p)
    idle_frames.append(p)
emit_anim(idle_frames, "player_idle", 5)

# Run: six frames (PRD 7.1 asks 6-8) — contact, down, pass, contact, down,
# pass, one full stride per three frames. Arms swing opposite the legs, and
# the body bobs a pixel on the passing frames, which is where the weight
# reads at this size.
run_poses = [
    # (left leg, right leg, left arm y, right arm y, body bob)
    ((5, 20, 4), (15, 20, 4), 12, 15, 0),
    ((7, 21, 3), (14, 20, 4), 13, 14, 1),
    ((8, 20, 4), (13, 19, 5), 14, 13, 1),
    ((6, 20, 4), (14, 20, 4), 15, 12, 0),
    ((9, 21, 3), (12, 20, 4), 14, 13, 1),
    ((9, 19, 5), (12, 20, 4), 13, 14, 1),
]
run_frames = []
for left, right, arm_a, arm_b, bob in run_poses:
    p = courier(body_top=5 + bob, arm_left=arm_a, arm_right=arm_b)
    legs(p, left, right)
    outline(p)
    run_frames.append(p)
emit_anim(run_frames, "player_run", 12)

# Jump: arms up, legs tucked.
p = courier(body_top=4, arm_left=9, arm_right=9)
legs(p, (8, 19, 3), (13, 19, 3))
outline(p)
emit_single(p, "player_jump")

# Fall: arms out for balance, legs splayed — reads as "not in control".
p = courier(body_top=6, arm_left=13, arm_right=13)
legs(p, (6, 20, 4), (14, 20, 4))
outline(p)
emit_single(p, "player_fall")

# Land: squashed. Anticipation frames are what sell weight at 8-bit sizes.
p = courier(body_top=9, squash=2, arm_left=16, arm_right=16)
legs(p, (7, 21, 3), (13, 21, 3))
outline(p)
emit_single(p, "player_land")

# Death: five frames (PRD 7.1 asks 4-6), played ONCE and held on the last —
# the player freezes on death (player.script's sticky `dead`), so a looping
# death would have the corpse twitching until restart.
death_frames = []
# 1: recoil, arms flung up.
p = courier(body_top=4, arm_left=7, arm_right=7)
legs(p, (7, 20, 4), (13, 20, 4))
outline(p)
death_frames.append(p)
# 2: knees buckle.
p = courier(body_top=7, arm_left=11, arm_right=11)
legs(p, (7, 21, 3), (13, 21, 3))
outline(p)
death_frames.append(p)
# 3-5: toppled. Drawn directly rather than via courier(), since the body is
# on its side and shares none of the standing layout.
#
# Every part is placed relative to `shift` INCLUDING its right edge. The
# first version pinned the head's right edge at a constant x while the body
# slid right, so the head shrank a pixel per frame and ended up as a small
# detached box. Keep widths fixed; move origins.
TORSO_W, HEAD_W = 12, 6
for step, (top, shift) in enumerate(((13, 0), (16, 1), (17, 2))):
    p = img(24, 24)
    x0 = 2 + shift
    rect(p, x0, top, x0 + TORSO_W, top + 6, CLOTH)               # torso, lying
    rect(p, x0, top, x0 + TORSO_W, top + 3, CLOTH_LIT)
    rect(p, x0 - 1, top + 4, x0 + 5, top + 7, INK_SOFT)          # legs, splayed
    head_x = x0 + TORSO_W
    rect(p, head_x, top - 1, head_x + HEAD_W, top + 6, SKIN)     # head, fallen
    rect(p, x0, top + 1, head_x, top + 3, STRAP)                 # strap
    if step == 2:
        # X eyes only on the last frame: the beat before still reads as
        # "falling", which is what makes the landing register.
        for dx, dy in ((1, 1), (3, 1), (2, 2), (1, 3), (3, 3)):
            px(p, head_x + dx, top + dy, INK)
    else:
        rect(p, head_x + 1, top + 1, head_x + 3, top + 3, INK)
    outline(p)
    death_frames.append(p)
emit_anim(death_frames, "player_death", 9, playback="PLAYBACK_ONCE_FORWARD")


# --- Package -----------------------------------------------------------
# The package has EYES. It is the game's whole premise that the thing you
# carry is alive and reacting, and a plain box cannot say that. Each state
# gets a body color plus an expression.

PACKAGE_STATES = {
    #                body                shade               eyes
    "stable":     ((206, 170, 120, 255), (166, 130, 86, 255),  "calm"),
    "nervous":    ((230, 208, 100, 255), (188, 164, 66, 255),  "worried"),
    "panic":      ((222, 78, 66, 255),   (172, 52, 46, 255),   "wide"),
    "explosive":  ((246, 148, 52, 255),  (196, 100, 32, 255),  "wide"),
    "heavy":      ((156, 118, 82, 255),  (112, 84, 58, 255),   "strain"),
    "light":      ((172, 216, 246, 255), (128, 176, 214, 255), "calm"),
    "magnetized": ((172, 96, 214, 255),  (128, 62, 168, 255),  "wide"),
    "sleeping":   ((112, 112, 136, 255), (82, 82, 104, 255),   "closed"),
}


def darker(color, factor):
    return (int(color[0] * factor), int(color[1] * factor), int(color[2] * factor), 255)


def package_body(body, shade):
    b = img(16, 16)
    rect(b, 2, 2, 14, 14, body)
    rect(b, 2, 12, 14, 14, shade)       # shaded base
    # Tape cross, the one thing that makes it read as a parcel. It gets its
    # OWN tone rather than reusing `shade`: drawn in the shade color it
    # merged into the shaded base and the cross vanished entirely.
    #
    # Kept BELOW the eyes — at 16x16 the face has to own the top half or the
    # expression stops reading, which is the whole reason it has one.
    tape = darker(shade, 0.72)
    rect(b, 2, 9, 14, 11, tape)
    rect(b, 7, 9, 9, 14, tape)
    return b


def eyes(b, kind):
    if kind == "closed":
        rect(b, 4, 6, 6, 7, INK)
        rect(b, 10, 6, 12, 7, INK)
        return
    if kind == "calm":
        rect(b, 4, 5, 6, 7, INK)
        rect(b, 10, 5, 12, 7, INK)
        return
    if kind == "worried":
        rect(b, 4, 5, 6, 7, INK)
        rect(b, 10, 5, 12, 7, INK)
        px(b, 4, 4, INK_SOFT)           # tilted brows
        px(b, 11, 4, INK_SOFT)
        return
    if kind == "wide":
        rect(b, 3, 4, 6, 8, WHITE)
        rect(b, 10, 4, 13, 8, WHITE)
        rect(b, 4, 6, 6, 8, INK)        # pupils dropped low = alarm
        rect(b, 10, 6, 12, 8, INK)
        return
    if kind == "strain":
        rect(b, 3, 4, 6, 8, WHITE)
        rect(b, 10, 4, 13, 8, WHITE)
        rect(b, 4, 4, 6, 6, INK)        # pupils pushed UP = straining
        rect(b, 10, 4, 12, 6, INK)
        px(b, 3, 4, INK_SOFT)           # heavy, downcast brows
        px(b, 4, 4, INK_SOFT)
        px(b, 11, 4, INK_SOFT)
        px(b, 12, 4, INK_SOFT)


def accents(b, state):
    """Per-state decoration, drawn AFTER outline() on purpose.

    Outlining runs before this: a loose 1px sparkle that goes through
    outline() comes out ringed in near-black and reads as debris stuck to
    the sprite, not as a highlight. Anything that is a highlight rather than
    part of the silhouette belongs here."""
    if state == "sleeping":
        rect(b, 11, 1, 14, 2, WHITE)     # a little Z, floating clear of the box
        px(b, 13, 2, WHITE)
        px(b, 12, 3, WHITE)
        rect(b, 11, 4, 14, 5, WHITE)
    elif state == "light":
        rect(b, 0, 3, 2, 4, SPARK)       # lifting, so the accents sit high
        rect(b, 14, 5, 16, 6, SPARK)
        px(b, 1, 7, SPARK)
    elif state == "magnetized":
        rect(b, 0, 5, 2, 7, SPARK)       # field arcs either side
        rect(b, 14, 5, 16, 7, SPARK)
        px(b, 1, 9, SPARK)
        px(b, 14, 9, SPARK)


for state, (body, shade, expression) in PACKAGE_STATES.items():
    if state == "explosive":
        continue  # emitted below as a two-frame animation of the same name
    b = package_body(body, shade)
    eyes(b, expression)
    if state == "heavy":
        # Weight pressing down, drawn INSIDE the box. The first attempt hung
        # these below the silhouette, where outline() turned them into two
        # dark blobs that read as the package leaking.
        rect(b, 2, 14, 14, 16, darker(shade, 0.6))
    outline(b)
    accents(b, state)
    emit_single(b, "package_" + state)

# Explosive gets the one package animation: a blinking fuse spark. A fuse
# that does not move does not read as a countdown.
#
# Named "package_explosive", NOT a separate id — package.script plays
# "package_" .. state_name, so an animation under any other name would be
# art nothing ever asks for. Constraint 2 in the module docstring.
fuse_frames = []
body, shade, expression = PACKAGE_STATES["explosive"]
for lit in (True, False):
    b = package_body(body, shade)
    eyes(b, expression)
    rect(b, 8, 0, 10, 2, INK_SOFT)      # fuse stub rising from the lid
    outline(b)                          # the fuse IS part of the silhouette
    if lit:
        # The spark is an accent, so it goes on after the outline — big
        # enough to actually see, since a fuse that does not visibly change
        # between frames is not a countdown.
        rect(b, 7, 0, 12, 2, SPARK)
        rect(b, 8, 0, 11, 1, WHITE)
    fuse_frames.append(b)
emit_anim(fuse_frames, "package_explosive", 6)


# --- Tiles (bands only, see constraint 1) ------------------------------
g = img(16, 16)
band(g, 0, 2, GRASS_LIT)
band(g, 2, 5, GRASS)
band(g, 5, 7, DIRT)
band(g, 7, 13, DIRT)
band(g, 13, 16, DIRT_DARK)
emit_single(g, "tile_ground")

t = img(16, 16)
band(t, 0, 2, STONE_LIT)
band(t, 2, 5, STONE)
band(t, 5, 12, STONE_DARK)
band(t, 12, 16, STONE_DEEP)
emit_single(t, "tile_platform")


# --- Hazards and props -------------------------------------------------
# Spike: three metal teeth with a lit left edge. Not stretched in practice
# (hazards are authored at the sprite's native half-extents), so vertical
# detail is safe here.
s = img(16, 16)
for i in range(3):
    cx = 3 + i * 5
    for y in range(15):
        wdt = y // 3
        rect(s, cx - wdt, 15 - y, cx + wdt + 1, 16 - y, METAL)
        px(s, cx - wdt, 15 - y, METAL_LIT)
rect(s, 0, 14, 16, 16, METAL_DARK)      # mounting base
outline(s)
emit_single(s, "spike")

# Saw blade, 16x16. PRD 7.1 lists "Serras (rotação)" as visually distinct
# from spikes; lethal_hazard.script spins this one. Drawn radially
# symmetric-ish about the CENTER, because anything off-center wobbles
# instead of spinning once the adapter rotates it.
saw = img(16, 16)
cx = cy = 7.5
TEETH = 6
# Body radius vs tooth tip. Both must stay under 7.5 (the half-width), or
# the disc fills the whole square and reads as a blob rather than a blade —
# which is exactly what the first attempt did at a 7.8 tip.
BODY_R, TIP_R = 4.6, 7.0
for y in range(16):
    for x in range(16):
        dx, dy = x + 0.5 - cx, y + 0.5 - cy
        dist = math.hypot(dx, dy)
        # Sawtooth in angle: radius ramps from body to tip across each
        # sector, so every tooth has a leading edge and a flat back.
        phase = ((math.atan2(dy, dx) + math.pi) / (2 * math.pi) * TEETH) % 1.0
        limit = BODY_R + (TIP_R - BODY_R) * phase
        if dist <= limit:
            px(saw, x, y, METAL_LIT if dist < BODY_R * 0.75 else METAL)
        if dist <= 1.8:
            px(saw, x, y, METAL_DARK)   # hub
outline(saw)
emit_single(saw, "saw")

# Delivery zone: a pad with a flag. Reads as "here", which is the only job.
d = img(40, 40)
rect(d, 3, 29, 37, 37, PAD)
rect(d, 3, 29, 37, 31, PAD_LIT)
rect(d, 3, 35, 37, 37, PAD_DARK)
rect(d, 18, 8, 22, 29, PAD_DARK)        # pole
rect(d, 22, 10, 34, 19, FLAG)
rect(d, 22, 17, 34, 19, (206, 176, 62, 255))
outline(d)
emit_single(d, "delivery")


# --- FX ----------------------------------------------------------------
# A single burst shape, scaled and faded by main/fx/burst.script. Tinted at
# spawn, so one image serves every impact colour.
fx = img(16, 16)
cx = cy = 7.5
for y in range(16):
    for x in range(16):
        dx, dy = x + 0.5 - cx, y + 0.5 - cy
        dist = math.hypot(dx, dy)
        ang = math.atan2(dy, dx)
        # Star-ish: radius pulses with angle so it reads as a burst rather
        # than a circle, which would look like a bubble.
        limit = 4.2 + 2.6 * abs(math.sin(ang * 3))
        if dist <= limit:
            px(fx, x, y, WHITE if dist < limit * 0.45 else SPARK)
emit_single(fx, "fx_burst")


# --- Parallax background layers (PRD section 7) -------------------------
# Each layer must TILE SEAMLESSLY: background.script repeats one image to
# cover a level that can be 1200 wide. Everything here is therefore drawn
# from functions whose period is exactly the image width, so the last column
# meets the first with no seam. Do not hand-place a feature near an edge.
#
# They are also full screen height (216) and drawn bottom-anchored, since the
# camera only pans horizontally.

SKY_TOP    = (58, 62, 108, 255)
SKY_MID    = (92, 88, 140, 255)
SKY_LOW    = (146, 112, 148, 255)
HILL_FAR   = (74, 78, 122, 255)
HILL_NEAR  = (56, 60, 98, 255)
TREE_DARK  = (38, 42, 70, 255)

BG_H = 216


def sky_layer(w=384):
    im = img(w, BG_H)
    # Bands only — the sky has no horizontal features, so it tiles trivially
    # and would survive any stretch too.
    band(im, 0, 70, SKY_TOP)
    band(im, 70, 120, SKY_MID)
    band(im, 120, 150, SKY_LOW)
    band(im, 150, BG_H, SKY_LOW)
    return im


def hill_layer(w=192, amp=22, base=118, color=HILL_FAR, harmonics=(1, 2)):
    """Rolling silhouette. The wave's periods divide the width exactly, which
    is what guarantees the tile is seamless."""
    im = img(w, BG_H)
    for x in range(w):
        height = 0.0
        for k in harmonics:
            height += math.sin(2 * math.pi * k * x / w) * (amp / k)
        top = int(base - height)
        rect(im, x, top, x + 1, BG_H, color)
    return im


def tree_layer(w=128):
    """Blocky treetops, placed on a grid that divides the width so the
    pattern repeats cleanly across the seam."""
    im = img(w, BG_H)
    rect(im, 0, 150, w, BG_H, TREE_DARK)
    step = 16                      # 128 / 16 = 8 trees, exact
    for i in range(w // step):
        cx = i * step + step // 2
        top = 128 if i % 2 == 0 else 136
        rect(im, cx - 5, top, cx + 5, 152, TREE_DARK)
        rect(im, cx - 3, top - 4, cx + 3, top, TREE_DARK)
    return im


emit_single(sky_layer(), "bg_sky")
emit_single(hill_layer(192, 22, 116, HILL_FAR, (1, 2)), "bg_hills")
emit_single(hill_layer(128, 14, 140, HILL_NEAR, (1, 3)), "bg_ridge")
emit_single(tree_layer(), "bg_trees")


# --- Per-level themes ---------------------------------------------------
# One theme per level, so the ten stop being interchangeable. They arrive one
# per slice; the four generic layers above stay until the last level has its
# own, and then they go.
#
# The sky is only horizontal bands, so it is uniform along X and does not
# need to be screen-wide: 64px tiled seven times costs a sixth of the atlas
# that a 384px sky would, which is what keeps ten themes affordable.
SKY_W, FAR_W, MID_W, NEAR_W = 64, 192, 128, 128


def sky(stops):
    """A vertical gradient from (y_end, colour) stops, top to bottom."""
    im = img(SKY_W, BG_H)
    y = 0
    for y_end, colour in stops:
        band(im, y, y_end, colour)
        y = y_end
    if y < BG_H:
        band(im, y, BG_H, stops[-1][1])
    return im


def treeline(w, color, step=16, tall=128, short=136, ground=150):
    """Tapered canopies on a grid that divides the width, so the pattern
    repeats across the seam. `step` must divide `w`.

    Tapered rather than rectangular on purpose: flat-topped blocks read as a
    fence or a skyline, which is what level 7's city wants and what a forest
    must not look like."""
    assert w % step == 0, "treeline step must divide the width"
    im = img(w, BG_H)
    rect(im, 0, ground, w, BG_H, color)
    for i in range(w // step):
        cx = i * step + step // 2
        top = tall if i % 2 == 0 else short
        rect(im, cx - 1, top + 6, cx + 1, ground + 2, color)   # trunk
        # Canopy: widest at the bottom, narrowing in three steps.
        for level, (half, y0, y1) in enumerate((
                (6, top + 10, ground - 2),
                (5, top + 5, top + 10),
                (3, top + 1, top + 5),
                (1, top - 1, top + 1))):
            rect(im, cx - half, y0, cx + half, y1, color)
    return im


# Level 1 — Tutorial Soft: dusk over rolling hills. Warm, open, unthreatening;
# it is the first thing anyone sees.
L1_SKY_TOP  = (48, 52, 96, 255)
L1_SKY_HIGH = (86, 78, 132, 255)
L1_SKY_MID  = (138, 100, 148, 255)
L1_SKY_WARM = (196, 126, 132, 255)
L1_SKY_LOW  = (232, 164, 122, 255)
L1_FAR      = (78, 80, 126, 255)
L1_MID      = (58, 62, 102, 255)
L1_NEAR     = (36, 40, 68, 255)

emit_single(sky([(48, L1_SKY_TOP), (86, L1_SKY_HIGH), (116, L1_SKY_MID),
                 (140, L1_SKY_WARM), (BG_H, L1_SKY_LOW)]), "bg1_sky")
emit_single(hill_layer(FAR_W, 24, 118, L1_FAR, (1, 2)), "bg1_far")
emit_single(hill_layer(MID_W, 14, 142, L1_MID, (1, 3)), "bg1_mid")
emit_single(treeline(NEAR_W, L1_NEAR), "bg1_near")


# --- Atlas -------------------------------------------------------------
def verify_contract():
    """Fail loudly if an animation the scripts play is missing.

    player.script plays "player_" .. player_movement.animation_state(...) and
    package.script plays "package_" .. the state machine's state name. A
    missing entry makes play_flipbook error at RUNTIME, and the headless
    suite renders nothing, so no test can catch it — this is the only place
    it can be caught cheaply. Constraint 2 in the module docstring.

    Keep these two lists in sync with main/core/player_movement.lua's
    animation_state and main/core/package_state_machine.lua's states.
    """
    required = {"player_" + s for s in ("idle", "run", "jump", "fall", "land",
                                        "death")}
    required |= {"package_" + s for s in PACKAGE_STATES}
    # Referenced as default_animation by the .sprite components.
    required |= {"tile_ground", "tile_platform", "spike", "saw", "delivery"}
    required |= {"bg_sky", "bg_hills", "bg_ridge", "bg_trees", "fx_burst"}
    # Per-level themes, added one slice at a time.
    for level in (1,):
        required |= {"bg%d_%s" % (level, role)
                     for role in ("sky", "far", "mid", "near")}

    emitted = set(SINGLES) | {a["id"] for a in ANIMS}
    missing = sorted(required - emitted)
    if missing:
        raise SystemExit(
            "generate_sprites: missing animations the game plays: "
            + ", ".join(missing))
    unused = sorted(emitted - required)
    if unused:
        # Not fatal — extra art may be intentional — but it is always worth
        # knowing, since the usual cause is a typo'd name that no script
        # will ever ask for.
        print("   note: emitted but never played:", ", ".join(unused))


def write_atlas():
    verify_contract()
    lines = []
    for name in sorted(SINGLES):
        lines.append("images {")
        lines.append('  image: "/main/sprites/%s.png"' % name)
        lines.append("  sprite_trim_mode: SPRITE_TRIM_MODE_OFF")
        lines.append("}")
    for anim in sorted(ANIMS, key=lambda a: a["id"]):
        lines.append("animations {")
        lines.append('  id: "%s"' % anim["id"])
        for frame in anim["frames"]:
            lines.append("  images {")
            lines.append('    image: "/main/sprites/%s.png"' % frame)
            lines.append("    sprite_trim_mode: SPRITE_TRIM_MODE_OFF")
            lines.append("  }")
        lines.append("  playback: %s" % anim["playback"])
        lines.append("  fps: %d" % anim["fps"])
        lines.append("  flip_horizontal: 0")
        lines.append("  flip_vertical: 0")
        lines.append("}")
    lines += ["margin: 0", "extrude_borders: 2", "inner_padding: 0", ""]
    with open(os.path.join(OUT, "game.atlas"), "w") as f:
        f.write("\n".join(lines))
    print("  ", "game.atlas", "(%d images, %d animations)" % (len(SINGLES), len(ANIMS)))


write_atlas()
print("generated placeholder sprites ->", os.path.relpath(OUT))
