-- Off-screen death timer (PRD 3.3: "pacote fugiu da tela" — stayed off
-- the visible area too long). Accumulates while off-screen, resets to
-- zero the instant it's back on-screen — unlike explosive.lua's one-way
-- countdown, this is a resettable accumulator, not a fuse. No PRD-given
-- threshold exists for "too long"; DEFAULT_TIMEOUT is this project's own
-- initial guess, to be tuned during phase 22's playtest pass, the same
-- as magnetism.lua's DEFAULT_STRENGTH. No Defold API calls here (rule 1);
-- dt and the offscreen test are injected (rule 3).

local M = {}

local DEFAULT_TIMEOUT = 2.0

function M.new()
	return { time_offscreen = 0 }
end

-- state: { time_offscreen }
-- is_offscreen: bool, this frame's fully_offscreen() result
-- returns: new_state, died (true only on the exact frame the timeout is
--   crossed — false before that frame and on every frame after, the same
--   one-shot shape as explosive.lua's `active`-gated update(), needed for
--   the same reason: without it, every frame past the timeout would keep
--   reporting died=true again)
function M.update(state, is_offscreen, dt, config)
	config = config or {}
	local timeout = config.timeout or DEFAULT_TIMEOUT

	if not is_offscreen then
		return { time_offscreen = 0 }, false
	end

	if state.time_offscreen >= timeout then
		return state, false
	end

	local new_time = state.time_offscreen + dt
	if new_time >= timeout then
		return { time_offscreen = timeout }, true
	end
	return { time_offscreen = new_time }, false
end

return M
