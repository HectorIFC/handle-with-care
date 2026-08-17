-- Rooms are data, so their geometry is testable — which is the main reason
-- they are data. This replaces, for rooms, what scripts/check_levels.py does
-- for the ten legacy levels: it runs in the suite, over the table the game
-- actually loads, using player_movement's own multipliers, instead of a
-- second program re-deriving the same arithmetic out of .collection text.

local rooms = require "main.core.rooms"

return function()
	describe("Rooms", function()

		test("every room is playable", function()
			-- The one that matters: no unreachable surface, no unsupported
			-- spawn, no unwinnable door, nothing off-screen, in any room.
			local problems = rooms.validate_all()
			if #problems > 0 then
				-- Printed rather than only asserted: deftest reports
				-- "assertion failed!" and nothing else, and which room broke
				-- is the entire content of this failure.
				for _, problem in ipairs(problems) do
					print("ROOM PROBLEM: " .. problem)
				end
			end
			assert(#problems == 0)
		end)

		test("every room names a theme that exists", function()
			for _, room in ipairs(rooms.ROOMS) do
				assert(rooms.theme(room.theme) ~= nil)
			end
		end)

		test("rooms are grouped in themes of five, the way the format wants", function()
			-- Level Devil groups five stages behind a door; the composition
			-- rule (teach, charge, charge, charge, combine) only reads if a
			-- theme is actually full. A partial theme is fine while it is
			-- being built, so this only checks the ones that are complete.
			local counts = {}
			for _, room in ipairs(rooms.ROOMS) do
				counts[room.theme] = (counts[room.theme] or 0) + 1
			end
			for theme, count in pairs(counts) do
				assert(count <= 5, theme .. " has more than five rooms")
			end
		end)

		test("a room's budget shrinks when it declares a mobility modifier", function()
			local plain = { theme = "falling", platforms = {} }
			local heavy = { theme = "falling", platforms = {}, modifier = "heavy_cycle" }
			local plain_reach, plain_apex = rooms.budget(plain)
			local heavy_reach, heavy_apex = rooms.budget(heavy)
			assert(heavy_reach < plain_reach)
			assert(heavy_apex < plain_apex)
		end)

		-- Negative proofs. A guard that has never failed has not been tested
		-- — the lesson from the delivery-zone bug, which shipped because the
		-- checker only ever ran against geometry that already passed.

		test("an unreachable platform is reported", function()
			local room = {
				id = "broken", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 80, y_top = 48 },
				-- 200 above the floor, against an apex of 56.9.
				platforms = { { x = 200, y = 200, half_width = 20, half_height = 8 } },
				hazards = {},
				door = { x = 40, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a door with nothing under it is reported", function()
			local room = {
				id = "broken_door", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 80, y_top = 48 },
				platforms = {},
				-- Well past the floor's right edge: the exact shape of the
				-- bug that shipped in level 9, where the zone hung over the
				-- pit and the checker said ok.
				door = { x = 300, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a door at the wrong height is reported", function()
			local room = {
				id = "high_door", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				-- Right x, but the carried package rests at 68 and cannot
				-- reach a zone centred at 160.
				door = { x = 200, y = 160 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a spawn over nothing is reported", function()
			local room = {
				id = "no_ground", theme = "falling",
				spawn = { x = 300, y = 60 },
				floor = { x_min = 0, x_max = 80, y_top = 48 },
				platforms = {},
				door = { x = 40, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a platform outside the screen is reported", function()
			local room = {
				id = "off_screen", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				-- A room has no camera, so anything past 384 is invisible
				-- rather than merely far away.
				platforms = { { x = 400, y = 80, half_width = 20, half_height = 8 } },
				door = { x = 40, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a room finishable by holding one direction is reported", function()
			-- This is the geometry room 1 actually SHIPPED with: a floor
			-- spanning the whole screen, the falling platform hovering
			-- decoratively above it, and the door at walking height. It was
			-- possible, reachable, winnable and completely trivial — every
			-- other guard passed it. A troll platformer may never be
			-- walkable in a straight line, so that is now a failure.
			local room = {
				id = "corridor", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {
					{ x = 150, y = 96, half_width = 40, half_height = 8, falling = true },
				},
				hazards = {},
				door = { x = 330, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a hazard standing in the walked band is enough to not be trivial", function()
			-- The same corridor, with one spike on the floor between spawn
			-- and door. Now it has to be jumped, so it is a room. This pins
			-- the rule's other half: without it, the check would reject
			-- rooms whose whole idea is a single well-placed hazard.
			local room = {
				id = "one_spike", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				hazards = { { x = 200, y = 56 } },
				door = { x = 330, y = 68 },
			}
			assert(#rooms.validate(room) == 0)
		end)

		test("a spike in the pit does not save a corridor", function()
			-- Below the floor the player walks on, so it threatens nobody
			-- who never leaves it. Distinguishing this from the case above
			-- is the reason the band is checked by height and not just by x.
			local room = {
				id = "pit_spike", theme = "falling",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				hazards = { { x = 200, y = 16 } },
				door = { x = 330, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a door that flees somewhere unreachable is reported", function()
			-- The retreat, not the home, is where the room ends. A door that
			-- runs out over a pit is unwinnable while every other guard here
			-- says ok — so validate checks EVERY position it can occupy.
			local room = {
				id = "flees_into_the_void", theme = "door",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 140, y_top = 48 },
				platforms = {},
				hazards = { { x = 90, y = 56 } },
				door = { x = 60, y = 68, lie = "flee",
					retreats = { { x = 340, y = 68 } } },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a door set to flee with nowhere to flee is reported", function()
			-- Otherwise it is silently the boring version of itself.
			local room = {
				id = "flee_nowhere", theme = "door",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				hazards = { { x = 200, y = 56 } },
				door = { x = 330, y = 68, lie = "flee" },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("an unknown lie is reported", function()
			local room = {
				id = "bad_lie", theme = "door",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				hazards = { { x = 200, y = 56 } },
				door = { x = 330, y = 68, lie = "teleports" },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a room whose wall cannot be outrun is reported", function()
			-- The chase equivalent of a door that flees forever: it would
			-- present as the player simply always dying, with every other
			-- guard reporting the room fine.
			local room = {
				id = "unwinnable_chase", theme = "chase",
				spawn = { x = 30, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {}, hazards = {},
				chase = { start = 0, speed = 300, acceleration = 20, slack = 0 },
				door = { x = 350, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a chased room is exempt from the straight-walk rule", function()
			-- Not a loophole: holding one direction is exactly what a chase
			-- asks for, and what makes it a room is that stopping kills you.
			local room = {
				id = "honest_chase", theme = "chase",
				spawn = { x = 30, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {}, hazards = {},
				chase = { start = -40, speed = 34, acceleration = 2, slack = 2 },
				door = { x = 350, y = 68 },
			}
			assert(#rooms.validate(room) == 0)
		end)

		test("an upside-down room is validated as its own reflection", function()
			-- Cheap proof that the reflection is right rather than merely
			-- symmetric-looking: the same layout, once the right way up and
			-- once inverted about the screen, must reach the same verdict.
			local upright_room = {
				id = "upright", theme = "gravity",
				spawn = { x = 30, y = 60 },
				floor = { x_min = 0, x_max = 120, y_top = 48, thickness = 32 },
				platforms = { { x = 200, y = 56, half_width = 40, half_height = 8 },
					{ x = 330, y = 56, half_width = 54, half_height = 8 } },
				hazards = { { x = 258, y = 16 } },
				door = { x = 330, y = 84 },
			}
			local flipped = {
				id = "flipped", theme = "gravity", inverted = true,
				spawn = { x = 30, y = 156 },
				floor = { x_min = 0, x_max = 120, y_top = 200, thickness = 32 },
				platforms = { { x = 200, y = 160, half_width = 40, half_height = 8 },
					{ x = 330, y = 160, half_width = 54, half_height = 8 } },
				hazards = { { x = 258, y = 200 } },
				door = { x = 330, y = 132 },
			}
			assert(#rooms.validate(upright_room) == 0)
			assert(#rooms.validate(flipped) == 0)
		end)

		test("an upside-down room with an unreachable ceiling is still reported", function()
			-- The reflection must not launder a broken room into a valid one.
			local room = {
				id = "bad_ceiling", theme = "gravity", inverted = true,
				spawn = { x = 30, y = 156 },
				floor = { x_min = 0, x_max = 120, y_top = 200, thickness = 32 },
				-- 150 below the ceiling the player walks on, against an apex
				-- of 56.9 in the other direction.
				platforms = { { x = 250, y = 20, half_width = 30, half_height = 8 } },
				hazards = {},
				door = { x = 60, y = 132 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("every theme that has rooms has exactly five of them", function()
			-- Sharper than the earlier "at most five", and it exists because
			-- a bad edit put a whole theme's five rooms into the WRONG TABLE
			-- (MODIFIER_MASS, where they were valid Lua and simply did not
			-- exist as far as the game was concerned). Nothing failed: the
			-- suite passed, validate_all iterated the rooms that were left,
			-- and only booting room 16 and getting room 1 gave it away. A
			-- count assertion over the table the game actually loads is the
			-- cheapest thing that could have caught it.
			local counts = {}
			for _, room in ipairs(rooms.ROOMS) do
				counts[room.theme] = (counts[room.theme] or 0) + 1
			end
			for theme, count in pairs(counts) do
				assert(count == 5, theme .. " has " .. count .. " rooms, not five")
			end
			assert(rooms.count() == #rooms.ROOMS)
			assert(rooms.count() % 5 == 0)
		end)

		test("an unknown modifier is reported", function()
			-- The hole this closes: a room could declare a modifier, have its
			-- geometry validated against that modifier's much smaller reach
			-- and apex, and then have room_builder spawn no driver for it.
			-- The room played easier than it was checked as, silently — the
			-- worst kind of mismatch, because everything reported fine.
			local room = {
				id = "typo_modifier", theme = "heavy",
				modifier = "heavy_cicle",
				spawn = { x = 30, y = 60 },
				floor = { x_min = 0, x_max = 120, y_top = 48 },
				platforms = { { x = 195, y = 56, half_width = 30, half_height = 8 },
					{ x = 327, y = 56, half_width = 57, half_height = 8 } },
				hazards = { { x = 245, y = 16 } },
				door = { x = 327, y = 84 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("a room whose fuse cannot be beaten is reported", function()
			-- The fuse equivalent of a wall that cannot be outrun. The worst
			-- moment the fuse can light is the first frame, so the whole walk
			-- has to fit inside it — explosive.lua detonates on its own
			-- countdown regardless of where the player has got to.
			local room = {
				id = "impossible_fuse", theme = "fuse",
				modifier = "explosive_cycle", fuse_time = 0.5,
				spawn = { x = 30, y = 60 },
				floor = { x_min = 0, x_max = 120, y_top = 48 },
				platforms = { { x = 200, y = 56, half_width = 40, half_height = 8 },
					{ x = 320, y = 56, half_width = 45, half_height = 8 } },
				hazards = { { x = 255, y = 16 } },
				door = { x = 320, y = 84 },
			}
			assert(#rooms.validate(room) > 0)
		end)

		test("an unknown theme is reported", function()
			local room = {
				id = "no_theme", theme = "does_not_exist",
				spawn = { x = 40, y = 60 },
				floor = { x_min = 0, x_max = 384, y_top = 48 },
				platforms = {},
				door = { x = 40, y = 68 },
			}
			assert(#rooms.validate(room) > 0)
		end)
	end)
end
