local mirror = require "main.core.mirror"

local WIDTH = 1000

return function()
	describe("mirror.mirror_x", function()
		test("reflects about the level's midpoint", function()
			assert(mirror.mirror_x(0, WIDTH) == 1000)
			assert(mirror.mirror_x(1000, WIDTH) == 0)
			assert(mirror.mirror_x(500, WIDTH) == 500)
		end)

		test("is self-inverse", function()
			-- What makes it safe to apply to authored positions without
			-- tracking whether it has already been applied.
			assert(mirror.mirror_x(mirror.mirror_x(237, WIDTH), WIDTH) == 237)
		end)
	end)

	describe("mirror.mirror_rect", function()
		test("moves the centre and leaves the extents alone", function()
			local r = mirror.mirror_rect({ x = 200, y = 50, half_width = 30, half_height = 8 }, WIDTH)
			assert(r.x == 800)
			assert(r.half_width == 30)
			assert(r.half_height == 8)
			assert(r.y == 50) -- vertical is never mirrored
		end)
	end)

	describe("mirror.in_normal_section", function()
		test("only the level's tail counts", function()
			-- PRD: "seção final não espelhada".
			assert(mirror.in_normal_section(950, WIDTH, 200) == true)
			assert(mirror.in_normal_section(700, WIDTH, 200) == false)
			assert(mirror.in_normal_section(800, WIDTH, 200) == true)
		end)

		test("a level with no normal section never reports one", function()
			assert(mirror.in_normal_section(999, WIDTH, nil) == false)
			assert(mirror.in_normal_section(999, WIDTH, 0) == false)
		end)
	end)

	describe("mirror.reaction_sign", function()
		test("flips horizontal reactions only when mirrored", function()
			assert(mirror.reaction_sign(true) == -1)
			assert(mirror.reaction_sign(false) == 1)
		end)
	end)

	describe("mirror.package_mirrored", function()
		test("the package stays mirrored through the mirrored part", function()
			assert(mirror.package_mirrored({
				player_x = 400, level_width = WIDTH, normal_section_width = 200 }) == true)
		end)

		test("and un-mirrors with the world in the final section", function()
			assert(mirror.package_mirrored({
				player_x = 900, level_width = WIDTH, normal_section_width = 200 }) == false)
		end)

		test("unless the level pins it mirrored throughout", function()
			-- This is the PRD's real trap: un-mirrored geometry while the
			-- package still reacts backwards, so the muscle memory built
			-- over the mirrored stretch betrays the player precisely when
			-- the world starts looking familiar again.
			assert(mirror.package_mirrored({
				player_x = 900, level_width = WIDTH, normal_section_width = 200,
				package_always_mirrored = true }) == true)
		end)
	end)
end
