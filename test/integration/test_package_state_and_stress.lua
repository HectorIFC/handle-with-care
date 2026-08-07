local wait = require "test.support.wait"

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	msg.post("/lethal_hazard#script", "test_reset")
	msg.post("/falling_platform#script", "test_reset")
	wait.frames(36) -- let the player actually fall and land — jumping needs grounded=true
end

local function do_jump_cycle()
	msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = true })
	wait.frames(3)
	msg.post("/player#script", "test_set_input", { move_x = 0, jump_pressed = false })
	wait.frames(45) -- let the jump arc complete and land (jump_velocity=320, gravity=-900 -> ~0.71s airtime)
end

return function()
	describe("Package state machine + stress (integration)", function()
		before(reset_all)

		test("stress starts at zero and Stable right after a reset", function()
			assert(go.get("/package#script", "current_stress") == 0)
			assert(go.get("/package#script", "current_state") == hash("stable"))
		end)

		test("a single jump raises stress above zero", function()
			do_jump_cycle()
			assert(go.get("/package#script", "current_stress") > 0)
		end)

		test("repeated jumps raise stress enough to leave Stable", function()
			for _ = 1, 6 do
				do_jump_cycle()
			end
			assert(go.get("/package#script", "current_stress") > 0)
			assert(go.get("/package#script", "current_state") ~= hash("stable"))
		end)

		test("a direction change raises stress", function()
			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = false })
			wait.frames(6)
			local stress_before = go.get("/package#script", "current_stress")
			msg.post("/player#script", "test_set_input", { move_x = -1, jump_pressed = false })
			wait.frames(6)
			assert(go.get("/package#script", "current_stress") > stress_before)
		end)

		test("shake becomes visible once out of Stable (package wobbles over several frames)", function()
			for _ = 1, 6 do
				do_jump_cycle()
			end
			assert(go.get("/package#script", "current_state") ~= hash("stable"))

			-- The player has landed and stopped moving by now, so any
			-- variation in the package's position across these frames must
			-- come from shake, not from chasing a moving target. Sample
			-- many frames instead of comparing just two adjacent ones —
			-- a single pair can land exactly on a sine extremum (near-zero
			-- derivative), where one frame's shake delta legitimately
			-- rounds away to nothing in float32.
			local min_x, max_x = math.huge, -math.huge
			for _ = 1, 20 do
				local pos = go.get_position("/package")
				min_x = math.min(min_x, pos.x)
				max_x = math.max(max_x, pos.x)
				wait.frames(1)
			end
			assert(max_x - min_x > 0.01)
		end)
	end)
end
