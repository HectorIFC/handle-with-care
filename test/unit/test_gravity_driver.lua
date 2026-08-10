local gravity = require "main.core.gravity_driver"

local FRAME = 1 / 60
local CONFIG = { mood_duration = 2.0, telegraph = 0.5 }
local function rng_fixed(v) return function() return v end end

local function advance(state, seconds, rng, config)
	local changes = 0
	for _ = 1, math.floor(seconds / FRAME) do
		local changed
		state, changed = gravity.update(state, FRAME, rng, config)
		if changed then changes = changes + 1 end
	end
	return state, changes
end

return function()
	describe("gravity_driver", function()
		test("starts on the normal mood", function()
			local state = gravity.new()
			assert(gravity.name(state) == "normal")
			assert(gravity.multiplier(state) == 1.0)
		end)

		test("announces before it applies (the PRD's deliberate delay)", function()
			-- An unsignalled gravity flip mid-jump is an unfair death, not a
			-- readable threat (PRD section 11).
			local state = advance(gravity.new(), 2.1, rng_fixed(1), CONFIG)
			assert(gravity.telegraphing(state) == true)
			assert(gravity.multiplier(state) == 1.0) -- not applied yet
		end)

		test("applies the mood once the telegraph elapses", function()
			local state, changes = advance(gravity.new(), 2.7, rng_fixed(1), CONFIG)
			assert(changes == 1)
			assert(gravity.telegraphing(state) == false)
			assert(gravity.multiplier(state) ~= 1.0)
		end)

		test("never announces the mood already running", function()
			-- "It changed to the same thing" reads as a bug and wastes a
			-- telegraph.
			local state = gravity.new()
			for _ = 1, 12 do
				local before = state.index
				state = advance(state, 2.7, rng_fixed(1), CONFIG)
				assert(state.index ~= before)
			end
		end)

		test("the change is one-shot, not a level that stays set", function()
			local state = advance(gravity.new(), 2.7, rng_fixed(1), CONFIG)
			local _, changed = gravity.update(state, FRAME, rng_fixed(1), CONFIG)
			assert(changed == false)
		end)

		test("rng picks which mood, so a test can pin it", function()
			local a = advance(gravity.new(), 2.7, rng_fixed(1), CONFIG)
			local b = advance(gravity.new(), 2.7, rng_fixed(2), CONFIG)
			assert(a.index ~= b.index)
		end)

		test("does not mutate the state it was given", function()
			local before = gravity.new()
			gravity.update(before, 99, rng_fixed(1), CONFIG)
			assert(before.elapsed == 0)
			assert(before.pending == nil)
		end)

		test("every mood has a usable multiplier", function()
			-- A zero or negative multiplier would invert or freeze gravity,
			-- which is level 6's job, not a mood's.
			for _, mood in ipairs(gravity.MOODS) do
				assert(mood.multiplier > 0)
				assert(type(mood.name) == "string")
			end
		end)
	end)
end
