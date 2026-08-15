-- Rooms: the game's levels, as DATA rather than as .collection files.
--
-- Pure Lua, no Defold API calls (rule 1). Nothing here mutates: M.THEMES and
-- M.ROOMS are constant tables, the same way gravity_driver.MOODS and
-- package_state_machine.RE_DERIVABLE_STATES are, and every function takes
-- its input and returns a fresh value (rule 2).
--
-- WHY THIS EXISTS. Every one of the ten levels ran left to right in a
-- straight line, which is fine for the first one and monotonous for the
-- other nine. The competitor that answers this best is Level Devil: ~200
-- SHORT stages grouped five to a theme, with the exit visible from the
-- start — and the exit lies. It beats monotony with a quantity of ideas
-- rather than with length. A room is one screen (384x216), lasts 5-15
-- seconds, and carries exactly one idea.
--
-- WHY DATA AND NOT COLLECTIONS. Forty .collection files would be forty
-- copies of the same wiring, and level geometry has already been the source
-- of two shipped bugs (a production scene whose ground did not match the
-- player's properties, and a platform placed above the jump apex). A room
-- that fits on one screen fits in a small table, so main/level/room_builder
-- .script spawns it with factory.create() — the same idiom player.script
-- already uses for its fx bursts — passing exactly the go.property values
-- rule 5 requires, from one place.
--
-- The payoff is that geometry becomes testable. M.validate is a unit test
-- away from every room, using the player's real constants, instead of a
-- Python script parsing .collection files with regexes.

local player_movement = require "main.core.player_movement"

local M = {}

-- One screen, from game.project's display.width/height. A room may not
-- place anything outside this: there is no camera scrolling in a room, so
-- off-screen is simply invisible.
M.SCREEN_WIDTH = 384
M.SCREEN_HEIGHT = 216

-- Themes group rooms five at a time, the way Level Devil groups its stages
-- behind a door. Each reuses a background palette and a music cue that
-- already exist, so a theme costs no new assets.
M.THEMES = {
	{ id = "falling", name = "THE FLOOR LIES", background = "bg2", music = "level_02" },
	{ id = "heavy", name = "DEAD WEIGHT", background = "bg3", music = "level_03" },
	{ id = "fuse", name = "LIT FUSE", background = "bg4", music = "level_04" },
	{ id = "magnet", name = "ATTRACTION", background = "bg5", music = "level_05" },
	{ id = "controls", name = "WRONG WAY", background = "bg7", music = "level_07" },
	{ id = "gravity", name = "UP IS A SUGGESTION", background = "bg6", music = "level_06" },
	{ id = "chase", name = "DO NOT STOP", background = "bg10", music = "level_10" },
	{ id = "door", name = "THE DOOR LIES", background = "bg9", music = "level_09" },
}

-- The player carries the package above itself, so "can the package reach the
-- door" is a different question from "can the player stand there". Defaults
-- mirror the go.property values on player.script, package.script and
-- delivery_zone.script; validate() takes them as config so a test can pin
-- them and so nothing here has to be edited when one of those changes.
M.DEFAULTS = {
	player_half_width = 8,
	player_half_height = 8,
	package_half = 6,
	package_offset_y = 12,
	door_half_width = 24,
	door_half_height = 24,
}

--- Rooms ---------------------------------------------------------------
--
-- Composition rule inside a theme: room 1 TEACHES the theme's piece BY
-- BETRAYING you with it once, cheaply and early; rooms 2-4 charge for it;
-- room 5 combines it with a piece from an earlier theme. A theme never
-- invents a ninth mechanic.
--
-- The first version of this rule said room 1 should teach "somewhere it
-- cannot kill", borrowed from the generic 2D patterns (safe zone,
-- foreshadowing). That is wrong for this genre and produced a room you
-- could finish by holding right. Level Devil's own first stage is a trap
-- tutorial disguised as a normal one: it teaches by betraying. What makes
-- that fair is not the absence of death, it is that restart is instant —
-- which this game already has on R. The cost of learning is one reset.
--
-- walkable_straight_through() below is that lesson as a test, so no room can
-- quietly become a corridor again.
--
-- Geometry notes that apply to every room:
--   * `floor` is the always-present base, described the way player.script
--     already wants it (ground_x_min/ground_x_max/ground_y_top).
--   * a platform's x/y is its CENTRE, matching platform.script.
--   * `door` is the delivery zone's centre. It must sit exactly
--     player_half_height + package_offset_y above a surface, which is what
--     puts the carried package inside it — validate() checks this rather
--     than trusting the number.
M.ROOMS = {
	{
		id = "falling_1",
		theme = "falling",
		name = "A FIRST STEP",
		-- Teaches by betraying: two platforms cross the pit and they look
		-- identical, but the first one drops the moment it is stood on. You
		-- learn what this theme is by losing to it once, about four seconds
		-- in, with R putting you back instantly.
		--
		-- The floor deliberately stops at 120, well short of the door. The
		-- first version of this room had it spanning the whole screen, which
		-- made the platform decoration and the room a corridor.
		spawn = { x = 30, y = 60 },
		floor = { x_min = 0, x_max = 120, y_top = 48 },
		platforms = {
			-- 160..240, the liar.
			{ x = 200, y = 56, half_width = 40, half_height = 8, falling = true },
			-- 276..384, solid, and where the door stands.
			{ x = 330, y = 56, half_width = 54, half_height = 8 },
		},
		hazards = {
			-- In the pit, under the gap the liar leaves behind. It is not
			-- what kills on the first attempt — the fall does — it is what
			-- makes the second attempt read as a decision.
			{ x = 258, y = 16 },
		},
		door = { x = 330, y = 84 },
	},
	{
		id = "falling_2",
		theme = "falling",
		name = "COMMITTED",
		-- Charges for it: now the floor under the drop is a pit, so the
		-- platform going away is the whole difficulty.
		spawn = { x = 30, y = 60 },
		floor = { x_min = 0, x_max = 90, y_top = 48 },
		platforms = {
			{ x = 150, y = 60, half_width = 36, half_height = 8, falling = true },
			{ x = 290, y = 60, half_width = 60, half_height = 8 },
		},
		hazards = {
			{ x = 200, y = 16 },
		},
		door = { x = 290, y = 80 },
	},
	{
		id = "falling_3",
		theme = "falling",
		name = "TWO OF THEM",
		spawn = { x = 30, y = 60 },
		floor = { x_min = 0, x_max = 80, y_top = 48 },
		platforms = {
			{ x = 130, y = 76, half_width = 30, half_height = 8, falling = true },
			{ x = 230, y = 104, half_width = 30, half_height = 8, falling = true },
			{ x = 330, y = 60, half_width = 50, half_height = 8 },
		},
		hazards = {
			{ x = 180, y = 16 },
			{ x = 280, y = 16 },
		},
		door = { x = 330, y = 80 },
	},
	{
		id = "falling_4",
		theme = "falling",
		name = "THE HIGH ROAD",
		-- The tall route is faster and made of falling platforms; the low
		-- route is solid but walled off by a spike that has to be jumped.
		-- Two ways through is the "branching" pattern, and it is what stops
		-- a theme's fourth room from feeling like its third.
		spawn = { x = 28, y = 60 },
		floor = { x_min = 0, x_max = 130, y_top = 48 },
		platforms = {
			{ x = 120, y = 116, half_width = 34, half_height = 8, falling = true },
			{ x = 235, y = 116, half_width = 34, half_height = 8, falling = true },
			{ x = 235, y = 60, half_width = 44, half_height = 8 },
			{ x = 340, y = 60, half_width = 44, half_height = 8 },
		},
		hazards = {
			{ x = 170, y = 60 },
		},
		door = { x = 340, y = 80 },
	},
	{
		id = "falling_5",
		theme = "falling",
		name = "HEAVY FOOTED",
		-- Room 5 layers: the floor still lies, but the package goes Heavy on
		-- a cycle, so the jump that cleared the gap a moment ago does not.
		-- Sized against Heavy's reach (34.8) and apex (39.8), not the
		-- player's unmodified 64 / 56.9.
		spawn = { x = 28, y = 60 },
		modifier = "heavy_cycle",
		floor = { x_min = 0, x_max = 110, y_top = 48 },
		platforms = {
			{ x = 155, y = 76, half_width = 26, half_height = 8, falling = true },
			{ x = 232, y = 92, half_width = 26, half_height = 8 },
			{ x = 309, y = 76, half_width = 26, half_height = 8, falling = true },
			{ x = 366, y = 60, half_width = 18, half_height = 8 },
		},
		hazards = {
			{ x = 195, y = 16 },
			{ x = 270, y = 16 },
		},
		door = { x = 366, y = 80 },
	},
}

