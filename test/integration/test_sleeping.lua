local wait = require "test.support.wait"

-- Sleeping (PRD 4.4): shake/forces zeroed and immune to the stress ladder,
-- like Magnetized — but unlike every other non-ladder state, it has an
-- actual exit condition wired this phase: a hard landing wakes it, handing
-- control back to the stress ladder rather than hardcoding "always Nervous"
-- or "always Panic" (see package.script's player_landed handler).

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	msg.post("/lethal_hazard#script", "test_reset")
	msg.post("/falling_platform#script", "test_reset")
	msg.post("/delivery_zone#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function set_package_state(state_name)
	msg.post("/package#script", "debug_set_state", { state = state_name })
	wait.frames(1)
end

local function set_stress(value)
	msg.post("/package#script", "debug_set_stress", { value = value })
	wait.frames(3) -- see CLAUDE.md's note on the ceiling-value settle window; harmless margin at non-ceiling values too
end

-- Teleports the player well above the ground and forces it airborne, then
-- waits long enough for it to fall and land. A fall from 200 to the
-- resting height (56) covers 144 units — impact velocity
-- sqrt(2 * 900 * 144) ~= 509 px/s, comfortably past heavy_landing_velocity
-- (400 by default). No ordinary jump reaches that: a normal jump's return
-- speed roughly equals its own launch velocity (320), well under it.
-- The fall itself completes in 34 frames at the locked 60Hz; waiting 45
-- leaves ~10 frames of slack for the landing message to dispatch and for
-- package.script's own update() to react to it.
local function hard_landing()
	msg.post("/player#script", "test_set_position", { x = 192, y = 200 })
	wait.frames(45)
end

return function()
	describe("Sleeping package state (integration)", function()
		before(reset_all)

		test("entering Sleeping leaves mass at the Stable default", function()
			set_package_state("sleeping")
			assert(go.get("/package#script", "mass") == 1.0)
		end)

		test("entering Sleeping does not add shake (package sits still, no wobble)", function()
			set_package_state("sleeping")

			local min_x, max_x = math.huge, -math.huge
			for _ = 1, 20 do
				local pos = go.get_position("/package")
				min_x = math.min(min_x, pos.x)
				max_x = math.max(max_x, pos.x)
				wait.frames(1)
			end
			assert((max_x - min_x) < 0.01)
		end)

		test("Sleeping sticks even as stress rises from repeated jumps", function()
			set_package_state("sleeping")
			-- 8 iterations, not 6: each one nets ~5.5 stress (6 from the
			-- jump, minus ~0.5 of grounded decay_safe over its ~6 grounded
			-- frames), landing around 44 — comfortable margin above
			-- nervous_threshold (30). 6 iterations only reached ~33, a
			-- ~3-point margin that real-engine dt jitter could erase — and
			-- the fix for that is MORE iterations, not longer waits: every
			-- extra grounded frame only decays stress further, so widening
			-- wait.frames() here would shrink the margin, not grow it (see
			-- the analogous note on the Nervous wake test below).
			for _ = 1, 8 do
				msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
				wait.frames(3)
				msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
				wait.frames(45)
			end
			-- Past nervous_threshold (30), not just "moved at all" — proves
			-- Sleeping resists a stress level that would otherwise have
			-- moved the ladder, not merely that stress accumulates.
			assert(go.get("/package#script", "current_stress") > 30)
			assert(go.get("/package#script", "current_state") == hash("sleeping"))
		end)

		test("a hard landing wakes the package (no longer Sleeping)", function()
			set_package_state("sleeping")
			hard_landing()
			assert(go.get("/package#script", "current_state") ~= hash("sleeping"))
		end)

		test("waking with low accumulated stress lands on Nervous", function()
			-- 25, minus a few points of grounded decay_safe (6/sec) accrued
			-- across this test's own waits, plus the 18-point heavy-landing
			-- bump, lands around 41 — comfortably mid-band in [30, 70), not
			-- pinned to either edge. 15 (the initially-chosen value) landed
			-- only ~1.4 points above the 30 threshold once decay_safe was
			-- accounted for — enough margin to occasionally flip under real
			-- windowed-engine dt jitter, and more wait.frames() margin
			-- elsewhere would have made that WORSE, not better, since decay
			-- only pulls stress down further the longer it waits grounded.
			set_stress(25)
			set_package_state("sleeping")
			hard_landing()
			assert(go.get("/package#script", "current_state") == hash("nervous"))
		end)

		test("waking with high accumulated stress lands on Panic", function()
			-- 60, minus a touch of grounded decay_safe, plus the 18-point
			-- heavy-landing bump, lands around 77 — clear of the 70
			-- threshold with margin (Panic's own stress accumulation only
			-- ever pushes this higher afterward, never back down).
			set_stress(60)
			set_package_state("sleeping")
			hard_landing()
			assert(go.get("/package#script", "current_state") == hash("panic"))
		end)
	end)
end
