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

### `wait.tick()` must never discard `coroutine.resume`'s result

**Status: fixed in phase 9a — do not "simplify" it back.**

Lua 5.1's `pcall` cannot yield, so deftest's own `xpcall` around a test body
only ever covers that body **up to its first `wait.frames()` call**.
Everything after the first yield is resumed by `wait.tick()` instead. The
original `tick()` called `coroutine.resume(co)` and threw the result away —
so any error raised after the first wait (a failed assertion, a nil index)
was silently swallowed *and* left deftest waiting forever on a coroutine
that was already dead. An ordinary test failure therefore presented as an
infinite hang with zero output. `tick()` now checks `ok, err`, prints the
error plus `debug.traceback(co)`, and exits non-zero (matching deftest's own
`os.exit`-on-failure contract, so `run_tests.sh`'s exit code stays correct).

### `dmengine_headless` intermittently stops updating game objects

**Status: open, ~1 run in 3 on arm64-macos, engine-level. Mitigated by a
retry in `run_tests.sh`, not fixed. Not caused by this project's code.**

The engine sometimes stops running its update phase entirely, part-way
through the integration suites. When it happens the process stays alive and
looks healthy: the main thread sits in the normal frame limiter (a `sample`
shows 7208 of 7210 stack samples in `dmEngine::Step` → `usleep`, and **zero**
Lua frames), it keeps accumulating CPU at the same ~1.5% a healthy headless
run uses, and **not a single error is logged**. But no game object updates
again, no test completes, and `run_tests.sh` would wait forever.

The decisive instrument was an unconditional heartbeat in
`test_runner.script`'s `update()`: a healthy ~102s run prints exactly 3 of
them, and a wedged run prints **zero** across 14,000+ frames. That rules out
every Lua-side explanation — it is `update()` itself that stops being
called, not a coroutine that fails to resume. Keep that heartbeat; it is
what makes this diagnosable at all, and it costs ~3 log lines per run.

It is not caused by phase 9a, or by any particular test. Across runs it
wedged after 189, 191, 193 and 193 tests — four different boundaries inside
the **Player movement** and **Package physics** integration suites, which
date from phases 1-2 and had been green for seven phases. There is no
offending test to disable: the engine stops wherever the suite happens to
be, so removing those suites would only move the symptom to whatever ran
next, at the cost of the coverage for the game's two most basic mechanics.

Ruled out, each with evidence, so nobody repeats the search:
- **Memory pressure** — htop showed 3.4-3.8G of 8G used with a normal load
  average while wedged. (Do not use `vm_stat`'s free-page count for this;
  macOS keeps free pages low by design and it reads as alarming when
  nothing is wrong.)
- **Spotlight indexing** — reproduces with the project excluded from it.
- **A slow suite / too many waited frames** — the suite is ~4,400 waited
  frames ≈ 73s at 60Hz and completes in ~102s; a wedge is not slowness.
- **A swallowed coroutine error** — `wait.tick()` now reports those (see
  above) and stays silent through a wedge.
- **`engine.run_while_iconified`** — the engine does gate updates on window
  state and the key is real, but setting it to 1 (verified present in the
  compiled `game.projectc`) does not stop the wedge. It is left enabled in
  `test/testing.settings` anyway: it is harmless for a run with no window,
  and keeping it on removes one variable from any future investigation.

**Mitigation:** `run_tests.sh` caps each engine run at `STALL_TIMEOUT` (150s,
~1.5x a healthy run) and retries up to `MAX_ATTEMPTS` (3). This cannot mask
a real failure — a genuine pass (exit 0) or genuine test failure (exit 1) is
returned immediately and never retried, so architecture rule 8 still holds;
only a run that produced **no result at all** is retried. Both values are
env-overridable and **both must grow as the suite grows**, since a wedged
engine emits nothing, making total runtime the only signal available.

**Also disabled, and this did not help:** `test.integration.test_player_movement`
and `test.integration.test_package_physics` are commented out in
`test_runner.script` (commented, not deleted), because every wedge observed
before that point had landed inside them. It made no difference — the very
next run wedged anyway with both disabled, and only the retry saved it,
which is exactly what the "no individual test owns the fault" conclusion
predicts. The suite is therefore 229 tests rather than 236, and the game's
two most basic mechanics (player movement, package attachment) currently
have no integration coverage. **Re-enable both lines** once the engine
issue is understood; there is no reason to keep them off beyond that.

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
- **Producing a hard landing in a test**: post `"test_set_position"` to the
  player with `{ x = ..., y = ... }` — it teleports the player and forces
  `grounded = false`, so the next `update()` starts a genuine free-fall
  from that height. No ordinary jump reaches `heavy_landing_velocity`
  (400 by default): a normal jump's return speed roughly equals its own
  launch velocity (320, well under it), and there's no other in-game way
  yet to gain that much height. Added in phase 8 to test Sleeping's
  wake-on-impact — see `test/integration/test_sleeping.lua`'s
  `hard_landing()` helper for the exact fall-height/frame-count math.
- **Hazards (phase 9a) check themselves against the player/package,
  inverted from every other pattern in this project.** Every prior
  synchronous read has the player or package pulling data from one other
  known object (`go.get_position(player_url)`, etc.). Hazards can't work
  that way: a level can have any number of them, and `go.property` has no
  way to express "an arbitrary number of other instances" for the player
  to enumerate. So `lethal_hazard.script`/`falling_platform.script` instead
  each hold a `player`/`package` URL and check themselves against that one
  well-known pair every frame — scales to any hazard count without a
  registry, at the cost of the player needing an explicit, fixed
  `has_extra_ground`/`extra_ground` slot (singular) for falling platforms
  to act as ground through. One slot is enough for this phase's own test
  collection; real multi-hazard levels (phase 10+) will need to revisit
  this if more than one is ever needed under the player at once.
- **Restart (phase 9b) is broadcast through Defold's input dispatch, not a
  registry — and that retires the "arbitrary number of instances" problem
  phase 9a flagged.** Every restorable object (`player`, `package`, each
  hazard, the delivery zone) calls `acquire_input_focus` and handles the
  `restart` action itself, **returning false so the action is never
  consumed**. Defold then delivers it to all of them, so a level can hold
  any number of hazards and one key press still restores every one, with
  nobody registered anywhere and no central controller to keep in sync.
  Consuming the action in `player.script` would silently leave every other
  object in its end-of-attempt state while only the player reset — if you
  ever add a new restorable object, the two things it must do are acquire
  focus and return false. Each object routes the key into the *same*
  `reset()` its `"reset"`/`"test_reset"` message handler uses, so a real
  restart and a test reset can never drift apart.
- **The delivery zone's position in `test.collection` is load-bearing in a
  way hazards' positions are not.** It sits at (60, 150), far from every
  column and Y range the other suites touch (their teleports live at
  x=192..300; the package settles around (200, 68)). A zone the package
  could drift into would *win the level* mid-test — and since a win freezes
  `player.script` exactly like death does, every later assertion in that
  suite would pass or fail for entirely the wrong reason, with no error to
  point at it. Only `test_delivery.lua` brings the package into the zone,
  explicitly. This is the same lesson as the falling-platform placement
  below, with a much larger blast radius.
- **A hazard placed in the shared `test.collection` can silently break an
  unrelated suite's test if it sits in that suite's fall path** — a new
  variant of the "reset the whole shared fixture" lesson from phase 5/6,
  this time about *position* rather than leftover *state*. The falling
  platform was first placed at the same x as `test_sleeping.lua`'s
  `hard_landing()` helper (which drops the player from y=200 to test a
  high-impact landing) — the player's now-extended ground check caught it
  on the platform at y=166 instead of letting it fall all the way to the
  main ground, so the impact velocity never crossed
  `heavy_landing_velocity` and three previously-passing Sleeping tests
  started failing. Fixed by moving the platform off that column (x=250
  instead of 192) — but the general lesson is: before placing anything new
  in `test.collection`, check what X columns and Y ranges the *existing*
  suites' teleports/falls already rely on, not just what your own new
  suite needs.
- **Magnetism only pulls a hazard if its position is actually within
  `magnet_radius` of the package's resting position** — obvious in
  hindsight, but the first attempt spawned `lethal_hazard` 100 units from
  the package's settled position (~200, 68), just outside the default
  95px radius, so `attraction_force` correctly returned zero every frame
  and the "Magnetized attracts a lethal hazard" test saw no movement at
  all. Moving the hazard's *default* spawn inside the radius to fix that
  created a worse problem: every OTHER suite that debug-sets Magnetized
  (`test_magnetized.lua`'s own tests, which don't expect any hazard
  nearby) would then have the hazard drift into contact mid-test, killing
  and freezing the player, making assertions like "the offset didn't
  change" trivially true for the wrong reason (a frozen player, not
  physics that genuinely didn't change). Fixed by keeping the hazard's
  *default* spawn deliberately outside the radius, and giving
  `lethal_hazard.script` its own test-only `"test_set_position"` hook so
  only the one dedicated attraction test brings it into range on demand.
- **Every PRD 3.3/4.7 fail condition funnels through one place**:
  `player.script`'s `die()` sets a sticky `dead` flag and posts
  `"player_died"` to the package (forward-declared, no listener yet —
  phase 9b is the real consumer), and `update()` freezes everything the
  instant `dead` is true. Hazard contact, a pit/off-world fall, staying
  off-screen too long, and the package's own `package_exploded` message
  (the player never drops the package, so its death is the player's too)
  all call the same function — a future fail condition should do the same
  rather than inventing its own flag. The package has the mirror image:
  its own pit/off-screen checks (PRD 3.3/4.7 name the *package*
  explicitly, and Panic's impulses can separate it meaningfully from the
  player) post `"package_died"` to the player, which routes into the same
  `die()`.
- **An accelerating faller always eventually re-meets a constant-velocity
  one — geometric divergence alone isn't a permanent "no longer solid"
  signal.** The falling platform's original design relied entirely on
  `resting_y_on_ground` naturally failing to match once the platform (at
  a constant `fall_speed`) moved away from the player (who resumes
  accelerating under gravity from a stop). That works only briefly: the
  player starts slower than the platform's fall but keeps accelerating,
  eventually catches up, gets re-grounded for one frame (zeroing
  `velocity_y`), free-falls again, and re-catches it — a repeating chase
  that produces a fresh `just_landed` (and potentially a bogus
  `player_landed` heavy-landing message) every cycle. Fixed with an
  explicit, permanent `is_falling` flag on the platform that `player.script`
  checks before ever considering it as ground again — geometry describes
  *this frame*, not "forever," so a one-way state transition needed an
  explicit flag, not an inferred one.
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
- **Magnetized (phase 7) is scheduled before hazards exist (phase 9a),
  so its integration test can't cover the actual "pull a hazard" behavior
  yet.** The PRD's attraction force applies to the *hazard*, not the
  package's own physics — unlike every other state so far
  (Heavy/Light/Panic/Explosive all feed into `package_physics` via
  mass/offset/force/shake). `core/magnetism.lua` is pure geometry, fully
  unit-tested in isolation, meant to be called by a future hazard adapter
  via `go.get_position("/package")` and
  `go.get("/package#script", "current_state") == hash("magnetized")` —
  both already exposed synchronously by `package.script` (rule 4), so no
  new `package.script` wiring was needed for a hazard to use it once
  phase 9a adds one. Mind the hash: `current_state` is stored as a hash,
  and a hash-vs-string `==` is always false, never true — easy to get
  wrong here since nothing catches it until you notice Magnetized simply
  never activates. `test/integration/test_magnetized.lua` instead guards the
  other half of the contract: entering Magnetized is a no-op for the
  package's own mass/shake/offset, same pattern as Explosive's
  `package_exploded` message and phase-timer trigger having no consumer
  yet — forward-declare the piece that's ready now, document what's
  deferred and why, wire the rest in when its dependency actually exists.
- **Integration `before` hooks must reset the whole shared fixture, not
  just the player.** All integration suites share one persistent
  player/package pair from `test/test.collection` for the entire test run
  (`test_runner.script` registers every suite against the same booted
  collection) — a `before` hook only defends *its own* suite against state
  left behind by whatever ran earlier, so it must reset every shared game
  object, not just the one the suite is nominally about. Post `test_reset`
  to both `/player#script` and `/package#script`, and wait the same ~36
  frames every other suite does (enough for the player to land and, since
  phase 9a, redundant margin for the package's own position reset below).
  Found the hard way in phase 5: two integration suites reset only the
  player, so jumps and direction changes bled stress into whichever suite
  ran next, producing intermittent failures reproducible only under the
  real (non-headless) engine, never headless.
- **`package.script`'s `test_reset` snaps `self.physics`'s position back to
  its spawn point (`self.initial_position`, captured in `init()`), the same
  as `player.script`/`lethal_hazard.script` already do.** Through phase 8
  this wasn't necessary: residual position lag was always Panic-impulse
  scale, small enough that the 0.35 lerp factor reconverged it well within
  the 36-frame reset wait on its own (`0.65^16 ≈ 1e-3` — see git history
  for the exact math if this ever needs re-deriving). Phase 9a broke that
  assumption: `test_hazards.lua`'s package-pit/off-screen tests drive the
  package to extreme positions (e.g. y=-500) via the `test_set_position`
  hook, which kills the player — and once the player is dead,
  `package.script`'s `update()` early-returns every frame, so the lerp
  never gets a chance to reconverge; the package is left frozen far below
  `kill_y`/off-screen. The next test's `before` hook then revives the
  player (`dead = false`), but on the very first live frame
  `package_died`/`offscreen_died` immediately re-derive `true` from that
  same stale position and kill the player again before a second frame of
  lerp can happen — leaking a lethal, frozen position into whatever test
  runs next (confirmed via a `print` of position/`dead` at test entry:
  `dead=true pkg_y=-156.58`, despite `reset_all()` having already run).
  Resetting position directly, rather than trusting the lerp, closes this
  regardless of how far off-screen a test drives the package or whether
  the player died from it.
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
  rather than reusing whatever worked last phase. As of phase 9a the whole
  suite is ~4,400 waited frames and lands at **~102-104s**, measured across
  several consecutive runs.
- **A run that looks frozen is usually just buffered — check before
  concluding anything.** `run_tests.sh` ends in `exec "$DMENGINE"`, so when
  its stdout is redirected to a file (not a terminal) the engine's libc uses
  full block buffering, and the log file can sit thousands of frames behind
  what has actually run. macOS has no `stdbuf`; use `script -q /dev/null
  ./scripts/run_tests.sh` instead, which hands the process a pseudo-terminal
  and forces line buffering, so the log reflects real progress. **Do this
  first** whenever a run seems stuck — an entire session was burned blaming
  memory pressure, Spotlight indexing and test logic for what was partly a
  buffered log.
- **How to tell "slow" from "wedged", with evidence rather than guesses.**
  Compare the engine's accumulated CPU time against wall clock:
  `ps -o pid,etime,time,%cpu -p $(pgrep -f dmengine_headless)`. A healthy
  run sits at a few percent (headless has almost nothing to compute), so low
  CPU alone proves nothing — but *low CPU plus a log that stops growing*
  means wedged, while high CPU on one core would mean a genuine busy loop.
  To find out where, `sample <pid> 10 -file /tmp/sample.txt` dumps the
  native stack: a main thread parked in `dmEngine::Step` (next to
  `dmTime::GetMonotonicTime`) with no frames below it is the normal frame
  limiter — the engine is fine and the problem is in Lua, not the engine.
  Do NOT reach for `memory_pressure`/`vm_stat` free-page counts as evidence;
  macOS deliberately keeps free pages low, and htop's `Mem` line is the
  honest read.
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
| 7 | Magnetized | Hazard attraction within `MAGNET_RADIUS` (done — see the Magnetized note under Testing; hazard-side wiring landed in phase 9a's `lethal_hazard.script`) |
| 8 | Sleeping | Wake-on-impact (done) |
| 9a | Hazards + death | Spikes, saws, falling platforms, pits, off-screen check (done — see the Hazards note under Testing; also present in `main.collection`, not just the test fixture). Overlap detection is AABB (see [Known environment limitations](#known-environment-limitations)), not engine physics queries. Spikes/saws share one `lethal_hazard.script` (mechanically identical, PRD's visual distinction doesn't exist yet), pull themselves toward a Magnetized package via `core/magnetism.lua` (closing the loop deferred from phase 7), and build stress via `stress.apply_near_hazard` when within `near_margin` even before contact (PRD 4.5's "perto de spike/serra"). Both hazard contact and the pit/off-screen checks cover the package as well as the player (Panic's impulses can separate them). Falling platforms are a second, optional ground-like surface on the player (`has_extra_ground`/`extra_ground`) — a single fixed slot, not a registry; real multi-hazard levels (phase 10+) will need to revisit this. Pits and off-screen are world-bounds checks (`kill_y`, screen dimensions read via `sys.get_config_int`), not per-instance geometry — no camera/scrolling system exists yet to make per-pit rectangles meaningful. |
| 9b | Delivery + win + restart | Delivery zone, win condition, instant restart (done — `core/delivery.lua` requires full containment, not mere overlap, per PRD 3.4's "dentro"; `delivery_zone.script` checks itself against the package, same inversion as hazards. `won` on `player.script` mirrors `dead`: sticky, freezes `update()`, and whichever landed first wins so a death and a delivery can't both claim the attempt. Restart (PRD 3.5, R) is broadcast through **Defold's input dispatch** rather than a registry — see the note under Testing.) |
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
  /delivery    # delivery zone (win condition)
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
