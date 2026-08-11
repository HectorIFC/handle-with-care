-- One-shot impact burst (PRD 7.1 lists "partículas" among the props).
--
-- Pure Lua, no Defold API calls (rule 1): this owns the shape of a burst's
-- life — how big it is and how visible it is at a given moment — and
-- main/fx/burst.script applies that to a sprite. Time is injected (rule 3);
-- the adapter accumulates dt and passes it in.
--
-- Deliberately NOT a particle system. Defold has one, but a .particlefx is a
-- large binary-ish resource that nothing in this project can verify: the
-- headless suite renders nothing, so a mis-authored emitter would look
-- exactly like a correct one until someone played the game. A scaled, faded
-- sprite is something whose curve can be unit-tested and whose failure mode
-- is visible in a diff.

local M = {}

local DEFAULT_DURATION = 0.35
local DEFAULT_START_SCALE = 0.4
local DEFAULT_END_SCALE = 1.8

-- Normalized position through the burst's life, clamped so an adapter that
-- overshoots by a frame gets 1 rather than something past the end.
function M.progress(elapsed, duration)
	duration = duration or DEFAULT_DURATION
	if duration <= 0 then
		return 1
	end
	local t = elapsed / duration
	if t < 0 then
		return 0
	end
	if t > 1 then
		return 1
	end
	return t
end

-- Grows fast then slows — the burst should read as an impact, and a linear
-- expansion reads as an object being inflated instead.
function M.scale_at(t, config)
	config = config or {}
	local from = config.start_scale or DEFAULT_START_SCALE
	local to = config.end_scale or DEFAULT_END_SCALE
	local eased = 1 - (1 - t) * (1 - t)
	return from + (to - from) * eased
end

-- Holds full opacity briefly before falling off, so the burst registers at
-- all: fading from the first frame makes a 0.35s effect read as a flicker.
function M.alpha_at(t)
	if t <= 0.25 then
		return 1
	end
	return 1 - (t - 0.25) / 0.75
end

function M.is_done(elapsed, duration)
	return M.progress(elapsed, duration) >= 1
end

return M
