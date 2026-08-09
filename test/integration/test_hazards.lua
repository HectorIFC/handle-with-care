local wait = require "test.support.wait"

-- Hazards and death conditions (PRD 3.3/4.7). Every fail condition funnels
-- through player.script's single `dead` flag — see its die() helper.

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	msg.post("/lethal_hazard#script", "test_reset")
	msg.post("/falling_platform#script", "test_reset")
	msg.post("/delivery_zone#script", "test_reset")
	msg.post("/level_controller#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function set_package_state(state_name)
	msg.post("/package#script", "debug_set_state", { state = state_name })
	wait.frames(1)
end

local function set_stress(value)
	msg.post("/package#script", "debug_set_stress", { value = value })
	wait.frames(3) -- see CLAUDE.md's note on the ceiling-value settle window
end

local function teleport_player(x, y)
	msg.post("/player#script", "test_set_position", { x = x, y = y })
end

local function teleport_hazard(x, y)
	msg.post("/lethal_hazard#script", "test_set_position", { x = x, y = y })
end

local function teleport_package(x, y)
	msg.post("/package#script", "test_set_position", { x = x, y = y })
end

-- Re-teleports the package every frame for `frames` frames. A single
-- teleport isn't enough to test the package's own off-screen timer:
-- package_physics lerps 35%/frame back toward the player+offset target,
-- which converges back on-screen in ~8 frames — far short of the
-- 120-frame timeout. Re-pinning every frame keeps it off-screen the whole
-- window instead.
local function pin_package(x, y, frames)
	for _ = 1, frames do
		teleport_package(x, y)
		wait.frames(1)
	end
end

return function()
	describe("Hazards and death conditions (integration)", function()
		before(reset_all)

		test("a lethal hazard kills the player on contact", function()
			-- lethal_hazard spawns at (300, 56) in test.collection —
			-- deliberately OUTSIDE magnetism's default radius (95) from
			-- the package's resting position (~200, 68), so it never
			-- drifts on its own during any OTHER suite's Magnetized tests.
			-- The dedicated attraction test below brings it into range
			-- explicitly instead.
			teleport_player(300, 56)
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)
			assert(go.get("/package#script", "player_died_count") == 1)
		end)

		test("Magnetized attracts a lethal hazard toward the package", function()
			-- Bring the hazard within magnet_radius (95) just for this
			-- test — its default spawn (300, 56) is deliberately outside
			-- that radius so it stays inert during every other suite.
			teleport_hazard(280, 56)
			wait.frames(1)

			set_package_state("magnetized")
			local package_pos = go.get_position("/package")
			local hazard_start = go.get_position("/lethal_hazard")
			local start_distance = math.abs(hazard_start.x - package_pos.x)

			wait.frames(20) -- short window: closes ~50 units at 150px/s, well short of actually reaching contact

			local hazard_now = go.get_position("/lethal_hazard")
			local package_pos_now = go.get_position("/package")
			local now_distance = math.abs(hazard_now.x - package_pos_now.x)

			assert(now_distance < start_distance)
		end)

		test("the player can rest on a falling platform before it falls", function()
			-- falling_platform spawns at (250, 150) — off the (192, ...)
			-- column test_sleeping.lua's hard_landing() falls through, so
			-- the two suites' fixtures don't intercept each other. half_height
			-- 8 -> top at 158; player half_height 8 -> resting on it at y=166.
			teleport_player(250, 166)
			wait.frames(3)
			assert(go.get("/player#script", "grounded") == true)
			assert(math.abs(go.get_position("/player").y - 166) < 1.0)
		end)

		test("standing on it long enough makes the platform fall, dropping the player", function()
			teleport_player(250, 166)
			wait.frames(3)
			assert(go.get("/player#script", "grounded") == true)

			local platform_start_y = go.get_position("/falling_platform").y
			wait.frames(75) -- fall_delay (60 frames) + margin for it to actually start dropping
			local platform_now_y = go.get_position("/falling_platform").y
			assert(platform_now_y < platform_start_y)

			-- The player free-falls once the platform drops out from under
			-- it, and lands back on the main ground (resting_y 56) once it
			-- clears the gap — same physics as any other fall.
			wait.frames(60)
			assert(go.get("/player#script", "grounded") == true)
			assert(math.abs(go.get_position("/player").y - 56) < 1.0)

			-- Confirms test_reset on the platform itself actually works —
			-- this is the exact reset path a copy-paste mistake silently
			-- broke once already this phase (see CLAUDE.md), and nothing
			-- else in this suite would have noticed since the test that
			-- needs the platform intact (above) runs BEFORE this one drops
			-- it.
			msg.post("/falling_platform#script", "test_reset")
			wait.frames(2)
			assert(math.abs(go.get_position("/falling_platform").y - 150) < 0.01)
			assert(go.get("/falling_platform#script", "is_falling") == false)
		end)

		test("falling below the kill plane kills the player (pit death)", function()
			teleport_player(192, -30) -- below kill_y (-20 by default)
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)
		end)

		test("staying fully off-screen too long kills the player", function()
			-- Off the TOP, not the side: teleporting sideways (e.g. x=-50)
			-- leaves the player falling toward the main ground/kill_y at
			-- the same time it's off-screen, and that fall reaches kill_y
			-- (-20) in ~31 frames — long before the 120-frame offscreen
			-- timeout, so a sideways teleport dies from the pit, not the
			-- timer, and can't tell the two conditions apart. y=5000 takes
			-- ~200 frames to fall to kill_y, comfortably outlasting the
			-- timeout, so death here is unambiguously the offscreen timer.
			-- 60/+90 rather than 100/+40, matching the package's equivalent
			-- test below: 100 sat close enough to the 120-frame timeout to
			-- fail intermittently. A 150-frame fall from y=5000 only reaches
			-- ~y=2190, so the wider window still cannot reach kill_y and the
			-- death stays unambiguously the off-screen timer's.
			teleport_player(192, 5000)
			wait.frames(60)
			assert(go.get("/player#script", "dead") == false,
				"player off-screen for only 60 frames but already dead")
			wait.frames(90)
			assert(go.get("/player#script", "dead") == true,
				"player off-screen for 150 frames, past the 120-frame timeout, but still alive")
		end)

		test("briefly going offscreen and back does not kill the player", function()
			teleport_player(192, 5000)
			wait.frames(30) -- well under the 120-frame timeout, and the fall (~116 units) is nowhere near kill_y either
			teleport_player(192, 100)
			wait.frames(140) -- long enough that a non-reset timer would have killed by now
			assert(go.get("/player#script", "dead") == false)
		end)

		test("the package falling below the kill plane also kills the player", function()
			-- Panic's impulses can genuinely separate the package from the
			-- player, so PRD 3.3/4.7 name the package explicitly for both
			-- pit and off-screen death — this and the next test drive the
			-- package's OWN checks independently of the player's, via
			-- test_set_position on the package itself.
			teleport_package(200, -500) -- lerps toward target but stays well below kill_y for several frames
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)
		end)

		test("the package staying off-screen too long also kills the player", function()
			-- Margins deliberately well clear of the 120-frame timeout on
			-- both sides, rather than the 100/+40 this used to sit at. Each
			-- pin_package() iteration is a real message dispatch plus a frame
			-- wait, so the package can start accumulating off-screen time a
			-- frame or two before the loop's own count begins — enough for a
			-- knife-edge 100 to intermittently read as already-dead. 60 is
			-- unambiguously under the timeout and 60+90=150 unambiguously
			-- over it, which is what this test actually means to assert.
			-- (The exact timeout arithmetic is unit-tested in
			-- test/unit/test_offscreen_timer.lua, where dt is injected and
			-- there is no dispatch timing to race.)
			pin_package(200, 5000, 60)
			assert(go.get("/player#script", "dead") == false,
				"package went off-screen for only 60 frames but the player is already dead")
			pin_package(200, 5000, 90)
			assert(go.get("/player#script", "dead") == true,
				"package was off-screen for 150 frames, past the 120-frame timeout, but the player is alive")
		end)

		test("multiple near_hazard messages in one frame don't stack stress beyond the per-second rate", function()
			-- Regression coverage: near_hazard used to apply
			-- stress_near_hazard_per_sec * dt directly per message, so N
			-- hazards in range the same frame would multiply the rate by
			-- N. accumulate_continuous_stress now latches a single flag,
			-- consumed and cleared once per frame regardless of how many
			-- messages arrived.
			local stress_before = go.get("/package#script", "current_stress")
			msg.post("/package#script", "near_hazard", { dt = 1 / 60 })
			msg.post("/package#script", "near_hazard", { dt = 1 / 60 })
			msg.post("/package#script", "near_hazard", { dt = 1 / 60 })
			wait.frames(1)
			local stress_after = go.get("/package#script", "current_stress")
			-- One frame's worth is ~0.1-0.2 net (12/sec near_hazard minus
			-- 6/sec grounded decay, at dt ~1/60); three times that (~0.6)
			-- would indicate the messages stacked instead of latching.
			-- The message reports the actual delta and state: this assertion
			-- has failed intermittently, and a bare "assertion failed!" gave
			-- nothing to work from.
			local delta = stress_after - stress_before
			assert(delta < 0.3, string.format(
				"near_hazard stacked: delta=%.4f (before=%.4f after=%.4f state=%s)",
				delta, stress_before, stress_after,
				tostring(go.get("/package#script", "current_state"))))
		end)

		test("the package exploding also kills the player (unified death)", function()
			set_stress(100)
			wait.frames(105) -- explosive_time (90 frames) + margin
			assert(go.get("/package#script", "detonated") == true)
			assert(go.get("/player#script", "dead") == true)
		end)

		test("once dead, the player freezes in place", function()
			teleport_player(300, 56) -- onto the lethal hazard
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)
			local pos_at_death = go.get_position("/player")

			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = true })
			wait.frames(30)

			local pos_later = go.get_position("/player")
			assert(pos_later.x == pos_at_death.x)
			assert(pos_later.y == pos_at_death.y)
		end)
	end)
end
