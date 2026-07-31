local wait = require "test.support.wait"

-- The package spawns at the same initial position as the player in
-- test/test.collection, and should converge to (player.x + offset_x,
-- player.y + offset_y) once settled. offset_x/offset_y are read from the
-- package's own go.property at runtime (not hardcoded here) so this test
-- tracks whatever a collection actually configures — see CLAUDE.md rule 5.
local CONVERGENCE_TOLERANCE = 0.5

local function reset_player()
	msg.post("/player#script", "test_reset")
	wait.seconds(0.05)
end

return function()
	describe("Package physics (integration, Stable state)", function()
		before(reset_player)

		test("converges to the player's position plus offset once settled", function()
			wait.seconds(1.0) -- let the player land and the package's lerp converge
			local offset_x = go.get("/package#script", "offset_x")
			local offset_y = go.get("/package#script", "offset_y")
			local player_pos = go.get_position("/player")
			local package_pos = go.get_position("/package")
			assert(math.abs(package_pos.x - (player_pos.x + offset_x)) < CONVERGENCE_TOLERANCE)
			assert(math.abs(package_pos.y - (player_pos.y + offset_y)) < CONVERGENCE_TOLERANCE)
		end)

		test("keeps following when the player moves", function()
			wait.seconds(1.0) -- settle first

			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = false })
			wait.seconds(0.5)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.seconds(1.0) -- let the package catch back up

			local offset_x = go.get("/package#script", "offset_x")
			local offset_y = go.get("/package#script", "offset_y")
			local player_pos = go.get_position("/player")
			local package_pos = go.get_position("/package")
			assert(math.abs(package_pos.x - (player_pos.x + offset_x)) < CONVERGENCE_TOLERANCE)
			assert(math.abs(package_pos.y - (player_pos.y + offset_y)) < CONVERGENCE_TOLERANCE)
		end)

		test("offset flips to the left side when the player faces left", function()
			wait.seconds(1.0) -- settle first

			msg.post("/player#script", "test_set_input", { move_x = -1, jump_pressed = false })
			wait.seconds(0.5)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.seconds(1.0)

			local offset_x = go.get("/package#script", "offset_x")
			local player_pos = go.get_position("/player")
			local package_pos = go.get_position("/package")
			assert(math.abs(package_pos.x - (player_pos.x - offset_x)) < CONVERGENCE_TOLERANCE)
		end)
	end)
end
