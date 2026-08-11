-- Parallax background layers (PRD section 7's "backgrounds com parallax
-- simples (2-3 camadas)").
--
-- Pure Lua, no Defold API calls (rule 1): this decides where a layer sits
-- given the camera, and main/level/background.script applies it. Stateless —
-- a layer's position is a function of the camera's, with nothing to carry
-- between frames, so there is no state to pass in or out (rule 2 is
-- satisfied trivially rather than ignored).

local M = {}

-- `factor` is how much of the world's motion a layer keeps:
--   1.0 — moves exactly with the world (no parallax at all)
--   0.0 — never moves relative to the camera (infinitely distant)
-- Anything between is a layer that drifts, which is the whole effect.
--
-- Screen position works out as -(camera_x * factor): at factor 1 the layer
-- shifts by the camera's full travel and so appears world-locked; at 0 it
-- does not shift and so appears pinned to the view.
function M.layer_x(camera_x, factor)
	return camera_x * (1 - factor)
end

-- The same, but wrapped so one tile can repeat forever instead of the level
-- needing a background as wide as itself.
--
-- Returns the world x of the FIRST copy, always at or left of the camera, so
-- the adapter can place its copies at x, x + tile_width, ... and be certain
-- the screen is covered. Wrapping by tile_width rather than letting the
-- offset grow without bound also keeps the numbers small on a long level,
-- where a raw offset would eventually cost float precision.
function M.wrapped_x(camera_x, factor, tile_width)
	if tile_width <= 0 then
		return camera_x
	end
	local shift = (camera_x * factor) % tile_width
	return camera_x - shift
end

-- How many copies of a tile are needed to cover the view no matter where the
-- wrap lands. One extra beyond the exact fit, because the first copy starts
-- at or before the camera's left edge, never exactly on it.
function M.copies_needed(screen_width, tile_width)
	if tile_width <= 0 then
		return 1
	end
	return math.ceil(screen_width / tile_width) + 1
end

return M
