local player_movement = require "main.core.player_movement"

return function()
	describe("player_movement.speed_multiplier", function()
		test("no change at or below the heavy threshold (1.5)", function()
			assert(player_movement.speed_multiplier(1.5) == 1)
			assert(player_movement.speed_multiplier(1.0) == 1)
			assert(player_movement.speed_multiplier(0.4) == 1)
		end)

		test("matches the PRD's ~35% speed reduction at the nominal Heavy mass", function()
			-- PRD 4.3: Heavy (mass 2.2~2.8) "reduz velocidade máxima do
			-- personagem em ~35%". This used to be 1/mass = 0.40, a 60%
			-- reduction — far harsher than designed.
			assert(math.abs(player_movement.speed_multiplier(2.5) - 0.65) < 0.01)
		end)

		test("mass still matters within the Heavy range", function()
			-- 2.2 and 2.8 must not feel identical, or the mass value is
			-- decoration.
			assert(player_movement.speed_multiplier(2.2) > player_movement.speed_multiplier(2.8))
		end)

		test("never slows the player to a standstill", function()
			-- A floor, not a softlock: an absurd mass is a difficulty spike,
			-- not a player pinned in place.
			assert(player_movement.speed_multiplier(50) >= 0.25)
		end)
	end)

	describe("player_movement.jump_multiplier", function()
		test("no change at or below the heavy threshold", function()
			assert(player_movement.jump_multiplier(1.0) == 1)
			assert(player_movement.jump_multiplier(1.5) == 1)
		end)

		test("matches the PRD's ~30% jump HEIGHT reduction at nominal Heavy mass", function()
			-- The multiplier applies to jump VELOCITY while the PRD's figure
			-- is about HEIGHT, and height scales with velocity squared — so
			-- the check is on the square, not on the multiplier itself.
			local velocity_multiplier = player_movement.jump_multiplier(2.5)
			assert(math.abs(velocity_multiplier * velocity_multiplier - 0.70) < 0.01)
		end)

		test("is gentler than the speed multiplier, as the PRD specifies", function()
			-- 30% height loss vs 35% speed loss. Reusing the speed figure for
			-- jumps (the old behavior) squared it into an 84% height loss and
			-- made Heavy effectively unjumpable.
			assert(player_movement.jump_multiplier(2.5) > player_movement.speed_multiplier(2.5))
		end)
	end)

	describe("player_movement.gravity_multiplier", function()
		test("no change at or above the light threshold (1.0)", function()
			assert(player_movement.gravity_multiplier(1.0) == 1)
			assert(player_movement.gravity_multiplier(2.5) == 1)
		end)

		test("scales by mass below the light threshold", function()
			assert(player_movement.gravity_multiplier(0.4) == 0.4)
			assert(player_movement.gravity_multiplier(0.5) == 0.5)
		end)
	end)

	describe("player_movement.new", function()
		test("starts idle, facing right, grounded", function()
			local state = player_movement.new()
			assert(state.velocity_x == 0)
			assert(state.velocity_y == 0)
			assert(state.facing == 1)
			assert(state.grounded == true)
		end)
	end)

	describe("player_movement.update", function()
		local config = { move_speed = 100, gravity = -1000, jump_velocity = 300 }

		test("moving right sets positive velocity_x and facing", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = 1, jump_pressed = false }, 1 / 60, config)
			assert(state.velocity_x == 100)
			assert(state.facing == 1)
		end)

		test("moving left sets negative velocity_x and facing", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = -1, jump_pressed = false }, 1 / 60, config)
			assert(state.velocity_x == -100)
			assert(state.facing == -1)
		end)

		test("releasing movement zeroes velocity_x but keeps last facing", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = -1, jump_pressed = false }, 1 / 60, config)
			state = player_movement.update(state, { move_x = 0, jump_pressed = false }, 1 / 60, config)
			assert(state.velocity_x == 0)
			assert(state.facing == -1)
		end)

		test("jumping while grounded applies jump_velocity and leaves the ground", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = 0, jump_pressed = true }, 1 / 60, config)
			assert(state.velocity_y == 300)
			assert(state.grounded == false)
		end)

		test("jump is ignored while airborne (no double jump)", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = 0, jump_pressed = true }, 1 / 60, config)
			local airborne_velocity_y = state.velocity_y
			state = player_movement.update(state, { move_x = 0, jump_pressed = true }, 1 / 60, config)
			assert(state.velocity_y < airborne_velocity_y) -- gravity applied, no second jump impulse
		end)

		test("gravity accumulates while airborne", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = 0, jump_pressed = true }, 1 / 60, config)
			local after_jump_velocity_y = state.velocity_y
			state = player_movement.update(state, { move_x = 0, jump_pressed = false }, 1 / 60, config)
			assert(state.velocity_y == after_jump_velocity_y + config.gravity * (1 / 60))
		end)

		test("uses default constants when no config is given", function()
			local state = player_movement.new()
			state = player_movement.update(state, { move_x = 1, jump_pressed = false }, 1 / 60)
			assert(state.velocity_x == 90) -- DEFAULT_MOVE_SPEED
		end)
	end)

	describe("player_movement.set_grounded", function()
		test("landing zeroes velocity_y and marks grounded", function()
			local state = player_movement.new()
			state.velocity_y = -250
			state.grounded = false
			state = player_movement.set_grounded(state, true)
			assert(state.velocity_y == 0)
			assert(state.grounded == true)
		end)

		test("leaving the ground preserves velocity_x and facing", function()
			local state = player_movement.new()
			state.velocity_x = 42
			state.facing = -1
			state = player_movement.set_grounded(state, false)
			assert(state.velocity_x == 42)
			assert(state.facing == -1)
			assert(state.grounded == false)
		end)
	end)

	describe("player_movement.integrate", function()
		test("computes position delta from velocity and dt", function()
			local state = { velocity_x = 100, velocity_y = -50 }
			local delta = player_movement.integrate(state, 0.5)
			assert(delta.dx == 50)
			assert(delta.dy == -25)
		end)
	end)

	describe("player_movement.resting_y_on_ground", function()
		local ground = { x_min = 128, x_max = 256, y_top = 48 }

		test("resting y is the ground's top plus half_height when crossing onto it", function()
			-- falling from y=60 to y=40 this frame, half_height=8: crosses the
			-- resting height of 56
			local resting_y = player_movement.resting_y_on_ground(192, 8, 60, 40, 8, ground)
			assert(resting_y == 56)
		end)

		test("nil when still above the resting height (hasn't reached it yet)", function()
			local resting_y = player_movement.resting_y_on_ground(192, 8, 100, 90, 8, ground)
			assert(resting_y == nil)
		end)

		test("nil when entirely to the right of the ground (ground ends at 256)", function()
			local resting_y = player_movement.resting_y_on_ground(300, 8, 60, 40, 8, ground)
			assert(resting_y == nil)
		end)

		test("nil when entirely to the left of the ground (ground starts at 128)", function()
			local resting_y = player_movement.resting_y_on_ground(50, 8, 60, 40, 8, ground)
			assert(resting_y == nil)
		end)

		test("nil when exactly touching the left edge with zero overlap", function()
			-- player's right edge (120+8=128) exactly meets ground's x_min (128)
			local resting_y = player_movement.resting_y_on_ground(120, 8, 60, 40, 8, ground)
			assert(resting_y == nil)
		end)

		test("nil when exactly touching the right edge with zero overlap", function()
			-- player's left edge (264-8=256) exactly meets ground's x_max (256)
			local resting_y = player_movement.resting_y_on_ground(264, 8, 60, 40, 8, ground)
			assert(resting_y == nil)
		end)

		test("detects a one-pixel overlap at the left edge", function()
			-- player's right edge (121+8=129) is 1px past ground's x_min (128)
			local resting_y = player_movement.resting_y_on_ground(121, 8, 60, 40, 8, ground)
			assert(resting_y == 56)
		end)

		test("detects a one-pixel overlap at the right edge", function()
			-- player's left edge (263-8=255) is 1px before ground's x_max (256)
			local resting_y = player_movement.resting_y_on_ground(263, 8, 60, 40, 8, ground)
			assert(resting_y == 56)
		end)

		test("detects a fast fall that would jump straight past the ground in one frame", function()
			local resting_y = player_movement.resting_y_on_ground(192, 8, 200, -50, 8, ground)
			assert(resting_y == 56)
		end)

		test("nil when moving upward (nothing to land on)", function()
			local resting_y = player_movement.resting_y_on_ground(192, 8, 56, 100, 8, ground)
			assert(resting_y == nil)
		end)

		test("nil when already below the resting height (fell through earlier)", function()
			local resting_y = player_movement.resting_y_on_ground(192, 8, 50, 40, 8, ground)
			assert(resting_y == nil)
		end)

		test("steady state: standing exactly at rest returns the same resting y", function()
			-- pos_y == target_y == resting_y — the most-executed path in the
			-- game (a standing player, every single frame).
			local resting_y = player_movement.resting_y_on_ground(192, 8, 56, 56, 8, ground)
			assert(resting_y == 56)
		end)
	end)

	describe("player_movement.animation_state", function()
		test("idle when grounded and not moving horizontally", function()
			local state = { grounded = true, velocity_x = 0, velocity_y = 0 }
			assert(player_movement.animation_state(state) == "idle")
		end)

		test("run when grounded and moving horizontally", function()
			local state = { grounded = true, velocity_x = 50, velocity_y = 0 }
			assert(player_movement.animation_state(state) == "run")
		end)

		test("jump when airborne and moving upward", function()
			local state = { grounded = false, velocity_x = 0, velocity_y = 200 }
			assert(player_movement.animation_state(state) == "jump")
		end)

		test("fall when airborne and moving downward", function()
			local state = { grounded = false, velocity_x = 0, velocity_y = -50 }
			assert(player_movement.animation_state(state) == "fall")
		end)

		test("with gravity pulling up, a jump goes down", function()
			-- One property decides which way is down. If the jump did not
			-- follow the sign of gravity, an upside-down room would launch
			-- the player into the ceiling they are standing on.
			local state = player_movement.new()
			local up = player_movement.update(state,
				{ move_x = 0, jump_pressed = true }, 1 / 60, { gravity = 900 })
			assert(up.velocity_y < 0)
			local down = player_movement.update(state,
				{ move_x = 0, jump_pressed = true }, 1 / 60, { gravity = -900 })
			assert(down.velocity_y > 0)
		end)

		test("inverted, the player rests under a surface", function()
			-- Falling upward onto the underside: the same crossing check
			-- reflected, which is why there is one implementation and not two.
			local ground = { x_min = 0, x_max = 100, y_top = 100, y_bottom = 80 }
			local resting = player_movement.resting_y_on_ground(
				50, 8, 60, 75, 8, ground, true)
			assert(resting == 72)          -- y_bottom - half_height
			-- And the same call the right way up finds nothing there.
			assert(player_movement.resting_y_on_ground(
				50, 8, 60, 75, 8, ground, false) == nil)
		end)

		test("inverted, rising counts as falling", function()
			-- The animation follows gravity too, or an upside-down player
			-- plays "jump" the whole way down.
			local rising = { velocity_x = 0, velocity_y = 100, facing = 1, grounded = false }
			assert(player_movement.animation_state(rising, false) == "jump")
			assert(player_movement.animation_state(rising, true) == "fall")
		end)
	end)
end