-- Modifier -> the jump budget it leaves. Only mobility modifiers appear
-- here: Magnetized, Explosive and Sleeping do not touch how far the player
-- can jump, which is exactly why they can be layered freely.
local MODIFIER_MASS = {
	heavy_cycle = 2.5,
}

function M.theme(id)
	for _, theme in ipairs(M.THEMES) do
		if theme.id == id then
			return theme
		end
	end
	return nil
end

function M.room(id)
	for index, room in ipairs(M.ROOMS) do
		if room.id == id then
			return room, index
		end
	end
	return nil
end

function M.count()
	return #M.ROOMS
end

-- How far and how high the player can jump inside this room, given the worst
-- modifier the room itself declares. Derived from player_movement's own
-- multipliers so it cannot drift from the game: airtime is 2v/g and apex is
-- v^2/2g.
function M.budget(room, config)
	config = config or {}
	local move_speed = config.move_speed or 90
	local jump_velocity = config.jump_velocity or 320
	local gravity = math.abs(config.gravity or -900)

	local mass = MODIFIER_MASS[room.modifier]
	if mass then
		move_speed = move_speed * player_movement.speed_multiplier(mass)
		jump_velocity = jump_velocity * player_movement.jump_multiplier(mass)
	end

	local airtime = 2 * jump_velocity / gravity
	return move_speed * airtime, (jump_velocity ^ 2) / (2 * gravity)
