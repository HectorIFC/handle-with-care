-- Generic geometry checks for hazards and death conditions (PRD 3.3/4.7).
-- Every hazard adapter reuses these instead of reimplementing overlap math.
-- Pure Lua, no Defold API calls (rule 1) — see main/hazards/*.script for
-- the adapters that read live positions and call these, and rule 9 for why
-- this is plain AABB geometry rather than an engine physics query.
--
-- A "rect" here is a live, centered rectangle: { x, y, half_width,
-- half_height }. Unlike player_movement.resting_y_on_ground's static
-- { x_min, x_max, y_top } ground rect (baked-in absolute bounds, since the
-- main ground never moves), hazards can move — a saw drifting toward a
-- Magnetized package, a falling platform dropping — so every check here
-- takes a live center position on every call instead.

local M = {}

function M.rect_overlap(a, b)
	local a_min_x, a_max_x = a.x - a.half_width, a.x + a.half_width
	local a_min_y, a_max_y = a.y - a.half_height, a.y + a.half_height
	local b_min_x, b_max_x = b.x - b.half_width, b.x + b.half_width
	local b_min_y, b_max_y = b.y - b.half_height, b.y + b.half_height
	return a_min_x < b_max_x and a_max_x > b_min_x and a_min_y < b_max_y and a_max_y > b_min_y
end

-- Is `player` currently resting on top of `surface`? Unlike
-- player_movement.resting_y_on_ground (which predicts a crossing between
-- this frame's start/target Y for the one static main ground rect), this
-- is a same-frame, no-prediction check meant for a surface that can move
-- out from under the player, like a falling platform: horizontal overlap,
-- and the player's feet within `epsilon` of the surface's top.
function M.standing_on(player, surface, epsilon)
	epsilon = epsilon or 0.5
	local player_min_x, player_max_x = player.x - player.half_width, player.x + player.half_width
	local surface_min_x, surface_max_x = surface.x - surface.half_width, surface.x + surface.half_width
	if player_max_x <= surface_min_x or player_min_x >= surface_max_x then
		return false
	end

	local player_bottom = player.y - player.half_height
	local surface_top = surface.y + surface.half_height
	return math.abs(player_bottom - surface_top) <= epsilon
end

-- Is `y` below the kill plane (PRD 3.3/4.7: "queda em buraco")? A simple
-- world-bounds check rather than per-pit geometry — this project has no
-- camera/scrolling system yet, so "fell into a pit" and "fell off the
-- bottom of the world" are the same event for now. Revisit once real
-- levels (phase 10+) need actual pit rectangles rather than a single
-- world-bottom threshold.
function M.below_kill_plane(y, kill_y)
	return y < kill_y
end

-- Is `rect` completely outside the visible play area (PRD 3.3: "pacote
-- fugiu da tela")? Fully outside, not just partially past an edge —
-- matches the PRD's "sai COMPLETAMENTE da tela". screen_width/
-- screen_height are the adapter's own read of game.project's actual
-- display settings (see player.script), not a duplicated constant here.
function M.fully_offscreen(rect, screen_width, screen_height)
	local min_x, max_x = rect.x - rect.half_width, rect.x + rect.half_width
	local min_y, max_y = rect.y - rect.half_height, rect.y + rect.half_height
	return max_x < 0 or min_x > screen_width or max_y < 0 or min_y > screen_height
end

return M
