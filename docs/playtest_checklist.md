# Playtest & Polish Checklist (phase 22)

The automated suite covers pure logic and object wiring, but **nothing
automated loads a level collection or runs a real graphics context** (see
CLAUDE.md). Everything below is manual, done in the Defold Editor or a real
`dmengine` build — not headless. Check each box by actually playing.

This is the acceptance pass for PRD sections 10 and 11. For what is already
proven, what is still missing, and who can do each remaining piece, see
[`v1_0_acceptance_status.md`](v1_0_acceptance_status.md).

## Per-level acceptance (PRD section 11)

For **each** of the 10 levels, confirm:

- [ ] **Completable fairly** — a first-time player can finish without
  frame-perfect input or memorized tricks.
- [ ] **At least 2 clear second-layer moments** — the level's twist bites in
  at least two distinct, readable ways.
- [ ] **Common deaths are legible in < 2s** — when you die, it is obvious
  *why* within two seconds (PRD section 11).
- [ ] **The package reacts visibly and audibly** — audio is currently
  generated placeholders, so judge *whether a cue fires at the right moment*,
  not whether it sounds good.
- [ ] **Restart (R) is instant** — no perceptible reload pause.
- [ ] **No softlocks** — there is no state you can reach with no way forward
  and no death to reset you.
- [ ] **The madness is clearly felt** — the level's central mechanic is
  unmistakable, not subtle.
- [ ] **Attempt duration lands in the PRD's 35-75s target** (section 5,
  "Estrutura das 10 Fases"). Time a clean run; if it is far under, the level
  is too short.

### Level-specific things to watch

- [ ] **L1 Tutorial Soft** — package sticks with no initial jolt; first
  spike death teaches the gap.
- [ ] **L2 Jump Scare** — stress climbs much faster per jump than L1; the
  opening gap genuinely needs a full jump; falling platforms drop on
  hesitation.
- [ ] **L3 Heavy Duty** — during a Heavy cycle the player is visibly slower
  and lower **but still clears every gap** (the phase-13 fix); the cycle
  turning mid-jump is felt but never an unfair death.
- [ ] **L4 Hot Potato** — the fuse gives enough time to sprint a stretch;
  going too slow detonates, going too fast spikes stress.
- [ ] **L5 Magnet Madness** — dodging one spike pulls another into your
  path; the overhead spike drags down onto you.
- [ ] **L6 Gravity Moods** — the mood is **telegraphed before it applies**;
  a floaty mood while carrying Light compounds; no gap is unclearable in the
  heavy (1.8x) mood.
- [ ] **L7 Control Freak** — inversion flips mid-hold correctly (you do not
  have to release and re-press); the relief windows are readable.
- [ ] **L8 Sleepy Package** — tall drops wake the package; waking lands it
  straight in Panic.
- [ ] **L9 Mirror World** — reactions are mirrored through the main stretch;
  the final section un-mirrors the world **while the package still reacts
  backwards** (the muscle-memory trap).
- [ ] **L10 Final Delivery** — all three combined modifiers are survivable
  together; no gap is impossible when two stack (the reason it cycles
  Magnetized, not Heavy).

## Menu, progression, save (PRD 6)

- [ ] Fresh boot opens on the main menu with **no** "Continue" entry.
- [ ] "New Game" starts level 1.
- [ ] Completing a level shows the result screen with time, attempts and a
  quip; "Next Level" advances.
- [ ] After any progress, "Continue" appears and resumes the furthest level.
- [ ] Close and reopen the game — **progress persisted** (this is the one
  thing the suite genuinely cannot check: it runs `in_memory_only`).
- [ ] "Level Select" shows unlocked levels; locked ones are not selectable.
- [ ] "New Game" from a save with progress **wipes progress but keeps volume
  settings**.
- [ ] Esc pauses a live level (the level actually freezes); Esc resumes.
- [ ] Pause → Restart reloads; Pause → Main Menu unloads and returns.
- [ ] Beating level 10 shows the all-complete state; every level is
  replayable afterward (PRD 6.2).

