-- The delivery zone as a liar (PRD-adjacent; this is the Level Devil idea
-- the research singled out as the best fit for this game).
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- dt and the distance to the package are injected; nothing here reads a
-- clock or a position (rule 3).
--
-- WHY THIS BELONGS HERE. Every level of this game is built on the package
-- betraying the player — it goes heavy, it panics, it explodes, it sleeps.
-- The one thing that never lied was the goal. Level Devil's exit "can move,
-- disappear or get blocked at any instance", and applying that to a game
-- whose whole premise is an untrustworthy delivery costs nothing thematically.
--
-- THE CONSTRAINT THAT SHAPES ALL OF IT: the lie has to END. A door that
-- flees forever is not difficult, it is unwinnable, and the difference
-- between a troll and a broken game is exactly that the player can always
-- eventually get there. So:
--
--   * flee moves the door a FIXED number of times, through a list of
--     positions the room author wrote down, and then stands still forever.
--   * vanish cycles closed/open on a timer, so waiting always works.
--
-- Both are therefore checkable: rooms.validate can require every position
-- the door can occupy to be a deliverable one, which it does.

local M = {}

M.HONEST = "honest"
M.FLEE = "flee"
M.VANISH = "vanish"

-- How close the package has to get before a fleeing door reacts. Large
-- enough that the door moves while the player is still committing to the
-- jump, which is what makes it funny rather than merely annoying.
local DEFAULT_TRIGGER_DISTANCE = 48

-- Seconds closed, then seconds open, for vanish. Open has to be long
-- enough to actually arrive during: the package is carried, it lags the
-- player through a lerp, and a window shorter than that lag would be a
-- coin flip rather than a timing test.
local DEFAULT_HIDDEN_TIME = 1.2
local DEFAULT_OPEN_TIME = 2.0

function M.new()
	return { flees = 0, timer = 0, hidden = false, was_near = false }
end

-- How many times a door with `retreats` can run away: once per position the
-- author wrote, never more. Kept as a function rather than read inline so
-- the "the lie ends" rule has one place to live.
function M.max_flees(retreats)
	return retreats and #retreats or 0
end

-- state: from M.new
-- distance: package-to-door distance this frame, in pixels
-- retreats: the list of positions this door may run to, or nil
--
-- The flee triggers on the package ARRIVING inside the radius, not on it
-- being inside: without the was_near edge, a door whose next position is
-- also within the radius of the player would burn every retreat in three
-- frames and the joke would never land.
function M.update(state, dt, distance, retreats, config)
	config = config or {}
	local behavior = config.behavior or M.HONEST
	local new_state = {
		flees = state.flees,
		timer = state.timer,
		hidden = state.hidden,
		was_near = state.was_near,
	}

	if behavior == M.FLEE then
		local trigger = config.trigger_distance or DEFAULT_TRIGGER_DISTANCE
		local near = distance <= trigger
		if near and not state.was_near and state.flees < M.max_flees(retreats) then
			new_state.flees = state.flees + 1
		end
		new_state.was_near = near
	elseif behavior == M.VANISH then
		local hidden_time = config.hidden_time or DEFAULT_HIDDEN_TIME
		local open_time = config.open_time or DEFAULT_OPEN_TIME
		new_state.timer = state.timer + dt
		local span = state.hidden and hidden_time or open_time
		if new_state.timer >= span then
			new_state.timer = new_state.timer - span
			new_state.hidden = not state.hidden
		end
	end

	return new_state
end

-- Where the door is right now: its authored home until it has fled, then
-- the retreat it has fled to. Returns x, y.
function M.position(state, home, retreats)
	if state.flees > 0 and retreats and retreats[state.flees] then
		return retreats[state.flees].x, retreats[state.flees].y
	end
	return home.x, home.y
end

-- Can the level be won right now? Only vanish ever says no, and only for
-- hidden_time at a stretch.
function M.is_open(state, config)
	config = config or {}
	if (config.behavior or M.HONEST) == M.VANISH then
		return not state.hidden
	end
	return true
end

-- Every position this door can ever occupy, so a validator can require all
-- of them to be winnable rather than only the one the author happened to
-- type first. This is what keeps "the lie ends" from being a comment.
function M.positions(home, retreats)
	local out = { { x = home.x, y = home.y } }
	for _, r in ipairs(retreats or {}) do
		out[#out + 1] = { x = r.x, y = r.y }
	end
	return out
end

return M
