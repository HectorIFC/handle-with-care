-- Pure movement logic for the player character. No Defold API calls here —
-- see main/player/player.script for the engine adapter that owns state,
-- reads input/collision, and applies position/animation back to the engine.

local M = {}

local DEFAULT_MOVE_SPEED = 90 -- px/s
local DEFAULT_GRAVITY = -900 -- px/s^2
local DEFAULT_JUMP_VELOCITY = 320 -- px/s
local DEFAULT_GROUNDED_NORMAL_Y_THRESHOLD = 0.7

-- Tolerance for the "was at/above the resting height" crossing check below.
-- `pos_y` arrives from a float32 engine position round-trip (go.set_position
-- writes a Lua double, go.get_position reads it back as float32) while
-- `resting_y` is computed in Lua doubles — without this slack, a resting_y
-- that isn't exactly float32-representable would read back a hair below
-- itself and permanently fail the `pos_y >= resting_y` check every frame.
local RESTING_EPSILON = 0.01

-- PRD 4.6: "quando mass > 1.5 -> multiplica velocidade e força de pulo do
-- personagem por 1/mass". Applies to Heavy (mass 2.2..2.8) — a heavier
-- package drags the player down to as little as ~36% of normal speed/jump.
local HEAVY_MASS_THRESHOLD = 1.5

-- Light isn't covered by 4.6's formula (it only fires above 1.5), and the
-- PRD's own wording for Light is qualitative ("controles ficam
-- escorregadios", "resposta mais atrasada e flutuante") rather than a
-- numeric rule. This project's chosen interpretation: Light doesn't slow
-- the player down, it makes falls floatier by scaling gravity by the
-- mass fraction itself (mass 0.35..0.5 -> 35%..50% of normal gravity) —
-- distinct from Heavy's effect, but built from the same "mass" input, and
-- revisitable during phase 22's playtest pass if it doesn't feel right.
local LIGHT_MASS_THRESHOLD = 1.0

-- Multiplier applied to move_speed and jump_velocity for the package's
-- current mass (see PRD 4.6). 1.0 (no change) below the Heavy threshold.
-- PRD 4.3 calibration for Heavy (mass 2.2~2.8, nominal 2.5): "Reduz
-- velocidade máxima do personagem em ~35%" and "Reduz altura do pulo em
-- ~30%". Expressed as a penalty per unit of excess mass so the mass value
-- still means something (2.2 and 2.8 must not feel identical), calibrated
-- to land exactly on the PRD's figures at 2.5: 1.5 excess x 0.2333 = 0.35
-- speed, 1.5 x 0.2 = 0.30 height.
--
-- These used to be a single `1 / mass` applied to BOTH speed and jump
-- velocity, which was far harsher than designed: at mass 2.5 that is 0.4
-- speed (60% slower, not 35%) and — because jump height scales with the
-- SQUARE of launch velocity — 0.16 height, an 84% reduction rather than
-- 30%. Heavy was effectively unjumpable, which only became visible when
-- level 3 needed to stay playable during a Heavy cycle.
local HEAVY_SPEED_PENALTY_PER_MASS = 0.2333
local HEAVY_JUMP_HEIGHT_PENALTY_PER_MASS = 0.2
-- Floors, so an absurd mass slows the player down without ever pinning
-- them in place (which would be a softlock, not a difficulty spike).
local MIN_SPEED_MULTIPLIER = 0.25
local MIN_JUMP_HEIGHT_MULTIPLIER = 0.25

function M.speed_multiplier(mass)
	if mass > HEAVY_MASS_THRESHOLD then
		local multiplier = 1 - (mass - 1) * HEAVY_SPEED_PENALTY_PER_MASS
		return math.max(multiplier, MIN_SPEED_MULTIPLIER)
	end
	return 1
end

-- Applied to jump VELOCITY, while the PRD's figure is about jump HEIGHT —
-- hence the square root: height scales with velocity squared, so a 30%
-- lower jump needs velocity x sqrt(0.7), not x 0.7.
function M.jump_multiplier(mass)
	if mass > HEAVY_MASS_THRESHOLD then
		local height = 1 - (mass - 1) * HEAVY_JUMP_HEIGHT_PENALTY_PER_MASS
		return math.sqrt(math.max(height, MIN_JUMP_HEIGHT_MULTIPLIER))
	end
	return 1
end

-- Multiplier applied to gravity for the package's current mass (Light
-- floatiness — this project's interpretation, see above). 1.0 (no change)
-- above the Light threshold.
function M.gravity_multiplier(mass)
	if mass < LIGHT_MASS_THRESHOLD then
		return mass
	end
	return 1
