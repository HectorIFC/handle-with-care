-- Side-scrolling camera (needed before levels 2-10: without one, a level
-- cannot exceed the 384x216 screen, which caps a successful attempt at
-- ~15s against the PRD's 35-75s target — see CLAUDE.md).
--
-- Pure Lua, no Defold API calls (rule 1): this decides where the camera
-- should be, and main/level/camera.script applies it. State in, new state
-- out (rule 2). dt is injected, never a clock read (rule 3).
--
-- The camera only moves horizontally. Levels are wide, not tall (PRD 7.1's
-- 384x216 base resolution with integer scaling), so a vertical axis would
-- be untested weight — add it when a level actually needs it.

local M = {}

-- How far the player may drift from the screen's center before the camera
-- follows. A dead zone rather than hard centering: the package trails the
-- player and wobbles constantly (shake, Panic impulses), so a camera glued
-- to the player would jitter the whole frame every time the package moved
-- the player a pixel.
local DEFAULT_DEAD_ZONE = 48
-- Fraction of the remaining gap closed per frame. Same per-frame (not
-- dt-scaled) convention as package_physics' lerp_factor, and for the same
-- reason: display.update_frequency locks the simulation at 60Hz, so a
-- constant per frame is a constant per unit of game time (CLAUDE.md rule 3).
local DEFAULT_FOLLOW_LERP = 0.12

function M.new(x)
	return { x = x or 0 }
end

-- The furthest left the camera may sit is 0 (the level's left edge lines up
-- with the screen's), and the furthest right is level_width - screen_width.
-- A level narrower than the screen pins the camera at 0 rather than going
-- negative, which is what keeps the existing one-screen levels behaving
-- exactly as they did before a camera existed.
function M.clamp(x, level_width, screen_width)
	local max_x = level_width - screen_width
	if max_x <= 0 then
		return 0
	end
	if x < 0 then
		return 0
	end
	if x > max_x then
		return max_x
	end
	return x
end

-- Where the camera wants to be, given the player's position: centered,
-- unless the player is still inside the dead zone around the current
-- center, in which case it does not want to move at all.
function M.target_x(state, player_x, screen_width, config)
	config = config or {}
	local dead_zone = config.dead_zone or DEFAULT_DEAD_ZONE
	local center = state.x + screen_width * 0.5
	local drift = player_x - center
	if math.abs(drift) <= dead_zone then
		return state.x
	end
	-- Move only by the amount that puts the player back on the dead zone's
	-- edge, not all the way to center: snapping to center on every exit
	-- would make the camera lurch each time the player turned around.
	if drift > 0 then
		return state.x + (drift - dead_zone)
	end
	return state.x + (drift + dead_zone)
end

function M.update(state, player_x, dt, config)
	config = config or {}
	local screen_width = config.screen_width or 384
	local level_width = config.level_width or screen_width
	local follow_lerp = config.follow_lerp or DEFAULT_FOLLOW_LERP

	local target = M.target_x(state, player_x, screen_width, config)
	local eased = state.x + (target - state.x) * follow_lerp
	return { x = M.clamp(eased, level_width, screen_width) }
end

-- PRD 3.3's "pacote fugiu da tela", made camera-relative. The old check
-- compared against the fixed screen rectangle, which is why a level could
-- never be wider than one screen: walking right to reach more level was
-- indistinguishable from fleeing the play area. Anything outside the
-- camera's current window is off-screen now, whatever the level's width.
function M.rect_offscreen(rect, camera_x, screen_width, screen_height)
	local min_x, max_x = rect.x - rect.half_width, rect.x + rect.half_width
	local min_y, max_y = rect.y - rect.half_height, rect.y + rect.half_height
	return max_x < camera_x
		or min_x > camera_x + screen_width
		or max_y < 0
		or min_y > screen_height
end

return M
