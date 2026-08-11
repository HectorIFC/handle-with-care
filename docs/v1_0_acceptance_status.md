# v1.0 Acceptance Status

Where the project actually stands against **PRD section 10** (the v1.0 scope)
and **PRD section 11** (the per-level acceptance criteria), as of
`v0.27.0` (`ae139f8`).

This document is deliberately conservative. An item is only **Done** when
something checkable proves it — a passing test, a file that exists, a
behavior reproducible headless. Anything that can only be confirmed by a
human looking at a screen, hearing a sound, or running a native toolchain is
marked as such, not quietly counted as finished.

Companion document: [`playtest_checklist.md`](playtest_checklist.md) is the
manual pass itself (the boxes to tick). This file is the map of what is
left and who can do it.

**Automated suite at this commit: 401 tests, 401 passing, 718 assertions,
0 failed, 0 errors.** Reproduced across two independent runs (one clean, one
that hit the known engine wedge and was absorbed by `run_tests.sh`'s retry).

---

## PRD section 10 — v1.0 scope

| Scope item | Status | Evidence / what is missing |
|---|---|---|
| 10 complete levels | **Built, acceptance pending** | `main/levels/level_01..10.collection` all exist, are reachable from the menu, and each level's mechanic has unit + integration coverage of its driver. What is *not* proven is section 11 (fairness, legibility, 35-75s pacing) — that needs the playtest. |
| Sticky package: physics + 8 states | **Done** | `core/package_physics.lua`, `core/package_state_machine.lua`, `core/stress.lua`, plus `explosive`, `magnetism`, `heavy_cycle`, `gravity_driver`, `input_inversion`, `mirror`. All 8 PRD states reachable in play, all unit-tested, all covered by integration suites against a real headless collection. |
| Menu + Save/Load | **Done in code; persistence across a real restart is manual** | `core/screen_flow.lua` + `main/ui/screens.script` (menu, level select, pause, result screen); `core/save.lua` + `save_adapter`; `core/settings.lua` + `settings_adapter` (kept separate so "New Game" cannot wipe preferences). The suite runs `in_memory_only`, so *actually writing and re-reading a file across a process restart* is a checklist item, not a test. |
| Complete audio | **Placeholders wired; real assets pending** | `core/audio_cues.lua` catalogs all 22 PRD section 8 cues; `scripts/generate_audio.py` synthesizes deterministic 8-bit `.ogg` placeholders; `main/audio/audio.script` plays the cue named by a `play_cue` message, with group gains from the settings adapter. Tests prove the wiring reaches the audio object and never throws — **not** that anything is audible (the null sound device cannot). Real chiptune is asset work; because filenames match the cue catalogue, the swap is drop-in with no trigger-site changes. |
| Web build (Poki + site) | **Not started — needs a native environment** | No build has been produced or run in a browser. Performance (PRD 9.5) is only checkable there. |
| Steam build (Windows) | **Save routing done; build not started** | `core/save_location.lua` (pure: app id, filenames, sys-vs-Steam backend decision, unit-tested) + `main/ui/storage.lua` (the single read/write seam). Setting an adapter's `steam` property routes writes through Steam Cloud with a local-file fallback. **The Steam Defold extension that provides the `steam` module `storage.lua` guards for is not added**, and no Windows build exists. |
| Keyboard support | **Done** | `input/game.input_binding`; move/jump/restart/menu navigation all bound and exercised by integration tests. Controls **remapping** (PRD 6.1) shipped in phase 25 — see below. |

Out of scope for v1.0 per the PRD and correctly absent: multiplayer, level
editor, native mobile, cosmetics, leaderboards, levels beyond 10.

---

## PRD section 11 — per-level acceptance

The seven criteria ("completable fairly", "at least 2 second-layer moments",
"deaths legible in < 2s", "the package reacts visibly and audibly",
"instant restart", "no softlocks", "the madness is felt") are **all
judgement calls about how the game feels**. None of them is automatable, and
pretending otherwise would be theater.

What the automated suite *does* contribute to them:

- **Instant restart** — the mechanism is tested (restart is broadcast through
  Defold's input dispatch; every restorable object resets through the same
  `reset()` a test message uses, so a real restart and a test reset cannot
  drift apart). Whether it *feels* instant is still visual.
- **No softlocks** — every fail condition funnels through `player.script`'s
  `die()`, and win through the mirrored `won` flag, both sticky. That removes
  the most likely softlock shape (a state with neither progress nor death),
  but does not prove a specific level's geometry has no trap.
- **Completable fairly** — level geometry is checked by *arithmetic* against
  the player's real constants (jump apex ~57, horizontal reach ~64, and the
  reduced figures under Heavy or a heavy gravity mood), not by playing. That
  arithmetic already caught two impossible layouts before they shipped
  (level 6's 70-unit gap under the heavy mood; level 10 stacking heavy
  gravity on a Heavy package, which put apex below the level's own step-ups).
  It cannot catch "technically possible but miserable".

Everything else is [`playtest_checklist.md`](playtest_checklist.md).

---

## What is left, and who can do it

### Code-side (doable in this repository, no special environment)

**Both items in this section are now done.** What remains for v1.0 is the
human/native work below — there is no known code-side gap left in the PRD
section 10 scope.

1. ~~**Sprite visual wiring.**~~ **Done in code (phase 24, v0.28.0)** — the
   game renders sprites, not `[label]` text. Every visual `.go` now carries a
   `.sprite` component fed by `main/sprites/game.atlas`; the player plays one
   image per animation state and flips with `facing`; the package plays one
   image per state and tints it. Variable-width ground and platforms are
   handled by scaling a band-drawn tile from the `half_width`/`half_height`
   the collections already author, rather than by a tilemap that would
   duplicate the geometry. Fixed a pre-existing bug on the way: the base
   floor was drawn 128 wide in all ten levels while the real walkable range
   is 112 to 140 — `main/player/ground.script` now derives the picture from
   the player's own bounds. **Still needs a human to look at it**: headless
   proves only that nothing broke (401/401) and that every collection
   compiles.
2. ~~**Controls remapping**~~ **Done (phase 25, v0.29.0)** — Options →
   Controls rebinds Move Left / Move Right / Jump, persisted in the settings
   file next to the volumes. Defold cannot change an input binding at
   runtime, so the binding file names actions after physical keys and
   `core/input_bindings.lua` decides what a key currently means at the point
   the action is consumed. Restart, pause and menu navigation stay on fixed
   keys on purpose: restart is broadcast to nine scripts, and a player who
   remaps menu confirm to a key they cannot press would be locked out of the
   screen that would let them fix it.

### Human / native environment only

3. **Real chiptune audio** (22 `.ogg` files) and **real pixel art** — asset
   authoring, not code. Both swap in without touching trigger sites.
4. **The Steam Defold extension**, then an actual **Steam (Windows) build**.
   The code seam is already in place and guarded (`type(_G.steam) == "table"`
   plus `pcall`), so a missing extension degrades to local-file saves rather
   than crashing.
5. **The Web (Poki) build**, and the **PRD 9.5 performance pass** in Chrome
   and Firefox — 60 FPS including during Panic shake and Explosive, no GC
   hitches on level load or restart.
6. **The section 10/11 acceptance playtest** across all 10 levels →
   the `v1.0.0` version bump. This is the gate, not a formality: several of
   the criteria (pacing, legibility, "the madness is felt") have never been
   observed by anyone.
7. **Audio audibility**, **visual regression**, and **FPS** — permanently
   manual by design, documented as accepted gaps in CLAUDE.md.

---

## Known issues carried into v1.0

- **`dmengine_headless` intermittently stops updating game objects**
  (~1 run in 3 on arm64-macOS). Environment-level, not project code —
  confirmed by a heartbeat that stops printing while the engine's main thread
  sits in its normal frame limiter with zero Lua frames on the stack.
  Mitigated by `run_tests.sh`'s retry (`STALL_TIMEOUT` 150s, `MAX_ATTEMPTS` 3);
  only runs producing *no result at all* are retried, so a genuine pass or
  failure is never masked. **Both limits must grow as the suite grows.** Has
  never been observed in a real windowed build; if it ever is, that is new
  information worth capturing.
- **`physics.raycast` and collision messages never fire under headless.**
  Confirmed with a from-scratch minimal reproduction. This is why all
  gameplay overlap detection is plain-Lua AABB. Worth re-verifying inside the
  Editor during the playtest — if physics queries do work in a real build,
  only the *test coverage* would need to stay geometry-based.
- **No automated test loads a level collection.** The suite boots
  `test/test.collection` only, deliberately, to keep engine boot time bounded.
  Level geometry is covered by arithmetic and by the playtest. This gap has
  bitten once before (phase 1 shipped a production scene whose ground did not
  match the player's properties, while only the test collection was covered).
