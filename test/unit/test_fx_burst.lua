local burst = require "main.core.fx_burst"

return function()
	describe("FX burst progress", function()
		test("runs from 0 to 1 over the duration", function()
			assert(burst.progress(0, 0.4) == 0)
			assert(math.abs(burst.progress(0.2, 0.4) - 0.5) < 1e-9)
			assert(burst.progress(0.4, 0.4) == 1)
		end)

		test("clamps rather than running past the end", function()
			-- The adapter accumulates dt, so it WILL overshoot by up to a
			-- frame; that must read as "finished", not as a scale past the
			-- end of the curve.
			assert(burst.progress(10, 0.4) == 1)
			assert(burst.progress(-1, 0.4) == 0)
		end)

		test("a zero or negative duration is instantly done, not a divide by zero", function()
			assert(burst.progress(0, 0) == 1)
			assert(burst.progress(0, -1) == 1)
			assert(burst.is_done(0, 0))
		end)

		test("is_done only once the whole duration has passed", function()
			assert(burst.is_done(0.39, 0.4) == false)
			assert(burst.is_done(0.4, 0.4) == true)
		end)
	end)

	describe("FX burst scale", function()
		test("starts small and ends at the configured size", function()
			local config = { start_scale = 0.5, end_scale = 2.0 }
			assert(math.abs(burst.scale_at(0, config) - 0.5) < 1e-9)
			assert(math.abs(burst.scale_at(1, config) - 2.0) < 1e-9)
		end)

		test("never shrinks part-way through", function()
			local previous = -1
			for step = 0, 100 do
				local scale = burst.scale_at(step / 100)
				assert(scale >= previous)
				previous = scale
			end
		end)

		test("decelerates: more growth happens in the first half than the second", function()
			-- This is what makes it read as an impact rather than as
			-- something being inflated at a constant rate.
			local first = burst.scale_at(0.5) - burst.scale_at(0)
			local second = burst.scale_at(1) - burst.scale_at(0.5)
			assert(first > second)
		end)
	end)

	describe("FX burst alpha", function()
		test("holds fully opaque at the start so the burst registers", function()
			assert(burst.alpha_at(0) == 1)
			assert(burst.alpha_at(0.2) == 1)
		end)

		test("reaches zero exactly at the end", function()
			assert(math.abs(burst.alpha_at(1)) < 1e-9)
		end)

		test("never rises once it has begun falling", function()
			local previous = 2
			for step = 0, 100 do
				local alpha = burst.alpha_at(step / 100)
				assert(alpha <= previous + 1e-9)
				previous = alpha
			end
		end)

		test("stays within 0..1 across the whole life", function()
			for step = 0, 100 do
				local alpha = burst.alpha_at(step / 100)
				assert(alpha >= -1e-9 and alpha <= 1 + 1e-9)
			end
		end)
	end)
end
