-- Pure package physics: offset + shake + residual forces + lerp smoothing,
-- following PRD section 4.3 exactly. No Defold API calls here — see
-- main/package/package.script for the adapter that reads the player's
-- position/facing synchronously (never via message — go.get_position, not
-- msg.post, see CLAUDE.md rule 4) and applies the result.
--
-- Phase 2 only wired up the Stable state (shake_intensity/forces always 0);
-- phase 4 added `offset_y_bonus` for Heavy/Light's vertical offset (PRD
-- 4.3's "Offset vertical extra"). Later phases drive non-zero shake/force/
-- offset values through `package_state` without needing to change this
-- formula.
--
-- `lerp_factor`/`velocity_damping` are applied per simulation frame, exactly
-- as PRD 4.3's pseudocode specifies (no dt scaling) — this project locks
-- the simulation to 60Hz via game.project's `display.update_frequency`
-- precisely so these per-frame constants behave the same on every machine.
-- If that assumption ever changes, every per-frame constant in this
-- project (not just here) needs revisiting, not just this module.

local M = {}

local DEFAULT_OFFSET_X = 8
local DEFAULT_OFFSET_Y = 12
local DEFAULT_LERP_FACTOR = 0.35
local DEFAULT_VELOCITY_DAMPING = 0.85
local SHAKE_X_FREQUENCY = 40
local SHAKE_Y_FREQUENCY = 35
local SHAKE_X_AMPLITUDE = 2
local SHAKE_Y_AMPLITUDE = 1.5

local function lerp(a, b, t)
	return a + (b - a) * t
end

function M.new(x, y)
	return {
		position_x = x,
		position_y = y,
		velocity_x = 0,
		velocity_y = 0,
	}
end

-- state: { position_x, position_y, velocity_x, velocity_y }
-- player: { x, y, facing } — facing is 1 (right) or -1 (left)
-- package_state: { shake_intensity, horizontal_force, vertical_force,
--   offset_y_bonus } — all default to 0 (the Stable state); phase 3+ states
--   populate these
-- time: accumulated elapsed seconds, used for the shake's sine/cosine phase
--   (injected by the adapter — never read from a clock directly, rule 3)
-- config: { offset_x, offset_y, lerp_factor, velocity_damping } (all optional)
function M.update(state, player, package_state, time, config)
	config = config or {}
	package_state = package_state or {}
	local offset_x = config.offset_x or DEFAULT_OFFSET_X
	local offset_y = config.offset_y or DEFAULT_OFFSET_Y
	local lerp_factor = config.lerp_factor or DEFAULT_LERP_FACTOR
	local velocity_damping = config.velocity_damping or DEFAULT_VELOCITY_DAMPING
	local shake_intensity = package_state.shake_intensity or 0
	local horizontal_force = package_state.horizontal_force or 0
	local vertical_force = package_state.vertical_force or 0
	local offset_y_bonus = package_state.offset_y_bonus or 0

	local target_x = player.x + offset_x * player.facing
	local target_y = player.y + offset_y + offset_y_bonus

	target_x = target_x + math.sin(time * SHAKE_X_FREQUENCY) * shake_intensity * SHAKE_X_AMPLITUDE
	target_y = target_y + math.cos(time * SHAKE_Y_FREQUENCY) * shake_intensity * SHAKE_Y_AMPLITUDE

	local velocity_x = state.velocity_x * velocity_damping + horizontal_force
	local velocity_y = state.velocity_y * velocity_damping + vertical_force

	target_x = target_x + velocity_x
	target_y = target_y + velocity_y

	return {
		position_x = lerp(state.position_x, target_x, lerp_factor),
		position_y = lerp(state.position_y, target_y, lerp_factor),
		velocity_x = velocity_x,
		velocity_y = velocity_y,
	}
end

return M
