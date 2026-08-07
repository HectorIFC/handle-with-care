local hazards = require "main.core.hazards"

return function()
	describe("hazards.rect_overlap", function()
		test("overlapping rects", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 5, y = 0, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == true)
		end)

		test("non-overlapping rects (far apart on x)", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 50, y = 0, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == false)
		end)

		test("non-overlapping rects (far apart on y)", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 0, y = 50, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == false)
		end)

		test("exactly touching edges do not count as overlapping", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 10, y = 0, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == false)
		end)

		test("diagonal overlap", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 8, y = 8, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == true)
		end)

		test("is symmetric (a,b same result as b,a)", function()
			local a = { x = 0, y = 0, half_width = 5, half_height = 5 }
			local b = { x = 8, y = 8, half_width = 5, half_height = 5 }
			assert(hazards.rect_overlap(a, b) == hazards.rect_overlap(b, a))
		end)
	end)

	describe("hazards.standing_on", function()
		test("standing directly on top", function()
			local player = { x = 0, y = 16, half_width = 8, half_height = 8 }
			local surface = { x = 0, y = 0, half_width = 32, half_height = 8 }
			assert(hazards.standing_on(player, surface) == true)
		end)

		test("not standing when horizontally clear of the surface", function()
			local player = { x = 100, y = 16, half_width = 8, half_height = 8 }
			local surface = { x = 0, y = 0, half_width = 32, half_height = 8 }
			assert(hazards.standing_on(player, surface) == false)
		end)

		test("not standing when too far above the surface", function()
			local player = { x = 0, y = 60, half_width = 8, half_height = 8 }
			local surface = { x = 0, y = 0, half_width = 32, half_height = 8 }
			assert(hazards.standing_on(player, surface) == false)
		end)

		test("within the default epsilon counts as standing", function()
			-- surface top is at y=8; player's feet 0.3 above it, under the
			-- default 0.5 epsilon.
			local player = { x = 0, y = 16.3, half_width = 8, half_height = 8 }
			local surface = { x = 0, y = 0, half_width = 32, half_height = 8 }
			assert(hazards.standing_on(player, surface) == true)
		end)

		test("respects a custom epsilon", function()
			local player = { x = 0, y = 17, half_width = 8, half_height = 8 } -- 1 unit above the surface top
			local surface = { x = 0, y = 0, half_width = 32, half_height = 8 }
			assert(hazards.standing_on(player, surface, 0.5) == false)
			assert(hazards.standing_on(player, surface, 1.5) == true)
		end)
	end)

	describe("hazards.below_kill_plane", function()
		test("below the kill plane", function()
			assert(hazards.below_kill_plane(-30, -20) == true)
		end)

		test("above the kill plane", function()
			assert(hazards.below_kill_plane(0, -20) == false)
		end)

		test("exactly at the kill plane does not count as below", function()
			assert(hazards.below_kill_plane(-20, -20) == false)
		end)
	end)

	describe("hazards.fully_offscreen", function()
		local screen_width, screen_height = 384, 216

		test("fully on-screen", function()
			local rect = { x = 192, y = 100, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == false)
		end)

		test("partially past the right edge is not fully offscreen", function()
			local rect = { x = 390, y = 100, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == false)
		end)

		test("fully past the right edge", function()
			local rect = { x = 400, y = 100, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == true)
		end)

		test("fully past the left edge", function()
			local rect = { x = -20, y = 100, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == true)
		end)

		test("fully past the top edge", function()
			local rect = { x = 192, y = 300, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == true)
		end)

		test("fully past the bottom edge", function()
			local rect = { x = 192, y = -30, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, screen_width, screen_height) == true)
		end)

		test("respects custom screen dimensions", function()
			local rect = { x = 90, y = 50, half_width = 8, half_height = 8 }
			assert(hazards.fully_offscreen(rect, 100, 100) == false)
			assert(hazards.fully_offscreen(rect, 50, 50) == true)
		end)
	end)
end