end

function M.new()
	return {
		velocity_x = 0,
		velocity_y = 0,
		facing = 1,
		grounded = true,
	}
end

-- input: { move_x = -1|0|1, jump_pressed = boolean }
-- config: { move_speed, gravity, jump_velocity } (all optional, see defaults above)
function M.update(state, input, dt, config)
	config = config or {}
	local move_speed = config.move_speed or DEFAULT_MOVE_SPEED
	local gravity = config.gravity or DEFAULT_GRAVITY
	local jump_velocity = config.jump_velocity or DEFAULT_JUMP_VELOCITY

	local facing = state.facing
	if input.move_x ~= 0 then
		facing = input.move_x > 0 and 1 or -1
	end

	local velocity_y = state.velocity_y
	local grounded = state.grounded
	if input.jump_pressed and state.grounded then
		-- A jump opposes gravity, whichever way gravity points. Derived from
		-- the sign of `gravity` rather than from a separate `inverted` flag,
		-- so there is exactly one thing to set to turn a room upside down
		-- and the two can never disagree.
		velocity_y = gravity > 0 and -jump_velocity or jump_velocity
		grounded = false
	elseif not state.grounded then
		velocity_y = state.velocity_y + gravity * dt
	end

	return {
		velocity_x = move_speed * input.move_x,
		velocity_y = velocity_y,
		facing = facing,
		grounded = grounded,
	}
end

-- Called by the adapter once per frame with this frame's ground-contact
-- result (see resting_y_on_ground). Landing zeroes vertical velocity;
-- leaving the ground (walking off an edge) leaves velocity_x/facing as-is.
function M.set_grounded(state, grounded)
	return {
		velocity_x = state.velocity_x,
		velocity_y = grounded and 0 or state.velocity_y,
		facing = state.facing,
		grounded = grounded,
	}
end

-- Position delta for this frame, given the current velocity. Kept separate
-- from `update` so both can be unit tested independently of each other.
function M.integrate(state, dt)
	return {
		dx = state.velocity_x * dt,
		dy = state.velocity_y * dt,
	}
end

-- Ground detection via plain AABB overlap, computed entirely in Lua rather
-- than through the engine's physics queries. `physics.raycast` and
-- `contact_point_response` were confirmed (by an isolated, from-scratch
-- reproduction — see CLAUDE.md) to never report a hit under this project's
-- headless test environment, on this platform, regardless of shape/group/
-- body type. Manual geometric ground checks sidestep that limitation
-- entirely and match this project's existing "manually simulated physics"
-- approach (see the PRD's package physics).
--
-- `ground` is a rectangle: { x_min, x_max, y_top }. Returns the Y the
-- player's center should rest at if the player (centered at `pos_x`, with
-- the given half_width, moving from `pos_y` to `target_y` this frame)
-- horizontally overlaps the ground AND would cross onto it this frame.
-- Returns nil otherwise (no horizontal overlap, or still above/already
-- below the surface).
--
-- `inverted` flips which FACE of the surface is standable. With gravity
-- pulling up, the player falls upward and comes to rest under a surface, on
-- `y_bottom`, having crossed it from below. The check is the same one
-- reflected, not a second implementation: everything about the geometry is
-- symmetric, and writing it twice is how the two halves drift apart.
function M.resting_y_on_ground(pos_x, half_width, pos_y, target_y, half_height,
	ground, inverted)
	local player_min_x = pos_x - half_width
	local player_max_x = pos_x + half_width
	if player_max_x <= ground.x_min or player_min_x >= ground.x_max then
		return nil
	end

	if inverted then
		local resting_y = (ground.y_bottom or ground.y_top) - half_height
		if pos_y <= resting_y + RESTING_EPSILON and target_y >= resting_y then
			return resting_y
		end
		return nil
	end

	local resting_y = ground.y_top + half_height
	if pos_y >= resting_y - RESTING_EPSILON and target_y <= resting_y then
		return resting_y
	end
	return nil
end

-- Derives the animation to display from the physics state. "land" is a
-- one-shot adapter-side trigger on the grounded false->true transition, not
-- modeled here — see player.script.
function M.animation_state(state, inverted)
	if not state.grounded then
		local rising = inverted and state.velocity_y < 0 or
			(not inverted and state.velocity_y > 0)
		if rising then
			return "jump"
		else
			return "fall"
		end
	elseif state.velocity_x ~= 0 then
		return "run"
	else
		return "idle"
	end
end

return M
