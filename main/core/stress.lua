-- Package stress system (PRD sections 4.5/4.8). Stress ranges 0..100 and
-- drives package_state_machine's Stable/Nervous/Panic/Explosive ladder. No
-- Defold API calls here — see main/package/package.script for the adapter
-- that decides which events happened this frame and calls these functions.
--
-- Scope note: PRD 4.5 groups "pulo alto" and "aterrissagem forte" into one
-- bullet, and separately lists "queda de altura média/alta" — this module
-- covers both with a single apply_heavy_landing, since impact velocity at
-- landing is a fair proxy for fall severity regardless of whether a jump
-- preceded it. "Perto de spike/serra" (near a hazard) isn't wired until
-- phase 9a adds hazards to react to.

local M = {}

local STRESS_MIN = 0
local STRESS_MAX = 100

local DEFAULT_STRESS_JUMP = 6
local DEFAULT_STRESS_HEAVY_LANDING = 18
local DEFAULT_STRESS_DIRECTION_CHANGE = 8
local DEFAULT_STRESS_PANIC_PER_SEC = 14
local DEFAULT_STRESS_DECAY_SAFE_PER_SEC = 6

local function clamp(value, min_value, max_value)
	if value < min_value then
		return min_value
	elseif value > max_value then
		return max_value
	end
	return value
end

local function apply(state, delta)
	return { value = clamp(state.value + delta, STRESS_MIN, STRESS_MAX) }
end

function M.new()
	return { value = 0 }
end

-- Builds a state at an explicit value, clamped the same way every other
-- mutation is — used by package.script's debug_set_stress hook so a manual
-- override can't produce a state no real gameplay path could ever reach.
function M.set(value)
	return { value = clamp(value, STRESS_MIN, STRESS_MAX) }
end

function M.apply_jump(state, config)
	config = config or {}
	return apply(state, config.stress_jump or DEFAULT_STRESS_JUMP)
end

function M.apply_heavy_landing(state, config)
	config = config or {}
	return apply(state, config.stress_heavy_landing or DEFAULT_STRESS_HEAVY_LANDING)
end

function M.apply_direction_change(state, config)
	config = config or {}
	return apply(state, config.stress_direction_change or DEFAULT_STRESS_DIRECTION_CHANGE)
end

-- Per-second accumulation while the package is in the Panic state.
function M.apply_panic(state, dt, config)
	config = config or {}
	local rate = config.stress_panic_per_sec or DEFAULT_STRESS_PANIC_PER_SEC
	return apply(state, rate * dt)
end

-- Per-second decay while grounded and not otherwise accumulating stress.
function M.decay_safe(state, dt, config)
	config = config or {}
	local rate = config.stress_decay_safe_per_sec or DEFAULT_STRESS_DECAY_SAFE_PER_SEC
	return apply(state, -rate * dt)
end

return M
