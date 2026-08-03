local knockback = require "main.core.knockback"

return function()
	describe("knockback.new", function()
		test("starts at zero velocity", function()
			local state = knockback.new()
			assert(state.velocity_x == 0)
			assert(state.velocity_y == 0)
		end)
	end)

	describe("knockback.apply", function()
		test("adds the given force to the current velocity", function()
			local state = knockback.new()
			state = knockback.apply(state, 10, -5)
			assert(state.velocity_x == 10)
			assert(state.velocity_y == -5)
		end)

		test("accumulates across repeated applications", function()
			local state = knockback.new()
			state = knockback.apply(state, 10, 20)
			state = knockback.apply(state, 5, -30)
			assert(state.velocity_x == 15)
			assert(state.velocity_y == -10)
		end)
	end)

	describe("knockback.decay", function()
		test("scales velocity by the default damping", function()
			local state = { velocity_x = 100, velocity_y = -200 }
			state = knockback.decay(state)
			assert(math.abs(state.velocity_x - 85) < 1e-9) -- 100 * 0.85
			assert(math.abs(state.velocity_y - (-170)) < 1e-9) -- -200 * 0.85
		end)

		test("respects a custom damping factor", function()
			local state = { velocity_x = 100, velocity_y = 0 }
			state = knockback.decay(state, { damping = 0.5 })
			assert(state.velocity_x == 50)
		end)

		test("converges to zero over repeated decay", function()
			-- 100 * 0.85^n only drops below 1e-6 around n=200 (0.85^100 is
			-- still ~8.8e-6) — use enough iterations to actually clear the
			-- tolerance instead of tightening the tolerance to match one
			-- specific iteration count.
			local state = { velocity_x = 100, velocity_y = 100 }
			for _ = 1, 200 do
				state = knockback.decay(state)
			end
			assert(math.abs(state.velocity_x) < 1e-6)
			assert(math.abs(state.velocity_y) < 1e-6)
		end)
	end)
end
