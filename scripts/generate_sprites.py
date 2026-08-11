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


# Idle: a two-frame breath. Barely moves — enough to look alive, not enough
# to distract while the player is reading the level.
idle_frames = []
for lift in (0, 1):
    p = courier(body_top=5 + lift)
    legs(p, (7, 20, 4), (13, 20, 4))
    outline(p)
    idle_frames.append(p)
emit_anim(idle_frames, "player_idle", 3)

# Run: four frames, contact / pass / contact / pass, with a one-pixel body
# bob. Arms swing opposite the legs.
run_poses = [
    ((5, 20, 4), (15, 20, 4), 12, 15, 0),
    ((8, 20, 4), (13, 19, 5), 13, 14, 1),
    ((6, 20, 4), (14, 20, 4), 15, 12, 0),
    ((9, 19, 5), (12, 20, 4), 14, 13, 1),
]
run_frames = []
for left, right, arm_a, arm_b, bob in run_poses:
    p = courier(body_top=5 + bob, arm_left=arm_a, arm_right=arm_b)
    legs(p, left, right)
    outline(p)
    run_frames.append(p)
emit_anim(run_frames, "player_run", 10)

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
    required = {"player_" + s for s in ("idle", "run", "jump", "fall", "land")}
    required |= {"package_" + s for s in PACKAGE_STATES}
    # Referenced as default_animation by the .sprite components.
    required |= {"tile_ground", "tile_platform", "spike", "delivery"}

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
