local heavy_cycle = require "main.core.heavy_cycle"

local FRAME = 1 / 60
local CONFIG = { heavy_duration = 1.0, normal_duration = 2.0 }

-- Advances `seconds` worth of frames, collecting every flip reported along
-- the way — the flips are the whole point of the module, so a helper that
-- threw them away would test nothing.
local function advance(state, seconds, config)
	local flips = {}
	for _ = 1, math.floor(seconds / FRAME) do
		local flipped
		state, flipped = heavy_cycle.update(state, FRAME, config)
		if flipped then
			table.insert(flips, flipped)
		end
	end
	return state, flips
end

return function()
	describe("heavy_cycle.new", function()
		test("starts normal by default", function()
			-- Dropping the player into Heavy before they have moved gives
			-- them no baseline to feel the change against.
			assert(heavy_cycle.new().heavy == false)
		end)

		test("can be asked to start heavy", function()
			assert(heavy_cycle.new(true).heavy == true)
		end)
	end)

	describe("heavy_cycle.update", function()
		test("reports nothing before the phase elapses", function()
			local state, flips = advance(heavy_cycle.new(), 1.5, CONFIG)
			assert(#flips == 0)
			assert(state.heavy == false)
		end)

		test("flips to heavy exactly once when the normal phase ends", function()
			local state, flips = advance(heavy_cycle.new(), 2.2, CONFIG)
			assert(#flips == 1)
			assert(flips[1] == heavy_cycle.HEAVY)
			assert(state.heavy == true)
		end)

		test("flips back to normal after the heavy phase", function()
			-- normal 2.0 then heavy 1.0 -> two flips by 3.2s
			local state, flips = advance(heavy_cycle.new(), 3.2, CONFIG)
			assert(#flips == 2)
			assert(flips[2] == heavy_cycle.NORMAL)
			assert(state.heavy == false)
		end)

		test("alternates indefinitely", function()
			local _, flips = advance(heavy_cycle.new(), 9.5, CONFIG)
			-- 2.0 + 1.0 + 2.0 + 1.0 + 2.0 + 1.0 = 9.0 -> six flips
			assert(#flips == 6)
			for index, flip in ipairs(flips) do
				local expected = (index % 2 == 1) and heavy_cycle.HEAVY or heavy_cycle.NORMAL
				assert(flip == expected)
			end
		end)

		test("the flip is one-shot, not a level that stays set", function()
			-- The adapter posts a message on it; a value that stayed set
			-- would re-post every single frame.
			local state = heavy_cycle.new()
			state = advance(state, 2.2, CONFIG)
			local _, flipped = heavy_cycle.update(state, FRAME, CONFIG)
			assert(flipped == nil)
		end)

		test("carries overshoot forward so cycles do not drift", function()
			-- One long frame must not make every subsequent cycle late.
			local state = heavy_cycle.new()
			local flipped
			state, flipped = heavy_cycle.update(state, 2.5, CONFIG)
			assert(flipped == heavy_cycle.HEAVY)
			assert(math.abs(state.elapsed - 0.5) < 1e-9)
		end)

		test("does not mutate the state it was given", function()
			local before = heavy_cycle.new()
			heavy_cycle.update(before, 5.0, CONFIG)
			assert(before.elapsed == 0)
			assert(before.heavy == false)
		end)

		test("uses its own defaults when no config is given", function()
			-- Defaults are 5.0 normal / 3.0 heavy, so 4s must not flip yet.
			local _, flips = advance(heavy_cycle.new(), 4.0, nil)
			assert(#flips == 0)
		end)
	end)

	describe("heavy_cycle state names are configurable", function()
		test("level 4 Hot Potato drives explosive with the same driver", function()
			-- Architecture rule 6: the phase-timer trigger must need no
			-- change to explosive.lua or the state machine.
			local config = { heavy_duration = 1.0, normal_duration = 2.0,
				heavy_state = "explosive", normal_state = "stable" }
			local _, flips = advance(heavy_cycle.new(), 2.2, config)
			assert(flips[1] == "explosive")
		end)

		test("defaults stay heavy/stable when not configured", function()
			local _, flips = advance(heavy_cycle.new(), 2.2, CONFIG)
			assert(flips[1] == "heavy")
		end)
	end)

	describe("heavy_cycle.progress", function()
		test("runs 0..1 across the current phase", function()
			local state = heavy_cycle.new()
			assert(heavy_cycle.progress(state, CONFIG) == 0)
			state = advance(state, 1.0, CONFIG)
			local mid = heavy_cycle.progress(state, CONFIG)
			assert(mid > 0.4 and mid < 0.6)
		end)

		test("measures against the heavy duration once heavy", function()
			-- The two phases have different lengths, so progress must follow
			-- whichever one is running or a telegraph would lie.
			local state = advance(heavy_cycle.new(), 2.2, CONFIG)
			assert(state.heavy == true)
			assert(heavy_cycle.progress(state, CONFIG) < 0.3)
		end)

		test("never exceeds 1, and a zero-length phase reads as complete", function()
			local state = { heavy = false, elapsed = 99 }
			assert(heavy_cycle.progress(state, CONFIG) == 1)
			assert(heavy_cycle.progress(state, { normal_duration = 0 }) == 1)
		end)
	end)
end
