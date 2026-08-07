local offscreen_timer = require "main.core.offscreen_timer"

return function()
	describe("offscreen_timer.new", function()
		test("starts at zero", function()
			assert(offscreen_timer.new().time_offscreen == 0)
		end)
	end)

	describe("offscreen_timer.update", function()
		test("accumulates while offscreen", function()
			local state = offscreen_timer.new()
			state = offscreen_timer.update(state, true, 0.5)
			assert(math.abs(state.time_offscreen - 0.5) < 1e-9)
		end)

		test("resets to zero as soon as back onscreen", function()
			local state = offscreen_timer.new()
			state = offscreen_timer.update(state, true, 1.5)
			state = offscreen_timer.update(state, false, 0.1)
			assert(state.time_offscreen == 0)
		end)

		test("never dies while onscreen", function()
			local state = offscreen_timer.new()
			local _, died = offscreen_timer.update(state, false, 100)
			assert(died == false)
		end)

		test("does not die before the timeout elapses", function()
			local state = offscreen_timer.new()
			local _, died = offscreen_timer.update(state, true, 1.0, { timeout = 2.0 })
			assert(died == false)
		end)

		test("dies exactly on the frame the timeout is crossed", function()
			local state = offscreen_timer.new()
			local died
			state, died = offscreen_timer.update(state, true, 1.9, { timeout = 2.0 })
			assert(died == false)
			state, died = offscreen_timer.update(state, true, 0.2, { timeout = 2.0 })
			assert(died == true)
		end)

		test("does not die again on frames after the timeout", function()
			-- Regression coverage for the same one-shot bug explosive.lua
			-- had before its `active` fix: without a guard, every
			-- subsequent still-offscreen frame would report died=true again.
			local state = offscreen_timer.new()
			state = offscreen_timer.update(state, true, 5.0, { timeout = 2.0 }) -- dies here
			local _, died_again = offscreen_timer.update(state, true, 0.1, { timeout = 2.0 })
			assert(died_again == false)
		end)

		test("re-arms if it goes back onscreen and then offscreen again", function()
			local state = offscreen_timer.new()
			state = offscreen_timer.update(state, true, 5.0, { timeout = 2.0 }) -- dies here
			state = offscreen_timer.update(state, false, 0.1) -- back onscreen, resets
			local died
			state, died = offscreen_timer.update(state, true, 5.0, { timeout = 2.0 })
			assert(died == true)
		end)

		test("respects a custom timeout", function()
			local state = offscreen_timer.new()
			local _, died = offscreen_timer.update(state, true, 0.6, { timeout = 0.5 })
			assert(died == true)
		end)

		test("uses the default timeout when no config is given", function()
			local state = offscreen_timer.new()
			local died
			state, died = offscreen_timer.update(state, true, 1.9)
			assert(died == false)
			state, died = offscreen_timer.update(state, true, 0.2)
			assert(died == true)
		end)
	end)
end
