local wait = require "test.support.wait"

-- Magnetized's own force pulls hazards toward the package (PRD 4.4) — it
-- does not touch the package's own physics at all, unlike every other state
-- implemented so far (Heavy/Light/Panic/Explosive all feed into
-- package_physics via mass/offset/force/shake). Hazards don't exist yet
-- (phase 9a), so there is no hazard object to integration-test being pulled
-- here — that arrives once a hazard adapter exists to call
-- core/magnetism.lua itself. This suite instead guards the other half of
-- the contract: entering Magnetized must be a no-op for the package's own
-- mass/shake/offset, since core/magnetism.lua's force is meant for
-- something else entirely to consume.

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function set_package_state(state_name)
	msg.post("/package#script", "debug_set_state", { state = state_name })
	wait.frames(1)
end

return function()
	describe("Magnetized package state (integration)", function()
		before(reset_all)

		test("entering Magnetized leaves mass at the Stable default", function()
			set_package_state("magnetized")
			assert(go.get("/package#script", "mass") == 1.0)
		end)

		test("entering Magnetized does not add shake (package sits still, no wobble)", function()
			set_package_state("magnetized")

			local min_x, max_x = math.huge, -math.huge
			for _ = 1, 20 do
				local pos = go.get_position("/package")
				min_x = math.min(min_x, pos.x)
				max_x = math.max(max_x, pos.x)
				wait.frames(1)
			end
			assert((max_x - min_x) < 0.01)
		end)

		test("entering Magnetized does not change the package's offset from the player", function()
			wait.frames(60) -- settle first, matching test_package_physics.lua's convergence pattern
			local stable_gap_y = go.get_position("/package").y - go.get_position("/player").y

			set_package_state("magnetized")
			wait.frames(60)
			local magnetized_gap_y = go.get_position("/package").y - go.get_position("/player").y

			assert(math.abs(magnetized_gap_y - stable_gap_y) < 0.5)
		end)

		test("Magnetized sticks (debug_set_state works the same as Heavy/Light)", function()
			set_package_state("magnetized")
			wait.frames(30)
			assert(go.get("/package#script", "current_state") == hash("magnetized"))
		end)
	end)
end
