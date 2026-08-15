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

-- The wobble a platform does while the player stands on it and before it
-- lets go. Two jobs, and it does the second one only because it grows:
--
--   * it says "this one is a liar" the moment you touch it, which is what
--     turns a death into a lesson rather than a surprise, and
--   * because the amplitude scales with how close the timer is to expiring,
--     it also says HOW LONG you have left. A constant shake would announce
--     the trap without telling you anything about the deadline, which is
--     the same complaint PRD 4.6's gravity moods answer with a telegraph.
--
-- Small on purpose: 2px at 16Hz reads as a shudder at this resolution. Any
-- more and it would fight the AABB ground check, since the surface the
-- player stands on really does move with it.
local DEFAULT_WOBBLE_AMPLITUDE = 2.0
local DEFAULT_WOBBLE_FREQUENCY = 16.0

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

-- How far left or right the platform should be drawn from its home x this
-- frame. Zero unless the player is standing on it and it has not let go yet.
--
-- No clock is read here (rule 3): time_standing is the state the adapter
-- already accumulates from injected dt, so the same input always produces
-- the same offset and a test can pin any point of the wobble exactly.
function M.wobble_offset(state, config)
	config = config or {}
	if state.falling or state.time_standing <= 0 then
		return 0
	end
	local fall_delay = config.fall_delay or DEFAULT_FALL_DELAY
	local amplitude = config.wobble_amplitude or DEFAULT_WOBBLE_AMPLITUDE
	local frequency = config.wobble_frequency or DEFAULT_WOBBLE_FREQUENCY
	-- Clamped, so a fall_delay of zero (or a frame that overshoots it)
	-- cannot produce an amplitude larger than asked for.
	local urgency = math.min(state.time_standing / fall_delay, 1)
	return math.sin(state.time_standing * frequency) * amplitude * urgency
end

return M
