#!/usr/bin/env python3
"""Check every level's geometry against what the player can actually do.

Nothing automated loads a level collection to play it, so a level that is
literally impossible builds, boots and passes the suite. This has bitten
twice: level 6 once had a 70-unit gap that could not be crossed in the heavy
gravity mood, and level 10 once stacked the heavy mood on a Heavy package,
which put the jump apex below the level's own step-ups. Both were caught by
doing this arithmetic on paper. This does it on every run instead.

It reads the collections as data — no engine, no Defold — and fails if any
gap is wider than the player can jump, or any step taller than the player
can reach, USING THE WORST MODIFIER THAT LEVEL ITSELF DECLARES. A level that
cycles Heavy is held to Heavy's reach even in the stretches where the cycle
is off, because the cycle can turn anywhere.

Run: python3 scripts/check_levels.py   (or `make check-levels`)
"""
import glob
import math
import os
import re
import sys

LEVELS = os.path.join(os.path.dirname(__file__), "..", "main", "levels")

# --- the player's real constants ---------------------------------------
# Read from main/player/player.script's go.property defaults rather than
# repeated here, so this cannot drift from the game (rule 5).
PLAYER = os.path.join(os.path.dirname(__file__), "..", "main", "player", "player.script")
CORE = os.path.join(os.path.dirname(__file__), "..", "main", "core", "player_movement.lua")
PACKAGE = os.path.join(os.path.dirname(__file__), "..", "main", "package", "package.script")
ZONE = os.path.join(os.path.dirname(__file__), "..", "main", "delivery",
                    "delivery_zone.script")


def property_default(path, name):
    src = open(path).read()
    m = re.search(r'go\.property\("%s",\s*(-?[\d.]+)\)' % name, src)
    if not m:
        raise SystemExit("check_levels: could not read %s from %s" % (name, path))
    return float(m.group(1))


MOVE_SPEED = property_default(PLAYER, "move_speed")
JUMP_VELOCITY = property_default(PLAYER, "jump_velocity")
GRAVITY = abs(property_default(PLAYER, "gravity"))

_core = open(CORE).read()
HEAVY_SPEED = float(re.search(r"local HEAVY_SPEED_MULTIPLIER = ([\d.]+)", _core).group(1)) \
    if re.search(r"local HEAVY_SPEED_MULTIPLIER = ([\d.]+)", _core) else 0.65
# The jump multiplier is stored as a height ratio and applied to velocity.
HEAVY_JUMP = math.sqrt(0.70)
HEAVY_MOOD_GRAVITY = 1.8


def reach(speed, jump_v, gravity):
    """How far the player travels horizontally during one full jump, and how
    high that jump gets. Airtime is 2v/g; apex is v^2/2g."""
    airtime = 2 * jump_v / gravity
    return speed * airtime, (jump_v ** 2) / (2 * gravity)


NORMAL = reach(MOVE_SPEED, JUMP_VELOCITY, GRAVITY)
HEAVY = reach(MOVE_SPEED * HEAVY_SPEED, JUMP_VELOCITY * HEAVY_JUMP, GRAVITY)
HEAVY_MOOD = reach(MOVE_SPEED, JUMP_VELOCITY, GRAVITY * HEAVY_MOOD_GRAVITY)
BOTH = reach(MOVE_SPEED * HEAVY_SPEED, JUMP_VELOCITY * HEAVY_JUMP,
             GRAVITY * HEAVY_MOOD_GRAVITY)


def budget(src):
    """The worst case this level can put the player in, from what the
    collection itself declares. Heavy and the heavy gravity mood are the only
    two modifiers that touch mobility — Magnetized, Explosive, Sleeping and
    control inversion do not, which is exactly why level 10 cycles Magnetized
    instead of Heavy."""
    mood = "/main/level/gravity_mood.go" in src
    # heavy_cycle drives Heavy only when it is NOT in one of its other modes.
    cycles_heavy = ("/main/level/heavy_cycle.go" in src
                    and not re.search(r'id: "(explosive|magnetized|sleeping)_mode"', src))
    if mood and cycles_heavy:
        return BOTH, "Heavy + heavy gravity mood"
    if cycles_heavy:
        return HEAVY, "Heavy"
    if mood:
        return HEAVY_MOOD, "heavy gravity mood"
    return NORMAL, "no mobility modifier"


