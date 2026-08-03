local wait = require "test.support.wait"

-- Panic is one of the stress-ladder states (see package_state_machine.lua):
-- it's always re-derived from the stress value every frame, so debug_set_state
-- alone can't force it to stick. Push stress directly instead and let the
-- ladder do its job — debug_set_stress is the one that reaches Panic/Nervous/
-- Explosive on demand; debug_set_state is for the non-ladder states only
-- (Heavy/Light/Magnetized/Sleeping).
local PANIC_THRESHOLD = 70

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function set_stress(value)
	msg.post("/package#script", "debug_set_stress", { value = value })
	wait.frames(1)
end

return function()
	describe("Panic impulses and player knockback (integration)", function()
		before(reset_all)

		test("pushing stress into the panic range actually enters Panic", function()
			set_stress(PANIC_THRESHOLD + 10)
			assert(go.get("/package#script", "current_state") == hash("panic"))
		end)

		test("entering Panic eventually knocks the player away from a stationary baseline", function()
			local baseline_x = go.get_position("/player").x
			local baseline_y = go.get_position("/player").y

			set_stress(PANIC_THRESHOLD + 10)
			-- panic_impulse_interval defaults to 0.55s (~33 frames); wait for
			-- a couple of impulses so the test isn't sensitive to any single
			-- (random) impulse landing near zero.
			wait.frames(90)

			local player_pos = go.get_position("/player")
			local displaced = (player_pos.x ~= baseline_x) or (player_pos.y ~= baseline_y)
			assert(displaced)
		end)

		test("Panic makes the package move noticeably (shake + impulses combined)", function()
			set_stress(PANIC_THRESHOLD + 10)
			wait.frames(90)

			local min_x, max_x = math.huge, -math.huge
			for _ = 1, 20 do
				local pos = go.get_position("/package")
				min_x = math.min(min_x, pos.x)
				max_x = math.max(max_x, pos.x)
				wait.frames(1)
			end
			assert(max_x - min_x > 0.01)
		end)

		test("knockback settles back down once impulses stop (leaving Panic)", function()
			set_stress(PANIC_THRESHOLD + 10)
			wait.frames(90) -- accumulate some knockback

			set_stress(0) -- drops back to Stable, stops the impulses
			wait.frames(60) -- give knockback time to decay via player's own damping

			local pos_a = go.get_position("/player")
			wait.frames(30)
			local pos_b = go.get_position("/player")
			-- no input, no more impulses: position should have settled
			assert(math.abs(pos_a.x - pos_b.x) < 0.5)
			assert(math.abs(pos_a.y - pos_b.y) < 0.5)
		end)
	end)
end
