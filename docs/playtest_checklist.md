# Playtest & Polish Checklist — rooms edition

The automated suite covers pure logic and object wiring, but **nothing
automated draws a pixel or plays a sound** (see CLAUDE.md). Everything below
is manual, done in a real windowed build. Check each box by actually
playing.

**To launch the game: `make play`.** To open one room directly, skipping the
ones before it: **`make play-room ROOM=N`** (N is the global room number,
1..40). `make checklist` prints this file.

The game is 40 one-screen rooms in 8 themes of 5 — see PRD section 10's
amendment. Within a theme: room 1 teaches by betraying once, rooms 2-4
charge for it, room 5 combines with an earlier theme's piece.

## Whole-game checks (do these first, they gate everything else)

- [ ] **Fullscreen does not touch the Mac's resolution.** Launch and quit:
      the desktop resolution must not change either way, Cmd-Tab must work
      while the game is up, and the game fills the screen as a borderless
      window. (This is the v0.65.0 engine bump's entire point; only a human
      at the machine can see it.)
- [ ] The select screen is a carousel: ONE theme per page, W/S flips theme,
      arrows move within the page, Enter plays, nothing overflows 216px.
      Prev/next buttons appear only when a page exists in that direction.
- [ ] Entering any room plays that THEME's music, not the generic loop, and
      shows that theme's background (eight distinct palettes across the
      themes — dusk hills appear nowhere except the menu).
- [ ] Winning a room, Next Level advances to the next room; Retry replays
      the SAME room; Main Menu returns; exactly ONE player on screen at all
      times (the two-players bug of v0.54.0 must stay dead).
- [ ] Pause (Esc) freezes a room — package shake and chasers included — and
      Resume continues it.
- [ ] R restarts instantly: player at the room's spawn, platforms restored,
      door back home with its lies re-armed, chaser back at its start.
- [ ] Progression: winning room N unlocks N+1, saves survive a full quit
      and relaunch, Continue resumes at the furthest room.

## Per-theme acceptance

Judge each theme by its own promise. PRD section 11 still applies to every
room: fair, deaths legible in under 2s, restart instant, no softlocks, the
madness clearly felt.

### THE FLOOR LIES (rooms 1-5, jagged peaks)
- [ ] Room 1: the two platforms look IDENTICAL and the first one drops —
      the lesson costs one death and about four seconds.
- [ ] Falling platforms shudder while stood on, and the shake visibly GROWS
      as the drop approaches (2px/16Hz — does it read as a warning, or as a
      rendering glitch? Tunables: wobble_amplitude/wobble_frequency).
- [ ] The slower fall (150) reads as the platform LEAVING, not vanishing.

### THE DOOR LIES (rooms 6-10, teal reflection)
- [ ] The fleeing door moves while you are still committing to the jump —
      funny, not merely annoying. (Tunable: trigger_distance, default 48.)
- [ ] A door that has spent its retreats stays put — the room is always
      finishable.
- [ ] Room 8 (vanish): the door's off phase is visibly a closed door, and
      waiting on solid ground always works.

### DO NOT STOP (rooms 11-15, red ruins)
- [ ] The wall enters the screen early enough to read as a threat before it
      is a death.
- [ ] Being caught reads correctly: the wall's face kills, the sprite fills
      the space behind it.
- [ ] Room 15: the door's retreat never sends you back toward the wall.

### UP IS A SUGGESTION (rooms 16-20, floating islands)
- [ ] Walking on ceilings reads as intentional, not as a bug. (The player
      sprite is NOT flipped upside down — decide whether it needs to be.)
- [ ] Jumps go DOWN, falls go UP, and the package hangs BELOW the player.
- [ ] Room 18: the falling platform falls AWAY (down) from the player
      standing under it.

### DEAD WEIGHT (rooms 21-25, factory chimneys)
- [ ] The Heavy cycle is readable: you can tell the package is heavy BEFORE
      committing to a jump (state color + the player's own sluggishness).
- [ ] The 3s/3s cycle: long enough to plan around, short enough to matter.

### LIT FUSE (rooms 26-30, hot dunes)
- [ ] The fuse is visible/audible enough that dying to it reads as "too
      slow", never as "what happened".
- [ ] Every room is beatable when the fuse lights at the worst moment
      (validate proves the walk fits; only play proves it FEELS possible).

### ATTRACTION (rooms 31-35, purple pillars)
- [ ] Hanging spikes visibly drift toward the package during the pull.
- [ ] A dragged spike never ends up parked ON the door (this is the one
      thing validate cannot prove — it depends on where the package is when
      the cycle turns; report the room number if it happens).

### WRONG WAY (rooms 36-40, upside-down city)
- [ ] The flip is READABLE: you can tell controls are inverted before the
      first spike teaches you. If not, the fix is a visual cue on the
      player, not a rooms change.
- [ ] Airborne mode (37, 38, 40): controls flip exactly while airborne and
      return exactly on landing.

## Performance & polish (PRD phase 22, unchanged)

- [ ] Steady 60 FPS on the target machines (Chrome/Firefox DevTools for the
      web build).
- [ ] Audio: sliders in Options change music and SFX volume; every state
      change and death has its cue.
- [ ] Controls remapping: movement rebinds work, R/Esc/Enter stay fixed,
      bindings survive a relaunch.
