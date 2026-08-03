-- Package state machine (PRD section 4.4): 8 discrete behavioral states.
-- No Defold API calls here — see main/package/package.script for the
-- adapter that reads stress/triggers and applies shake/tint/mass.
--
-- Stable/Nervous/Panic transition automatically from the stress value (see
-- update_from_stress, driven by core/stress.lua). Heavy/Light/Magnetized/
-- Sleeping are NOT part of the stress ladder — the PRD triggers them from
-- other conditions (cyclic timers, hazard proximity, impact detection) that
-- later phases (4, 7, 8) will call directly via set_state.
--
-- Explosive is a one-way exit from the ladder, reachable from it (stress
-- crossing explosive_threshold) but never re-derived back down once
-- entered — see the RE_DERIVABLE_STATES note below for why.

local M = {}

M.STABLE = "stable"
M.NERVOUS = "nervous"
M.PANIC = "panic"
M.HEAVY = "heavy"
M.LIGHT = "light"
M.EXPLOSIVE = "explosive"
M.MAGNETIZED = "magnetized"
M.SLEEPING = "sleeping"

-- States update_from_stress is allowed to overwrite. Explosive is
-- deliberately absent: once entered (whether via stress crossing
-- explosive_threshold below, or an explicit set_state call from a future
-- phase-timer trigger), it must stick regardless of what stress does
-- afterward. Without this exclusion, a single frame of decay_safe from
-- exactly the threshold value drops stress just below it, and this
-- function would immediately re-derive Panic on the very next frame —
-- aborting the detonation before explosive.lua's timer ever runs. The same
-- exclusion is also what lets a phase-timer trigger force Explosive while
-- stress is still low without it bouncing back a frame later, the way
-- debug_set_state("panic") famously doesn't stick (see CLAUDE.md).
local RE_DERIVABLE_STATES = {
	[M.STABLE] = true,
	[M.NERVOUS] = true,
	[M.PANIC] = true,
}

local DEFAULT_NERVOUS_THRESHOLD = 30
local DEFAULT_PANIC_THRESHOLD = 70
local DEFAULT_EXPLOSIVE_THRESHOLD = 100

local DEFAULT_NERVOUS_SHAKE_INTENSITY = 0.5
local DEFAULT_PANIC_SHAKE_INTENSITY = 1.0
local DEFAULT_EXPLOSIVE_SHAKE_INTENSITY = 1.0

local DEFAULT_HEAVY_MASS = 2.5
local DEFAULT_LIGHT_MASS = 0.4

-- PRD 4.4: "Offset Y do pacote desce" (Heavy) / "Offset Y sobe" (Light).
local DEFAULT_HEAVY_OFFSET_Y_BONUS = -6
local DEFAULT_LIGHT_OFFSET_Y_BONUS = 6

-- PRD 4.4: Light gets "vertical_force positivo constante leve (flutua)".
local DEFAULT_LIGHT_VERTICAL_FORCE = 40

function M.new()
	return { current_state = M.STABLE }
end

-- Directly sets the state, bypassing stress-driven logic. Used by later
-- phases for triggers that aren't stress-based (Heavy/Light cycles,
-- Magnetized proximity, Sleeping/wake).
function M.set_state(state, new_state)
	return { current_state = new_state }
end

-- Recomputes current_state from `stress` for the states on the stress
-- ladder (Stable/Nervous/Panic). Leaves any other current state (Heavy/
-- Light/Magnetized/Sleeping, and Explosive once entered) untouched — those
-- exit only via set_state, called by whatever later-phase logic owns their
-- trigger (package.script's explosive detonation handling, for Explosive).
function M.update_from_stress(state, stress, config)
	if not RE_DERIVABLE_STATES[state.current_state] then
		return state
	end

	config = config or {}
	local nervous_threshold = config.nervous_threshold or DEFAULT_NERVOUS_THRESHOLD
	local panic_threshold = config.panic_threshold or DEFAULT_PANIC_THRESHOLD
	local explosive_threshold = config.explosive_threshold or DEFAULT_EXPLOSIVE_THRESHOLD

	local new_state
	if stress >= explosive_threshold then
		new_state = M.EXPLOSIVE
	elseif stress >= panic_threshold then
		new_state = M.PANIC
	elseif stress >= nervous_threshold then
		new_state = M.NERVOUS
	else
		new_state = M.STABLE
	end

	return { current_state = new_state }
end

-- Shake intensity for the current state (PRD 4.4). Explosive's own value is
-- the ceiling reached right before detonation — package.script scales it by
-- explosive.progress() so shake actually ramps up over the countdown
-- instead of snapping to full intensity the instant Explosive is entered.
function M.shake_intensity(state, config)
	config = config or {}
	if state.current_state == M.NERVOUS then
		return config.nervous_shake_intensity or DEFAULT_NERVOUS_SHAKE_INTENSITY
	elseif state.current_state == M.PANIC then
		return config.panic_shake_intensity or DEFAULT_PANIC_SHAKE_INTENSITY
	elseif state.current_state == M.EXPLOSIVE then
		return config.explosive_shake_intensity or DEFAULT_EXPLOSIVE_SHAKE_INTENSITY
	end
	return 0
end

-- Virtual mass for the current state (PRD 4.2/4.4). Drives the player's own
-- speed/gravity multipliers (see player_movement.speed_multiplier/
-- gravity_multiplier) — 1.0 (Stable's mass) for every state except
-- Heavy/Light.
function M.mass(state, config)
	config = config or {}
	if state.current_state == M.HEAVY then
		return config.heavy_mass or DEFAULT_HEAVY_MASS
	elseif state.current_state == M.LIGHT then
		return config.light_mass or DEFAULT_LIGHT_MASS
	end
	return 1.0
end

-- Extra vertical offset added on top of the package's normal offset_y
-- (PRD 4.4: Heavy sits lower, Light floats higher). Zero for every other
-- state.
function M.offset_y_bonus(state, config)
	config = config or {}
	if state.current_state == M.HEAVY then
		return config.heavy_offset_y_bonus or DEFAULT_HEAVY_OFFSET_Y_BONUS
	elseif state.current_state == M.LIGHT then
		return config.light_offset_y_bonus or DEFAULT_LIGHT_OFFSET_Y_BONUS
	end
	return 0
end

-- Constant vertical force for the current state (PRD 4.4: Light floats).
-- Zero for every other state — Panic's own random impulses arrive with
-- phase 5.
function M.vertical_force(state, config)
	config = config or {}
	if state.current_state == M.LIGHT then
		return config.light_vertical_force or DEFAULT_LIGHT_VERTICAL_FORCE
	end
	return 0
end

return M
