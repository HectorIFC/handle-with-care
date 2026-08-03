local explosive = require "main.core.explosive"

return function()
	describe("explosive.new", function()
		test("starts idle", function()
			assert(explosive.new().timer == 0)
			assert(explosive.new().active == false)
		end)
	end)

	describe("explosive.start", function()
		test("sets the timer to the default explosive_time", function()
			assert(explosive.start().timer == 1.5)
		end)

		test("respects a custom explosive_time", function()
			assert(explosive.start({ explosive_time = 2.0 }).timer == 2.0)
		end)

		test("marks the timer active", function()
			assert(explosive.start().active == true)
		end)
	end)

	describe("explosive.update", function()
		test("counts the timer down by dt", function()
			local state = explosive.start({ explosive_time = 1.0 })
			state = explosive.update(state, 0.4)
			assert(math.abs(state.timer - 0.6) < 1e-9)
		end)

		test("does not detonate while time remains", function()
			local state = explosive.start({ explosive_time = 1.0 })
			local _, detonated = explosive.update(state, 0.4)
			assert(detonated == false)
		end)

		test("detonates exactly on the frame the timer crosses zero", function()
			local state = explosive.start({ explosive_time = 1.0 })
			local detonated
			state, detonated = explosive.update(state, 0.6)
			assert(detonated == false)
			state, detonated = explosive.update(state, 0.4)
			assert(detonated == true)
			assert(state.timer == 0)
		end)

		test("detonates in one shot when dt overshoots the remaining time", function()
			local state = explosive.start({ explosive_time = 1.0 })
			local _, detonated = explosive.update(state, 5.0)
			assert(detonated == true)
		end)

		test("does not detonate again on frames after detonation", function()
			local state = explosive.start({ explosive_time = 1.0 })
			state = explosive.update(state, 5.0) -- detonates here
			local _, detonated_again = explosive.update(state, 0.1)
			assert(detonated_again == false)
		end)

		test("an idle (never-started) timer never detonates", function()
			local state = explosive.new()
			local _, detonated = explosive.update(state, 1.0)
			assert(detonated == false)
		end)

		test("clears active on detonation", function()
			local state = explosive.start({ explosive_time = 1.0 })
			state = explosive.update(state, 5.0)
			assert(state.active == false)
		end)

		test("an explosive_time of zero detonates immediately, not never", function()
			-- Regression test: update() used to treat timer <= 0 as "idle,
			-- never started", which is indistinguishable from a genuine
			-- zero-length fuse — the package would re-arm every frame
			-- without ever reporting detonated. active is what makes the
			-- two cases distinguishable.
			local state = explosive.start({ explosive_time = 0 })
			local _, detonated = explosive.update(state, 0.016)
			assert(detonated == true)
		end)
	end)

	describe("explosive.progress", function()
		test("zero right after starting", function()
			local state = explosive.start({ explosive_time = 1.0 })
			assert(explosive.progress(state, { explosive_time = 1.0 }) == 0)
		end)

		test("0.5 halfway through", function()
			local config = { explosive_time = 1.0 }
			local state = explosive.start(config)
			state = explosive.update(state, 0.5)
			assert(math.abs(explosive.progress(state, config) - 0.5) < 1e-9)
		end)

		test("clamped to 1 once detonated", function()
			local config = { explosive_time = 1.0 }
			local state = explosive.start(config)
			state = explosive.update(state, 5.0)
			assert(explosive.progress(state, config) == 1)
		end)

		test("uses the default explosive_time when no config is given", function()
			local state = explosive.start()
			assert(explosive.progress(state) == 0)
		end)
	end)
end
