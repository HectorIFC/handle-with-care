-- An advancing lethal wall — the "do not stop" theme, and the second
-- structural answer to every level running left to right at the player's own
-- pace. Kaizo's accelerating autoscroll and Mighty Jill Off's pursuing
-- spider are the same idea: the level stops waiting for you.
--
-- Pure Lua, no Defold API calls (rule 1). State in, new state out (rule 2).
-- dt is injected, never a clock read (rule 3).
--
-- Deliberately NOT built on lethal_hazard: that one sits still and checks
-- itself against the player, and its whole contract is a fixed position a
-- room author placed. This moves under its own power, accelerates, and — the
-- part that matters — has to be provably OUTRUNNABLE, which is a question a
-- static spike never has to answer.
--
-- THE CONSTRAINT, the same shape as door_lie's "the lie must end": a chaser
-- faster than the player is not difficulty, it is an unwinnable room. So the
-- motion is a closed-form function of elapsed time, which is what lets
-- rooms.validate prove, without running the game, that the player can still
-- reach the door with time to spare.

local M = {}

-- Slower than the player's 90 px/s on purpose. The pressure should come from
-- never being able to stop, not from a race the player loses by walking.
local DEFAULT_SPEED = 42
local DEFAULT_ACCELERATION = 4

-- How much dawdling a room forgives when validate checks it is survivable:
-- the player is assumed to waste this long somewhere (hesitating at a gap,
-- waiting out a vanishing door) and still make it.
M.DEFAULT_SLACK = 1.5

function M.new(start)
	return { position = start or 0, time = 0 }
end

-- Where the wall is after `time` seconds. Closed form rather than
-- accumulated, so validate can ask about a moment the game has not reached
-- and get the same answer the game will.
function M.position_at(start, time, config)
	config = config or {}
	local speed = config.speed or DEFAULT_SPEED
	local acceleration = config.acceleration or DEFAULT_ACCELERATION
	return start + speed * time + 0.5 * acceleration * time * time
end

function M.update(state, dt, start, config)
	local time = state.time + dt
	return { position = M.position_at(start, time, config), time = time }
end

-- Has the wall reached this rect? Only the trailing edge matters — the wall
-- is a half-plane, not a box, so anything at or behind its face is caught.
-- A box would let a fast player end up on the wrong side and survive, which
-- reads as a bug rather than as a reprieve.
function M.caught(state, rect)
	return rect.x - (rect.half_width or 0) <= state.position
end

-- Can the player still finish? Answered in the same closed form the game
-- runs on, so this is a proof rather than an estimate.
--
-- The player is assumed to walk the whole way at move_speed: horizontal
-- speed is unchanged in the air in this game, so jumping over gaps costs no
-- ground. `slack` is the dawdling the room forgives on top of that.
function M.survivable(config)
	local distance = config.door_x - config.spawn_x
	if distance <= 0 then
		return false, 0
	end
	local walk_time = distance / config.move_speed
	local deadline = walk_time + (config.slack or M.DEFAULT_SLACK)
	-- Where the player is at the deadline (they have arrived and are
	-- standing at the door), against where the wall has got to.
	local wall = M.position_at(config.start, deadline, config)
	return wall < config.door_x, wall
end

return M
