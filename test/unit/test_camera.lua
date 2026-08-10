local camera = require "main.core.camera"

local SCREEN_W = 384
local SCREEN_H = 216

local function rect(x, y, hw, hh)
	return { x = x, y = y, half_width = hw or 8, half_height = hh or 8 }
end

return function()
	describe("camera.clamp", function()
		test("never scrolls left of the level's start", function()
			assert(camera.clamp(-50, 1000, SCREEN_W) == 0)
		end)

		test("never scrolls past the level's right edge", function()
			-- A 1000-wide level on a 384 screen can scroll to 616 and no
			-- further, or the player would see past the end of the level.
			assert(camera.clamp(9999, 1000, SCREEN_W) == 616)
		end)

		test("a level narrower than the screen pins the camera at 0", function()
			-- This is what keeps the existing one-screen levels behaving
			-- exactly as they did before a camera existed.
			assert(camera.clamp(0, 384, SCREEN_W) == 0)
			assert(camera.clamp(100, 200, SCREEN_W) == 0)
		end)

		test("leaves a valid position untouched", function()
			assert(camera.clamp(300, 1000, SCREEN_W) == 300)
		end)
	end)

	describe("camera.target_x dead zone", function()
		test("does not move while the player is inside the dead zone", function()
			-- Camera at 0 means the screen center is 192; a player within
			-- 48 of that must not drag the camera, or the package's constant
			-- wobble would jitter the whole frame.
			local state = camera.new(0)
			assert(camera.target_x(state, 192, SCREEN_W) == 0)
			assert(camera.target_x(state, 192 + 47, SCREEN_W) == 0)
			assert(camera.target_x(state, 192 - 47, SCREEN_W) == 0)
		end)

		test("moves only by the overshoot once the player leaves the dead zone", function()
			-- Not all the way to center: snapping would lurch every time the
			-- player turned around.
			local state = camera.new(0)
			assert(camera.target_x(state, 192 + 60, SCREEN_W) == 12)
			assert(camera.target_x(state, 192 - 60, SCREEN_W) == -12)
		end)

		test("a custom dead zone is respected", function()
			local state = camera.new(0)
			assert(camera.target_x(state, 192 + 20, SCREEN_W, { dead_zone = 10 }) == 10)
		end)
	end)

	describe("camera.update", function()
		test("eases toward the target rather than snapping", function()
			local state = camera.new(0)
			local config = { screen_width = SCREEN_W, level_width = 1000 }
			state = camera.update(state, 400, 1 / 60, config)
			-- Target is 400-192-48 = 160; one frame at 0.12 covers 19.2.
			assert(state.x > 0 and state.x < 160)
		end)

		test("converges on the target when the player stands still", function()
			local state = camera.new(0)
			local config = { screen_width = SCREEN_W, level_width = 1000 }
			for _ = 1, 200 do
				state = camera.update(state, 400, 1 / 60, config)
			end
			-- Settles with the player on the dead zone's edge, not centered.
			assert(math.abs(state.x - 160) < 0.5)
		end)

		test("stays clamped inside a level narrower than the screen", function()
			local state = camera.new(0)
			local config = { screen_width = SCREEN_W, level_width = 384 }
			for _ = 1, 100 do
				state = camera.update(state, 380, 1 / 60, config)
			end
			assert(state.x == 0)
		end)

		test("does not mutate the state it was given", function()
			local before = camera.new(0)
			camera.update(before, 400, 1 / 60, { screen_width = SCREEN_W, level_width = 1000 })
			assert(before.x == 0)
		end)
	end)

	describe("camera.rect_offscreen", function()
		test("something inside the camera window is on-screen", function()
			assert(camera.rect_offscreen(rect(500, 100), 400, SCREEN_W, SCREEN_H) == false)
		end)

		test("something left of the camera window is off-screen", function()
			assert(camera.rect_offscreen(rect(300, 100), 400, SCREEN_W, SCREEN_H) == true)
		end)

		test("something right of the camera window is off-screen", function()
			assert(camera.rect_offscreen(rect(900, 100), 400, SCREEN_W, SCREEN_H) == true)
		end)

		test("walking deep into a wide level is NOT off-screen", function()
			-- The whole reason this replaces hazards.fully_offscreen: with a
			-- fixed screen rect, x=900 would read as "fled the play area",
			-- making a level wider than one screen impossible.
			assert(camera.rect_offscreen(rect(900, 100), 700, SCREEN_W, SCREEN_H) == false)
		end)

		test("vertical bounds stay absolute, since the camera never pans up", function()
			assert(camera.rect_offscreen(rect(500, -50), 400, SCREEN_W, SCREEN_H) == true)
			assert(camera.rect_offscreen(rect(500, 300), 400, SCREEN_W, SCREEN_H) == true)
		end)

		test("partially visible does not count as off-screen", function()
			-- PRD 3.3 says "sai COMPLETAMENTE da tela".
			assert(camera.rect_offscreen(rect(402, 100), 400, SCREEN_W, SCREEN_H) == false)
		end)
	end)
end