end

-- Every standable surface in the room, as { left, right, top }.
function M.surfaces(room)
	local out = {
		{ room.floor.x_min, room.floor.x_max, room.floor.y_top },
	}
	for _, p in ipairs(room.platforms or {}) do
		out[#out + 1] = { p.x - p.half_width, p.x + p.half_width, p.y + p.half_height }
	end
	return out
end

-- Is `target` reachable from ANY other surface? Dropping down is free, so
-- only climbing is limited by the apex; and the player clears a gap wider
-- than its airborne travel by its own width, since it leaves the ledge with
-- its trailing half still over it and lands with its leading half already
-- over the next one.
local function reachable(target, all, max_gap, max_step, half_width)
	for _, other in ipairs(all) do
		if other ~= target and target[3] - other[3] <= max_step then
			if other[2] >= target[1] and other[1] <= target[2] then
				return true -- overlapping in x: step across, no jump needed
			end
			local gap = other[2] < target[1] and target[1] - other[2]
				or other[1] - target[2]
			if gap - 2 * half_width <= max_gap then
				return true
			end
		end
	end
	return false
end

-- Can this room be finished by holding one direction? That is the one thing
-- a troll platformer may never be, and the first version of room 1 was
-- exactly it: a floor spanning the whole screen with the falling platform
-- placed decoratively above it, so the room was a corridor with a flag at
-- the end.
--
-- "Possible" was already checked. This checks that it is a GAME — the same
-- blind spot scripts/check_levels.py has for the ten legacy levels, where
-- every arithmetic guard proves a level can be completed and none of them
-- ever asked whether completing it required doing anything.
--
-- Trivial means all three: the spawn's surface runs unbroken to under the
-- door, the door sits at that surface's own resting height (so no climb is
-- needed), and nothing lethal stands in the walked band.
local function walkable_straight_through(room, player_half_height,
	package_offset_y)
	local spawn_top = nil
	for _, s in ipairs(M.surfaces(room)) do
		if room.spawn.x >= s[1] and room.spawn.x <= s[2] and room.spawn.y >= s[3]
			and (spawn_top == nil or s[3] > spawn_top) then
			spawn_top = s[3]
		end
	end
	if spawn_top == nil then
		return false -- unsupported spawn is its own, louder problem
	end

	-- The unbroken run of surfaces at the spawn's height containing the
	-- spawn. Grown by repeated passes rather than sorting, because two
	-- platforms that merely touch still form one walkable floor.
	local left, right = room.spawn.x, room.spawn.x
	local grew = true
	while grew do
		grew = false
		for _, s in ipairs(M.surfaces(room)) do
			if s[3] == spawn_top and s[2] >= left and s[1] <= right then
				if s[1] < left then left, grew = s[1], true end
				if s[2] > right then right, grew = s[2], true end
			end
		end
	end

	if room.door.x < left or room.door.x > right then
		return false -- a gap or a climb stands between spawn and door
	end
	if room.door.y ~= spawn_top + player_half_height + package_offset_y then
		return false -- the door is not at walking height
	end

	local low = math.min(room.spawn.x, room.door.x)
	local high = math.max(room.spawn.x, room.door.x)
	for _, h in ipairs(room.hazards or {}) do
		local half_width = h.half_width or 8
		local half_height = h.half_height or 8
		-- Only a hazard actually standing in the walked band counts. One in
		-- the pit below is scenery to someone who never leaves the floor.
		if h.x + half_width >= low and h.x - half_width <= high
			and h.y + half_height >= spawn_top
			and h.y - half_height <= spawn_top + 2 * player_half_height then
			return false
		end
	end
	return true
