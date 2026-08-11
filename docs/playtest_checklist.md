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
- [ ] **Screen shake fires on impact**: a hard landing nudges, a death hits
  harder, a detonation is the biggest. It settles quickly rather than
  rattling on.
- [ ] Shake **never scrolls the background or kills you** — it is visual
  only. Blow up next to a screen edge and confirm nothing dies from it.
- [ ] **Saws spin and spikes do not**, and the two are tellable apart at a
  glance while playing (PRD 7.1).
- [ ] A spinning saw kills at the **same distance** as a still one — the
  hitbox must not appear to change with the blade's angle.
- [ ] **A burst appears on impact** — hard landing, death, detonation — in a
  colour that suits the event, growing and fading in about a third of a
  second rather than lingering.
- [ ] **The UI renders in the pixel font**, not Defold's default — title,
  menu, hint, result screen, and the package's debug number.
- [ ] Every glyph is legible and correctly spaced: check a quip with
  punctuation, a time like "40.2s", and the volume bar's # and . characters.
- [ ] No faint fringes around letters (a padding-bleed symptom).
- [ ] Bursts **clean themselves up**: die repeatedly in one attempt and
  confirm nothing accumulates on screen or slows the game down.

## Music (PRD section 8) — listening test

Nothing in this section can be automated: the suite proves the wiring and
the generator proves the signal is clean, but **no one has ever heard any of
this**. Judge it by ear.

- [ ] Each of the ten levels plays its **own theme**, and they are
  distinguishable from one another.
- [ ] The theme suits the level: 3 heavy and low, 4 urgent, 8 sparse and
  slow, 10 the busiest.
- [ ] **Loops are seamless** — sit on one level for two full loops and
  listen for a click or a gap at the seam. The generator checks the sample
  values line up, which is necessary but not sufficient.
- [ ] Changing level **swaps** the track rather than layering two.
- [ ] Menu music plays on the menu, stops when a level starts, and comes
  back on returning to the menu.
- [ ] Win and game-over stings fire and do not loop.
- [ ] Nothing distorts at master volume 100%.
- [ ] No track is so busy it buries the SFX that carry gameplay information
  (package panic, the explosive fuse).

## Performance (PRD 9.5) — real build only

- [ ] **60 FPS stable** in Chrome and Firefox (DevTools performance panel),
  including during Panic shake and Explosive.
- [ ] No GC hitches on level load or restart.
- [ ] Build size is reasonable with engine compression on.

## Known gaps carried into this pass

- **All audio is synthesized by `scripts/generate_audio.py`** — 32 cues,
  including ten per-level chiptune themes written by a small NES-style
  tracker (2 pulse + triangle + noise, ADSR, chord progressions, drums).
  There are no sampled assets anywhere in this project. It is deterministic,
  so regenerating is byte-identical and any diff is a real edit.
  **Nobody has heard it.** The generator asserts what is checkable (no
  clipping, no DC offset, clean loop seams, every named cue has a file) and
  the rest is the listening test above.
- **Visuals are generated placeholder sprites, not final art.** The atlas is
  wired in (`scripts/generate_sprites.py` → `main/sprites/game.atlas`), so
  the game renders shapes rather than `[label]` text — but judge **layout,
  size and readability**, not art quality. Real pixel art is a drop-in swap.
- **The package still shows a debug stress number** next to it
  (`debug_hud` on `package.script`, on by default). It is there to make this
  pass judgeable; turn it off before shipping.
- **Controls remapping** (PRD 6.1's "Controles") is unimplemented.
- **The pixel font renders nowhere the suite can see it.** The suite passes
  with it wired (467), which proves it loads and never throws, but a null
  graphics device draws no glyphs. If the UI comes up blank, garbled or in
  the wrong shapes, the font is where to look first —
  `scripts/generate_font.py` regenerates it, and reverting the
  `font:`/`material:` lines in `main/ui/*.label` back to
  `/builtins/fonts/default.font` + `label.material` restores the previous UI
  immediately.
- **`dmengine_headless` intermittent wedge**: affects the automated suite
  only (mitigated by retry), not the real windowed build. If a real build
  ever wedges the same way, that is new information worth capturing.
