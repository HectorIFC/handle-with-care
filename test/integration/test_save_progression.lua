local wait = require "test.support.wait"

-- Save/progression wiring (PRD 6.2). The save adapter in test/test.collection
-- runs with in_memory_only = true, so nothing here can read or clobber the
-- developer's own progress file — the wiring is what's under test, not
-- sys.save itself.

local function reset_all()
	-- Wipe FIRST, then reset the objects. Order matters and is easy to
	-- break by accident: the controller's own reset posts level_started,
	-- which records an attempt, so wiping afterwards would erase the very
	-- attempt the "Continue becomes available" test asserts on. It happens
	-- to survive the other order too (the controller's post lands in the
	-- next dispatch cycle, after new_game), but relying on that would make
	-- a future reordering of these lines fail for a completely opaque
	-- reason.
	msg.post("/save_adapter#script", "new_game")
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	msg.post("/lethal_hazard#script", "test_reset")
	msg.post("/falling_platform#script", "test_reset")
	msg.post("/delivery_zone#script", "test_reset")
	msg.post("/level_controller#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function deliver_package()
	msg.post("/package#script", "test_set_position", { x = 60, y = 150 })
	wait.frames(5)
end

return function()
	describe("Save and progression wiring (integration)", function()
		before(reset_all)

		test("a fresh save starts with only level 1 unlocked", function()
			assert(go.get("/save_adapter#script", "unlocked") == 1)
			assert(go.get("/save_adapter#script", "all_complete") == false)
		end)

		test("starting a level records an attempt, so Continue becomes available", function()
			-- reset_all's test_reset re-runs the controller's start_attempt,
			-- which is what posts level_started.
			assert(go.get("/save_adapter#script", "has_progress") == true)
		end)

		test("the level controller counts elapsed time while the attempt runs", function()
			local before_time = go.get("/level_controller#script", "elapsed")
			wait.frames(30)
			local after = go.get("/level_controller#script", "elapsed")
			assert(after > before_time)
		end)

		test("winning the level unlocks the next one", function()
			assert(go.get("/save_adapter#script", "unlocked") == 1)
			deliver_package()
			assert(go.get("/player#script", "won") == true)
			assert(go.get("/save_adapter#script", "unlocked") == 2)
		end)

		test("the clock stops once the attempt is decided", function()
			deliver_package()
			local at_win = go.get("/level_controller#script", "elapsed")
			wait.frames(30)
			assert(go.get("/level_controller#script", "elapsed") == at_win)
		end)

		test("a win reports completion exactly once, not every frame", function()
			-- player.script's `won` is sticky, so without the controller's
			-- own `reported` latch this would post a completion every frame
			-- the package sits in the zone.
			deliver_package()
			wait.frames(40)
			assert(go.get("/save_adapter#script", "unlocked") == 2) -- not 3+
		end)

		test("dying does not unlock anything", function()
			msg.post("/player#script", "test_set_position", { x = 192, y = -30 })
			wait.frames(5)
			assert(go.get("/player#script", "dead") == true)
			assert(go.get("/save_adapter#script", "unlocked") == 1)
		end)

		test("new_game wipes progression back to level 1", function()
			deliver_package()
			assert(go.get("/save_adapter#script", "unlocked") == 2)

			msg.post("/save_adapter#script", "new_game")
			wait.frames(2)
			assert(go.get("/save_adapter#script", "unlocked") == 1)
			assert(go.get("/save_adapter#script", "has_progress") == false)
		end)
	end)
end