## Options (PRD 6.1)

- [ ] Master/Music/SFX sliders move with left/right and show a bar.
- [ ] Fullscreen toggles and actually changes the window.
- [ ] Settings persist across a restart of the game.
- [ ] Each slider **audibly** changes its channel; master scales the others.
  (Now checkable — placeholder audio is wired. Judge routing and relative
  levels, not sound quality.)
- [ ] **Controls** opens from Options and shows the current key for Move
  Left, Move Right and Jump.
- [ ] Selecting a row waits for a key; the key you press becomes the binding
  and the row updates.
- [ ] Pressing a key **another action already uses** is refused with a
  readable reason, and nothing changes.
- [ ] Binding an action to **Down or Up does not also scroll the menu** —
  one physical key raises both a remappable and a menu action, so this is
  the case most likely to break.
- [ ] Esc during capture cancels; Esc on the screen returns to Options.
- [ ] The new binding **works in a level**, including after restarting the
  game (it lives in the settings file, not the save file).
- [ ] "New Game" wipes progress but **keeps the remapped keys**.

## Visuals (placeholder sprites, phase 24)

Nothing here is checkable headless — the whole point of this section is that
a human has to look at the screen.

- [ ] Every object renders as a **sprite**, not text: player, package,
  ground, platforms, falling platforms, spikes, delivery zone.
- [ ] **Platform widths match what you can stand on** — walk to each edge and
  confirm the sprite ends exactly where the footing does.
- [ ] **The base floor matches its walkable range** in every level. This was
  wrong before phase 24 (the floor was drawn 128 wide in all ten levels while
  the real range is 112 in level 1 and 140 in levels 3-10), so it is worth
  checking per level rather than spot-checking one.
- [ ] The player **flips horizontally** when changing direction.
- [ ] The player's animation changes across idle / run / jump / fall / land.
- [ ] The package **changes image across all 8 states** (force them with the
  levels that cycle each, or the debug messages).
- [ ] **No z-fighting / flicker** where objects overlap. Intended draw order,
  back to front: ground, platforms, delivery zone, hazards, player, package.
- [ ] The ground and platform tiles do **not look smeared** when stretched
  wide — they are drawn as horizontal bands specifically to survive this.
- [ ] **Parallax reads as depth**: walking right, the sky barely moves, the
  hills drift, the tree line moves most. Nothing slides against the world.
- [ ] **No seam** appears in any background layer as the level scrolls, and
  no gap at either end of a long level.

## Performance (PRD 9.5) — real build only

- [ ] **60 FPS stable** in Chrome and Firefox (DevTools performance panel),
  including during Panic shake and Explosive.
- [ ] No GC hitches on level load or restart.
- [ ] Build size is reasonable with engine compression on.

## Known gaps carried into this pass

- **Audio is placeholders, not final.** All 22 cues from
  `core/audio_cues.lua` exist as generated 8-bit `.ogg` files
  (`scripts/generate_audio.py`) and are wired end to end, so every audio
  checkbox above is now checkable — but judge **whether the right cue fires
  at the right moment**, not whether it sounds good. Real chiptune is a
  drop-in swap (filenames match the cue catalogue) and changes no trigger
  site.
- **Visuals are generated placeholder sprites, not final art.** The atlas is
  wired in (`scripts/generate_sprites.py` → `main/sprites/game.atlas`), so
  the game renders shapes rather than `[label]` text — but judge **layout,
  size and readability**, not art quality. Real pixel art is a drop-in swap.
- **The package still shows a debug stress number** next to it
  (`debug_hud` on `package.script`, on by default). It is there to make this
  pass judgeable; turn it off before shipping.
- **Controls remapping** (PRD 6.1's "Controles") is unimplemented.
- **`dmengine_headless` intermittent wedge**: affects the automated suite
  only (mitigated by retry), not the real windowed build. If a real build
  ever wedges the same way, that is new information worth capturing.
