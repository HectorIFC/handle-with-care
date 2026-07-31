local package_physics = require "main.core.package_physics"

return function()
	describe("package_physics.new", function()
		test("starts at the given position with zero velocity", function()
			local state = package_physics.new(10, 20)
			assert(state.position_x == 10)
			assert(state.position_y == 20)
			assert(state.velocity_x == 0)
			assert(state.velocity_y == 0)
		end)
	end)

	describe("package_physics.update (Stable state: no shake, no forces)", function()
		local config = { offset_x = 8, offset_y = 12, lerp_factor = 0.5, velocity_damping = 0.85 }
		local stable = { shake_intensity = 0, horizontal_force = 0, vertical_force = 0 }

		test("lerps toward the player position plus offset, facing right", function()
			local state = package_physics.new(0, 0)
			local player = { x = 100, y = 50, facing = 1 }
			state = package_physics.update(state, player, stable, 0, config)
			-- target = (108, 62); lerp 0.5 from (0,0) -> (54, 31)
			assert(state.position_x == 54)
			assert(state.position_y == 31)
		end)

		test("offset flips to the other side when facing left", function()
			local state = package_physics.new(0, 0)
			local player = { x = 100, y = 50, facing = -1 }
			state = package_physics.update(state, player, stable, 0, config)
			-- target = (92, 62); lerp 0.5 from (0,0) -> (46, 31)
			assert(state.position_x == 46)
			assert(state.position_y == 31)
		end)

		test("converges toward the target over repeated updates", function()
			local state = package_physics.new(0, 0)
			local player = { x = 100, y = 50, facing = 1 }
			for _ = 1, 50 do
				state = package_physics.update(state, player, stable, 0, config)
			end
			assert(math.abs(state.position_x - 108) < 0.01)
			assert(math.abs(state.position_y - 62) < 0.01)
		end)

		test("uses default constants when no config is given", function()
			local state = package_physics.new(0, 0)
			local player = { x = 0, y = 0, facing = 1 }
			state = package_physics.update(state, player, stable, 0)
			-- default offset (8, 12), default lerp_factor 0.35: target (8,12) -> (2.8, 4.2)
			assert(math.abs(state.position_x - 2.8) < 1e-9)
			assert(math.abs(state.position_y - 4.2) < 1e-9)
		end)

		test("nil package_state behaves like the Stable state (no shake/forces)", function()
			local state = package_physics.new(0, 0)
			local player = { x = 100, y = 50, facing = 1 }
			state = package_physics.update(state, player, nil, 0, config)
			assert(state.position_x == 54)
			assert(state.position_y == 31)
		end)
	end)

	describe("package_physics.update (shake)", function()
		local config = { offset_x = 0, offset_y = 0, lerp_factor = 1, velocity_damping = 0.85 }
		local player = { x = 0, y = 0, facing = 1 }

		test("zero shake_intensity contributes nothing regardless of time", function()
			local state = package_physics.new(0, 0)
			local shaking = { shake_intensity = 0, horizontal_force = 0, vertical_force = 0 }
			state = package_physics.update(state, player, shaking, 1.2345, config)
			assert(state.position_x == 0)
			assert(state.position_y == 0)
		end)

		test("non-zero shake_intensity offsets position by a deterministic sinusoid", function()
			local state = package_physics.new(0, 0)
			local shaking = { shake_intensity = 1, horizontal_force = 0, vertical_force = 0 }
			local time = 0.1
			state = package_physics.update(state, player, shaking, time, config)
			-- lerp_factor=1, so position lands exactly on the shake-only target
			local expected_x = math.sin(time * 40) * 1 * 2
			local expected_y = math.cos(time * 35) * 1 * 1.5
			assert(math.abs(state.position_x - expected_x) < 1e-9)
			assert(math.abs(state.position_y - expected_y) < 1e-9)
		end)

		test("shake scales linearly with shake_intensity", function()
			local half_state = package_physics.new(0, 0)
			local full_state = package_physics.new(0, 0)
			local half = { shake_intensity = 0.5, horizontal_force = 0, vertical_force = 0 }
			local full = { shake_intensity = 1.0, horizontal_force = 0, vertical_force = 0 }
			half_state = package_physics.update(half_state, player, half, 0.1, config)
			full_state = package_physics.update(full_state, player, full, 0.1, config)
			assert(math.abs(half_state.position_x * 2 - full_state.position_x) < 1e-9)
		end)

		test("shake is added to the target before smoothing, not to the position after", function()
			-- lerp_factor=1 elsewhere in this suite makes "lerp first, add
			-- shake after" and "add shake to the target, then lerp"
			-- indistinguishable. Use a partial lerp and a non-zero start
			-- position so the order of operations actually matters.
			local config_partial = { offset_x = 0, offset_y = 0, lerp_factor = 0.5, velocity_damping = 0.85 }
			local state = package_physics.new(10, 10)
			local shaking = { shake_intensity = 1, horizontal_force = 0, vertical_force = 0 }
			local time = 0.1
			state = package_physics.update(state, player, shaking, time, config_partial)
			local shake_x = math.sin(time * 40) * 1 * 2
			local shake_y = math.cos(time * 35) * 1 * 1.5
			local expected_x = 10 + ((0 + shake_x) - 10) * 0.5
			local expected_y = 10 + ((0 + shake_y) - 10) * 0.5
			assert(math.abs(state.position_x - expected_x) < 1e-9)
			assert(math.abs(state.position_y - expected_y) < 1e-9)
		end)
	end)

	describe("package_physics.update (residual forces)", function()
		local config = { offset_x = 0, offset_y = 0, lerp_factor = 1, velocity_damping = 0.85 }
		local player = { x = 0, y = 0, facing = 1 }

		test("a constant force accumulates into velocity and moves the package", function()
			local state = package_physics.new(0, 0)
			local panicking = { shake_intensity = 0, horizontal_force = 100, vertical_force = 0 }
			state = package_physics.update(state, player, panicking, 0, config)
			-- velocity_x = 0*0.85 + 100 = 100; lerp_factor=1 -> position lands on target (0+100)
			assert(state.velocity_x == 100)
			assert(state.position_x == 100)
		end)

		test("velocity decays by velocity_damping once the force stops", function()
			local state = package_physics.new(0, 0)
			local impulse = { shake_intensity = 0, horizontal_force = 100, vertical_force = 0 }
			state = package_physics.update(state, player, impulse, 0, config)
			local no_force = { shake_intensity = 0, horizontal_force = 0, vertical_force = 0 }
			state = package_physics.update(state, player, no_force, 0, config)
			assert(math.abs(state.velocity_x - 100 * 0.85) < 1e-9)
		end)

		test("a constant vertical force accumulates into velocity_y and moves the package", function()
			local state = package_physics.new(0, 0)
			local panicking = { shake_intensity = 0, horizontal_force = 0, vertical_force = 150 }
			state = package_physics.update(state, player, panicking, 0, config)
			assert(state.velocity_y == 150)
			assert(state.position_y == 150)
		end)

		test("velocity_y decays by velocity_damping once the vertical force stops", function()
			local state = package_physics.new(0, 0)
			local impulse = { shake_intensity = 0, horizontal_force = 0, vertical_force = 150 }
			state = package_physics.update(state, player, impulse, 0, config)
			local no_force = { shake_intensity = 0, horizontal_force = 0, vertical_force = 0 }
			state = package_physics.update(state, player, no_force, 0, config)
			assert(math.abs(state.velocity_y - 150 * 0.85) < 1e-9)
		end)

		test("residual velocity is added to the target before smoothing, not to the position after", function()
			local config_partial = { offset_x = 0, offset_y = 0, lerp_factor = 0.5, velocity_damping = 0.85 }
			local state = package_physics.new(10, 10)
			local impulse = { shake_intensity = 0, horizontal_force = 100, vertical_force = 150 }
			state = package_physics.update(state, player, impulse, 0, config_partial)
			-- velocity_x=100, velocity_y=150; target = (0+100, 0+150); lerp 0.5 from (10,10)
			local expected_x = 10 + (100 - 10) * 0.5
			local expected_y = 10 + (150 - 10) * 0.5
			assert(math.abs(state.position_x - expected_x) < 1e-9)
			assert(math.abs(state.position_y - expected_y) < 1e-9)
		end)
	end)
end
