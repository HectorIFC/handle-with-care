local wait = require "test.support.wait"

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
	wait.frames(1) -- let mass/config sync at least once
end

return function()
	describe("Heavy & Light affecting the player (integration)", function()
		before(reset_all)

		test("package mass reflects Stable/Heavy/Light defaults", function()
			-- go.property stores floats as float32; 0.4 (unlike 1.0/2.5) has
			-- no exact float32 representation, so this needs a tolerance —
			-- see CLAUDE.md's float32 round-trip note (phase 1's
			-- RESTING_EPSILON) for the same class of issue.
			assert(go.get("/package#script", "mass") == 1.0)
			set_package_state("heavy")
			assert(go.get("/package#script", "mass") == 2.5)
			set_package_state("light")
			assert(math.abs(go.get("/package#script", "mass") - 0.4) < 1e-6)
		end)

		test("Heavy makes the player move a shorter distance in the same window", function()
			local stable_start = go.get_position("/player").x
			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = false })
			wait.frames(30)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			local stable_distance = go.get_position("/player").x - stable_start

			reset_all()
			set_package_state("heavy")

			local heavy_start = go.get_position("/player").x
			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = false })
			wait.frames(30)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			local heavy_distance = go.get_position("/player").x - heavy_start

			assert(heavy_distance < stable_distance)
			assert(heavy_distance > 0) -- still moves, just less
		end)

		test("Heavy makes the player rise less in a fixed window after jumping", function()
			local stable_start_y = go.get_position("/player").y
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
			wait.frames(1)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.frames(5)
			local stable_rise = go.get_position("/player").y - stable_start_y

			reset_all()
			set_package_state("heavy")

			local heavy_start_y = go.get_position("/player").y
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
			wait.frames(1)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.frames(5)
			local heavy_rise = go.get_position("/player").y - heavy_start_y

			assert(heavy_rise < stable_rise)
			assert(heavy_rise > 0) -- still jumped, just less
		end)

		test("Light reduces effective gravity, so the player stays higher after the same time airborne", function()
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
			wait.frames(1)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.frames(30)
			local stable_y = go.get_position("/player").y

			reset_all()
			set_package_state("light")

			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
			wait.frames(1)
			msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
			wait.frames(30)
			local light_y = go.get_position("/player").y

			assert(light_y > stable_y)
		end)

		test("the package sits lower when Heavy and floats higher when Light", function()
			wait.frames(60)
			local stable_gap = go.get_position("/package").y - go.get_position("/player").y

			set_package_state("heavy")
			wait.frames(60)
			local heavy_gap = go.get_position("/package").y - go.get_position("/player").y

			set_package_state("light")
			wait.frames(60)
			local light_gap = go.get_position("/package").y - go.get_position("/player").y

			assert(heavy_gap < stable_gap)
			assert(light_gap > stable_gap)
		end)
	end)
end
