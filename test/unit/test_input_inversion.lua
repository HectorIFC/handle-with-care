local inversion = require "main.core.input_inversion"

local FRAME = 1 / 60
local TIMED = { inverted_duration = 2.0, normal_duration = 1.0 }
local AIRBORNE = { mode = inversion.MODE_AIRBORNE }

local function advance(state, seconds, grounded, config)
	local changes = 0
	for _ = 1, math.floor(seconds / FRAME) do
		local changed
		state, changed = inversion.update(state, FRAME, grounded, config)
		if changed then changes = changes + 1 end
	end
	return state, changes
end

return function()
	describe("input_inversion.apply", function()
		test("passes movement through untouched when normal", function()
			local state = inversion.new(false)
			assert(inversion.apply(state, 1) == 1)
			assert(inversion.apply(state, -1) == -1)
			assert(inversion.apply(state, 0) == 0)
		end)

		test("flips movement when inverted", function()
			local state = inversion.new(true)
			assert(inversion.apply(state, 1) == -1)
			assert(inversion.apply(state, -1) == 1)
		end)

		test("standing still stays still either way", function()
			-- Inverting zero must not produce -0 weirdness or a phantom nudge.
			assert(inversion.apply(inversion.new(true), 0) == 0)
		end)
	end)

	describe("input_inversion timed mode", function()
		test("starts normal and flips on schedule", function()
			local state, changes = advance(inversion.new(), 1.1, true, TIMED)
			assert(changes == 1)
			assert(state.inverted == true)
		end)

		test("flips back after the inverted phase", function()
			-- PRD's "volta ao normal por poucos segundos".
			local state, changes = advance(inversion.new(), 3.2, true, TIMED)
			assert(changes == 2)
			assert(state.inverted == false)
		end)

		test("the change is one-shot", function()
			local state = advance(inversion.new(), 1.1, true, TIMED)
			local _, changed = inversion.update(state, FRAME, true, TIMED)
			assert(changed == false)
		end)

		test("carries overshoot so cycles do not drift", function()
			local state, changed = inversion.update(inversion.new(), 1.5, true, TIMED)
			assert(changed == true)
			assert(math.abs(state.elapsed - 0.5) < 1e-9)
		end)
	end)

	describe("input_inversion airborne mode", function()
		test("inverted exactly while off the ground", function()
			-- PRD's "inversão só no ar": every jump becomes a commitment.
			local state = inversion.update(inversion.new(), FRAME, false, AIRBORNE)
			assert(state.inverted == true)
			state = inversion.update(state, FRAME, true, AIRBORNE)
			assert(state.inverted == false)
		end)

		test("ignores the timer entirely", function()
			-- Grounded for far longer than any configured phase must never
			-- flip on its own in this mode.
			local state, changes = advance(inversion.new(), 10.0, true,
				{ mode = inversion.MODE_AIRBORNE, inverted_duration = 0.1, normal_duration = 0.1 })
			assert(changes == 0)
			assert(state.inverted == false)
		end)

		test("reports the change only on the frame it happens", function()
			local state, changed = inversion.update(inversion.new(), FRAME, false, AIRBORNE)
			assert(changed == true)
			local _, again = inversion.update(state, FRAME, false, AIRBORNE)
			assert(again == false)
		end)
	end)

	test("does not mutate the state it was given", function()
		local before = inversion.new()
		inversion.update(before, 99, true, TIMED)
		assert(before.elapsed == 0)
		assert(before.inverted == false)
	end)
end
