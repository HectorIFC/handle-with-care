-- Input inversion driver (PRD section 10, level 7 "Control Freak": os
-- controles invertidos enquanto carrega o pacote, with the second layer
-- being "volta ao normal por poucos segundos + inversão só no ar").
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- dt injected (rule 3).
--
-- Owns only the SCHEDULE of inversion, never the input itself: apply() is a
-- one-liner the adapter calls, which keeps the whole "when are controls
-- inverted" question in one unit-testable place while player.script stays
-- unaware the feature exists.

local M = {}

M.NORMAL = "normal"
M.INVERTED = "inverted"

local DEFAULT_INVERTED_DURATION = 6.0
local DEFAULT_NORMAL_DURATION = 3.0

-- PRD's "inversão só no ar" as a mode rather than a second module: the
-- level picks whether inversion is constant on a timer, or gated on being
-- airborne (which makes every jump a commitment, since the controls flip
-- the moment the player's feet leave the ground).
M.MODE_TIMED = "timed"
M.MODE_AIRBORNE = "airborne"

function M.new(start_inverted)
	return { inverted = start_inverted or false, elapsed = 0 }
end

local function duration_for(inverted, config)
	if inverted then
		return config.inverted_duration or DEFAULT_INVERTED_DURATION
	end
	return config.normal_duration or DEFAULT_NORMAL_DURATION
end

-- returns: new_state, changed
--   In airborne mode the schedule is ignored entirely and inversion simply
--   tracks `grounded`, so the state is derived rather than timed.
function M.update(state, dt, grounded, config)
	config = config or {}

	if (config.mode or M.MODE_TIMED) == M.MODE_AIRBORNE then
		local inverted = not grounded
		return { inverted = inverted, elapsed = 0 }, inverted ~= state.inverted
	end

	local elapsed = state.elapsed + dt
	local duration = duration_for(state.inverted, config)
	if elapsed < duration then
		return { inverted = state.inverted, elapsed = elapsed }, false
	end
	-- Overshoot carried forward so cycles cannot drift, same as the other
	-- timed drivers in this project.
	return { inverted = not state.inverted, elapsed = elapsed - duration }, true
end

-- The actual effect. Separate from update() so a test can check the
-- transformation without driving a clock, and so the adapter never
-- reimplements "inverted means times minus one".
function M.apply(state, move_x)
	if state.inverted then
		return -move_x
	end
	return move_x
end

return M
