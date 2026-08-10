-- Cyclic Heavy driver (PRD section 10, level 3 "Heavy Duty": "Pacote fica
-- pesado em ciclos"). Alternates the package between Heavy and normal on a
-- fixed schedule, and reports the exact frame it flips so the adapter can
-- drive the state machine.
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- dt is injected, never a clock read (rule 3) — the same shape as
-- explosive.lua's countdown, which this is deliberately modelled on.
--
-- Why this exists at all: until now Heavy was only reachable through
-- package.script's `debug_set_state` test hook (see CLAUDE.md). This is the
-- real trigger that hook was standing in for. It does NOT know about the
-- state machine — it only says "flip now, to this state" — which is what
-- keeps the same driver reusable for any future cyclic state.

local M = {}

-- No PRD value exists for the cadence; these are this project's own
-- starting point, to be tuned in phase 22's playtest pass, the same as
-- magnetism.lua's DEFAULT_STRENGTH. Normal is longer than heavy so the
-- level is playable between cycles rather than a constant slog.
local DEFAULT_HEAVY_DURATION = 3.0
local DEFAULT_NORMAL_DURATION = 5.0

M.HEAVY = "heavy"
M.NORMAL = "stable"

-- `start_heavy` lets a level open in either phase. Starting normal is the
-- kinder default: dropping the player into a Heavy cycle before they have
-- moved gives them no baseline to feel the change against.
function M.new(start_heavy)
	return {
		heavy = start_heavy or false,
		elapsed = 0,
	}
end

-- The two state names are config, not constants: level 4 "Hot Potato" is
-- the same cycle driving stable -> explosive instead of stable -> heavy
-- (PRD level 4, and architecture rule 6's expectation that the phase-timer
-- trigger needs no change to explosive.lua or the state machine). Keeping
-- the driver state-agnostic is what makes that a config change rather than
-- a second near-identical module.
local function state_names(config)
	return config.heavy_state or M.HEAVY, config.normal_state or M.NORMAL
end

local function duration_for(heavy, config)
	if heavy then
		return config.heavy_duration or DEFAULT_HEAVY_DURATION
	end
	return config.normal_duration or DEFAULT_NORMAL_DURATION
end

-- returns: new_state, flipped_to
--   flipped_to is the state name to switch to on exactly the frame the
--   cycle turns over, and nil on every other frame. One-shot for the same
--   reason offscreen_timer's `died` is: the adapter posts a message on it,
--   and a value that stayed set would re-post every frame.
function M.update(state, dt, config)
	config = config or {}
	local elapsed = state.elapsed + dt
	local duration = duration_for(state.heavy, config)

	if elapsed < duration then
		return { heavy = state.heavy, elapsed = elapsed }, nil
	end

	-- Carries the overshoot into the next phase instead of resetting to
	-- zero, so a long frame cannot make cycles drift steadily longer than
	-- configured over the course of a level.
	local now_heavy = not state.heavy
	local heavy_state, normal_state = state_names(config)
	return { heavy = now_heavy, elapsed = elapsed - duration },
		(now_heavy and heavy_state or normal_state)
end

-- How far through the current phase, 0..1. For a HUD or a telegraph so the
-- cycle is readable rather than a surprise — PRD section 11 requires the
-- level's madness to be "claramente sentida", and an unsignalled mass
-- change is just an unfair death.
function M.progress(state, config)
	config = config or {}
	local duration = duration_for(state.heavy, config)
	if duration <= 0 then
		return 1
	end
	local ratio = state.elapsed / duration
	if ratio > 1 then
		return 1
	end
	return ratio
end

return M