def surfaces(src):
    """Every standable surface as (left, right, top), from the authored
    position plus the half-extents the AABB ground check uses."""
    out = []
    pattern = re.compile(
        r'instances \{\n  id: "[^"]+"\n  prototype: "[^"]*(platform|falling_platform)\.go"\n'
        r'  position \{\n    x: ([-\d.]+)\n    y: ([-\d.]+)\n(?:.*?\n)*?\}\n')
    for m in pattern.finditer(src):
        block = m.group(0)
        hw = re.search(r'id: "half_width"\n      value: "([-\d.]+)"', block)
        hh = re.search(r'id: "half_height"\n      value: "([-\d.]+)"', block)
        hw = float(hw.group(1)) if hw else 32.0
        hh = float(hh.group(1)) if hh else 8.0
        x, y = float(m.group(2)), float(m.group(3))
        out.append((x - hw, x + hw, y + hh))
    return sorted(out)


def base_floor(src):
    """The level's always-present floor, described on the PLAYER instance."""
    def prop(name, default):
        m = re.search(r'id: "%s"\n      value: "([-\d.]+)"' % name, src)
        return float(m.group(1)) if m else default
    return (prop("ground_x_min", 0.0), prop("ground_x_max", 140.0),
            prop("ground_y_top", 48.0))


# The player clears a gap wider than its airborne travel by exactly its own
# width: it leaves the edge with its trailing half still over the ledge and
# lands with its leading half already over the next one. CLAUDE.md states
# this as `gap - 2 * player_half_width`, and leaving it out reports
# perfectly playable gaps as impossible.
PLAYER_HALF_WIDTH = property_default(PLAYER, "half_width")


def reachable_from(target, others, max_gap, max_step):
    """Is `target` reachable from ANY other surface, not merely the one
    before it in x order? Sorting by x and comparing neighbours assumes the
    player must progress strictly left to right, which flags a high platform
    as unreachable even when a lower one right beside it is the real
    approach."""
    tl, tr, tt = target
    for ol, orr, ot in others:
        if (ol, orr, ot) == target:
            continue
        # Dropping down is free; only climbing is limited by the apex. An
        # earlier version skipped the higher source instead of accepting it,
        # which reported every platform below a ledge as unreachable.
        if tt - ot > max_step:
            continue
        if orr >= tl and ol <= tr:
            return True  # overlapping in x: step across, no jump needed
        gap = tl - orr if orr < tl else ol - tr
        if gap - 2 * PLAYER_HALF_WIDTH <= max_gap:
            return True
    return False


# --- the delivery zone --------------------------------------------------
# Everything above answers "can the player get there". None of it answers
# "is there a there" — the win condition was not checked at all until a
# level shipped with its delivery zone hanging over the pit, 45 units past
# the end of the last platform, while this script reported ok. Reaching
# every surface is worth nothing if the goal is not on one.

PLAYER_HALF_HEIGHT = property_default(PLAYER, "half_height")
PACKAGE_OFFSET_Y = property_default(PACKAGE, "offset_y")
PACKAGE_HALF_HEIGHT = property_default(PACKAGE, "half_height")
ZONE_HALF_WIDTH = property_default(ZONE, "half_width")
ZONE_HALF_HEIGHT = property_default(ZONE, "half_height")


