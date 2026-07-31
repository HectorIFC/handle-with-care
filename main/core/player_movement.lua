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
		velocity_y = jump_velocity
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
function M.resting_y_on_ground(pos_x, half_width, pos_y, target_y, half_height, ground)
	local player_min_x = pos_x - half_width
	local player_max_x = pos_x + half_width
	if player_max_x <= ground.x_min or player_min_x >= ground.x_max then
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
function M.animation_state(state)
	if not state.grounded then
		if state.velocity_y > 0 then
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
