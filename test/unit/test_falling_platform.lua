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

		test("an untouched platform does not wobble", function()
			assert(falling_platform.wobble_offset(falling_platform.new()) == 0)
		end)

		test("a platform that has let go does not wobble", function()
			-- Once it is falling it has nothing left to warn about, and a
			-- shudder on the way down would read as the drop being unstable
			-- rather than as a warning.
			local state = { time_standing = 5, falling = true }
			assert(falling_platform.wobble_offset(state) == 0)
		end)

		test("the wobble grows as the platform runs out of patience", function()
			-- The whole point: the shake says "liar" immediately and "soon"
			-- as the timer runs down. Sampled at matching points of the sine
			-- so the comparison is about amplitude, not about phase — the
			-- frequency is chosen to make one full period fit fall_delay.
			local config = { fall_delay = 1.0, wobble_frequency = 2 * math.pi,
				wobble_amplitude = 4 }
			local early = falling_platform.wobble_offset(
				{ time_standing = 0.25, falling = false }, config)
			local late = falling_platform.wobble_offset(
				{ time_standing = 1.25, falling = false }, config)
			assert(early > 0 and late > 0)
			assert(late > early)
		end)

		test("the wobble never exceeds its amplitude", function()
			-- Including past fall_delay, which a slow frame can overshoot:
			-- urgency is clamped, so a dropped frame cannot fling the
			-- platform sideways out from under the player.
			local config = { fall_delay = 0.5, wobble_amplitude = 3 }
			for step = 0, 200 do
				local offset = falling_platform.wobble_offset(
					{ time_standing = step * 0.02, falling = false }, config)
				assert(offset <= 3.0001 and offset >= -3.0001)
			end
		end)

		test("the wobble goes both ways", function()
			-- Left AND right, not a one-sided lurch, which would drag the
			-- standable surface off its authored position.
			local config = { fall_delay = 10, wobble_frequency = 16,
				wobble_amplitude = 2 }
			local saw_left, saw_right = false, false
			for step = 1, 200 do
				local offset = falling_platform.wobble_offset(
					{ time_standing = step * 0.01, falling = false }, config)
				if offset < -0.01 then saw_left = true end
				if offset > 0.01 then saw_right = true end
			end
			assert(saw_left and saw_right)
		end)
	end)
end
