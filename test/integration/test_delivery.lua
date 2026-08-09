local wait = require "test.support.wait"

-- Delivery zone, win condition and restart (PRD 3.4/3.5).
--
-- The zone sits at (60, 150) in test/test.collection — deliberately far from
-- everything every other suite touches (their teleports live at x=192..300,
-- and the package settles around (200, 68)). That matters more here than for
-- any other fixture: a zone the package could wander into would win the
-- level mid-test, freezing the player and making unrelated assertions pass
-- or fail for entirely the wrong reason. Only this suite brings the package
-- into it, explicitly.

local function reset_all()
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
	wait.frames(3)
end

return function()
	describe("Delivery zone and win condition (integration)", function()
		before(reset_all)

		test("nothing is delivered while the package is nowhere near the zone", function()
			assert(go.get("/delivery_zone#script", "delivered") == false)
			assert(go.get("/player#script", "won") == false)
		end)

		test("putting the package inside the zone wins the level", function()
			deliver_package()
			assert(go.get("/delivery_zone#script", "delivered") == true)
			assert(go.get("/player#script", "won") == true)
		end)

		test("winning freezes the player, the same as dying does", function()
			deliver_package()
			local frozen_at = go.get_position("/player")
			msg.post("/player#script", "test_set_input", { move_x = 1, jump_pressed = true })
			wait.frames(20)
			local now = go.get_position("/player")
			assert(math.abs(now.x - frozen_at.x) < 0.01)
			assert(math.abs(now.y - frozen_at.y) < 0.01)
		end)

		test("the win is one-way: it does not re-fire every frame it sits there", function()
			-- delivered is sticky, so a package resting in the zone must not
			-- keep re-posting package_delivered — the same one-shot shape the
			-- offscreen timer and explosive detonation both use.
			deliver_package()
			wait.frames(30)
			assert(go.get("/delivery_zone#script", "delivered") == true)
			assert(go.get("/player#script", "won") == true)
		end)

		test("a dead player cannot win, even with the package in the zone", function()
			-- A fail condition already decided the attempt; geometry must not
			-- overturn it (core/delivery.is_delivered's player_dead guard).
			msg.post("/player#script", "test_set_position", { x = 192, y = -30 }) -- below kill_y
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)

			deliver_package()
			assert(go.get("/delivery_zone#script", "delivered") == false)
			assert(go.get("/player#script", "won") == false)
		end)

		test("reset clears a win, so the level can be replayed", function()
			deliver_package()
			assert(go.get("/player#script", "won") == true)

			reset_all()
			assert(go.get("/player#script", "won") == false)
			assert(go.get("/delivery_zone#script", "delivered") == false)
		end)

		test("reset revives a dead player and puts it back at the start", function()
			-- PRD 3.5's restart, exercised through the message the R key
			-- routes into (on_input calls the same reset()), since headless
			-- input injection isn't available here.
			local start = go.get_position("/player")
			msg.post("/player#script", "test_set_position", { x = 192, y = -30 })
			wait.frames(3)
			assert(go.get("/player#script", "dead") == true)

			reset_all()
			assert(go.get("/player#script", "dead") == false)
			local now = go.get_position("/player")
			assert(math.abs(now.x - start.x) < 1.0)
		end)
	end)
end