end

-- Everything that can be wrong with a room, as a list of sentences. Empty
-- means the room is playable.
--
-- This replaces scripts/check_levels.py for rooms, and is strictly better
-- than it was: it runs as a unit test, over the data the game actually
-- loads, using the same constants the game moves by — rather than a second
-- program re-deriving the geometry out of .collection text.
function M.validate(room, config)
	config = config or {}
	local d = M.DEFAULTS
	local player_half_width = config.player_half_width or d.player_half_width
	local player_half_height = config.player_half_height or d.player_half_height
	local package_half = config.package_half or d.package_half
	local package_offset_y = config.package_offset_y or d.package_offset_y
	local door_half_width = config.door_half_width or d.door_half_width
	local door_half_height = config.door_half_height or d.door_half_height

	local problems = {}
	local function fail(message)
		problems[#problems + 1] = message
	end

	if not M.theme(room.theme) then
		fail(string.format("room %s names theme %q, which does not exist",
			tostring(room.id), tostring(room.theme)))
	end

	local max_gap, max_step = M.budget(room, config)
	local surfaces = M.surfaces(room)

	-- A room is one screen with no camera, so anything outside it is simply
	-- not there. Checked before reachability, because an off-screen platform
	-- would otherwise report as an unreachable one and hide the real cause.
	for _, p in ipairs(room.platforms or {}) do
		if p.x - p.half_width < 0 or p.x + p.half_width > M.SCREEN_WIDTH
			or p.y - p.half_height < 0 or p.y + p.half_height > M.SCREEN_HEIGHT then
			fail(string.format(
				"room %s has a platform at (%d, %d) reaching outside the %dx%d screen",
				tostring(room.id), p.x, p.y, M.SCREEN_WIDTH, M.SCREEN_HEIGHT))
		end
	end

	for index, surface in ipairs(surfaces) do
		if index > 1 and not reachable(surface, surfaces, max_gap, max_step,
			player_half_width) then
			fail(string.format(
				"room %s: the surface at x=%d..%d (top y=%d) cannot be reached "
				.. "from any other, with a gap budget of %.1f and a climb of %.1f",
				tostring(room.id), surface[1], surface[2], surface[3],
				max_gap, max_step))
		end
	end

	-- The player has to START on something, or the room opens with a fall it
	-- never asked for.
	local spawn_supported = false
	for _, s in ipairs(surfaces) do
		if room.spawn.x >= s[1] and room.spawn.x <= s[2] and room.spawn.y >= s[3] then
			spawn_supported = true
		end
	end
	if not spawn_supported then
		fail(string.format("room %s spawns the player at (%d, %d) with no surface under it",
			tostring(room.id), room.spawn.x, room.spawn.y))
	end

	-- And the door has to be winnable. core/delivery.lua requires the package
	-- rect to be fully INSIDE the zone (PRD 3.4's "dentro"), not merely
	-- overlapping it, so this uses containment too — a check that accepted a
	-- corner touching would pass rooms the game itself refuses to award.
	local rest_offset = player_half_height + package_offset_y
	local door_ok = false
	for _, s in ipairs(surfaces) do
		local rest_y = s[3] + rest_offset
		if s[2] >= room.door.x - door_half_width
			and s[1] <= room.door.x + door_half_width
			and room.door.y - door_half_height <= rest_y - package_half
			and rest_y + package_half <= room.door.y + door_half_height then
			door_ok = true
		end
	end
	if not door_ok then
		fail(string.format(
			"room %s: the door at (%d, %d) has no surface under it that puts the "
			.. "package inside — standing on a surface with top y=T leaves the "
			.. "package centred at T+%d",
			tostring(room.id), room.door.x, room.door.y, rest_offset))
	end

	if walkable_straight_through(room, player_half_height, package_offset_y) then
		fail(string.format(
			"room %s can be finished by holding one direction: the spawn's floor "
			.. "runs unbroken to the door, the door is at walking height, and "
			.. "nothing lethal is in the way",
			tostring(room.id)))
	end

	return problems
end

-- Every problem across every room, so one test can cover the whole game.
function M.validate_all(config)
	local problems = {}
	for _, room in ipairs(M.ROOMS) do
		for _, problem in ipairs(M.validate(room, config)) do
			problems[#problems + 1] = problem
		end
	end
	return problems
end

return M
