-- The advancing wall. The test that matters is the last group: a chaser
-- faster than the player is not difficulty, it is an unwinnable room, and
-- it would present as "I always die" rather than as anything diagnosable.

local chaser = require "main.core.chaser"

return function()
	describe("Chaser", function()

		test("stands still before any time has passed", function()
			local state = chaser.new(-40)
			assert(state.position == -40)
		end)

		test("advances, and faster the longer it has been going", function()
			local config = { speed = 40, acceleration = 10 }
			local first = chaser.position_at(0, 1, config)
			local second = chaser.position_at(0, 2, config)
			assert(first == 45)              -- 40*1 + 5*1
			assert(second == 100)            -- 40*2 + 5*4
			assert(second - first > first)   -- accelerating, not linear
		end)

		test("integrating frame by frame matches the closed form", function()
			-- The whole validator depends on this: it asks where the wall
			-- will be at a moment the game has not reached, so the two have
			-- to agree exactly.
			local config = { speed = 40, acceleration = 10 }
			local state = chaser.new(-20)
			for _ = 1, 120 do
				state = chaser.update(state, 1 / 60, -20, config)
			end
			local closed = chaser.position_at(-20, state.time, config)
			assert(math.abs(state.position - closed) < 0.0001)
		end)

		test("catches anything at or behind its face", function()
			local state = { position = 100, time = 0 }
			assert(chaser.caught(state, { x = 100, half_width = 8 }) == true)
			assert(chaser.caught(state, { x = 108, half_width = 8 }) == true)
			assert(chaser.caught(state, { x = 130, half_width = 8 }) == false)
		end)

		test("it is a half-plane, not a box", function()
			-- A box would let a fast player end up past it and survive, which
			-- reads as a bug rather than as a reprieve.
			local state = { position = 100, time = 0 }
			assert(chaser.caught(state, { x = -500, half_width = 8 }) == true)
		end)

		test("a slow wall leaves the player time to finish", function()
			local ok = chaser.survivable({
				spawn_x = 30, door_x = 350, move_speed = 90,
				start = -40, speed = 34, acceleration = 2, slack = 2,
			})
			assert(ok == true)
		end)

		test("a wall faster than the player is rejected", function()
			-- The negative proof. 200 px/s against a 90 px/s player: no
			-- amount of skill wins, so it must never reach a room.
			local ok, wall_x = chaser.survivable({
				spawn_x = 30, door_x = 350, move_speed = 90,
				start = 0, speed = 200, acceleration = 0, slack = 0,
			})
			assert(ok == false)
			assert(wall_x > 350)
		end)

		test("acceleration alone can make a survivable wall unsurvivable", function()
			-- Same starting speed, and the room stops being winnable purely
			-- because the wall keeps getting faster — the case a "speed <
			-- move_speed" check would have waved through.
			local base = { spawn_x = 30, door_x = 350, move_speed = 90,
				start = -40, speed = 34, slack = 2 }
			base.acceleration = 2
			assert(chaser.survivable(base) == true)
			base.acceleration = 40
			assert(chaser.survivable(base) == false)
		end)

		test("a door behind the spawn is never survivable", function()
			-- Degenerate, but it would otherwise divide into a negative walk
			-- time and report a nonsense pass.
			assert(chaser.survivable({
				spawn_x = 300, door_x = 100, move_speed = 90, start = 0,
			}) == false)
		end)
	end)
end
