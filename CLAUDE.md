# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

**Handle With Care** is a 2D 8-bit platformer built in **Defold** (Lua). The
player carries an unstable, reactive package to a delivery zone at the end of
each level; the package has its own physics and 8 behavioral states that react
(often destructively) to jumps, falls, sudden stops, and time.

The full design spec — physics formulas, state definitions, stress system
constants, level list, art/audio direction, acceptance criteria — lives in
[`Handle_With_Care_PRD_v2.1.md`](Handle_With_Care_PRD_v2.1.md). That file is
the source of truth for design; this file is the source of truth for how to
work in the codebase.

The development roadmap (phased vertical slices, one per game system/level)
is inlined below in [Sliced roadmap](#sliced-roadmap) so it stays
version-controlled alongside the rules that reference it.

## Stack

- **Engine**: Defold (Lua 5.1-ish dialect, Defold's own runtime)
- **Testing**: [deftest](https://github.com/britzl/deftest) (Telescope syntax:
  `describe`/`test`/`before`/`after`), added as a game.project dependency
- **Headless build/run**: `bob.jar` + `dmengine_headless`, downloaded on
  demand by `scripts/run_tests.sh` (see `.defold/`, gitignored). `bob.jar`
  requires **OpenJDK 25+** to run (older JDKs fail with
  `UnsupportedClassVersionError`) — matches `java-version` in `ci.yml`.
- **CI**: GitHub Actions (`.github/workflows/ci.yml`), runs the same script
- **License**: proprietary, all rights reserved (see `LICENSE`) — this is
  **not** open source. Never suggest adding an OSS license, a
  `CONTRIBUTING.md` inviting outside PRs, or anything implying the code is
  shareable.

## Language

Every deliverable in this repository — source code, file/folder names,
comments, commit messages, this file, any other doc — is written in
**American English**. (Conversational replies to the user may be in whatever
language they're using; that's the only exception.)

## Architecture rules (non-negotiable, apply from the first line of game code)

1. **Pure core vs. thin adapter.** All game logic (package physics, the
   8-state machine, the stress system, save/load, level progression) lives in
   `/main/core/*.lua` — plain Lua modules with **no calls to
   `go.*`/`msg.*`/`sprite.*`** or any other Defold engine API. `.script` files
   under `/main/player`, `/main/package`, etc. are thin adapters: they read
   engine input/position, call the core module, and apply the result back
   (`go.set_position`, `sprite.play`, ...). This is what makes the core
   100% unit-testable without the engine running.
2. **No state as a module upvalue.** Defold's `require()` caches modules —
   the same table is returned every time. Core functions take state in and
   return new state out explicitly, e.g. `stress.apply_jump(state, event) ->
   new_state`. Never store `local package_state = {...}` at a module's top
   level. The adapter `.script` owns the actual state, in `self`.
3. **Time and randomness are always injected.** No function under
   `/main/core` calls `math.random()` or reads a clock directly. Anything
   that needs randomness or elapsed time (the sinusoidal shake, panic
   impulses, timers) takes `time`/`dt`/an `rng` function as a parameter. The
   adapter passes the real thing (`os.clock()`, `math.random`); tests pass
   fixed, deterministic stubs. Skipping this makes physics unit tests
   non-deterministic and is expensive to retrofit later — do it right the
   first time.
   **Per-frame constants assume a locked 60Hz simulation, not real seconds.**
   `lerp_factor`, `velocity_damping`, and future stress/decay rates are
   applied once per simulated frame exactly as the PRD's pseudocode
   specifies (no dt-scaling) — this only produces consistent game feel
   because `game.project`'s `display.update_frequency = 60` locks the
   engine's update rate regardless of the player's monitor refresh rate. If
   that setting is ever removed, every per-frame constant across the whole
   project needs revisiting, not just whichever module you're touching.
4. **Package position is read synchronously, not via message.** The package
   adapter calls `go.get_position(player_url)` directly inside its own
   `update()` to compute offset + lerp. It never waits on a `msg.post` from
   the player for per-frame position, since `msg.post` is asynchronous and
   would add a perceptible frame of lag to the "physical stickiness".
   `msg.post` is reserved for discrete events (jumped, landed, hit a hazard).
5. **Tunable constants vs. core defaults.** Physics constants (stress gain
   per jump, HEAVY_MASS, MAGNET_RADIUS, etc.) exist as defaults inside the
   core module, but the adapter exposes them as `go.property` (Defold only
   supports scalar/vector/hash/bool/resource types there) and **passes them
   as arguments** into the core function. Never hardcode the same constant
   in two places. This includes level geometry: a `.collection` that places
   a platform/hazard at a given position/size must also set that instance's
   matching `go.property` values (e.g. `ground_x_min`/`ground_y_top`) via an
   explicit `component_properties` block — never rely on the script's
   `go.property` defaults happening to match one particular collection.
   (Phase 1 shipped with exactly this bug: `main.collection`'s ground didn't
   match `player.script`'s defaults, and only `test.collection` — which
   happened to match — was covered by tests, so the production scene was
   silently broken. Fixed by adding explicit `component_properties`
   overrides per collection.)
6. **`explosive` ships with a dual trigger from the start.** Explosive
   activates when stress reaches 100 **or** via an explicit phase-timer
   trigger (needed later for the "Hot Potato" level). Design
   `core/explosive.lua`'s API to accept both from day one — do not bolt the
   second trigger on later.
   Shipped in phase 6 as: `explosive.lua` itself doesn't know or care which
   trigger fired — `start()`/`update()` just own the countdown once told to
   begin. What makes both paths work is `package_state_machine.lua` treating
   Explosive as a one-way, non-re-derivable exit (see `RE_DERIVABLE_STATES`)
   reachable either through the stress ladder (`update_from_stress`) or a
   direct `set_state` call — the same generic escape hatch Heavy/Light
   already use for their own non-stress triggers. Phase 14 (Hot Potato) is
   expected to call `set_state(machine, "explosive")` directly from its own
   cyclic timer; no changes to `explosive.lua` or the state machine should
   be needed to support that.
7. **Shared integration test harness.** Reuse one test collection per
   subsystem (e.g. a single `test_player_package.collection`) across
   multiple slices instead of creating a new heavy collection per phase, to
   keep headless engine boot time bounded as the suite grows.
8. **Never regress test determinism for convenience.** If a test needs to
   "just work" by adding a `sleep`/frame-count fudge factor, that's a sign
   the core function under test is missing a time/dt parameter — fix the
   signature, don't paper over it.
9. **Gameplay-critical collision/overlap detection is plain Lua, not engine
   physics queries.** `physics.raycast` and `contact_point_response` do not
   report hits in this project's headless test environment (see [Known
   environment limitations](#known-environment-limitations) — confirmed via
   an isolated, from-scratch reproduction, not a mistake in this project's
   files). Anything that needs to be covered by an automated integration
   test — ground contact, hazard overlap, delivery-zone entry — must be
   computed via a pure Lua geometry check in `/main/core` (AABB overlap is
   usually enough), the same way `player_movement.resting_y_on_ground`
   does it. `.collisionobject` components can still be added for a level's
   visual/Editor-side representation, but never make gameplay logic depend
   on their query/message APIs actually firing.

## Known environment limitations

### `physics.raycast` / `contact_point_response` never fire under headless

**Status: confirmed, unresolved, environment-level — not a bug in this
project's files.**

While building phase 1 (player movement), ground detection was originally
implemented with `physics.raycast` against a `.collisionobject` platform.
It never returned a hit, in any configuration tried:

- Box vs. sphere vs. external `.convexshape` shapes
- Static, kinematic, and dynamic (mass > 0) target bodies
- Custom group names vs. Defold's own `"default"` group
- Raycasting from a script with no collisionobject of its own vs. one that
  has one
- `physics.type` unset (defaults to `2D` — confirmed in engine source) vs.
  explicitly `2D`
- `physics.scale` unset vs. `0.02` (the value used by Defold's own
  `collision_project` test fixture)
- `physics.use_fixed_timestep` default (`1`) vs. explicitly `0`
- Defold stable (`1.13.0`) vs. beta (`1.13.1`)
- `contact_point_response` messages from genuine kinematic/static overlap
  (never received either — same likely root cause)

The dead giveaway: a **from-scratch, minimal, standalone Defold project**
(no deftest, no dependencies, one static box, one raycast call in `init()`)
reproduced the exact same `nil` result on this machine
(arm64-macos, `dmengine_headless`). This rules out anything about this
repository's configuration — it points at the headless engine/platform
combination itself.

**What this means practically:**
- Automated (headless, CI-running) integration tests cannot rely on
  `physics.raycast`, `physics.raycast_async`, or any collision-object
  message (`contact_point_response`, `collision_response`,
  `trigger_response`) actually firing. Design around this per rule 9 above.
- This has **not** been re-tested inside the actual Defold Editor or a real
  (non-headless) desktop/web build — it's possible the limitation is
  specific to `dmengine_headless` on this platform and physics queries work
  fine when actually playing the game. **Re-verify this once the Editor is
  available** (open a level with a hazard, check in the Editor's console
  whether raycast/contact messages fire) — if they do work there, hazard
  *gameplay* logic could still use real physics queries; only the
  *automated test coverage* for that logic would need to stay geometry-based
  (e.g. an integration test asserting the AABB math directly, or a manual
  test checklist item instead of an automated one).
- If a future phase (9a: hazards) needs this re-litigated, start from this
  section instead of rediscovering it from scratch — the investigation is
  expensive (raycast source read down to `GetGroupBitIndex` in
  `comp_collision_object.cpp`, `physics.use_fixed_timestep`'s config key in
  `engine.cpp`, etc.) and it all led back to the same empirical conclusion.

### `test/support/wait.lua`'s `M.seconds()` can under-wait in a real (non-headless) engine

**Status: fixed — use `M.frames(n)` for anything that depends on a specific
number of simulation steps; `M.seconds()` is for the rare case where real
elapsed duration matters more than an exact tick count.**

Phase 3's integration tests originally used only `wait.seconds(duration)`
(implemented via `go.animate`, which resumes after that much *accumulated
dt* has passed). All 80 tests passed reliably under `dmengine_headless`.
The first time the user ran the actual game with a real window (real
Vulkan/GPU context, real shader compilation), two convergence-tolerance
tests failed and the process exited (deftest's `os.exit(1)` on failure
closes the whole app — mistakable for "the game crashed").

Root cause: a real graphics context's startup (window creation, shader
compilation — nonexistent in headless's null graphics device) can produce
one anomalously large `dt` on an early frame. Since `M.seconds()` only
guarantees *accumulated* dt, not a frame count, that one large `dt` can
satisfy an entire `wait.seconds(1.0)` in far fewer real ticks than the ~60
frames the convergence math assumed — leaving the lerp nowhere near
converged when the assertion runs.

Fix: added `M.frames(n)`, which waits for exactly `n` real `update()` ticks
via a counter in `test_runner.script`'s own `update()`, immune to any single
frame's `dt`. All `wait.seconds(X)` call sites were converted to
`wait.frames(X * 60)` (this project locks `display.update_frequency = 60`,
so that conversion matches the original intent).

**A second, subtler bug surfaced fixing the first one:** the initial
`M.tick()` iterated `pending_frame_waits` in place while resuming
coroutines mid-loop. A test that resumes and immediately calls
`M.frames(1)` again (e.g. a "sample position, wait 1 frame" loop run 20
times) inserts a fresh entry that the *same* `tick()` call would then
revisit and immediately resolve too — collapsing 20 intended real frames
into one. Fixed by snapshotting which entries are due before resuming
anyone, so anything a resumed coroutine adds is deferred to the next real
`tick()`. If you ever touch `wait.lua`, preserve that snapshot-then-resume
order — it's not optional.

**Takeaway:** a fully-green headless suite does not guarantee the same
behavior in a real windowed build. Section 4.9's "playtest e ajuste fino"
(phase 22) is the natural place for a full pass, but it's worth spot-
checking a real (non-headless) `dmengine` run after any phase that adds
new `wait`-heavy integration tests, not just at the very end.

## Testing

- **Unit tests** (`/test/unit/*.lua`): exercise `/main/core` modules in
  isolation, no live game objects. Fast, deterministic (see rule 3 above).
- **Integration tests** (`/test/integration/*.lua`): run against real
  `.collection` instances headless, verifying wiring between game objects
  (input → player → package → hazards/messages) via `go.get_position`/
  `go.get`/custom test messages and plain Lua geometry — not engine physics
  queries (see architecture rule 9 and [Known environment
  limitations](#known-environment-limitations)).
- **Forcing a package state for tests/manual debugging**: post
  `"debug_set_state"` to the package with `{ state = "heavy" }` for the
  **non-ladder** states (Heavy/Light/Magnetized/Sleeping) — this is how
  Heavy/Light are entered until phase 13 adds Heavy Duty's real cyclic
  timer trigger. It does **not** stick for Stable/Nervous/Panic:
  `update_from_stress` re-derives those from `self.stress` every single
  frame (that's the whole point of the ladder), so it overwrites a debug-set
  ladder state again on the very next `update()`. To reach Nervous/Panic
  on demand, post `"debug_set_stress"` with `{ value = 80 }` instead and let
  the ladder do its job naturally — found the hard way when phase 5's first
  Panic integration test silently reset to Stable one frame after being
  debug-set. **Explosive is the one exception**: since phase 6, it's
  deliberately excluded from `update_from_stress`'s re-derivable set (see
  `RE_DERIVABLE_STATES` in `package_state_machine.lua`), so
  `debug_set_state({ state = "explosive" })` sticks immediately, the same
  as Heavy/Light.
- **A stress value set to exactly the ceiling (100) can transiently dip
  below a threshold one frame later, even though nothing external changed
  it.** `accumulate_continuous_stress` decides whether to accumulate or
  decay stress by reading `self.machine.current_state` — but that read
  reflects last frame's ladder decision, not this frame's, since
  `update_from_stress` runs after it. Debug-setting stress straight to 100
  from Stable means the very next frame still takes the grounded-decay
  branch (current_state is still stale-Stable), nudging stress to 99.9 —
  under the Explosive threshold — before the ladder re-derives Panic
  instead. It self-corrects a frame or two later (now-Panic's own
  accumulation climbs stress back to 100), but any test that debug-sets
  stress to exactly 100 and asserts Explosive needs a few frames' margin
  for that settle, not just one. This never bites organic gameplay: by the
  time stress climbs to 100 through real jumps/landings, it has already
  crossed the Panic threshold (70) frames earlier, so current_state is
  already Panic (which accumulates, not decays) on the critical frame.
- **A "was X / is X" transition check inside `update()` can't detect a
  state that was mutated by `on_message` earlier the same frame** — because
  that mutation already happened before `update()` started, so both the
  "before" and "after" reads inside `update()` see the same, already-new
  value. This is why Explosive's timer-start check in `package.script`
  tests `not self.explosive.active and not self.detonated` instead of
  comparing state before/after `update_from_stress` (the way Panic's
  `was_panic`/`is_panic` does) — Panic is only ever entered via
  `update_from_stress`, which runs *inside* `update()`, so that comparison
  works for it; Explosive can also be entered directly by
  `debug_set_state`/a future phase-timer trigger, whose `on_message`
  mutation precedes `update()` entirely. The check is on `explosive.active`,
  not the timer's sign: `timer <= 0` is also true both before the first
  `start()` and right after detonation, and an `explosive_time` of exactly
  0 would be indistinguishable from idle, leaving the package re-arming
  every frame without ever reporting detonated — `active` is what makes
  "never started", "counting down", and "just detonated" distinguishable.
  Leaving Explosive (currently only via `debug_set_state`) clears both
  `active` and `detonated` in one place, so climbing back in later re-arms
  cleanly instead of getting stuck.
- **Integration `before` hooks must reset the whole shared fixture, not
  just the player.** All integration suites share one persistent
  player/package pair from `test/test.collection` for the entire test run
  (`test_runner.script` registers every suite against the same booted
  collection) — a `before` hook only defends *its own* suite against state
  left behind by whatever ran earlier, so it must reset every shared game
  object, not just the one the suite is nominally about. Post `test_reset`
  to both `/player#script` and `/package#script`, and wait the same ~36
  frames every other suite does (enough for the player to land **and** for
  the package's 0.35 lerp factor to fully reconverge its position — see
  the note below on why position is left alone). Found the hard way in
  phase 5: two integration suites reset only the player, so jumps and
  direction changes bled stress into whichever suite ran next, producing
  intermittent failures reproducible only under the real (non-headless)
  engine, never headless.
- **`package.script`'s `test_reset` zeroes `self.physics`'s velocity but
  deliberately leaves its position alone.** Residual velocity from a Panic
  impulse decays only at 0.85/frame, so left unset it would bleed into
  whatever runs next — the same class of leak as the point above, in a
  different field. Position doesn't need the same treatment: the player
  lands on frame 20 of the 36-frame wait — the fall from 100 to 56 at
  gravity -900 takes 19 gravity frames, plus one frame at the start where
  `test_reset` has restored `grounded = true` so no gravity is applied
  yet — leaving 16 frames for the 0.35 lerp factor to contract any
  leftover position lag by `0.65^16 ≈ 1e-3`, which puts the package
  within ~0.006 of its target, well under `CONVERGENCE_TOLERANCE = 0.5`,
  before any assertion runs. The two are load-bearing on each other — if
  the reset wait is ever
  shortened, position needs resetting too.
- **Comparing a `go.property` float against a literal** (e.g. asserting
  `mass == 0.4`): use a small epsilon, not `==`. `go.property` stores floats
  as float32; values like `0.4` (unlike `1.0`/`2.5`) have no exact float32
  representation, so a Lua double literal comparison can fail by a hair —
  same class of issue as `RESTING_EPSILON` in `player_movement.lua`.
- Both use deftest's Telescope-style syntax:

  ```lua
  return function()
      describe("Stress system", function()
          test("increases on jump", function()
              local state = stress.new()
              state = stress.apply_jump(state, { amount = 6 })
              assert(state.value == 6)
          end)
      end)
  end
  ```

- Every new/changed suite must be `require`d and registered in
  `test/test_runner.script`'s `suites` table — that's the single entry point
  deftest boots from (see `test/testing.settings`, which overrides
  `bootstrap.main_collection` to `/test/test.collectionc` without touching
  production's bootstrap in `game.project`). Note the trailing `c`: Defold's
  `bootstrap.main_collection`/`bootstrap.render`/`input.game_binding` keys
  take the **compiled** resource extension (`.collectionc`,
  `.input_bindingc`), not the source one — check `game.project` for the
  existing examples before adding a new bootstrap-level key.

### Running tests

- **Locally / CI (headless, no Editor needed)**:
  ```bash
  ./scripts/run_tests.sh
  ```
  Downloads (once, cached in `.defold/`, gitignored, verified against a
  pinned SHA-256 before use) the specific `dmengine_headless` + `bob.jar`
  release pinned by `DEFOLD_VERSION`/`DEFOLD_SHA1` at the top of the script,
  builds using `test/testing.settings`, and runs the suite. The process exit
  code reflects the test result — verified empirically in this repo's own
  setup: `deftest.run()` calls `os.exit(1)` on any failure and `os.exit(0)`
  on success, and `dmengine_headless` propagates that as its real process
  exit code. This script's exit code IS the test result, use it in any
  automation.
- **From the Defold Editor (manual, visual)**: temporarily set
  `bootstrap.main_collection` in `game.project` to `/test/test.collectionc`,
  press Play, read pass/fail output in the console, then revert
  `game.project` — or just trust `scripts/run_tests.sh` for day-to-day use
  and reserve the Editor for actually playing the game.
- **Running the built test collection via either `dmengine_headless` or the
  real windowed `dmengine` binary, e.g. for a manual spot-check**: give it a
  generous timeout, and grow that timeout as the suite grows. Both pace
  frames near real 60Hz — confirmed empirically (low CPU usage, ~60s wall
  clock to match ~60s of simulated frames), correcting an earlier assumption
  in this file that headless has no vsync and races through `wait.frames(n)`
  at CPU speed regardless of `n`. It doesn't: `display.update_frequency = 60`
  paces the engine's own tick loop the same way in both modes, so total
  suite runtime scales with the sum of every test's waited frame count, not
  just the number of tests or headless-vs-windowed. Phase 6 alone added
  several hundred frames' worth of `wait.frames()` calls (explosive_time is
  90 frames, and some tests wait for it twice) and pushed what had been a
  comfortable 60s timeout to ~60-62s for *both* binaries — not a hang, just
  genuinely that much real time elapsing 60 simulated frames at a time. This
  will keep growing every phase; `scripts/run_tests.sh` itself has no
  internal timeout (it just execs and waits), so this only bites ad hoc
  spot-checks wrapped in an external `timeout` — budget generously (150s+)
  rather than reusing whatever worked last phase.
- **CI**: `.github/workflows/ci.yml` runs `./scripts/run_tests.sh
  x86_64-linux` on every push and pull request.
- **Bumping the pinned Defold version**: update `DEFOLD_VERSION`/
  `DEFOLD_SHA1` in `scripts/run_tests.sh`, regenerate the `BOB_SHA256` and
  per-platform `DMENGINE_SHA256_*` constants (download each artifact once,
  `shasum -a 256` it), and update the cache key in `ci.yml` to match — all as
  one reviewable commit, never resolved automatically at run time.

### What tests do NOT cover (accepted, documented gaps)

- **FPS/performance**: `dmengine_headless` has no real GPU/vsync, so
  "assert 60 FPS" in CI would be theater. Performance is a manual checklist
  item (Chrome/Firefox DevTools), not an automated test.
- **Visual regression** (pixel art correctness): not automated. Rely on the
  manual test checklist that accompanies every slice.

## Git workflow — read this before touching git

**Claude never runs write git commands** — no `git add`, `git commit`,
`git push`, `git tag`, `git merge`, etc. Only read-only commands
(`git status`, `git log`, `git diff`, `git show`, ...) are allowed. The user
runs every commit and push themselves.

At the end of each development slice, Claude:
1. Runs `./scripts/run_tests.sh` and confirms it passes.
2. Provides a manual test checklist for the Defold Editor.
3. Drafts a commit message (Conventional Commits + suggested SemVer version,
   see below) for the user to run — never executes it.

### Commit message convention

[Conventional Commits](https://www.conventionalcommits.org/) prefix +
suggested version bump in the subject, e.g.:

```
feat: package attaches to player with stable-state physics (v0.3.0)
```

Common prefixes used in this project: `feat:` (new gameplay/system/level),
`fix:`, `test:` (test-only changes), `chore:` (tooling/CI/build/docs).

## Versioning

- The version lives in `game.project`'s `[project] version` key.
- While the game is under construction, stay on the `0.x.y` line: bump the
  **minor** version once per completed development slice (e.g.
  `0.1.0` → `0.2.0`), keep **patch** for fixes within an already-shipped
  slice.
- `1.0.0` is reserved for the moment the full v1.0 scope in PRD section 10 is
  complete (all 10 levels, menu/save, full audio, Web + Steam builds).

## Sliced roadmap

One vertical slice per row. Each ships with its own tests, manual checklist,
and drafted commit (Conventional Commits + the version shown) — see
[Definition of Done](#definition-of-done-every-slice) below.

| # | Slice | Scope |
|---|-------|-------|
| 0 | Bootstrap | Folder structure, deftest, CI, `LICENSE`, this file (done) |
| 1 | Player movement core | `core/player_movement.lua`, input bindings, idle/run/jump/fall/land (done) |
| 2 | Package attaches (Stable) | `core/package_physics.lua` offset+lerp, synchronous position read (done) |
| 3 | State machine + stress + shake | `core/package_state_machine.lua`, `core/stress.lua`, sinusoidal shake, minimal debug HUD (done) |
| 4 | Heavy & Light | Mass multiplier affecting player speed/jump (done) |
| 5 | Panic | Random impulses + player knockback (done) |
| 6 | Explosive | `core/explosive.lua` with dual trigger (stress>=100 OR phase timer) from day one (done) |
| 7 | Magnetized | Hazard attraction within `MAGNET_RADIUS` |
| 8 | Sleeping | Wake-on-impact |
| 9a | Hazards + death | Spikes, saws, falling platforms, pits, off-screen check — overlap detection via AABB (see [Known environment limitations](#known-environment-limitations)), not engine physics queries |
| 9b | Delivery + win + restart | Delivery zone, win condition, instant restart |
| 10 | Level 1: Tutorial Soft | First fully playable level, section 11 acceptance checklist |
| 11 | Menu, save/load, progression | Main menu, `core/save.lua` port + localStorage adapter, level unlocks, result screen, pause |
| 12 | Level 2: Jump Scare | |
| 13 | Level 3: Heavy Duty | New cyclic timer driver for Heavy cycles |
| 14 | Level 4: Hot Potato | Uses `explosive.lua`'s phase-timer trigger |
| 15 | Level 5: Magnet Madness | |
| 16 | Level 6: Gravity Moods | New `core/gravity_driver.lua` |
| 17 | Level 7: Control Freak | New `core/input_inversion.lua` |
| 18 | Level 8: Sleepy Package | |
| 19 | Level 9: Mirror World | New `core/mirror.lua` |
| 20 | Level 10: Final Delivery | Combination level, no new mechanic |
| 21 | Audio + Options + Credits | Full SFX/music, volume/fullscreen/controls screen, credits |
| 22 | Polish, playtest, performance | 60 FPS tuning, atlas optimization, Chrome/Firefox checklist (manual only) |
| 23 | Final build | Steam file-save adapter, Web (Poki) + Steam builds, full section 10/11 acceptance → `v1.0.0` |

Full rationale and formula-level detail for each slice lives in
[`Handle_With_Care_PRD_v2.1.md`](Handle_With_Care_PRD_v2.1.md).

## Definition of Done (every slice)

A slice is done only when:
1. New/changed `/main/core` modules have unit tests covering relevant edge
   cases (e.g. stress at 0 and 100, timers at zero).
2. Any new wiring between game objects has an integration test against a
   real (headless) collection.
3. `./scripts/run_tests.sh` passes.
4. A manual test checklist for the Defold Editor is provided alongside the
   change (the Editor is not installed in every environment this project is
   worked on — assume the user runs it, not Claude).
5. A commit message is drafted (Conventional Commits + SemVer), never
   executed by Claude.

## Folder structure

```
/main
  /core        # pure Lua logic, no Defold API — 100% unit-testable
  /player      # .go/.script adapters
  /package
  /hazards
  /levels      # 1 .collection per game phase
  /ui
  /audio
  /fx
/test
  /unit        # deftest suites over /main/core, no live engine objects
  /integration # deftest suites over real collections, headless dmengine
/input
/render
/scripts
  run_tests.sh
.github/workflows/ci.yml
LICENSE
game.project
```
