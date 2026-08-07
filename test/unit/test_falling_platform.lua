local falling_platform = require "main.core.falling_platform"

return function()
	describe("falling_platform.new", function()
		test("starts idle, not falling", function()
			local state = falling_platform.new()
			assert(state.time_standing == 0)
			assert(state.falling == false)
		end)
	end)

	describe("falling_platform.update", function()
		test("accumulates time_standing while stood on", function()
			local state = falling_platform.new()
			state = falling_platform.update(state, true, 0.3, { fall_delay = 1.0 })
			assert(math.abs(state.time_standing - 0.3) < 1e-9)
			assert(state.falling == false)
		end)

		test("resets time_standing as soon as no longer stood on", function()
			local state = falling_platform.new()
			state = falling_platform.update(state, true, 0.8, { fall_delay = 1.0 })
			state = falling_platform.update(state, false, 0.1, { fall_delay = 1.0 })
			assert(state.time_standing == 0)
			assert(state.falling == false)
		end)

		test("does not fall before fall_delay elapses", function()
			local state = falling_platform.new()
			local _, just_started = falling_platform.update(state, true, 0.5, { fall_delay = 1.0 })
			assert(just_started == false)
		end)

		test("starts falling exactly on the frame fall_delay is crossed", function()
			local state = falling_platform.new()
			local just_started
			state, just_started = falling_platform.update(state, true, 0.9, { fall_delay = 1.0 })
			assert(just_started == false)
			state, just_started = falling_platform.update(state, true, 0.2, { fall_delay = 1.0 })
			assert(just_started == true)
			assert(state.falling == true)
		end)

		test("does not report just_started_falling again on later frames", function()
			local state = falling_platform.new()
			state = falling_platform.update(state, true, 5.0, { fall_delay = 1.0 }) -- starts falling here
			local _, just_started_again = falling_platform.update(state, true, 0.1, { fall_delay = 1.0 })
			assert(just_started_again == false)
		end)

		test("stepping off mid-fall does not stop or reset the fall", function()
			local state = falling_platform.new()
			state = falling_platform.update(state, true, 5.0, { fall_delay = 1.0 }) -- starts falling here
			state = falling_platform.update(state, false, 1.0, { fall_delay = 1.0 })
			assert(state.falling == true)
		end)

		test("respects a custom fall_delay", function()
			local state = falling_platform.new()
			local _, just_started = falling_platform.update(state, true, 0.6, { fall_delay = 0.5 })
			assert(just_started == true)
		end)

		test("uses the default fall_delay when no config is given", function()
			local state = falling_platform.new()
			local just_started
			state, just_started = falling_platform.update(state, true, 0.9)
			assert(just_started == false)
			state, just_started = falling_platform.update(state, true, 0.2)
			assert(just_started == true)
		end)
	end)
end
