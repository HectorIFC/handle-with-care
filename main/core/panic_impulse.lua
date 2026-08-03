-- Pure random-impulse generator for the Panic state (PRD 4.4/4.8): every
-- ~PANIC_IMPULSE_INTERVAL seconds, produces one random horizontal/vertical
-- force — a discrete kick, not a sustained push, so the returned force is
-- zero on every frame except the exact one where the interval elapses.
-- package_physics's own velocity_damping decays the resulting velocity
-- naturally between impulses. No Defold API calls here — `dt` and `rng`
-- are injected (never math.random()/a clock read directly, rule 3).

local M = {}

local DEFAULT_INTERVAL = 0.55
local DEFAULT_HORIZONTAL_MIN, DEFAULT_HORIZONTAL_MAX = -120, 120
local DEFAULT_VERTICAL_MIN, DEFAULT_VERTICAL_MAX = 80, 160

function M.new()
	return { time_since_last = 0, horizontal_force = 0, vertical_force = 0 }
end

-- state: { time_since_last, horizontal_force, vertical_force }
-- dt: elapsed seconds this frame
-- rng: function(min, max) -> number in [min, max] (injected by the adapter,
--   e.g. `function(a, b) return a + math.random() * (b - a) end`)
-- config: { interval, horizontal_min, horizontal_max, vertical_min, vertical_max }
-- returns: new_state, triggered (true only on the frame a fresh impulse fires)
function M.update(state, dt, rng, config)
	config = config or {}
	local interval = config.interval or DEFAULT_INTERVAL
	local time_since_last = state.time_since_last + dt

	if time_since_last >= interval then
		local horizontal_min = config.horizontal_min or DEFAULT_HORIZONTAL_MIN
		local horizontal_max = config.horizontal_max or DEFAULT_HORIZONTAL_MAX
		local vertical_min = config.vertical_min or DEFAULT_VERTICAL_MIN
		local vertical_max = config.vertical_max or DEFAULT_VERTICAL_MAX
		return {
			time_since_last = 0,
			horizontal_force = rng(horizontal_min, horizontal_max),
			vertical_force = rng(vertical_min, vertical_max),
		}, true
	end

	return { time_since_last = time_since_last, horizontal_force = 0, vertical_force = 0 }, false
end

return M
