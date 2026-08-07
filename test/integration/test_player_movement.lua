local wait = require "test.support.wait"

-- The ground platform in test/test.collection sits centered at (192, 40),
-- half-extents (64, 8): top edge at y=48, spanning x 128..256. The player
-- (half_height=8) spawns at (192, 100) — above the platform — and its
-- deterministic resting height is exactly 48 + 8 = 56 (no engine physics
-- involved, so this isn't a tolerance band — see player_movement.lua).
local RESTING_Y = 56

-- All suites share one persistent player/package pair for the whole test
-- run (see test/test.collection) — only this suite's own before-hook protects
-- it from state left behind by whatever ran earlier, so both must be reset.
local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	msg.post("/lethal_hazard#script", "test_reset")
	msg.post("/falling_platform#script", "test_reset")
	wait.frames(36) -- let the player land
end

return function()
	describe("Player movement (integration)", function()
		before(reset_all)

		test("falls under gravity and comes to rest on top of the ground", function()
			wait.frames(36)
			local settled_pos = go.get_position("/player")
			assert(settled_pos.y == RESTING_Y)

			wait.frames(6)
			local later_pos = go.get_position("/player")
			assert(later_pos.y == settled_pos.y) -- fully at rest, no further drift
		end)

		test("moves right while move_right input is held", function()
			wait.frames(36)
			local start_pos = go.get_position("/player")
			assert(start_pos.y == RESTING_Y) -- confirms it actually landed first

			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = false })
			wait.frames(18)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })

			local end_pos = go.get_position("/player")
			assert(end_pos.x > start_pos.x)
		end)

		test("moves left while move_left input is held", function()
			wait.frames(36)
			local start_pos = go.get_position("/player")
			assert(start_pos.y == RESTING_Y) -- confirms it actually landed first

			msg.post("/player#script", "test_set_input", { move_x = -1, jump_pressed = false })
			wait.frames(18)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })

			local end_pos = go.get_position("/player")
			assert(end_pos.x < start_pos.x)
		end)

		test("jumping while grounded lifts the player upward", function()
			wait.frames(36)
			local grounded_y = go.get_position("/player").y
			assert(grounded_y == RESTING_Y) -- confirms it actually landed first

			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
			wait.frames(6)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })

			local airborne_y = go.get_position("/player").y
			assert(airborne_y > grounded_y)
		end)
	end)
end