def delivery_zone(src):
    """The zone as (centre x, centre y, half width, half height).

    Scoped to the zone's own instance block, unlike base_floor's file-wide
    search: half_width is a property on every platform and hazard too, so a
    loose regex would happily return a platform's."""
    m = re.search(r'instances \{\n  id: "[^"]*delivery[^"]*"\n(?:.*?\n)*?\}\n', src)
    if not m:
        return None
    block = m.group(0)
    pos = re.search(r'position \{\n    x: ([-\d.]+)\n    y: ([-\d.]+)', block)

    def prop(name, default):
        found = re.search(r'id: "%s"\n      value: "([-\d.]+)"' % name, block)
        return float(found.group(1)) if found else default

    return (float(pos.group(1)), float(pos.group(2)),
            prop("half_width", ZONE_HALF_WIDTH),
            prop("half_height", ZONE_HALF_HEIGHT))


def deliverable_from(zone, walk):
    """Is there a surface the player can stand on that puts the package
    INSIDE the zone?

    Containment, not overlap: core/delivery.lua's is_inside requires the
    package rect to be fully within the zone (PRD 3.4's "dentro"), so a
    check that accepted a corner touching would pass levels the game itself
    would refuse to award.

    The vertical test is exact — the package's resting height is fully
    determined by the surface. The horizontal one is deliberately coarse
    (does the surface's span reach the zone's at all), because the player
    can stand anywhere along the surface and carries the package offset_x to
    whichever side it is facing. That makes this side permissive rather than
    strict: it catches a zone with no surface near it, which is the failure
    that has actually happened, and would not catch a zone overhanging a
    surface by a few pixels."""
    cx, cy, zhw, zhh = zone
    for left, right, top in walk:
        # Standing on this surface, the player's centre is half its height
        # above the top, and the package rides offset_y above that.
        rest_y = top + PLAYER_HALF_HEIGHT + PACKAGE_OFFSET_Y
        if right < cx - zhw or left > cx + zhw:
            continue                       # cannot stand under the zone
        if (cy - zhh <= rest_y - PACKAGE_HALF_HEIGHT
                and rest_y + PACKAGE_HALF_HEIGHT <= cy + zhh):
            return True
    return False


def check(path):
    src = open(path).read()
    name = os.path.basename(path)
    (max_gap, max_step), why = budget(src)
    problems = []

    walk = [base_floor(src)] + surfaces(src)
    walk.sort()
    for target in walk[1:]:
        if not reachable_from(target, walk, max_gap, max_step):
            tl, tr, tt = target
            problems.append(
                "the surface at x=%.0f..%.0f (top y=%.0f) cannot be reached from "
                "any other: needs a gap <=%.1f and a step <=%.1f (%s)"
                % (tl, tr, tt, max_gap, max_step, why))

    zone = delivery_zone(src)
    if zone is None:
        problems.append("no delivery zone: the level cannot be won")
    elif not deliverable_from(zone, walk):
        cx, cy, zhw, zhh = zone
        problems.append(
            "the delivery zone at x=%.0f y=%.0f (%.0fx%.0f) has no surface "
            "under it that puts the package inside: standing on a surface "
            "with top y=T leaves the package centred at T+%.0f, and it must "
            "fit whole within y=%.0f..%.0f"
            % (cx, cy, zhw * 2, zhh * 2,
               PLAYER_HALF_HEIGHT + PACKAGE_OFFSET_Y, cy - zhh, cy + zhh))
    return name, why, max_gap, max_step, problems


def main():
    print("player reach: %.1f wide / %.1f high normal, %.1f/%.1f Heavy, "
          "%.1f/%.1f heavy mood, %.1f/%.1f both"
          % (NORMAL[0], NORMAL[1], HEAVY[0], HEAVY[1],
             HEAVY_MOOD[0], HEAVY_MOOD[1], BOTH[0], BOTH[1]))
    failed = False
    for path in sorted(glob.glob(os.path.join(LEVELS, "level_*.collection"))):
        name, why, max_gap, max_step, problems = check(path)
        status = "FAIL" if problems else "ok"
        print("  %-22s %-26s gap<=%5.1f step<=%5.1f  %s"
              % (name, why, max_gap, max_step, status))
        for p in problems:
            print("      %s" % p)
            failed = True
    if failed:
        raise SystemExit("check_levels: at least one level cannot be completed")
    print("all levels are within what the player can actually do")


main()
