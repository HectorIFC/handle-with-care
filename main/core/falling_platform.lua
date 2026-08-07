-- Falling platform timer (roadmap phase 9a: "plataformas que caem").
-- Tracks how long the player has been standing on it; once that exceeds
-- fall_delay, the platform starts falling and never becomes solid ground
-- again — a one-way trigger once started, the same shape as explosive.lua's
-- countdown, just gated by continuous contact instead of a single trigger.
-- No Defold API calls here (rule 1); dt and the contact test are injected
-- (rule 3) — the adapter (main/hazards/falling_platform.script) is what
-- actually drives the platform's Y position downward once `falling` is
-- true, and what computes "is the player standing on me" via
-- core/hazards.standing_on against its own live position.

local M = {}

local DEFAULT_FALL_DELAY = 1.0

function M.new()
	return { time_standing = 0, falling = false }
end

-- state: { time_standing, falling }
-- is_standing_on: bool, this frame's contact result — ignored once
--   already falling, so a platform mid-drop doesn't reset just because
--   the player stepped off (or fell off) partway through
-- returns: new_state, just_started_falling (true only on the exact frame
--   time_standing crosses fall_delay)
function M.update(state, is_standing_on, dt, config)
	config = config or {}
	local fall_delay = config.fall_delay or DEFAULT_FALL_DELAY

	if state.falling then
		return state, false
	end

	if not is_standing_on then
		return { time_standing = 0, falling = false }, false
	end

	local new_time = state.time_standing + dt
	if new_time >= fall_delay then
		return { time_standing = new_time, falling = true }, true
	end
	return { time_standing = new_time, falling = false }, false
end

return M
