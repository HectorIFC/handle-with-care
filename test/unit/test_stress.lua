local stress = require "main.core.stress"

return function()
	describe("stress.new", function()
		test("starts at zero", function()
			assert(stress.new().value == 0)
		end)
	end)

	describe("stress.apply_jump", function()
		test("adds the default amount", function()
			local state = stress.apply_jump(stress.new())
			assert(state.value == 6)
		end)

		test("respects a custom config amount", function()
			local state = stress.apply_jump(stress.new(), { stress_jump = 10 })
			assert(state.value == 10)
		end)
	end)

	describe("stress.apply_heavy_landing", function()
		test("adds the default amount", function()
			local state = stress.apply_heavy_landing(stress.new())
			assert(state.value == 18)
		end)
	end)

	describe("stress.apply_direction_change", function()
		test("adds the default amount", function()
			local state = stress.apply_direction_change(stress.new())
			assert(state.value == 8)
		end)
	end)

	describe("stress.apply_panic", function()
		test("scales with dt at the default per-second rate", function()
			local state = stress.apply_panic(stress.new(), 0.5)
			assert(math.abs(state.value - 7) < 1e-9) -- 14/sec * 0.5s
		end)
	end)

	describe("stress.decay_safe", function()
		test("decreases stress scaled by dt", function()
			local state = { value = 50 }
			state = stress.decay_safe(state, 1)
			assert(state.value == 44) -- 50 - 6/sec * 1s
		end)
	end)

	describe("stress.set", function()
		test("builds a state at the given value", function()
			assert(stress.set(42).value == 42)
		end)

		test("clamps a value above 100", function()
			assert(stress.set(500).value == 100)
		end)

		test("clamps a value below 0", function()
			assert(stress.set(-10).value == 0)
		end)
	end)

	describe("stress clamping (0..100)", function()
		test("never exceeds 100 no matter how much is added", function()
			local state = { value = 98 }
			state = stress.apply_heavy_landing(state)
			assert(state.value == 100)
		end)

		test("never drops below 0 no matter how much decays", function()
			local state = { value = 3 }
			state = stress.decay_safe(state, 10)
			assert(state.value == 0)
		end)

		test("stays exactly at 100 when already saturated and adding more", function()
			local state = { value = 100 }
			state = stress.apply_jump(state)
			assert(state.value == 100)
		end)

		test("stays exactly at 0 when already empty and decaying further", function()
			local state = { value = 0 }
			state = stress.decay_safe(state, 1)
			assert(state.value == 0)
		end)
	end)
end
