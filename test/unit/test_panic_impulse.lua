local panic_impulse = require "main.core.panic_impulse"

return function()
	describe("panic_impulse.new", function()
		test("starts with zero timer and zero force", function()
			local state = panic_impulse.new()
			assert(state.time_since_last == 0)
			assert(state.horizontal_force == 0)
			assert(state.vertical_force == 0)
		end)
	end)

	describe("panic_impulse.update", function()
		local config = { interval = 0.5, horizontal_min = -100, horizontal_max = 100, vertical_min = 50, vertical_max = 150 }
		local function fixed_rng(value)
			return function(_, _) return value end
		end

		test("no impulse before the interval elapses", function()
			local state = panic_impulse.new()
			local triggered
			state, triggered = panic_impulse.update(state, 0.3, fixed_rng(999), config)
			assert(triggered == false)
			assert(state.horizontal_force == 0)
			assert(state.vertical_force == 0)
			assert(state.time_since_last == 0.3)
		end)

		test("triggers exactly when the interval elapses", function()
			local state = panic_impulse.new()
			local triggered
			state, triggered = panic_impulse.update(state, 0.5, fixed_rng(42), config)
			assert(triggered == true)
			assert(state.horizontal_force == 42)
			assert(state.vertical_force == 42)
			assert(state.time_since_last == 0)
		end)

		test("triggers when the interval is exceeded across several frames", function()
			local state = panic_impulse.new()
			local triggered
			state, triggered = panic_impulse.update(state, 0.2, fixed_rng(1), config)
			assert(triggered == false)
			state, triggered = panic_impulse.update(state, 0.2, fixed_rng(1), config)
			assert(triggered == false)
			state, triggered = panic_impulse.update(state, 0.2, fixed_rng(7), config)
			assert(triggered == true) -- 0.2+0.2+0.2 = 0.6 >= 0.5
			assert(state.horizontal_force == 7)
		end)

		test("force is zero again on the frame right after an impulse fires", function()
			local state = panic_impulse.new()
			state = panic_impulse.update(state, 0.5, fixed_rng(42), config)
			local triggered
			state, triggered = panic_impulse.update(state, 0.01, fixed_rng(42), config)
			assert(triggered == false)
			assert(state.horizontal_force == 0)
			assert(state.vertical_force == 0)
		end)

		test("passes distinct min/max ranges to rng for horizontal vs vertical", function()
			local seen = {}
			local function recording_rng(min_value, max_value)
				table.insert(seen, { min = min_value, max = max_value })
				return 0
			end
			local state = panic_impulse.new()
			panic_impulse.update(state, 0.5, recording_rng, config)
			assert(seen[1].min == -100 and seen[1].max == 100)
			assert(seen[2].min == 50 and seen[2].max == 150)
		end)

		test("uses default constants when no config is given", function()
			local state = panic_impulse.new()
			local triggered
			state, triggered = panic_impulse.update(state, 0.55, function(a, b) return a end, nil)
			assert(triggered == true)
			assert(state.horizontal_force == -120) -- DEFAULT_HORIZONTAL_MIN
		end)
	end)
end
