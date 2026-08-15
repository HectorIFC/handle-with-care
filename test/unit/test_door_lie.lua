-- The delivery zone as a liar. The tests that matter most here are the ones
-- proving the lie ENDS: a door that flees forever is not difficult, it is
-- unwinnable, and that is the only line between a troll and a broken game.

local door_lie = require "main.core.door_lie"

return function()
	describe("Door lie", function()

		local RETREATS = { { x = 200, y = 68 }, { x = 300, y = 68 } }

		test("an honest door never moves and is always open", function()
			local state = door_lie.new()
			for _ = 1, 100 do
				state = door_lie.update(state, 1 / 60, 0, RETREATS,
					{ behavior = door_lie.HONEST })
			end
			local x, y = door_lie.position(state, { x = 50, y = 68 }, RETREATS)
			assert(x == 50 and y == 68)
			assert(door_lie.is_open(state, { behavior = door_lie.HONEST }) == true)
		end)

		test("a fleeing door moves when the package arrives", function()
			local config = { behavior = door_lie.FLEE, trigger_distance = 48 }
			local state = door_lie.new()
			state = door_lie.update(state, 1 / 60, 200, RETREATS, config) -- far
			assert(state.flees == 0)
			state = door_lie.update(state, 1 / 60, 10, RETREATS, config) -- arrives
			assert(state.flees == 1)
			local x = door_lie.position(state, { x = 50, y = 68 }, RETREATS)
			assert(x == 200)
		end)

		test("staying close does not burn every retreat at once", function()
			-- The flee triggers on ARRIVING inside the radius, not on being
			-- inside it. Without that edge, a door whose next position is
			-- also near the player would spend all its retreats in three
			-- frames and the joke would never land.
			local config = { behavior = door_lie.FLEE, trigger_distance = 48 }
			local state = door_lie.new()
			for _ = 1, 60 do
				state = door_lie.update(state, 1 / 60, 10, RETREATS, config)
			end
			assert(state.flees == 1)
		end)

		test("a fleeing door runs out of retreats and then stands still", function()
			-- THE rule: the lie ends. Otherwise the room is unwinnable.
			local config = { behavior = door_lie.FLEE, trigger_distance = 48 }
			local state = door_lie.new()
			for _ = 1, 20 do
				-- Alternating far/near so every approach is a fresh edge.
				state = door_lie.update(state, 1 / 60, 200, RETREATS, config)
				state = door_lie.update(state, 1 / 60, 10, RETREATS, config)
			end
			assert(state.flees == #RETREATS)
			local x, y = door_lie.position(state, { x = 50, y = 68 }, RETREATS)
			assert(x == 300 and y == 68)
		end)

		test("a door set to flee with no retreats simply never moves", function()
			-- Degenerate rather than broken: rooms.validate rejects this at
			-- authoring time, and if one ever slipped through, the room is
			-- still finishable.
			local config = { behavior = door_lie.FLEE }
			local state = door_lie.new()
			state = door_lie.update(state, 1 / 60, 0, nil, config)
			assert(state.flees == 0)
			assert(door_lie.position(state, { x = 50, y = 68 }, nil) == 50)
		end)

		test("a vanishing door always comes back", function()
			-- The other half of "the lie ends": waiting has to work, or the
			-- room is a coin flip.
			local config = { behavior = door_lie.VANISH,
				hidden_time = 1.0, open_time = 1.0 }
			local state = door_lie.new()
			local saw_closed, saw_open = false, false
			for _ = 1, 300 do
				state = door_lie.update(state, 1 / 60, 0, nil, config)
				if door_lie.is_open(state, config) then saw_open = true
				else saw_closed = true end
			end
			assert(saw_closed and saw_open)
		end)

		test("a vanishing door does not move", function()
			local config = { behavior = door_lie.VANISH }
			local state = door_lie.new()
			for _ = 1, 200 do
				state = door_lie.update(state, 1 / 60, 5, RETREATS, config)
			end
			assert(door_lie.position(state, { x = 50, y = 68 }, RETREATS) == 50)
		end)

		test("positions lists the home and every retreat", function()
			-- What lets rooms.validate require ALL of them to be winnable,
			-- rather than only the one the author typed first.
			local all = door_lie.positions({ x = 50, y = 68 }, RETREATS)
			assert(#all == 3)
			assert(all[1].x == 50)
			assert(all[3].x == 300)
		end)

		test("max_flees is the number of places to run to", function()
			assert(door_lie.max_flees(nil) == 0)
			assert(door_lie.max_flees({}) == 0)
			assert(door_lie.max_flees(RETREATS) == 2)
		end)
	end)
end
